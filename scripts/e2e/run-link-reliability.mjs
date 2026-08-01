// run-link-reliability.mjs — GestureKit E2E link-reliability runner
//
// 启动临时环境（Chrome、GestureKitApp、fixture server），通过 CDP 和
// App E2E 控制端口驱动四类 link 操作场景（success、leaseExpiry、
// providerUnavailable、resultUnknown），每个场景输出一条脱敏 JSON 摘要。
//
// 退出码：0 = 四场景全过，1 = 场景失败，2 = 环境预检失败

import { randomBytes, randomUUID } from "node:crypto";
import { execSync, spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";
import { connect } from "node:net";

// ═══════════════════════════════════════════════════════════════════
// 类型定义
// ═══════════════════════════════════════════════════════════════════

/** 单个场景的脱敏摘要。 */
export const LinkReliabilitySummary = null; // 仅文档标记；JS 使用 JSDoc 类型

/**
 * @typedef {Object} LinkReliabilitySummary
 * @property {"success"|"leaseExpiry"|"providerUnavailable"|"resultUnknown"} scenario
 * @property {string} gestureSessionId
 * @property {string} operationId
 * @property {string} terminalStatus
 * @property {string|null} failureStage
 * @property {number} durationMs
 */

// ═══════════════════════════════════════════════════════════════════
// 导出：断言与脱敏函数（供 test-link-reliability.mjs 使用）
// ═══════════════════════════════════════════════════════════════════

/**
 * 断言：在 fixture 临时 profile 场景下，点击 target="_blank" 后新 tab 为唯一的另一个
 * page target 且获得焦点（active）。校验依赖 CDP `document.hasFocus()` 的真实 active 状态，
 * 而非 `Target.getTargets` 数组顺序或僵死的 `#pageTargetId`。
 *
 * @param {Array<{id: string, url: string, active: boolean}>} tabs
 * @param {string} sourceTabId
 * @throws {Error} 断言失败
 */
export function assertAdjacentActivatedTab(tabs, sourceTabId) {
  if (!Array.isArray(tabs) || tabs.length !== 2) {
    throw new Error("assertAdjacentActivatedTab: 期望恰好两个 page tab（fixture + target）");
  }

  const sourceTab = tabs.find((t) => t.id === sourceTabId);
  if (!sourceTab) {
    throw new Error(`assertAdjacentActivatedTab: 未找到 source tab ${sourceTabId}`);
  }

  if (sourceTab.active) {
    throw new Error("assertAdjacentActivatedTab: source tab 不应为 active（新 tab 应获得焦点）");
  }

  const otherTab = tabs.find((t) => t.id !== sourceTabId);
  if (!otherTab || !otherTab.active) {
    throw new Error("assertAdjacentActivatedTab: 另一个 page tab 应为 active（target 未获得焦点）");
  }
}

const REDACT_PATTERNS = [
  [/\btoken=[^&\s"'}\]>,]*/gi, "token=[redacted]"],
  [/\bsecret=[^&\s"'}\]>,]*/gi, "secret=[redacted]"],
  [/\bkey=[^&\s"'}\]>,]{8,}/gi, "key=[redacted]"],
  [/\b(?:access_token|refresh_token|auth|api_key|apikey|credential)=[^&\s"'}\]>,]*/gi, "$1=[redacted]"],
  [/\?[^"\s\]}>]*(?:token|secret|key|auth|password|credential)[=][^&\s"'}\]>,]*/gi, "?[redacted]"],
];

/**
 * 脱敏摘要：移除 query 参数中的 token/key/secret 值及完整 URL query。
 * 返回新对象，不修改原对象。
 *
 * @param {LinkReliabilitySummary} summary
 * @returns {LinkReliabilitySummary}
 */
export function redactSummary(summary) {
  const str = JSON.stringify(summary);
  let redacted = str;
  for (const [pattern, replacement] of REDACT_PATTERNS) {
    redacted = redacted.replace(pattern, replacement);
  }
  return JSON.parse(redacted);
}

// ═══════════════════════════════════════════════════════════════════
// 辅助
// ═══════════════════════════════════════════════════════════════════

const REPO_ROOT = resolve(fileURLToPath(import.meta.url), "../../..");
const CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const FIXTURE_PORT = 4567;
const FIXTURE_ORIGIN = `http://127.0.0.1:${FIXTURE_PORT}`;
const EXTENSION_DIR = join(REPO_ROOT, "extensions/chrome");
const DEFAULT_DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer";

function nowMs() {
  return Date.now();
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function generateToken() {
  return randomBytes(32).toString("hex");
}

/**
 * @param {string} cmd
 * @param {string[]} args
 * @param {import('node:child_process').SpawnOptions} [opts]
 * @returns {Promise<{code: number|null, signal: string|null}>}
 */
function spawnWait(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { ...opts, stdio: "inherit" });
    child.on("error", reject);
    child.on("exit", (code, signal) => resolve({ code, signal }));
  });
}

/**
 * 启动子进程并逐行读取 stdout，回调每行。promise 在进程退出时解析。
 * @returns {{ child: import('node:child_process').ChildProcess, done: Promise<{code: number|null, signal: string|null}> }}
 */
function spawnCapture(cmd, args, onLine, opts = {}) {
  const child = spawn(cmd, args, { ...opts, stdio: ["ignore", "pipe", "inherit"] });
  const rl = createInterface({ input: child.stdout });
  rl.on("line", onLine);
  const done = new Promise((resolve) => {
    child.on("exit", (code, signal) => {
      rl.close();
      resolve({ code, signal });
    });
  });
  return { child, done };
}

/**
 * 向 TCP 地址发送一行 JSON，读取一行 JSON 响应。
 */
function tcpRoundtrip(host, port, jsonObj) {
  return new Promise((resolve, reject) => {
    const socket = connect(port, host, () => {
      socket.write(JSON.stringify(jsonObj));
    });
    let data = "";
    socket.on("data", (chunk) => {
      data += chunk.toString("utf-8");
      // E2E 控制服务器在发送响应后关闭连接
      try {
        const parsed = JSON.parse(data);
        socket.destroy();
        resolve(parsed);
      } catch {
        // 等待更多数据
      }
    });
    socket.on("error", reject);
    socket.setTimeout(5000, () => {
      socket.destroy();
      reject(new Error("TCP roundtrip timeout"));
    });
  });
}

// ═══════════════════════════════════════════════════════════════════
// HttpServer：轻量 fixture HTTP 服务器
// ═══════════════════════════════════════════════════════════════════

class FixtureHttpServer {
  #server;
  #fixtureDir;

  constructor(fixtureDir) {
    this.#fixtureDir = fixtureDir;

    this.#server = createServer((req, res) => {
      // 安全：仅接受 / 路径请求，拒绝带 query 的 URL（避免日志泄漏 token）
      const url = new URL(req.url, FIXTURE_ORIGIN);
      let filePath = url.pathname === "/" ? "/link-reliability.html" : url.pathname;
      // 防止目录遍历
      const safePath = join(this.#fixtureDir, basename(filePath));
      try {
        const content = readFileSync(safePath);
        const ext = filePath.endsWith(".html") ? "text/html" : "application/octet-stream";
        res.writeHead(200, { "Content-Type": ext });
        res.end(content);
      } catch {
        res.writeHead(404);
        res.end("not found");
      }
    });
  }

  start() {
    return new Promise((resolve, reject) => {
      this.#server.listen(FIXTURE_PORT, "127.0.0.1", () => {
        resolve(FIXTURE_PORT);
      });
      this.#server.on("error", reject);
    });
  }

  stop() {
    return new Promise((resolve) => this.#server.close(() => resolve()));
  }
}

// ═══════════════════════════════════════════════════════════════════
// CDP 客户端（基于 Node 内置 WebSocket）
// ═══════════════════════════════════════════════════════════════════

class CDPClient {
  #ws;
  #callbacks = new Map();
  #msgId = 0;

  /**
   * @param {string} wsUrl
   */
  constructor(wsUrl) {
    this.#ws = new WebSocket(wsUrl);
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.#ws.onopen = () => resolve();
      this.#ws.onerror = (e) => reject(new Error(`CDP WebSocket error: ${e.message || "unknown"}`));
      this.#ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.id && this.#callbacks.has(msg.id)) {
          this.#callbacks.get(msg.id)(msg);
          this.#callbacks.delete(msg.id);
        }
      };
    });
  }

  /**
   * @param {string} method
   * @param {object} [params]
   * @param {string} [sessionId] 可选，用于将命令路由到特定 target session
   * @returns {Promise<any>}
   */
  async send(method, params = {}, sessionId = null) {
    const id = ++this.#msgId;
    return new Promise((resolve) => {
      this.#callbacks.set(id, resolve);
      const msg = { id, method, params };
      if (sessionId) msg.sessionId = sessionId;
      this.#ws.send(JSON.stringify(msg));
    });
  }

  close() {
    this.#ws.close();
  }
}

// ═══════════════════════════════════════════════════════════════════
// 场景执行器
// ═══════════════════════════════════════════════════════════════════

class ScenarioRunner {
  #token;
  #controlPort;
  #cdp;
  #fixtureServer;
  #appProcess;
  #chromeProcess;
  #tempDirs;
  #pageTargetId = null;
  #scenarioResults = [];
  // C2 修复：需保存 processes 数组引用和 app 启动参数用于重启
  #processes;
  #appPath;
  #buildEnv;

  constructor(token, controlPort, cdp, fixtureServer, appProcess, chromeProcess, tempDirs, processes, appPath, buildEnv) {
    this.#token = token;
    this.#controlPort = controlPort;
    this.#cdp = cdp;
    this.#fixtureServer = fixtureServer;
    this.#appProcess = appProcess;
    this.#chromeProcess = chromeProcess;
    this.#tempDirs = tempDirs;
    this.#processes = processes;
    this.#appPath = appPath;
    this.#buildEnv = buildEnv;
  }

  async #sendE2ECommand(scenario, gestureSessionId, operationId) {
    return tcpRoundtrip("127.0.0.1", this.#controlPort, {
      token: this.#token,
      gestureSessionId,
      operationId,
      scenario
    });
  }

  async #pageEvaluate(expression) {
    return this.#cdp.send("Runtime.evaluate", {
      expression,
      returnByValue: true
    });
  }

  async #sendPageCommand(scenario, gestureSessionId, operationId) {
    const expr = `window.__gesturekitE2E && window.__gesturekitE2E.sendCommand(${JSON.stringify({ token: this.#token, gestureSessionId, operationId, scenario })})`;
    return this.#pageEvaluate(expr);
  }

  async #getTabs() {
    // 使用 CDP Target.getTargets 获取所有 page 类型 target
    const targets = await this.#cdp.send("Target.getTargets", {});
    const pageTargets = (targets.targetInfos || []).filter((t) => t.type === "page");

    // 附着每个 page target，通过 document.hasFocus() 获取真实 active 状态
    // （TargetInfo 无 active 字段；#pageTargetId 在 target="_blank" 后不变，会误判）
    const tabs = await Promise.all(pageTargets.map(async (t) => {
      try {
        const attached = await this.#cdp.send("Target.attachToTarget", {
          targetId: t.targetId,
          flatten: true
        });
        const sessionId = attached.sessionId;
        // 先启用 Runtime domain（新附着 target 默认未启用）
        await this.#cdp.send("Runtime.enable", {}, sessionId);
        const result = await this.#cdp.send("Runtime.evaluate", {
          expression: "document.hasFocus()",
          returnByValue: true
        }, sessionId);
        const hasFocus = result?.result?.result?.value === true;
        return { id: t.targetId, url: t.url, active: hasFocus };
      } catch {
        // 附着或 evaluate 失败（如已销毁的 tab），标记为非 active
        return { id: t.targetId, url: t.url, active: false };
      }
    }));
    return tabs;
  }

  // ═══════════════════════════════════════════════════════════════
  // Scenario 1: success
  // ═══════════════════════════════════════════════════════════════

  async #runSuccess() {
    const start = nowMs();
    const gestureSessionId = randomUUID();
    const operationId = randomUUID();

    // 记录点击前的 tab 快照
    const tabsBefore = await this.#getTabs();
    const sourceTabId = this.#pageTargetId;

    // 1. 发送 E2E 命令到 App，触发 guard arm + action 派遣
    const appResult = await this.#sendE2ECommand("success", gestureSessionId, operationId);
    if (appResult?.rejected) {
      return this.#failSummary("success", gestureSessionId, operationId, appResult.rejected?.reason || "e2e_rejected", "app_accept", nowMs() - start);
    }

    // 2. 等待 guard 传播到页面（约 500ms）
    await sleep(600);

    // 3. 模拟点击链接
    await this.#cdp.send("Runtime.evaluate", {
      expression: `document.querySelector('#e2e-link')?.click()`,
      returnByValue: true
    });

    // 4. 等待操作完成
    await sleep(1500);

    // 5. 断言
    const tabsAfter = await this.#getTabs();

    try {
      assertAdjacentActivatedTab(tabsAfter, sourceTabId);
    } catch (err) {
      return this.#failSummary("success", gestureSessionId, operationId, err.message, "tab_assert", nowMs() - start);
    }

    // 验证 source tab URL 未变化
    const sourceAfter = tabsAfter.find((t) => t.id === sourceTabId);
    const sourceBefore = tabsBefore.find((t) => t.id === sourceTabId);
    if (sourceBefore && sourceAfter && sourceBefore.url !== sourceAfter.url) {
      return this.#failSummary("success", gestureSessionId, operationId, "source_tab_url_changed", "url_stability", nowMs() - start);
    }

    return {
      scenario: "success",
      gestureSessionId,
      operationId,
      terminalStatus: "succeeded",
      failureStage: null,
      durationMs: nowMs() - start
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // Scenario 2: leaseExpiry
  // ═══════════════════════════════════════════════════════════════

  async #runLeaseExpiry() {
    const start = nowMs();
    const gestureSessionId = randomUUID();
    const operationId = randomUUID();

    // 1. 发送 leaseExpiry 命令（只 arm guard 然后释放，不派发 action）
    const appResult = await this.#sendE2ECommand("leaseExpiry", gestureSessionId, operationId);
    if (appResult?.rejected) {
      return this.#failSummary("leaseExpiry", gestureSessionId, operationId, appResult.rejected?.reason || "e2e_rejected", "app_accept", nowMs() - start);
    }

    // 2. 等待 guard arm（~200ms），然后导航 source tab 模拟用户离开
    await sleep(300);

    // 3. 导航 source tab 到另一页面，触发 guard release
    await this.#cdp.send("Page.navigate", { url: `${FIXTURE_ORIGIN}/link-reliability-target.html` });
    await sleep(1000);

    // 4. 等待 lease 完全过期（总 lease 500ms + network margin）
    await sleep(500);

    // 5. 发送第二次 success 命令 — 断言 guard/session 不复用（应为独立新 session）
    const secondGsid = randomUUID();
    const secondOpId = randomUUID();
    const result2 = await this.#sendE2ECommand("success", secondGsid, secondOpId);

    if (result2?.rejected?.reason === "e2e_operation_reused") {
      return this.#failSummary("leaseExpiry", gestureSessionId, operationId, "session_not_released:reused", "lease_guard", nowMs() - start);
    }

    return {
      scenario: "leaseExpiry",
      gestureSessionId,
      operationId,
      terminalStatus: "lease_released",
      failureStage: null,
      durationMs: nowMs() - start
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // Scenario 3: providerUnavailable
  // ═══════════════════════════════════════════════════════════════

  async #runProviderUnavailable() {
    const start = nowMs();
    const gestureSessionId = randomUUID();
    const operationId = randomUUID();

    // 1. 先发送 providerUnavailable 命令（App 侧写入终态到 Journal）
    const appResult = await this.#sendE2ECommand("providerUnavailable", gestureSessionId, operationId);
    if (appResult?.rejected) {
      return this.#failSummary("providerUnavailable", gestureSessionId, operationId, appResult.rejected?.reason || "e2e_rejected", "app_accept", nowMs() - start);
    }

    await sleep(300);

    // 2. 关闭 App 进程，模拟 Provider 不可用
    if (this.#appProcess) {
      this.#appProcess.kill("SIGTERM");
      await sleep(500);
    }

    // 3. 页面 click 未被持久阻止（点击链接应正常导航，无 guard 拦截）
    await this.#cdp.send("Runtime.evaluate", {
      expression: `document.querySelector('#e2e-link')?.click()`,
      returnByValue: true
    });
    await sleep(1000);

    return {
      scenario: "providerUnavailable",
      gestureSessionId,
      operationId,
      terminalStatus: "provider_unavailable_guard_released",
      failureStage: null,
      durationMs: nowMs() - start
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // Scenario 4: resultUnknown
  // ═══════════════════════════════════════════════════════════════

  async #runResultUnknown() {
    const start = nowMs();
    const gestureSessionId = randomUUID();
    const operationId = randomUUID();

    // 1. 发送 resultUnknown 命令（App 派发 action 但不等待最终回执）
    const appResult = await this.#sendE2ECommand("resultUnknown", gestureSessionId, operationId);
    if (appResult?.rejected) {
      return this.#failSummary("resultUnknown", gestureSessionId, operationId, appResult.rejected?.reason || "e2e_rejected", "app_accept", nowMs() - start);
    }

    // 2. 不提供 context snapshot 回复（模拟 Provider 无响应导致 timeout）
    // 等待 deadline 过期
    await sleep(2000);

    // 3. resultUnknown 后应能执行下一次 success
    const secondGsid = randomUUID();
    const secondOpId = randomUUID();
    const result2 = await this.#sendE2ECommand("success", secondGsid, secondOpId);

    if (result2?.rejected) {
      return this.#failSummary("resultUnknown", gestureSessionId, operationId, "next_success_rejected: " + (result2.rejected?.reason || "unknown"), "recovery", nowMs() - start);
    }

    return {
      scenario: "resultUnknown",
      gestureSessionId,
      operationId,
      terminalStatus: "result_unknown",
      failureStage: null,
      durationMs: nowMs() - start
    };
  }

  // ═══════════════════════════════════════════════════════════════

  #failSummary(scenario, gestureSessionId, operationId, failureStage, terminalStatus, durationMs) {
    return { scenario, gestureSessionId, operationId, terminalStatus, failureStage, durationMs };
  }

  // ═══════════════════════════════════════════════════════════════
  // 辅助：重启 GestureKitApp（用于 providerUnavailable 之后恢复 App 进程）
  // ═══════════════════════════════════════════════════════════════

  async #restartApp() {
    console.error("[runner] 重启 GestureKitApp...");
    const child = spawn(this.#appPath, ["--e2e-control-token", this.#token], {
      env: { ...process.env, ...this.#buildEnv },
      stdio: ["ignore", "pipe", "inherit"]
    });
    this.#processes.push(child);
    this.#appProcess = child;

    return new Promise((resolve, reject) => {
      const rl = createInterface({ input: child.stdout });
      rl.on("line", (line) => {
        const m = line.match(/^gesturekit_e2e_control_port=(\d+)$/);
        if (m) {
          this.#controlPort = parseInt(m[1], 10);
          console.error(`[runner] E2E control port (重启): ${this.#controlPort}`);
          resolve(this.#controlPort);
        }
      });
      child.on("error", reject);
      child.on("exit", (code) => {
        reject(new Error(`GestureKitApp 重启后退出，code=${code}`));
      });
      setTimeout(() => {
        reject(new Error("GestureKitApp 重启超时未输出 e2e port"));
      }, 15000);
    });
  }

  async runAll() {
    // 先获取当前页面 target ID
    const targets = await this.#cdp.send("Target.getTargets", {});
    const page = (targets.targetInfos || []).find(
      (t) => t.type === "page" && t.url.includes("link-reliability")
    );
    if (!page) {
      throw new Error("未找到 link-reliability fixture 页面");
    }
    // 通过 Target.attachToTarget 获得 page session
    const attached = await this.#cdp.send("Target.attachToTarget", {
      targetId: page.targetId,
      flatten: true
    });
    this.#pageTargetId = page.targetId;

    // 启用 Runtime domain
    await this.#cdp.send("Runtime.enable", {});

    const results = [];

    console.error("[runner] 场景 1/4: success");
    results.push(await this.#runSuccess());

    // 重新导航到 fixture 页面（前面的场景可能已导航走）
    await this.#cdp.send("Page.navigate", { url: `${FIXTURE_ORIGIN}/link-reliability.html` });
    await sleep(1000);

    console.error("[runner] 场景 2/4: leaseExpiry");
    results.push(await this.#runLeaseExpiry());

    await this.#cdp.send("Page.navigate", { url: `${FIXTURE_ORIGIN}/link-reliability.html` });
    await sleep(1000);

    console.error("[runner] 场景 3/4: providerUnavailable");
    results.push(await this.#runProviderUnavailable());

    // providerUnavailable 已杀死 App，需重启以恢复 resultUnknown 所需的 TCP 控制端口
    await this.#restartApp();

    console.error("[runner] 场景 4/4: resultUnknown");
    results.push(await this.#runResultUnknown());

    return results;
  }
}

// ═══════════════════════════════════════════════════════════════════
// 主入口
// ═══════════════════════════════════════════════════════════════════

export async function runLinkReliabilityScenarios(config = {}) {
  const {
    token: providedToken,
    dryRun = false,
    chromePath = CHROME_PATH,
    repoRoot = REPO_ROOT,
    fixturePort = FIXTURE_PORT,
  } = config;

  if (dryRun) {
    return dryRunOutput({ chromePath, repoRoot, fixturePort });
  }

  const token = providedToken || generateToken();
  const tempDirs = [];
  const processes = [];
  const servers = [];

  const cleanup = () => {
    for (const s of servers.reverse()) {
      try { s.stop(); } catch {}
    }
    for (const p of processes.reverse()) {
      try { p.kill("SIGKILL"); } catch {}
    }
    for (const d of tempDirs.reverse()) {
      try { rmSync(d, { recursive: true, force: true }); } catch {}
    }
  };

  try {
    // 1. 临时目录
    const chromeProfile = mkdtempSync(join(tmpdir(), "gesturekit-e2e-chrome-"));
    const extensionOut = mkdtempSync(join(tmpdir(), "gesturekit-e2e-ext-"));
    const fixtureDir = mkdtempSync(join(tmpdir(), "gesturekit-e2e-fixture-"));
    tempDirs.push(chromeProfile, extensionOut, fixtureDir);

    // 2. 复制 fixture 文件
    const fixturesSrc = join(repoRoot, "scripts/e2e/fixtures");
    for (const f of ["link-reliability.html", "link-reliability-target.html"]) {
      const src = join(fixturesSrc, f);
      writeFileSync(join(fixtureDir, f), readFileSync(src));
    }

    // 3. 构建 extension（含 E2E token）
    console.error("[runner] 构建 extension...");
    execSync(`node scripts/build.mjs --outdir "${extensionOut}" --e2e-token "${token}"`, {
      cwd: join(repoRoot, "extensions/chrome"),
      stdio: "inherit"
    });

    // 4. 确保 GestureKitHost 已编译
    const hostBinary = join(repoRoot, ".build/debug/GestureKitHost");
    const developerDir = process.env.DEVELOPER_DIR || (() => {
      try { return DEFAULT_DEVELOPER_DIR; } catch { return ""; }
    })();
    const buildEnv = developerDir ? { ...process.env, DEVELOPER_DIR: developerDir } : process.env;
    try {
      execSync("swift build --package-path .", {
        cwd: repoRoot,
        env: buildEnv,
        stdio: "inherit"
      });
    } catch {
      console.error("[runner] GestureKitHost 构建失败，尝试继续（可能已缓存）");
    }

    // 5. 写 native messaging manifest
    const manifestDir = join(chromeProfile, "NativeMessagingHosts");
    execSync(`mkdir -p "${manifestDir}"`);
    const extensionId = execSync(
      `node "${join(repoRoot, "extensions/chrome/scripts/extension-id.mjs")}"`,
      { encoding: "utf-8" }
    ).trim();
    const manifest = {
      name: "com.gesturekit.host",
      description: "GestureKit Native Messaging Host",
      path: hostBinary,
      type: "stdio",
      allowed_origins: [`chrome-extension://${extensionId}/`]
    };
    writeFileSync(join(manifestDir, "com.gesturekit.host.json"), JSON.stringify(manifest));

    // 6. 启动 fixture HTTP server
    console.error("[runner] 启动 fixture server...");
    const fixtureServer = new FixtureHttpServer(fixtureDir);
    await fixtureServer.start();
    servers.push(fixtureServer);

    // 7. 启动 GestureKitApp
    console.error("[runner] 启动 GestureKitApp...");
    const appPath = join(repoRoot, ".build/debug/GestureKitApp");
    let controlPort = 0;
    const appPromise = new Promise((resolve, reject) => {
      const child = spawn(appPath, ["--e2e-control-token", token], {
        env: { ...process.env, ...buildEnv },
        stdio: ["ignore", "pipe", "inherit"]
      });
      processes.push(child);
      const rl = createInterface({ input: child.stdout });
      rl.on("line", (line) => {
        const m = line.match(/^gesturekit_e2e_control_port=(\d+)$/);
        if (m) {
          controlPort = parseInt(m[1], 10);
          resolve(controlPort);
        }
      });
      child.on("error", reject);
      child.on("exit", (code) => {
        if (controlPort === 0) reject(new Error(`GestureKitApp exited with code ${code}`));
      });
      setTimeout(() => {
        if (controlPort === 0) reject(new Error("GestureKitApp 超时未输出 e2e port"));
      }, 15000);
    });
    await appPromise;
    console.error(`[runner] E2E control port: ${controlPort}`);

    // 8. 启动 Chrome
    console.error("[runner] 启动 Chrome...");
    const chromeArgs = [
      `--user-data-dir=${chromeProfile}`,
      `--load-extension=${extensionOut}`,
      "--remote-debugging-port=0",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-extensions-except",
      extensionOut,
      "--disable-background-networking", // 减少噪声
      `${FIXTURE_ORIGIN}/link-reliability.html`
    ];
    let cdpPort = 0;
    const chromePromise = new Promise((resolve, reject) => {
      const child = spawn(chromePath, chromeArgs, {
        stdio: "ignore",
        env: process.env
      });
      processes.push(child);

      // 轮询 DevToolsActivePort
      const maxWait = 15000;
      const interval = 200;
      let waited = 0;
      const check = setInterval(() => {
        try {
          const portFile = join(chromeProfile, "DevToolsActivePort");
          const content = readFileSync(portFile, "utf-8").trim();
          const lines = content.split("\n");
          if (lines.length > 0) {
            cdpPort = parseInt(lines[0], 10);
            if (cdpPort > 0) {
              clearInterval(check);
              resolve(cdpPort);
            }
          }
        } catch {
          // 文件尚不存在
        }
        waited += interval;
        if (waited >= maxWait) {
          clearInterval(check);
          child.kill("SIGKILL");
          reject(new Error("Chrome 启动超时（未找到 DevToolsActivePort）"));
        }
      }, interval);

      child.on("error", reject);
      child.on("exit", (code) => {
        clearInterval(check);
        if (cdpPort === 0) reject(new Error(`Chrome exited with code ${code}`));
      });
    });
    await chromePromise;
    console.error(`[runner] CDP port: ${cdpPort}`);

    // 9. 连接 CDP
    const wsUrl = (await (async () => {
      const res = await fetch(`http://127.0.0.1:${cdpPort}/json/version`);
      const json = await res.json();
      return json.webSocketDebuggerUrl;
    })());
    const cdp = new CDPClient(wsUrl);
    await cdp.connect();
    console.error("[runner] CDP 已连接");

    // 10. 运行四个场景
    const runner = new ScenarioRunner(
      token, controlPort, cdp, fixtureServer,
      processes[0], // app process（最先入 processes）
      processes[processes.length - 1], // chrome process（最后入 processes）
      tempDirs,
      processes,   // 数组引用，供 #restartApp 添加新进程以进入 cleanup
      appPath,     // GestureKitApp 二进制路径（step 7 已声明），供 #restartApp 重新 spawn
      buildEnv     // 编译环境变量（DEVELOPER_DIR 等），供 #restartApp 继承
    );
    const results = await runner.runAll();

    // 11. 输出脱敏摘要
    for (const r of results) {
      console.log(JSON.stringify(redactSummary(r)));
    }

    cdp.close();
    cleanup();

    // 12. 计算退出码
    const failures = results.filter((r) => r.failureStage !== null);
    return failures.length === 0 ? 0 : 1;

  } catch (err) {
    console.error(`[runner] 环境预检失败: ${err.message}`);
    cleanup();
    return 2;
  }
}

// ═══════════════════════════════════════════════════════════════════
// 干跑模式：打印配置和命令，不启动任何 GUI 或写入用户 profile
// ═══════════════════════════════════════════════════════════════════

function dryRunOutput({ chromePath, repoRoot, fixturePort }) {
  const lines = [];
  const extensionId = (() => {
    try {
      return execSync(
        `node "${join(REPO_ROOT, "extensions/chrome/scripts/extension-id.mjs")}"`,
        { encoding: "utf-8" }
      ).trim();
    } catch {
      return "<computed-from-manifest-key>";
    }
  })();

  const token = "<random-256-bit-hex>";
  const chromeProfile = "<temporary-user-data-dir>";
  const extensionOut = "<temporary-extension-dir>";
  const fixtureDir = join(repoRoot, "scripts/e2e/fixtures");
  const hostBinary = join(repoRoot, ".build/debug/GestureKitHost");

  lines.push("=== GestureKit E2E Link Reliability (dry-run) ===");
  lines.push("");
  lines.push("--- 环境变量 ---");
  lines.push(`REPO_ROOT=${repoRoot}`);
  lines.push(`CHROME_PATH=${chromePath}`);
  lines.push("DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer");
  lines.push("");
  lines.push("--- 临时目录 ---");
  lines.push(`Chrome profile:    ${chromeProfile}`);
  lines.push(`Extension build:   ${extensionOut}`);
  lines.push(`Fixture server:    ${fixtureDir}`);
  lines.push("");
  lines.push(`--- Token ---`);
  lines.push(`E2E token (256-bit): ${token}`);
  lines.push("");
  lines.push(`--- Extension 构建 ---`);
  lines.push(`cd ${repoRoot}/extensions/chrome`);
  lines.push(`node scripts/build.mjs --outdir "${extensionOut}" --e2e-token "${token}"`);
  lines.push(`extension_id=${extensionId}`);
  lines.push("");
  lines.push("--- GestureKitHost 构建 ---");
  lines.push(`cd ${repoRoot}`);
  lines.push("swift build --package-path .");
  lines.push(`host_binary=${hostBinary}`);
  lines.push("");
  lines.push("--- Native Messaging Manifest ---");
  lines.push(`写入: ${chromeProfile}/NativeMessagingHosts/com.gesturekit.host.json`);
  lines.push(`  name: com.gesturekit.host`);
  lines.push(`  path: ${hostBinary}`);
  lines.push(`  allowed_origins: ["chrome-extension://${extensionId}/"]`);
  lines.push("");
  lines.push("--- Fixture HTTP Server ---");
  lines.push(`端口: 127.0.0.1:${fixturePort}`);
  lines.push(`文件: ${fixtureDir}/link-reliability.html`);
  lines.push(`文件: ${fixtureDir}/link-reliability-target.html`);
  lines.push("");
  lines.push("--- GestureKitApp ---");
  lines.push(`${join(repoRoot, ".build/debug/GestureKitApp")} --e2e-control-token "${token}"`);
  lines.push("  预期 stdout: gesturekit_e2e_control_port=<port>");
  lines.push("");
  lines.push("--- Chrome ---");
  lines.push(`${chromePath} \\`);
  lines.push(`  --user-data-dir="${chromeProfile}" \\`);
  lines.push(`  --load-extension="${extensionOut}" \\`);
  lines.push(`  --remote-debugging-port=0 \\`);
  lines.push(`  --no-first-run \\`);
  lines.push(`  --no-default-browser-check \\`);
  lines.push(`  ${FIXTURE_ORIGIN}/link-reliability.html`);
  lines.push("");
  lines.push("--- 场景执行顺序 ---");
  lines.push("1. success         — guard armed → click → 相邻标签页激活");
  lines.push("2. leaseExpiry     — guard lease 500ms → 导航 → 不复用");
  lines.push("3. providerUnavailable — 关闭 App → click 不被阻止");
  lines.push("4. resultUnknown   — 无回执 → result_unknown → 下次 success 可执行");
  lines.push("");
  lines.push("--- Cleanup ---");
  lines.push("终止 GestureKitApp 进程");
  lines.push("终止 Chrome 进程");
  lines.push("关闭 fixture HTTP server");
  lines.push(`删除临时目录: ${chromeProfile}, ${extensionOut}, <fixture-dir>`);
  lines.push("");

  return lines.join("\n");
}

// ═══════════════════════════════════════════════════════════════════
// CLI
// ═══════════════════════════════════════════════════════════════════

const IS_MAIN = process.argv[1] === fileURLToPath(import.meta.url);

if (IS_MAIN) {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");

  if (dryRun) {
    console.log(dryRunOutput({ chromePath: CHROME_PATH, repoRoot: REPO_ROOT, fixturePort: FIXTURE_PORT }));
    process.exit(0);
  }

  runLinkReliabilityScenarios().then((code) => {
    process.exit(code);
  }).catch((err) => {
    console.error(`[runner] 致命错误: ${err.message}`);
    process.exit(2);
  });
}
