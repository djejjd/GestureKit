#!/usr/bin/env node
// probe-link-reliability.mjs — GestureKit v2.4.1 Task 1 一次性探针
//
// 回答 4 个问题：
//   (a) 扩展可加载性：把 manifest.json + popup.html + smoke.html + dist/ 构建输出拷成
//       "完整可加载扩展副本" 后，能否被 Chrome 真正加载（content script 注入）？
//       —— 注意：Google Chrome（品牌版）自 142 起忽略 --load-extension，改用 CDP
//          Extensions.loadUnpacked 加载。
//   (b) 扩展 ID 算法：含 key 的扩展 -> key 推导 ID；无 key 扩展 -> 路径推导 ID
//       （sha256(realpath) 前 16 字节 nibble 映射）。两者均可复现，给出实测值。
//   (c) manifest 读取位置：<user-data-dir>/NativeMessagingHosts vs
//       用户级 ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/
//   (d) leaseExpiry 复核：broken chain 下 content script 是否有 guard、普通点击是否被拦截。
//
// 安全：全部使用临时 profile / 临时目录 / 独立 host 名（com.gesturekit.host.e2e.probe），
// 绝不写或替换用户级真实 com.gesturekit.host manifest；运行结束清理进程与临时目录。
//
// 用法：node scripts/dev/probe-link-reliability.mjs
//       CHROME_PATH=... node scripts/dev/probe-link-reliability.mjs

import { createHash } from "node:crypto";
import { execSync, spawn } from "node:child_process";
import { createServer } from "node:http";
import {
  mkdirSync, readFileSync, writeFileSync, rmSync,
  existsSync, realpathSync, chmodSync, copyFileSync, readdirSync
} from "node:fs";
import { createServer as createNetServer } from "node:net";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// ────────────────────────────────────────────────────────────────────
// 常量
// ────────────────────────────────────────────────────────────────────

const REPO_ROOT = resolve(fileURLToPath(import.meta.url), "../../..");
const CHROME = process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const EXT_SRC = join(REPO_ROOT, "extensions/chrome");
const FIXTURE_SRC = join(REPO_ROOT, "scripts/e2e/fixtures/link-reliability.html");
// 用户级 NMH 目录：仅当 Chrome 用默认 user-data-dir 时才会读取；
// 探针（临时 profile）验证的是 <user-data-dir>/NativeMessagingHosts。
const USER_NMH_DIR = `${process.env.HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts`;
const FIXED_TARGET_URL = "https://example.test/e2e-target";

const BASE = join(tmpdir(), `gesturekit-probe-${process.pid}`);
const EXT_DIR = join(BASE, "ext");          // 含 key 的完整副本
const EXT_NOKEY_DIR = join(BASE, "ext-nokey"); // 无 key 副本（路径 ID 算法验证）
const PROFILE_DIR = join(BASE, "profile");
const MARKER_PROFILE = join(BASE, "marker-profile.txt");
const MARKER_USER = join(BASE, "marker-user.txt");

const log = (msg) => console.log(`[probe] ${msg}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function sha256buf(str) {
  return createHash("sha256").update(str).digest();
}

/** 候选算法：sha256(input) 前 16 字节，每字节高/低 nibble 映射为 'a'..'p'。 */
function idFromHashBytes(hashBytes) {
  let id = "";
  for (let i = 0; i < 32; i++) {
    const b = hashBytes[Math.floor(i / 2)];
    const nibble = i % 2 === 0 ? b >> 4 : b & 0x0f;
    id += String.fromCharCode(0x61 + nibble);
  }
  return id;
}

function predictPathId(pathStr) {
  return idFromHashBytes(sha256buf(pathStr));
}

function findFreePort() {
  return new Promise((resolvePort, reject) => {
    const probe = createNetServer();
    probe.on("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => resolvePort(port));
    });
  });
}

// ────────────────────────────────────────────────────────────────────
// CDP 客户端
// ────────────────────────────────────────────────────────────────────

class CDPClient {
  #ws;
  #callbacks = new Map();
  #msgId = 0;
  events = [];

  constructor(wsUrl) { this.#ws = new WebSocket(wsUrl); }

  async connect() {
    return new Promise((res, rej) => {
      this.#ws.onopen = () => res();
      this.#ws.onerror = (e) => rej(new Error(`CDP WebSocket error: ${e.message || "unknown"}`));
      this.#ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.id && this.#callbacks.has(msg.id)) {
          this.#callbacks.get(msg.id)(msg);
          this.#callbacks.delete(msg.id);
        } else if (msg.method) {
          this.events.push(msg);
        }
      };
    });
  }

  async send(method, params = {}, sessionId = null) {
    const id = ++this.#msgId;
    return new Promise((res) => {
      this.#callbacks.set(id, res);
      const msg = { id, method, params };
      if (sessionId) msg.sessionId = sessionId;
      this.#ws.send(JSON.stringify(msg));
    });
  }

  clearEvents() { this.events.length = 0; }

  close() { try { this.#ws.close(); } catch {} }
}

/** 等待页面 reload 后出现的 content script isolated world 执行上下文。 */
async function waitForIsolatedContext(cdp, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const evt = cdp.events.find((e) =>
      e.method === "Runtime.executionContextCreated" &&
      e.params?.context?.auxData?.type === "isolated");
    if (evt) return evt.params.context;
    await sleep(250);
  }
  return null;
}

/** 在指定 contextId 中求值。 */
async function evaluateInContext(cdp, sessionId, contextId, expression) {
  const resp = await cdp.send("Runtime.evaluate", {
    expression,
    returnByValue: true,
    contextId,
  }, sessionId);
  return resp?.result?.result?.value;
}

// ────────────────────────────────────────────────────────────────────
// fixture server + Chrome
// ────────────────────────────────────────────────────────────────────

function startFixtureServer() {
  return new Promise(async (res, rej) => {
    const port = await findFreePort();
    const server = createServer((req, res2) => {
      const url = new URL(req.url, `http://127.0.0.1:${port}`);
      if (url.pathname === "/link-reliability.html") {
        res2.writeHead(200, { "Content-Type": "text/html" });
        res2.end(readFileSync(FIXTURE_SRC));
      } else {
        res2.writeHead(404);
        res2.end("not found");
      }
    });
    server.on("error", rej);
    server.listen(port, "127.0.0.1", () => res({ server, port }));
  });
}

async function launchChrome(extraArgs = []) {
  const args = [
    `--user-data-dir=${PROFILE_DIR}`,
    "--remote-debugging-port=0",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    "--disable-component-update",
    "--no-experiments",
    ...extraArgs,
  ];
  log(`启动 Chrome: ${CHROME}`);
  const child = spawn(CHROME, args, { stdio: "ignore" });
  const portFile = join(PROFILE_DIR, "DevToolsActivePort");
  const deadline = Date.now() + 20000;
  let cdpPort = 0;
  while (Date.now() < deadline) {
    try {
      const line = readFileSync(portFile, "utf-8").trim().split("\n")[0];
      if (Number.parseInt(line, 10) > 0) { cdpPort = Number.parseInt(line, 10); break; }
    } catch {}
    if (child.exitCode !== null && child.exitCode !== undefined) break;
    await sleep(200);
  }
  if (cdpPort === 0) {
    child.kill("SIGKILL");
    throw new Error("Chrome 启动超时（未找到 DevToolsActivePort）");
  }
  log(`Chrome CDP port: ${cdpPort}`);
  return { child, cdpPort };
}

async function connectCDP(cdpPort) {
  const res = await fetch(`http://127.0.0.1:${cdpPort}/json/version`);
  const json = await res.json();
  const cdp = new CDPClient(json.webSocketDebuggerUrl);
  await cdp.connect();
  return cdp;
}

async function waitForTarget(cdp, predicate, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const resp = await cdp.send("Target.getTargets", {});
    const infos = resp?.result?.targetInfos || [];
    const hit = infos.find(predicate);
    if (hit) return hit;
    await sleep(250);
  }
  return null;
}

async function evaluateInSession(cdp, sessionId, expression, awaitPromise = false) {
  const resp = await cdp.send("Runtime.evaluate", {
    expression,
    returnByValue: true,
    awaitPromise,
  }, sessionId);
  return resp?.result?.result?.value;
}

async function attach(cdp, targetId) {
  const resp = await cdp.send("Target.attachToTarget", { targetId, flatten: true });
  return resp?.result?.sessionId;
}

// ────────────────────────────────────────────────────────────────────
// 构建完整可加载副本
// ────────────────────────────────────────────────────────────────────

function buildExtensionCopy(outDir, { withKey = true } = {}) {
  mkdirSync(outDir, { recursive: true });
  // 构建到 <outDir>/dist，使 manifest 内 dist/... 引用与实际布局一致
  execSync(`node scripts/build.mjs --outdir "${join(outDir, "dist")}"`, {
    cwd: EXT_SRC,
    stdio: "inherit",
  });
  for (const f of ["manifest.json", "popup.html", "smoke.html"]) {
    copyFileSync(join(EXT_SRC, f), join(outDir, f));
  }
  mkdirSync(join(outDir, "dist/popup"), { recursive: true });
  copyFileSync(join(EXT_SRC, "src/popup/popup.css"), join(outDir, "dist/popup/popup.css"));
  if (!withKey) {
    const manifestPath = join(outDir, "manifest.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf-8"));
    delete manifest.key;
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  }
}

// ────────────────────────────────────────────────────────────────────
// 探针 A+B
// ────────────────────────────────────────────────────────────────────

async function probeLoadAndId() {
  log("=== 探针 (a)+(b)：扩展可加载性 + 扩展 ID 算法 ===");
  buildExtensionCopy(EXT_DIR, { withKey: true });
  buildExtensionCopy(EXT_NOKEY_DIR, { withKey: false });
  log(`含 key 副本目录: ${EXT_DIR}`);
  log(`无 key 副本目录: ${EXT_NOKEY_DIR}`);

  const { server, port } = await startFixtureServer();
  const fixtureUrl = `http://127.0.0.1:${port}/link-reliability.html`;
  // 先以 about:blank 启动（content script 只在扩展加载后打开的页面注入），
  // 扩展加载完成后再经 CDP 导航到 fixture 页面。
  const { child: chromeProc, cdpPort } = await launchChrome(["about:blank"]);

  try {
    const cdp = await connectCDP(cdpPort);

    // 1) 加载含 key 的扩展（真实 GestureKit 副本）
    const r1 = await cdp.send("Extensions.loadUnpacked", { path: EXT_DIR });
    const idWithKey = r1?.result?.id || null;
    const keyDerivedId = (() => {
      try {
        return execSync(`node "${join(EXT_SRC, "scripts/extension-id.mjs")}"`, { encoding: "utf-8" }).trim();
      } catch { return null; }
    })();
    log(`[a/b] Extensions.loadUnpacked(含 key 副本) -> id=${idWithKey}`);
    log(`[b]   manifest key 推导 ID（extension-id.mjs）= ${keyDerivedId}`);
    log(`[b]   两者一致? ${idWithKey === keyDerivedId}`);

    // 2) 加载无 key 副本，验证路径推导 ID 算法
    const r2 = await cdp.send("Extensions.loadUnpacked", { path: EXT_NOKEY_DIR });
    const idNoKey = r2?.result?.id || null;
    const pathReal = realpathSync(EXT_NOKEY_DIR);
    const predictReal = predictPathId(pathReal);
    const predictLiteral = predictPathId(EXT_NOKEY_DIR);
    log(`[b]   Extensions.loadUnpacked(无 key 副本) -> id=${idNoKey}`);
    log(`[b]   无 key 目录 realpath = ${pathReal}`);
    log(`[b]   预测 sha256(realpath) = ${predictReal}  <- 匹配? ${idNoKey === predictReal}`);
    log(`[b]   预测 sha256(字面路径)  = ${predictLiteral}  <- 匹配? ${idNoKey === predictLiteral}`);

    // 3) 等我们的扩展 service worker 启动（MV3 懒加载，install 后应触发）
    let ourSw = null;
    if (idWithKey) {
      ourSw = await waitForTarget(cdp, (t) => t.type === "service_worker" && t.url.includes(idWithKey));
      log(`[a] 扩展 service worker 出现? ${Boolean(ourSw)}` + (ourSw ? ` url=${ourSw.url}` : ""));
    }

    // 4) 扩展加载完成后，经 CDP 打开 fixture 页面，验证 content script 注入
    //    content script 运行在 isolated world，须先 reload 捕获其执行上下文再求值。
    await cdp.send("Target.createTarget", { url: fixtureUrl });
    const page = await waitForTarget(cdp, (t) => t.type === "page" && t.url.includes("link-reliability"));
    let contentInjected = false;
    let injectedState = null;
    let isolatedCtx = null;
    if (page) {
      const pageSession = await attach(cdp, page.targetId);
      await cdp.send("Runtime.enable", {}, pageSession);
      await cdp.send("Page.enable", {}, pageSession);
      cdp.clearEvents();
      await cdp.send("Page.reload", {}, pageSession);
      isolatedCtx = await waitForIsolatedContext(cdp, 10000);
      if (isolatedCtx) {
        injectedState = await evaluateInContext(cdp, pageSession, isolatedCtx.id,
          `(() => { const s = window.__gestureKitPointerTrackerState; return s ? { linkClickProtectionEnabled: s.linkClickProtectionEnabled, hasLastPointer: s.lastPointer !== null } : null; })()`);
        contentInjected = Boolean(injectedState);
      }
      log(`[a] content script 注入（isolated world）= ${contentInjected}` +
        (injectedState ? ` state=${JSON.stringify(injectedState)}` : ""));

      // (d) leaseExpiry 复核
      await probeLeaseExpiry(cdp, pageSession, isolatedCtx, page.targetId);
    }

    // 5) (c) manifest 读取位置（复用已加载的扩展 SW）
    await probeManifestLocations(cdp, ourSw, idWithKey);

    return {
      a_loadable: Boolean(idWithKey && ourSw),
      a_contentScriptInjected: contentInjected,
      b_idWithKey: idWithKey,
      b_keyDerivedId: keyDerivedId,
      b_idNoKey: idNoKey,
      b_pathReal: pathReal,
      b_predictReal: predictReal,
      b_predictLiteral: predictLiteral,
      c_profileLevelRead: existsSync(MARKER_PROFILE),
      c_userLevelRead: existsSync(MARKER_USER),
    };
  } finally {
    chromeProc.kill("SIGKILL");
    await sleep(300);
    server.close();
  }
}

// ────────────────────────────────────────────────────────────────────
// 探针 (d)
// ────────────────────────────────────────────────────────────────────

async function probeLeaseExpiry(cdp, pageSession, isolatedCtx, pageTargetId) {
  log("=== 探针 (d)：leaseExpiry 复核（broken chain 下普通点击）===");
  // reload 后等页面完全就绪（#e2e-link 存在且有非零布局），避免点击过早被丢弃
  const readyDeadline = Date.now() + 8000;
  let ready = false;
  while (Date.now() < readyDeadline) {
    const st = await evaluateInSession(cdp, pageSession, `(() => {
      const el = document.querySelector('#e2e-link');
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return (document.readyState === "complete" && r.width > 0 && r.height > 0) || null;
    })()`);
    if (st) { ready = true; break; }
    await sleep(300);
  }
  await sleep(1000); // 额外稳定时间
  log(`[d] 页面就绪? ${ready}`);

  // 点击前：在 isolated world 检查 content script 状态（应无 guard、protection=false）
  const before = isolatedCtx ? await evaluateInContext(cdp, pageSession, isolatedCtx.id, `(() => {
    const s = window.__gestureKitPointerTrackerState;
    return s ? { linkClickProtectionEnabled: s.linkClickProtectionEnabled, protectedLinkClick: s.protectedLinkClick, pendingConsumedClick: s.pendingConsumedClick } : null;
  })()`) : null;
  log(`[d] 点击前 content script 状态（isolated world）: ${JSON.stringify(before)}`);

  const center = await evaluateInSession(cdp, pageSession, `(() => {
    const el = document.querySelector('#e2e-link');
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
  })()`);
  log(`[d] 链接中心坐标: ${JSON.stringify(center)}`);
  if (center) {
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: center.x, y: center.y }, pageSession);
    await sleep(100);
    await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", x: center.x, y: center.y, button: "left", clickCount: 1 }, pageSession);
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", x: center.x, y: center.y, button: "left", clickCount: 1 }, pageSession);
  }
  // 点击后立即读 isolated 状态（若上下文仍在）与 location，诊断是否被 content script 拦截
  await sleep(250);
  const postCtx = cdp.events.find((e) =>
    e.method === "Runtime.executionContextDestroyed" || e.method === "Runtime.executionContextsCleared");
  const postState = isolatedCtx ? await evaluateInContext(cdp, pageSession, isolatedCtx.id, `(() => {
    const s = window.__gestureKitPointerTrackerState;
    return s ? { protectedLinkClick: s.protectedLinkClick, lastLinkClick: s.lastLinkClick, pendingConsumedClick: s.pendingConsumedClick } : null;
  })()`).catch(() => "(context gone)") : null;
  const postHref = await evaluateInSession(cdp, pageSession, "location.href").catch(() => "(nav gone)");
  log(`[d] 点击后 250ms isolated 状态: ${JSON.stringify(postState)}；location.href=${postHref}${postCtx ? "（context 已销毁）" : ""}`);
  // example.test 导航到错误页后 TargetInfo.url 更新较慢（约 1~4s），等待足够长
  await sleep(4500);

  const targets = await cdp.send("Target.getTargets", {});
  const pages = (targets?.result?.targetInfos || []).filter((t) => t.type === "page");
  // 排除 about:blank（初始标签），找被点击的 fixture 标签（应已导航到 example.test 错误页）
  const pageNow = pages.find((t) => t.url !== "about:blank") || pages[0];
  const navigated = Boolean(pageNow && (pageNow.url === FIXED_TARGET_URL || pageNow.url.startsWith("https://example.test")));
  const pageCount = pages.length;
  log(`[d] 点击后全部 page target = ${pages.map((p) => p.url).join(" | ")}`);
  log(`[d] 普通点击是否正常导航（未拦截）= ${navigated}（page 数=${pageCount}）`);
  return { navigated, before };
}

// ────────────────────────────────────────────────────────────────────
// 探针 (c)
// ────────────────────────────────────────────────────────────────────

async function probeManifestLocations(cdp, ourSw, extensionId) {
  log("=== 探针 (c)：native messaging manifest 读取位置 ===");
  if (!ourSw || !extensionId) {
    log("[c] 未获取到扩展 service worker，跳过 manifest 位置测试");
    return;
  }
  const sessionId = await attach(cdp, ourSw.targetId);

  const renderHostScript = (markerPath) => `#!/bin/sh\nprintf 'probe %s\\n' "$(date +%s)" >> "${markerPath}"\nsleep 1\nexit 0\n`;
  const writeHost = (markerPath) => {
    const script = join(BASE, `marker-host-${Math.random().toString(36).slice(2)}.sh`);
    writeFileSync(script, renderHostScript(markerPath));
    chmodSync(script, 0o755);
    return script;
  };
  const manifestOf = (hostName, hostPath) => ({
    name: hostName,
    description: "GestureKit E2E probe native host (temporary)",
    path: hostPath,
    type: "stdio",
    allowed_origins: [`chrome-extension://${extensionId}/`],
  });

  const evalConnect = (hostName) => `(() => new Promise((resolve) => {
    let done = false;
    const finish = (obj) => { if (!done) { done = true; resolve(obj); } };
    try {
      const port = chrome.runtime.connectNative(${JSON.stringify(hostName)});
      port.onMessage.addListener((m) => finish({ msg: m }));
      port.onDisconnect.addListener(() => finish({ error: (chrome.runtime.lastError && chrome.runtime.lastError.message) || "disconnected" }));
      setTimeout(() => finish({ timeout: true }), 3000);
    } catch (e) {
      finish({ syncError: String((e && e.message) || e) });
    }
  }))()`;

  // 测试 1：profile 级 —— 独立 host 名，只写 <user-data-dir>/NativeMessagingHosts
  const profileHost = "com.gesturekit.host.e2e.probe.profile";
  log(`[c] 测试 1：profile 级 <user-data-dir>/NativeMessagingHosts（host=${profileHost}）`);
  const profileNmdDir = join(PROFILE_DIR, "NativeMessagingHosts");
  mkdirSync(profileNmdDir, { recursive: true });
  rmSync(MARKER_PROFILE, { force: true });
  writeFileSync(join(profileNmdDir, `${profileHost}.json`), JSON.stringify(manifestOf(profileHost, writeHost(MARKER_PROFILE))));
  const res1 = await evaluateInSession(cdp, sessionId, evalConnect(profileHost), true);
  await sleep(1200);
  const profileRead = existsSync(MARKER_PROFILE);
  log(`[c] profile 级 manifest 被读取? ${profileRead}  (connectNative 结果: ${JSON.stringify(res1)})`);

  // 测试 2：用户级 —— 独立 host 名，只写用户级目录（备份/恢复，绝不触碰真实 com.gesturekit.host）
  const userHost = "com.gesturekit.host.e2e.probe.user";
  log(`[c] 测试 2：用户级 NativeMessagingHosts（host=${userHost}）`);
  mkdirSync(USER_NMH_DIR, { recursive: true });
  const userManifestPath = join(USER_NMH_DIR, `${userHost}.json`);
  const hadBackup = existsSync(userManifestPath);
  const backupPath = hadBackup ? join(USER_NMH_DIR, `${userHost}.json.probe-bak`) : null;
  if (hadBackup) copyFileSync(userManifestPath, backupPath);
  rmSync(MARKER_USER, { force: true });
  writeFileSync(userManifestPath, JSON.stringify(manifestOf(userHost, writeHost(MARKER_USER))));
  try {
    const res2 = await evaluateInSession(cdp, sessionId, evalConnect(userHost), true);
    await sleep(1200);
    const userRead = existsSync(MARKER_USER);
    log(`[c] 用户级 manifest 被读取? ${userRead}  (connectNative 结果: ${JSON.stringify(res2)})`);
    rmSync(userManifestPath, { force: true });
    if (hadBackup) copyFileSync(backupPath, userManifestPath);
    log(`[c] 用户级 probe manifest 已移除${hadBackup ? "，备份已恢复" : ""}`);
  } catch (e) {
    rmSync(userManifestPath, { force: true });
    if (hadBackup) copyFileSync(backupPath, userManifestPath);
    throw e;
  }
}

// ────────────────────────────────────────────────────────────────────
// main
// ────────────────────────────────────────────────────────────────────

async function main() {
  if (!existsSync(CHROME)) {
    console.error(`[probe] Chrome 不存在: ${CHROME}（可用 CHROME_PATH 覆盖）`);
    process.exit(2);
  }
  if (!existsSync(join(EXT_SRC, "node_modules"))) {
    console.error(`[probe] 扩展依赖未安装: 请先 cd extensions/chrome && npm install`);
    process.exit(2);
  }

  mkdirSync(EXT_DIR, { recursive: true });
  mkdirSync(PROFILE_DIR, { recursive: true });

  try {
    const r = await probeLoadAndId();
    console.log("");
    console.log("========== 探针结论摘要 ==========");
    console.log(JSON.stringify({
      a_loadable: r.a_loadable,
      a_contentScriptInjected: r.a_contentScriptInjected,
      b_idWithKey: r.b_idWithKey,
      b_keyDerivedId: r.b_keyDerivedId,
      b_idNoKey: r.b_idNoKey,
      b_pathReal: r.b_pathReal,
      b_predictReal: r.b_predictReal,
      b_predictLiteral: r.b_predictLiteral,
      c_profileLevelRead: r.c_profileLevelRead,
      c_userLevelRead: r.c_userLevelRead,
    }, null, 2));
  } finally {
    try { rmSync(BASE, { recursive: true, force: true }); } catch {}
    log(`临时目录已清理: ${BASE}`);
  }
}

main().catch((e) => {
  console.error(`[probe] 失败: ${e?.message || e}`);
  try { rmSync(BASE, { recursive: true, force: true }); } catch {}
  process.exit(1);
});
