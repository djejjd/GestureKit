// Isolated real-Chrome acceptance: no user Chrome profile or App is stopped.
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { createServer as httpServer } from "node:http";
import { createServer as tcpServer } from "node:net";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomBytes, randomUUID, createHash } from "node:crypto";
import { CDPClient, waitForExtensionServiceWorker } from "./run-link-reliability.mjs";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const chromePath = process.env.CHROME_PATH ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const hostPath = process.env.GESTUREKIT_TEST_HOST ?? join(repo, ".build/debug/GestureKitHost");
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(probe, name, timeoutMs = 20_000) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    try { const value = await probe(); if (value) return value; } catch (error) { lastProbeError = error.message; }
    await sleep(100);
  }
  throw Error(`acceptance_timeout stage=${name}`);
}

if (process.argv.includes("--dry-run")) {
  console.log("extension_recovery scenarios=app_restart,native_host_exit,build_update,existing_page_restore isolated_profile=true");
  process.exit(0);
}
assert.ok(existsSync(chromePath), "Chrome is required");
assert.ok(existsSync(hostPath), "Build GestureKitHost or set GESTUREKIT_TEST_HOST");
const root = mkdtempSync(join(tmpdir(), "gesturekit-recovery-"));
const extension = join(root, "extension");
const profile = join(root, "profile");
mkdirSync(extension); mkdirSync(profile);
// Match the user's unpacked/developer installation. CDP loadUnpacked alone can
// temporarily load with developer mode off, then Chrome rejects runtime.reload.
mkdirSync(join(profile, "Default"));
writeFileSync(join(profile, "Default/Preferences"), JSON.stringify({ extensions: { ui: { developer_mode: true } } }));
let chromeProcess, cdp, appServer;
const sockets = new Set();
let appSession = randomUUID();
let port;
let pageRequests = 0;
let acknowledgements = 0;
let lastStatus;
let lastProbeError;
let diagnosticCall;
let diagnosticWorker;
let diagnosticExtensionId;
let diagnosticPageSession;
const fixture = httpServer((req, res) => {
  if (req.url === "/page") pageRequests++;
  res.writeHead(200, { "Content-Type": "text/html", "Cache-Control": "no-store" });
  res.end('<html><body><input id="draft" value="original"><a id="link" href="/target">Link</a></body></html>');
});
fixture.on("connection", socket => sockets.add(socket));

function startApp(listenPort = 0) {
  appSession = randomUUID();
  appServer = tcpServer(socket => {
    sockets.add(socket); socket.on("close", () => sockets.delete(socket));
    let buffer = "";
    const send = (type, payload) => socket.write(JSON.stringify({
      protocolVersion: 2, messageId: randomUUID(), providerSessionId: appSession,
      gestureSessionId: null, operationId: null, type, timestamp: Date.now(), payload, error: null
    }) + "\n");
    socket.on("data", bytes => {
      buffer += bytes.toString();
      while (buffer.includes("\n")) {
        const end = buffer.indexOf("\n"), line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
        let envelope; try { envelope = JSON.parse(line); } catch { continue; }
        if (envelope.type === "provider_hello") send("provider_challenge", { nonce: randomBytes(32).toString("base64"), expiresAt: Date.now() + 30_000 });
        if (envelope.type === "provider_authenticate") send("configuration_snapshot", { storeEpoch: appSession, schemaVersion: 3, configurationVersion: 1, configJSON: "{}" });
        if (envelope.type === "configuration_ack") acknowledgements++;
      }
    });
  });
  return new Promise(resolve => appServer.listen(listenPort, "127.0.0.1", () => { port = appServer.address().port; resolve(); }));
}

try {
  for (const file of ["src", "manifest.json", "popup.html", "smoke.html", "package-lock.json"]) cpSync(join(repo, "extensions/chrome", file), join(extension, file), { recursive: true });
  const hostName = "com.gesturekit.recovery.acceptance";
  const build = () => execFileSync(process.execPath, [join(repo, "extensions/chrome/scripts/build.mjs")], {
    cwd: extension, env: { ...process.env, GESTUREKIT_HOST_NAME: hostName }, stdio: "pipe"
  });
  build();
  const firstBuild = JSON.parse(readFileSync(join(extension, "dist/build.json"))).buildId;
  await new Promise(resolve => fixture.listen(0, "127.0.0.1", resolve));
  await startApp();
  const manifest = JSON.parse(readFileSync(join(extension, "manifest.json")));
  const extensionId = [...createHash("sha256").update(Buffer.from(manifest.key, "base64")).digest().subarray(0, 16)]
    .map(byte => String.fromCharCode(97 + (byte >> 4), 97 + (byte & 15))).join("");
  const wrapper = join(root, "host.sh"), pidFile = join(root, "host.pid");
  // Quote paths for a POSIX shell without evaluating their contents.
  const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
  writeFileSync(wrapper, `#!/bin/sh\necho $$ > ${quote(pidFile)}\nexec ${quote(hostPath)} "$@"\n`, { mode: 0o700 });
  const nativeDir = join(profile, "NativeMessagingHosts"); mkdirSync(nativeDir);
  writeFileSync(join(nativeDir, `${hostName}.json`), JSON.stringify({ name: hostName, description: "Isolated GestureKit acceptance", path: wrapper, type: "stdio", allowed_origins: [`chrome-extension://${extensionId}/`] }));
  chromeProcess = spawn(chromePath, [
    `--user-data-dir=${profile}`, "--headless=new", "--remote-debugging-port=0", "--enable-unsafe-extension-debugging",
    "--no-first-run", "--no-default-browser-check", "--disable-background-networking", "about:blank"
  ], { stdio: "ignore", env: { ...process.env, GESTUREKIT_IPC_PORT: String(port) } });
  await until(() => existsSync(join(profile, "DevToolsActivePort")), "chrome_start");
  const [debugPort, debugPath] = readFileSync(join(profile, "DevToolsActivePort"), "utf8").trim().split("\n");
  cdp = new CDPClient(`ws://127.0.0.1:${debugPort}${debugPath}`); await cdp.connect();
  const call = async (method, params = {}, sessionId) => {
    let timer;
    let response;
    try {
      response = await Promise.race([cdp.send(method, params, sessionId), new Promise((_, reject) => { timer = setTimeout(() => reject(Error(`CDP timeout ${method}`)), 5_000); })]);
    } finally { clearTimeout(timer); }
    if (response.error) throw Error(`CDP command failed ${method}: ${response.error.code} ${response.error.message}`);
    return response.result;
  };
  diagnosticCall = call; diagnosticExtensionId = extensionId;
  const initialPage = (await call("Target.getTargets")).targetInfos.find(target => target.type === "page");
  diagnosticPageSession = (await call("Target.attachToTarget", { targetId: initialPage.targetId, flatten: true })).sessionId;
  await call("ServiceWorker.enable", {}, diagnosticPageSession);
  await call("Page.navigate", { url: "chrome://extensions" }, diagnosticPageSession);
  await until(async () => {
    const probe = await call("Runtime.evaluate", { expression: "typeof chrome.developerPrivate !== 'undefined'", returnByValue:true }, diagnosticPageSession);
    return probe.result.value;
  }, "developer_settings_ready");
  const developerMode = await call("Runtime.evaluate", {
    expression: "new Promise(resolve=>chrome.developerPrivate.updateProfileConfiguration({inDeveloperMode:true},()=>chrome.developerPrivate.getProfileConfiguration(value=>resolve(value.inDeveloperMode))))",
    awaitPromise:true, returnByValue:true
  }, diagnosticPageSession);
  assert.equal(developerMode.result.value, true, "developer mode must be enabled through Chrome's own settings");
  const loaded = await call("Extensions.loadUnpacked", { path: extension });
  assert.equal(loaded.id, extensionId);
  async function worker(expression) {
    const target = await waitForExtensionServiceWorker(cdp, extensionId, 2_000);
    if (!target) throw Error("worker unavailable");
    const { sessionId } = await call("Target.attachToTarget", { targetId: target.targetId, flatten: true });
    try {
      const result = await call("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true }, sessionId);
      if (result.exceptionDetails) throw Error(`worker expression failed: ${result.exceptionDetails.text}`);
      return result.result.value;
    } finally { try { await call("Target.detachFromTarget", { sessionId }); } catch {} }
  }
  diagnosticWorker = worker;
  const status = async () => {
    lastStatus = await worker('chrome.storage.local.get(["gesturekitStatus","gesturekitDevelopmentUpdate","gesturekitRunningBuild"])');
    return lastStatus;
  };
  await until(async () => (await status()).gesturekitStatus?.appConnected, "initial_authentication");
  assert.ok(acknowledgements > 0);
  const firstPid = readFileSync(pidFile, "utf8").trim();

  // App stops and starts, but Chrome and its Native port remain alive.
  const originalAcknowledgements = acknowledgements;
  for (const socket of [...sockets]) {
    if (socket.localPort === port) socket.destroy();
  }
  await new Promise(resolve => appServer.close(resolve));
  await startApp(port);
  await until(() => acknowledgements > originalAcknowledgements, "app_restart_reauthentication");
  assert.equal(readFileSync(pidFile, "utf8").trim(), firstPid, "App restart must not require replacing the Native host");
  console.log("app_restart_recovered=true");

  // Terminating only this fixture's Native host must reconstruct the Native port.
  process.kill(Number(firstPid), "SIGTERM");
  await until(() => readFileSync(pidFile, "utf8").trim() !== firstPid, "native_host_reconnect");
  await until(async () => (await status()).gesturekitStatus?.appConnected, "native_host_configuration");
  console.log("native_host_exit_recovered=true");

  const target = await call("Target.createTarget", { url: `http://127.0.0.1:${fixture.address().port}/page` });
  const pageSession = (await call("Target.attachToTarget", { targetId: target.targetId, flatten: true })).sessionId;
  await until(async () => {
    const response = await call("Runtime.evaluate", { expression: '!!document.querySelector("#draft")', returnByValue: true }, pageSession);
    return response.result.value;
  }, "page_ready");
  await call("Runtime.evaluate", { expression: 'document.querySelector("#draft").value="unsaved draft"' }, pageSession);
  const pagesBefore = pageRequests;
  writeFileSync(join(extension, "src/popup/popup.ts"), readFileSync(join(extension, "src/popup/popup.ts"), "utf8") + "\n// acceptance build update\n");
  build();
  const newBuild = JSON.parse(readFileSync(join(extension, "dist/build.json"))).buildId;
  assert.notEqual(newBuild, firstBuild);
  // Attaching DevTools during runtime.reload can orphan the old inspector and
  // hold the replacement worker waiting for a debugger. Do not inspect this window.
  await sleep(8_000);
  await until(async () => {
    const current = await status();
    return current.gesturekitRunningBuild === newBuild && current.gesturekitDevelopmentUpdate?.stage === "applied" && current.gesturekitStatus?.appConnected;
  }, "automatic_build_reload", 20_000);
  const restored = await until(async () => worker(`(async()=>{const tabs=await chrome.tabs.query({});const tab=tabs.find(t=>t.url?.endsWith('/page'));if(!tab)return null;try{return await chrome.tabs.sendMessage(tab.id,{type:'gesturekit.contentVersion'})}catch{return null}})()`), "content_restore");
  assert.equal(restored.buildId, newBuild);
  const form = await call("Runtime.evaluate", { expression: 'document.querySelector("#draft").value', returnByValue: true }, pageSession);
  assert.equal(form.result.value, "unsaved draft");
  assert.equal(pageRequests, pagesBefore, "updating the extension must not refresh existing web pages");
  console.log("automatic_build_reload=true existing_page_restored=true draft_preserved=true");
} catch (error) {
  console.error(JSON.stringify({ failure: error.message, lastProbeError, lastStatus,
    workerErrors: cdp?.events.filter(event => event.method === "ServiceWorker.workerErrorReported").map(event => event.params.errorMessage?.errorMessage),
    workerVersions: cdp?.events.filter(event => event.method === "ServiceWorker.workerVersionUpdated").slice(-4).map(event => event.params.versions?.map(v => ({status:v.status,runningStatus:v.runningStatus}))) }));
  if (diagnosticCall && diagnosticExtensionId) {
    try {
      const target = await diagnosticCall("Target.createTarget", { url: "chrome://extensions" });
      const { sessionId } = await diagnosticCall("Target.attachToTarget", { targetId: target.targetId, flatten: true });
      const result = await diagnosticCall("Runtime.evaluate", { expression: "new Promise(resolve=>chrome.developerPrivate.getExtensionsInfo({includeDisabled:true,includeTerminated:true},items=>resolve(items.map(x=>({id:x.id,state:x.state,disableReasons:x.disableReasons,runtimeErrors:x.runtimeErrors?.map(e=>e.message),manifestErrors:x.manifestErrors?.map(e=>e.message)})))))", awaitPromise:true, returnByValue:true }, sessionId);
      console.error(JSON.stringify({ extensionState:result.result?.value }));
    } catch {}

    try {
      await diagnosticCall("ServiceWorker.startWorker", { scopeURL: `chrome-extension://${diagnosticExtensionId}/` }, diagnosticPageSession);
      console.error("diagnostic_worker_start_requested=true");
      console.error(JSON.stringify(await diagnosticWorker('chrome.storage.local.get(["gesturekitRunningBuild","gesturekitDevelopmentUpdate"])')));
    } catch (diagnosticError) { console.error(`diagnostic_worker_start_failed=${diagnosticError.message}`); }
  }
  throw error;
} finally {
  try { cdp?.close(); } catch { /* browser exited */ }
  if (chromeProcess) {
    chromeProcess.kill("SIGTERM");
    await Promise.race([new Promise(resolve => chromeProcess.once("exit", resolve)), sleep(2_000)]);
  }
  for (const socket of sockets) socket.destroy();
  appServer?.close(); fixture.closeAllConnections(); fixture.close();
  // Chrome helper processes can finish writing shortly after the parent exits.
  rmSync(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
}
