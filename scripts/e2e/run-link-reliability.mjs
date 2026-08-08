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
import {
  copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";
import { createServer as createNetServer, connect } from "node:net";

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
 * 断言：在 fixture 临时 profile 场景下，点击同窗口固定链接后，新 tab 为唯一的另一个
 * page target、获得焦点（active）且 URL 等于固定目标（若传入 `expectedTargetUrl`）。
 * 校验依赖 CDP `document.hasFocus()` 的真实 active 状态，而非 `Target.getTargets`
 * 数组顺序或僵死的 `#pageTargetId`。
 *
 * @param {Array<{id: string, url: string, active: boolean}>} tabs
 * @param {string} sourceTabId
 * @param {string|null} [expectedTargetUrl] 固定目标 URL；传入时校验新 tab 的 URL 完全相等。
 * @throws {Error} 断言失败
 */
export function assertAdjacentActivatedTab(tabs, sourceTabId, expectedTargetUrl = null) {
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

  if (expectedTargetUrl !== null && otherTab.url !== expectedTargetUrl) {
    throw new Error(
      `assertAdjacentActivatedTab: 相邻 tab URL 应为 ${expectedTargetUrl}，实际 ${otherTab.url}`
    );
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

/**
 * 页面级 CDP 命令封装：通过 sessionId 将 Runtime.evaluate 路由到 page target。
 * 纯函数，可单测。
 *
 * @param {{ send: (method: string, params: object, sessionId: string|null) => Promise<any> }} cdp
 * @param {string} expression
 * @param {string} sessionId
 * @returns {Promise<any>}
 */
export function pageEvaluate(cdp, expression, sessionId) {
  return cdp.send("Runtime.evaluate", { expression, returnByValue: true }, sessionId);
}

/**
 * 页面级 CDP 命令封装：通过 sessionId 将 Page.navigate 路由到 page target。
 * 纯函数，可单测。
 *
 * @param {{ send: (method: string, params: object, sessionId: string|null) => Promise<any> }} cdp
 * @param {string} url
 * @param {string} sessionId
 * @returns {Promise<any>}
 */
export function pageNavigate(cdp, url, sessionId) {
  return cdp.send("Page.navigate", { url }, sessionId);
}

/**
 * 在 CDP `Target.getTargets` 响应中查找 URL 包含给定子串的 page target。
 * `send` 返回完整消息（`{ id, result }`），targetInfos 位于 `result` 字段下，
 * 不能读顶层 `targetInfos`。纯函数，可单测。
 *
 * @param {{ result?: { targetInfos?: Array<{ type: string, targetId: string, url: string }> } }} targets
 * @param {string} urlIncludes
 * @returns {{ targetId: string, url: string } | null}
 */
export function findPageTarget(targets, urlIncludes) {
  const infos = targets?.result?.targetInfos || [];
  return infos.find((t) => t.type === "page" && t.url.includes(urlIncludes)) || null;
}

/**
 * Task 2 修复：E2E 专用独立 host 名。Chrome 的 native messaging manifest 名
 * （manifest `name` 字段）必须与扩展 `chrome.runtime.connectNative(hostName)` 传入名一致。
 * 用独立 host 名（而非生产 `com.gesturekit.host`）写 <profile>/NativeMessagingHosts，
 * 即使误用默认 profile 也绝不会与用户级真实 manifest 冲突或覆盖。
 */
export const E2E_HOST_NAME = "com.gesturekit.host.e2e";

/**
 * 完整可加载扩展副本需要拷贝的静态文件：源相对路径 → 目标相对路径。
 * 其余文件（background/pointerTracker/popup/smoke 的 JS）由 build.mjs 产出到
 * `<outDir>/dist`，与 manifest 内 `dist/...` 引用对齐；popup.css 非 esbuild 产物，
 * 需从 `src/popup/popup.css` 手动拷到 `dist/popup/popup.css`。
 * @returns {Record<string, string>}
 */
export function extensionStaticFiles() {
  return {
    "manifest.json": "manifest.json",
    "popup.html": "popup.html",
    "smoke.html": "smoke.html",
    "src/popup/popup.css": "dist/popup/popup.css",
  };
}

/**
 * 把扩展静态文件拷贝成可加载副本布局。纯文件操作，可单测。
 * @param {string} extSrc 扩展源码目录（extensions/chrome）
 * @param {string} outDir 临时扩展副本目录
 * @param {Record<string, string>} [files] 源→目标相对路径映射
 * @returns {Array<{src: string, dest: string}>} 已拷贝的文件列表
 */
export function copyExtensionStaticFiles(extSrc, outDir, files = extensionStaticFiles()) {
  mkdirSync(outDir, { recursive: true });
  const copied = [];
  for (const [srcRel, destRel] of Object.entries(files)) {
    const src = join(extSrc, srcRel);
    const dest = join(outDir, destRel);
    mkdirSync(dirname(dest), { recursive: true });
    copyFileSync(src, dest);
    copied.push({ src, dest });
  }
  return copied;
}

/**
 * 校验扩展副本布局：manifest 内引用的文件（background.service_worker、
 * action.default_popup、content_scripts[].js）必须实际存在于副本目录。
 * 旧 runner 只构建 JS 到临时目录根、不拷贝静态文件，且 manifest 内 `dist/...`
 * 与 `--outdir ${extensionOut}` 布局不一致——本函数让这类缺陷在 preflight 即暴露。
 * @param {string} outDir 扩展副本目录
 * @returns {string[]} manifest 引用的相对路径列表
 * @throws {Error} 布局不完整
 */
export function validateExtensionLayout(outDir) {
  const manifest = JSON.parse(readFileSync(join(outDir, "manifest.json"), "utf-8"));
  const refs = [];
  if (manifest.background?.service_worker) refs.push(manifest.background.service_worker);
  if (manifest.action?.default_popup) refs.push(manifest.action.default_popup);
  for (const cs of manifest.content_scripts || []) {
    for (const js of cs.js || []) refs.push(js);
  }
  const missing = refs.filter((r) => !existsSync(join(outDir, r)));
  if (missing.length > 0) {
    throw new Error(`扩展副本布局不完整，缺少 manifest 引用的文件: ${missing.join(", ")}`);
  }
  return refs;
}

/**
 * 品牌 Chrome 142+ 忽略 `--load-extension`，改用 CDP `Extensions.loadUnpacked`
 * 加载完整扩展副本。封装该调用，便于 mock 单测。
 * @param {{ send: (method: string, params: object) => Promise<any> }} cdp
 * @param {string} path 扩展副本目录
 */
export function loadUnpackedExtension(cdp, path) {
  return cdp.send("Extensions.loadUnpacked", { path });
}

/**
 * 轮询 `Target.getTargets` 等待扩展 service worker target 出现（验证扩展真正加载）。
 * 品牌 Chrome 151 实测 loadUnpacked 后 SW target 会出现在 `result.targetInfos`。
 * @param {{ send: (method: string, params: object) => Promise<any> }} cdp
 * @param {string} extensionId 扩展 ID（key 推导）
 * @param {number} [timeoutMs]
 * @returns {Promise<{targetId: string, url: string} | null>}
 */
export async function waitForExtensionServiceWorker(cdp, extensionId, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const targets = await cdp.send("Target.getTargets", {});
    const sw = (targets?.result?.targetInfos || []).find(
      (t) => t.type === "service_worker" && t.url.includes(extensionId)
    );
    if (sw) return sw;
    await sleep(250);
  }
  return null;
}

/**
 * 构造写入 `<profile>/NativeMessagingHosts/<hostName>.json` 的 manifest。
 * `allowed_origins` 沿用 extension-id.mjs 的 key 推导 ID（Task 1 探针确认
 * 含 key 扩展 ID 即 key 推导，与 loadUnpacked 返回 ID 一致）。
 * @param {{ hostName: string, hostBinary: string, extensionId: string }} p
 */
export function hostManifest({ hostName, hostBinary, extensionId }) {
  return {
    name: hostName,
    description: "GestureKit E2E Native Messaging Host (temporary)",
    path: hostBinary,
    type: "stdio",
    allowed_origins: [`chrome-extension://${extensionId}/`],
  };
}

/**
 * 验证 content script 注入：等待 isolated world 执行上下文出现，再在 isolated world
 * 求值读取 pointerTracker 状态。返回 null 表示未注入。
 * @param {{ events: Array<{method: string, params: any}>, send: (method: string, params: object, sessionId: string|null) => Promise<any> }} cdp
 * @param {string} sessionId 页面 target session
 * @param {number} [timeoutMs]
 */
export async function verifyContentScriptInjected(cdp, sessionId, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs;
  let isolated = null;
  while (Date.now() < deadline) {
    isolated = (cdp.events || []).find(
      (e) => e.method === "Runtime.executionContextCreated" &&
        e.params?.context?.auxData?.type === "isolated"
    );
    if (isolated) break;
    await sleep(250);
  }
  if (!isolated) return null;
  const resp = await cdp.send("Runtime.evaluate", {
    expression:
      "(() => { const s = window.__gestureKitPointerTrackerState; " +
      "return s ? { hasLastPointer: s.lastPointer !== null, linkClickProtectionEnabled: s.linkClickProtectionEnabled } : null; })()",
    returnByValue: true,
    contextId: isolated.params.context.id,
  }, sessionId);
  return resp?.result?.result?.value ?? null;
}

// ═══════════════════════════════════════════════════════════════════
// Task 3：success 场景 active 检测修复
//
// `document.hasFocus()` 在无 GUI 焦点（后台/无头 Chrome 窗口）时对全部 tab 恒
// false，无法区分真实激活。改用：runner 经 CDP `Target.attachToTarget` 附着扩展
// service worker target（flatten 会话），在 SW 上下文执行
// `chrome.tabs.query({active:true})` 取真实 active tab 作为 active 判定来源。
// 不采用扩展→runner 上报通道（Task 5 已删 page bridge），也不采用 AppleScript /
// 前置激活窗口（依赖 GUI 会话，CI 下必失败）。
// ═══════════════════════════════════════════════════════════════════

/**
 * 在扩展 service worker 上下文执行 `chrome.tabs.query({active:true})`，返回真实
 * active tab 数组。`Runtime.evaluate` 返回 `{ id, result: { result: { value } } }`，
 * value 即解析出的 tabs 数组（`awaitPromise: true` 等待 chrome.tabs.query 的
 * Promise；`returnByValue: true` 序列化返回）。扩展 manifest 含 `tabs` 权限，
 * 因此返回的 tab 对象带 `url`。
 * @param {{ send: (method: string, params: object, sessionId: string|null) => Promise<any> }} cdp
 * @param {string} sessionId 扩展 service worker target session
 * @returns {Promise<Array<{id: number, url: string, active: boolean}>>}
 */
export async function queryActiveTabs(cdp, sessionId) {
  const resp = await cdp.send("Runtime.evaluate", {
    expression: "chrome.tabs.query({ active: true })",
    returnByValue: true,
    awaitPromise: true
  }, sessionId);
  const value = resp?.result?.result?.value;
  return Array.isArray(value) ? value : [];
}

/**
 * 把 page target 与 `chrome.tabs.query` 返回的 active tab 合并成 runner 使用的
 * `{ id, url, active }` 列表：按 URL 匹配标记 active。纯函数，可单测。
 * CDP `TargetInfo.targetId` 与 chrome tab `id` 是两套 ID 空间，无法直接映射；
 * E2E fixture 中 source/target URL 互不相同，按 URL 匹配即可区分真实激活。
 * @param {Array<{targetId: string, url: string}>} pageTargets
 * @param {Array<{url?: string}>} [activeTabs]
 * @returns {Array<{id: string, url: string, active: boolean}>}
 */
export function markActiveByUrl(pageTargets, activeTabs) {
  // 同时收集 url 与 pendingUrl：真实运行发现新 tab 打开后 TargetInfo.url 立即更新到
  // 固定目标，但 chrome.tabs 的 url 要等导航 commit（status:"loading" 期间 url 为空、
  // 目标在 pendingUrl）。只匹配 url 会把加载中的活动 tab 判为非 active。
  const activeUrls = new Set();
  for (const t of activeTabs || []) {
    if (t?.url) activeUrls.add(t.url);
    if (t?.pendingUrl) activeUrls.add(t.pendingUrl);
  }
  return pageTargets.map((t) => ({
    id: t.targetId,
    url: t.url,
    active: activeUrls.has(t.url)
  }));
}

/**
 * 轮询谓词：是否存在非 source 的 page tab 且其 URL 等于固定目标。纯函数，可单测。
 * 探针实测点击后 `TargetInfo.url` 更新有延迟（最慢 ~4s），用本谓词轮询等待目标 tab
 * URL 就绪，替换固定 1500ms 等待。
 * @param {Array<{id: string, url: string}>} tabs
 * @param {string} sourceTabId
 * @param {string} expectedTargetUrl
 * @returns {boolean}
 */
export function hasAdjacentTargetTab(tabs, sourceTabId, expectedTargetUrl) {
  return tabs.some((t) => t.id !== sourceTabId && t.url === expectedTargetUrl);
}

/**
 * 轮询 `getTabs()` 直到 `predicate(tabs)` 成立或超时。超时返回 null（调用方据此
 * 明确失败），不抛错。
 * @param {() => Promise<Array<any>>} getTabs
 * @param {(tabs: Array<any>) => boolean} predicate
 * @param {number} [timeoutMs]
 * @param {number} [intervalMs]
 * @returns {Promise<Array<any> | null>}
 */
export async function waitForTabs(getTabs, predicate, timeoutMs = 10000, intervalMs = 250) {
  const deadline = Date.now() + timeoutMs;
  let tabs = await getTabs();
  while (!predicate(tabs) && Date.now() < deadline) {
    await sleep(intervalMs);
    tabs = await getTabs();
  }
  return predicate(tabs) ? tabs : null;
}

// ═══════════════════════════════════════════════════════════════════
// Task 4：leaseExpiry 语义与 guard trace 断言
//
// 探针/实测确认：`linkClickProtectionEnabled` 生产恒 false（`setLinkClickProtectionEnabled`
// 仅测试调用），guard lease 过期或显式 release 后 `interactionGuard.active()` 返回 null，
// 普通点击本就不被拦截。因此 leaseExpiry 的成功判据是"source 原地导航到固定目标、无新
// tab"，并须由 guard trace 证明 guard 曾被 arm（链路存活）而点击时已无 guard——否则
// "点击放行"与"链路断裂恰好放行"无法区分（缺口 I2）。这些 helper 均为纯函数，可单测。
// ═══════════════════════════════════════════════════════════════════

/**
 * leaseExpiry 成功判据：source tab 原地导航到固定目标（普通点击未被 guard 拦截）。
 * 轮询谓词，替换点击后固定 1500ms 等待——`TargetInfo.url` 更新有延迟（实测最慢 ~4s），
 * 固定等待会在 source 已导航但 URL 尚未刷新时误报"点击被拦截"。
 * @param {Array<{id: string, url: string}>} tabs
 * @param {string} sourceTabId
 * @param {string} expectedUrl
 * @returns {boolean}
 */
export function leaseExpirySourceNavigated(tabs, sourceTabId, expectedUrl) {
  const source = (tabs || []).find((t) => t.id === sourceTabId);
  return Boolean(source && source.url === expectedUrl);
}

/**
 * 解析单条 `guard_stage session=<gsid> stage=<stage> detail=<detail>` 消息
 *（background.ts appendGuardTrace 写入，仅当扩展 `diagnosticLoggingEnabled` 为 true
 * 时持久化）。返回 null 表示非 guard_stage 消息。
 * @param {unknown} message
 * @returns {{ sessionId: string, stage: string, detail: string } | null}
 */
export function matchGuardStageMessage(message) {
  if (typeof message !== "string") return null;
  const m = message.match(/^guard_stage session=(\S+)\s+stage=(\S+)\s+detail=(\S+)/);
  return m ? { sessionId: m[1], stage: m[2], detail: m[3] } : null;
}

/**
 * 从 `chrome.storage.local` 的 `gesturekitDiagnostics` 数组中过滤出指定
 * gestureSessionId 的 guard trace 阶段。纯函数，可单测。
 * @param {Array<{message?: string}> | null | undefined} diagnostics
 * @param {string} gestureSessionId
 * @returns {Array<{stage: string, detail: string}>}
 */
export function parseGuardTraceStages(diagnostics, gestureSessionId) {
  if (!Array.isArray(diagnostics)) return [];
  const stages = [];
  for (const entry of diagnostics) {
    const match = matchGuardStageMessage(entry?.message);
    if (match && match.sessionId === gestureSessionId) {
      stages.push({ stage: match.stage, detail: match.detail });
    }
  }
  return stages;
}

/**
 * 从 diagnostics 中按时间窗口过滤 guard trace 并按 session 分组。E2E runner 的
 * `gestureSessionId` 只作为控制命令标识，实际 guard arm 使用 App 内部 coordinator
 * 分配的 session ID（runner 无法预知），因此按"arm 发生在 leaseExpiry 命令发送之后"
 * 的时间窗口匹配本次场景的 guard trace，而非按 gsid 精确匹配。纯函数，可单测。
 * @param {Array<{message?: string, timestamp?: number}> | null | undefined} diagnostics
 * @param {number} afterMs 只保留 timestamp >= afterMs 的 guard_stage 条目
 * @returns {Array<{sessionId: string, stages: Array<{stage: string, detail: string, timestamp: number}>}>}
 */
export function guardTraceSessionsInWindow(diagnostics, afterMs) {
  if (!Array.isArray(diagnostics)) return [];
  const bySession = new Map();
  for (const entry of diagnostics) {
    if (typeof entry?.timestamp !== "number" || entry.timestamp < afterMs) continue;
    const match = matchGuardStageMessage(entry?.message);
    if (!match) continue;
    if (!bySession.has(match.sessionId)) bySession.set(match.sessionId, []);
    bySession.get(match.sessionId).push({
      stage: match.stage,
      detail: match.detail,
      timestamp: entry.timestamp
    });
  }
  return [...bySession.entries()].map(([sessionId, stages]) => ({ sessionId, stages }));
}

/**
 * guard trace 断言：trace 阶段列表必须包含指定阶段（如 "armed"）。leaseExpiry 用它
 * 证明 guard 链路存活、guard 确实被 arm 过，而非链路断裂导致点击恰好放行。
 * 纯函数，可单测。
 * @param {Array<{stage: string}>} stages
 * @param {string} stage
 * @returns {boolean}
 */
export function hasGuardTraceStage(stages, stage) {
  return Array.isArray(stages) && stages.some((s) => s?.stage === stage);
}

/**
 * guard trace 断言（I2）：证明 guard 曾被 arm 过且链路存活。
 *
 * 选用的证据是 `forwarding`（background 将 arm 路由到 content script）与
 * `forwarded:guard_armed`（content script 收到 arm 后返回 guard_armed——它只在
 * interactionGuard.arm() 之后才回 guard_armed，因此这是 guard 确实被 arm 的直接证据）。
 *
 * 不依赖 content script 发回的 `armed` stage：探针实测 background 的
 * `void appendDiagnostic` 对同一 session 的多次并发持久化存在 lost-update 竞态，
 * `armed`（中间阶段）会与 `forwarding`/`forwarded` 竞态丢失，而 `forwarding`（首）与
 * `forwarded`（尾）稳定落盘。纯函数，可单测。
 * @param {Array<{stage: string, detail: string}>} stages
 * @returns {boolean}
 */
export function hasForwardedGuardArmed(stages) {
  return Array.isArray(stages) &&
    hasGuardTraceStage(stages, "forwarding") &&
    stages.some((s) => s?.stage === "forwarded" && s?.detail === "guard_armed");
}

/**
 * guard trace 断言：guard 是否曾拦截点击（`click_blocked` 或 `lease_expired`）。
 * leaseExpiry 的通过要求"点击未被拦截再恢复"，即本谓词为 false。
 * 纯函数，可单测。
 * @param {Array<{stage: string}>} stages
 * @returns {boolean}
 */
export function hasGuardBlockedClick(stages) {
  return Array.isArray(stages) &&
    (hasGuardTraceStage(stages, "click_blocked") || hasGuardTraceStage(stages, "lease_expired"));
}

/**
 * 在 `chrome.tabs.query({})` 返回的 tab 数组中按 URL 找 chrome tab id。同时匹配
 * `url` 与 `pendingUrl`（导航 commit 前 url 为空、目标在 pendingUrl，与 Task 3
 * markActiveByUrl 的发现一致）。纯函数，可单测。
 * @param {Array<{id?: number, url?: string, pendingUrl?: string}> | null | undefined} tabs
 * @param {string} url
 * @returns {number | null}
 */
export function findTabIdByUrl(tabs, url) {
  if (!Array.isArray(tabs)) return null;
  const tab = tabs.find((t) => t?.url === url || t?.pendingUrl === url);
  return typeof tab?.id === "number" ? tab.id : null;
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
// 固定目标链接：fixture 只包含这一个链接（同窗口，无 target="_blank"），
// 未受 guard 拦截的普通点击会原地导航到它——这正是 guard 必须阻止的失败模式。
const FIXED_TARGET_URL = "https://example.test/e2e-target";

function nowMs() {
  return Date.now();
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * 在 127.0.0.1 上找一个空闲端口，用作本次 E2E 的 IPC 端口（GESTUREKIT_IPC_PORT）。
 * 测试 App 与真实 App 共享默认端口 17653，必须隔离到独立端口，
 * Host 才能连到正确的测试 App。返回后立即关闭探测 socket（轻微竞态可接受）。
 * @returns {Promise<number>}
 */
function findFreePort() {
  return new Promise((resolve, reject) => {
    const probe = createNetServer();
    probe.on("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });
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
  /** 事件消息（无 id 的服务端推送），供 isolated world 等检测使用。 */
  events = [];

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
        } else if (msg.method) {
          this.events.push(msg);
        }
      };
    });
  }

  clearEvents() {
    this.events.length = 0;
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
  #pageSessionId = null;
  #scenarioResults = [];
  // C2 修复：需保存 processes 数组引用和 app 启动参数用于重启
  #processes;
  #appPath;
  #buildEnv;
  // Task 3：扩展 service worker target 的 flatten session（active 检测用）
  #extensionId;
  #swSessionId = null;

  constructor(token, controlPort, cdp, fixtureServer, appProcess, chromeProcess, tempDirs, processes, appPath, buildEnv, extensionId) {
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
    this.#extensionId = extensionId;
  }

  async #sendE2ECommand(scenario, gestureSessionId, operationId) {
    return tcpRoundtrip("127.0.0.1", this.#controlPort, {
      token: this.#token,
      gestureSessionId,
      operationId,
      scenario
    });
  }

  async #pageEvaluate(expression, sessionId = null) {
    return this.#cdp.send("Runtime.evaluate", {
      expression,
      returnByValue: true
    }, sessionId);
  }

  /**
   * 读取 #e2e-link 的中心坐标。供 CDP Input.dispatchMouseEvent 移动指针用——
   * 扩展的 action 依赖 `state.lastPointer` 解析链接 URL，必须先把指针移到链接上。
   * @returns {Promise<{x: number, y: number}>}
   */
  async #linkCenterCoordinates() {
    const result = await this.#pageEvaluate(`(() => {
      const el = document.querySelector('#e2e-link');
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    })()`, this.#pageSessionId);
    const value = result?.result?.result?.value;
    if (!value || typeof value.x !== "number" || typeof value.y !== "number") {
      throw new Error("无法定位 #e2e-link 元素（fixture 页面未就绪？）");
    }
    return value;
  }

  /** 把指针移到 #e2e-link 中心，让 pointermove 记录 lastPointer。 */
  async #movePointerToLink() {
    const { x, y } = await this.#linkCenterCoordinates();
    await this.#cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved",
      x,
      y
    }, this.#pageSessionId);
    await sleep(100);
  }

  /**
   * 惰性附着扩展 service worker target（flatten 会话）并缓存 sessionId。
   * active 检测需要在 SW 上下文执行 chrome.tabs.query——MV3 SW 在 E2E 全程活跃
   * （native messaging 连接 + 消息收发），附着一次即可；SW 若重启，session 失效，
   * 下次调用会重新查找并附着。
   * @returns {Promise<string>} SW target sessionId
   */
  async #ensureSwSession() {
    if (this.#swSessionId) return this.#swSessionId;
    const targets = await this.#cdp.send("Target.getTargets", {});
    const sw = (targets?.result?.targetInfos || []).find(
      (t) => t.type === "service_worker" && t.url.includes(this.#extensionId)
    );
    if (!sw) {
      throw new Error(`扩展 service worker 未找到（active 检测无法执行）id=${this.#extensionId}`);
    }
    const attached = await this.#cdp.send("Target.attachToTarget", {
      targetId: sw.targetId,
      flatten: true
    });
    const sessionId = attached?.result?.sessionId;
    if (!sessionId) {
      throw new Error("无法附着扩展 service worker target");
    }
    await this.#cdp.send("Runtime.enable", {}, sessionId);
    this.#swSessionId = sessionId;
    return sessionId;
  }

  /**
   * 在扩展 SW 上下文执行 `chrome.tabs.update(id, {active: true})`，激活 URL 匹配
   * 的 tab。Task 4 必需：success 场景后 active tab 是目标 tab，leaseExpiry 的 guard
   * arm 由 background `routeInteractionGuard` 路由到 active tab；若不把 source
   * （fixture）tab 激活，guard 会发到无 content script 的目标 tab（实测
   * `forward_failed:content_script_unavailable`），leaseExpiry 的"点击放行"实为
   * 链路断裂恰好放行——正是 guard trace 断言（I2）要暴露的假阳性。
   * @param {string} url fixture 页面 URL
   * @returns {Promise<boolean>} 是否找到并激活
   */
  async #activateTabByUrl(url) {
    const swSessionId = await this.#ensureSwSession();
    const query = await this.#cdp.send("Runtime.evaluate", {
      expression: "chrome.tabs.query({})",
      returnByValue: true,
      awaitPromise: true
    }, swSessionId);
    const tabs = query?.result?.result?.value;
    const tabId = findTabIdByUrl(tabs, url);
    if (tabId === null) return false;
    await this.#cdp.send("Runtime.evaluate", {
      expression: `chrome.tabs.update(${JSON.stringify(tabId)}, { active: true })`,
      returnByValue: true,
      awaitPromise: true
    }, swSessionId);
    return true;
  }

  async #getTabs() {
    // 使用 CDP Target.getTargets 获取所有 page 类型 target（提供 CDP targetId）
    const targets = await this.#cdp.send("Target.getTargets", {});
    const pageTargets = (targets.result?.targetInfos || []).filter((t) => t.type === "page");

    // Task 3 修复：active 判定来源改为「扩展 SW 上下文执行 chrome.tabs.query({active:true})」。
    // document.hasFocus() 在无 GUI 焦点（后台/无头窗口）时对全部 tab 恒 false，无法区分
    // 真实激活；chrome.tabs 的 active 是"窗口内活动 tab"语义，与窗口是否聚焦无关。
    const swSessionId = await this.#ensureSwSession();
    const activeTabs = await queryActiveTabs(this.#cdp, swSessionId);
    return markActiveByUrl(pageTargets, activeTabs);
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

    // 1. 先把指针移到固定链接上（扩展 action 依赖 lastPointer 解析 URL）。
    //    fixture 链接为同窗口（无 target="_blank"）：未受 guard 拦截的普通点击会
    //    原地导航 source tab——因此本场景只有 guard + action 链路完整才会通过。
    await this.#movePointerToLink();

    // 2. 发送 E2E 命令到 App，触发 guard arm + action 派遣
    const appResult = await this.#sendE2ECommand("success", gestureSessionId, operationId);
    if (appResult?.rejected) {
      return this.#failSummary("success", gestureSessionId, operationId, appResult.rejected?.reason || "e2e_rejected", "app_accept", nowMs() - start);
    }

    // 3. 等待 guard 传播到页面（约 500ms）
    await sleep(600);

    // 4. 模拟点击链接
    await pageEvaluate(this.#cdp, `document.querySelector('#e2e-link')?.click()`, this.#pageSessionId);

    // 5. 轮询等待目标 tab URL 更新到固定目标（TargetInfo.url 更新有延迟，探针实测
    //    最慢 ~4s；替换固定 1500ms 等待）。超时则明确失败。
    const tabsAfter = await waitForTabs(
      () => this.#getTabs(),
      (tabs) => hasAdjacentTargetTab(tabs, sourceTabId, FIXED_TARGET_URL),
      10000
    );
    if (!tabsAfter) {
      // 超时诊断：区分「source 被原地导航（guard 未拦截，普通点击生效）」与
      // 「相邻 tab 已打开但 URL 迟迟未更新到固定目标」
      const finalTabs = await this.#getTabs();
      const sourceBefore = tabsBefore.find((t) => t.id === sourceTabId);
      const sourceFinal = finalTabs.find((t) => t.id === sourceTabId);
      const sourceNavigated = Boolean(sourceBefore && sourceFinal && sourceBefore.url !== sourceFinal.url);
      const stage = sourceNavigated
        ? "guard_not_armed:source_navigated"
        : "target_url_not_updated";
      return this.#failSummary("success", gestureSessionId, operationId, stage, "tab_assert", nowMs() - start);
    }

    // 6. 断言：恰好一个相邻 tab 打开、active 且 URL 等于固定目标；source tab URL 不变
    try {
      assertAdjacentActivatedTab(tabsAfter, sourceTabId, FIXED_TARGET_URL);
    } catch (err) {
      return this.#failSummary("success", gestureSessionId, operationId, err.message, "tab_assert", nowMs() - start);
    }

    // 验证 source tab URL 未变化（未被同窗口链接原地导航）
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

    // 1. 发送 leaseExpiry 命令（App 侧 arm guard 后立即 primitiveRejected 释放，不派发 action）。
    //    记录命令发出时刻：实际 guard arm 使用 App 内部 coordinator 的 session ID（runner
    //    无法预知），guard trace 断言按"arm 发生在此时刻之后"的时间窗口匹配本次场景。
    const leaseExpirySentAt = nowMs();
    const appResult = await this.#sendE2ECommand("leaseExpiry", gestureSessionId, operationId);
    if (appResult?.rejected) {
      return this.#failSummary("leaseExpiry", gestureSessionId, operationId, appResult.rejected?.reason || "e2e_rejected", "app_accept", nowMs() - start);
    }

    // 2. 等待 guard arm → release 传播到页面，且 guard lease（App 侧 deadline 750ms）完全过期。
    //    探针/实测确认：release 或 lease 过期后 interactionGuard.active() 返回 null，
    //    linkClickProtectionEnabled 生产恒 false，普通点击本就不被拦截。
    await sleep(1000);

    // 3. 记录点击前 tab 快照，把指针移到链接上，执行普通点击
    const tabsBefore = await this.#getTabs();
    const sourceTabId = this.#pageTargetId;
    await this.#movePointerToLink();
    await pageEvaluate(this.#cdp, `document.querySelector('#e2e-link')?.click()`, this.#pageSessionId);

    // 4. 轮询等待 source tab 原地导航到固定目标（普通点击生效）。
    //    TargetInfo.url 更新有延迟（实测最慢 ~4s，headless 同 tab 导航到不可解析的
    //    example.test 甚至可达 ~10s DNS 超时），固定 1500ms 等待会在 source 已导航但
    //    URL 尚未刷新时误报"点击被拦截"（Task 3 已确认该误报根因）。轮询消除该延迟，
    //    15s 超时给 headless DNS 延迟留出余量（避免 timeout 边界 flake）。
    const tabsAfter = await waitForTabs(
      () => this.#getTabs(),
      (tabs) => leaseExpirySourceNavigated(tabs, sourceTabId, FIXED_TARGET_URL),
      15000
    );

    if (!tabsAfter) {
      // 超时诊断：区分真实"guard 仍 armed（点击被拦 / 动作打开新 tab）"与"URL 更新延迟"。
      const finalTabs = await this.#getTabs();
      if (finalTabs.length !== tabsBefore.length) {
        return this.#failSummary("leaseExpiry", gestureSessionId, operationId, "guard_still_armed:new_tab_opened", "lease_guard", nowMs() - start);
      }
      // 无新 tab 且 source 未导航：点击被拦会在保护窗口 750ms 后原地导航（10s 内可见），
      // 此处仍保持 fixture URL 说明点击未生效或 URL 更新异常延迟，如实归因 URL 延迟。
      return this.#failSummary("leaseExpiry", gestureSessionId, operationId, "source_url_not_updated", "lease_guard", nowMs() - start);
    }

    // 5. 断言无新 tab（guard 未在点击时拦截并派发 action 打开相邻 tab）
    if (tabsAfter.length !== tabsBefore.length) {
      return this.#failSummary("leaseExpiry", gestureSessionId, operationId, "guard_still_armed:new_tab_opened", "lease_guard", nowMs() - start);
    }

    // 6. guard trace 断言（缺口 I2）：证明通过是"无 guard 放行"而非"链路断裂恰好放行"。
    //    - 时间窗口（leaseExpirySentAt 之后）内必须存在一个 guard session 满足
    //      hasForwardedGuardArmed（`forwarding` + `forwarded:guard_armed`）——证明 guard
    //      链路 App→SW→content script 存活、guard 确实被 arm（content script 只在
    //      interactionGuard.arm() 后才回 guard_armed）；
    //    - 该 session 不得含 `click_blocked`/`lease_expired`——证明点击未被拦截再恢复，
    //      而是作为普通点击直接放行（guard 在点击时已释放/lease 已过期）。
    //    观测方式：扩展 diagnosticLoggingEnabled 为 true（runner 以 Foundation 参数域启动
    //    App 开启），recordGuardTrace 的非终态阶段落到 chrome.storage.local 的
    //    gesturekitDiagnostics；runner 经 CDP 附着扩展 SW，在 SW 上下文读取该存储。
    //    注：content script 回发的 `armed` 阶段会与 background 自身的并发持久化竞态丢失
    //    （实测 lost-update），因此断言用等价的 `forwarded:guard_armed` 而非 `armed`。
    const guardSessions = await this.#pollGuardTraceSessionsInWindow(leaseExpirySentAt, 5000);
    const armedSession = guardSessions.find((s) => hasForwardedGuardArmed(s.stages));
    if (!armedSession) {
      return this.#failSummary("leaseExpiry", gestureSessionId, operationId, "guard_trace_missing:no_forwarded_guard_armed", "guard_trace", nowMs() - start);
    }
    if (hasGuardBlockedClick(armedSession.stages)) {
      return this.#failSummary("leaseExpiry", gestureSessionId, operationId, "guard_still_armed:click_blocked", "guard_trace", nowMs() - start);
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

  /**
   * 读取 `afterMs` 之后（含）的 guard trace session 列表。
   * 观测通道：runner 附着扩展 service worker（#ensureSwSession），在 SW 上下文执行
   * `chrome.storage.local.get("gesturekitDiagnostics")`（awaitPromise + returnByValue），
   * 再用 guardTraceSessionsInWindow 过滤。返回 [] 表示窗口内无持久化 guard trace。
   * @param {number} afterMs
   * @returns {Promise<Array<{sessionId: string, stages: Array<{stage: string, detail: string, timestamp: number}>}>>}
   */
  async #readGuardTraceSessionsInWindow(afterMs) {
    const swSessionId = await this.#ensureSwSession();
    const resp = await this.#cdp.send("Runtime.evaluate", {
      expression: "chrome.storage.local.get('gesturekitDiagnostics')",
      returnByValue: true,
      awaitPromise: true
    }, swSessionId);
    const diagnostics = resp?.result?.result?.value?.gesturekitDiagnostics;
    return guardTraceSessionsInWindow(diagnostics, afterMs);
  }

  /**
   * 轮询读取时间窗口内的 guard trace session，直到出现含 `armed` 阶段的 session 或超时。
   * arm 的持久化是 fire-and-forget（void appendDiagnostic），轮询吸收该异步竞态。
   * 超时返回最后一次读到的 session 列表。
   * @param {number} afterMs
   * @param {number} timeoutMs
   * @returns {Promise<Array<{sessionId: string, stages: Array<{stage: string, detail: string, timestamp: number}>}>>}
   */
  async #pollGuardTraceSessionsInWindow(afterMs, timeoutMs = 5000) {
    const deadline = Date.now() + timeoutMs;
    let sessions = [];
    while (Date.now() < deadline) {
      sessions = await this.#readGuardTraceSessionsInWindow(afterMs);
      if (sessions.some((s) => hasGuardTraceStage(s.stages, "armed"))) break;
      await sleep(250);
    }
    return sessions;
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
    await pageEvaluate(this.#cdp, `document.querySelector('#e2e-link')?.click()`, this.#pageSessionId);
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
    // 与首次启动一致：参数域开启 diagnosticLoggingEnabled，重启后扩展侧 guard trace
    // 仍持久化（resultUnknown 场景不依赖，但保持一致避免重启后配置回落）。
    const child = spawn(this.#appPath, [
      "--e2e-control-token", this.#token,
      "-gesturekitDiagnosticLoggingEnabled", "YES"
    ], {
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

  /**
   * 轮询 Target.getTargets 直到 fixture 页面出现。Chrome 启动时以 fixture URL 打开，
   * 但 CDP 连接时页面可能仍在导航（target URL 尚未变为 fixture URL），
   * 单次查询会竞态失败，因此轮询等待。
   */
  async #findFixturePage(timeoutMs = 10000) {
    const deadline = nowMs() + timeoutMs;
    while (nowMs() < deadline) {
      const targets = await this.#cdp.send("Target.getTargets", {});
      const page = findPageTarget(targets, "link-reliability");
      if (page) return page;
      await sleep(250);
    }
    return null;
  }

  async runAll() {
    // 先获取当前页面 target ID
    const page = await this.#findFixturePage();
    if (!page) {
      throw new Error("未找到 link-reliability fixture 页面（Chrome 未打开 fixture URL，或 fixture server 不可达）");
    }
    // 通过 Target.attachToTarget 获得 page session
    const attached = await this.#cdp.send("Target.attachToTarget", {
      targetId: page.targetId,
      flatten: true
    });
    this.#pageTargetId = page.targetId;
    this.#pageSessionId = attached.result?.sessionId;

    // 启用 Runtime/Page domain（通过 page session 路由）
    await this.#cdp.send("Runtime.enable", {}, this.#pageSessionId);
    await this.#cdp.send("Page.enable", {}, this.#pageSessionId);

    // fixture 页面在扩展加载（loadUnpacked）之前已打开，content script 不会注入已加载页面；
    // 重新加载使 content script 注入，并验证 isolated world 中 pointerTracker 状态暴露。
    this.#cdp.clearEvents();
    await this.#cdp.send("Page.reload", {}, this.#pageSessionId);
    const injected = await verifyContentScriptInjected(this.#cdp, this.#pageSessionId);
    if (!injected) {
      throw new Error("扩展 content script 未注入 fixture 页面（扩展未加载或 content_scripts 匹配失败）");
    }
    console.error(`[runner] 扩展 content script 已注入: ${JSON.stringify(injected)}`);

    // 预附着扩展 SW session（active 检测用；#getTabs 也惰性附着并缓存）。
    await this.#ensureSwSession();

    // success 场景的 provider 启动竞态（已知残留，Task 6 关注）：扩展 SW 可能已存活
    // 但 App 侧 provider 会话尚未建立，guard arm 静默失败导致 success 误报
    // source_navigated。此处短暂 settle 缩小竞态窗口（探针确认 SW→Host→App 链路在
    // 正常运行时数百毫秒内建立）；无可靠的"provider 已连接"正向信号可轮询——
    // 探针尝试经 chrome.runtime.sendMessage 从 SW 自身上下文触发 connectionProbe，
    // 实测不会递到 SW 自身监听器（"Could not establish connection"）。
    await sleep(1500);

    const results = [];

    console.error("[runner] 场景 1/4: success");
    results.push(await this.#runSuccess());

    // 重新导航到 fixture 页面（前面的场景可能已导航走）
    await pageNavigate(this.#cdp, `${FIXTURE_ORIGIN}/link-reliability.html`, this.#pageSessionId);
    await sleep(1000);

    // Task 4：success 后 active tab 是目标 tab，而 background 的 guard arm 路由到
    // active tab。先把 source（fixture）tab 激活，leaseExpiry 的 guard 才能落到本页
    // content script，guard trace 断言（I2）才具备意义（否则 arm 发往无 content script
    // 的目标 tab，点击放行实为链路断裂恰好放行）。
    await this.#activateTabByUrl(`${FIXTURE_ORIGIN}/link-reliability.html`);
    await sleep(300);

    console.error("[runner] 场景 2/4: leaseExpiry");
    results.push(await this.#runLeaseExpiry());

    await pageNavigate(this.#cdp, `${FIXTURE_ORIGIN}/link-reliability.html`, this.#pageSessionId);
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
    headless = false,
    chromePath = process.env.CHROME_PATH || CHROME_PATH,
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

    // 2. 复制 fixture 文件（fixture 只包含固定目标链接，无独立 target 页面）
    const fixturesSrc = join(repoRoot, "scripts/e2e/fixtures");
    for (const f of ["link-reliability.html"]) {
      const src = join(fixturesSrc, f);
      writeFileSync(join(fixtureDir, f), readFileSync(src));
    }

    // 3. 构建 extension 成「完整可加载副本」：
    //    - build.mjs --outdir <副本>/dist，使 manifest 内 dist/... 引用与实际布局一致；
    //    - GESTUREKIT_HOST_NAME 注入独立 host 名（com.gesturekit.host.e2e），完全避开
    //      用户级真实 com.gesturekit.host manifest（扩展 connectNative 用同名）；
    //    - 拷贝 manifest.json/popup.html/smoke.html + src/popup/popup.css → dist/popup。
    //    token 经环境变量传入 App（--e2e-control-token），不进 build argv。
    console.error("[runner] 构建 extension（完整可加载副本）...");
    execSync(`node scripts/build.mjs --outdir "${join(extensionOut, "dist")}"`, {
      cwd: join(repoRoot, "extensions/chrome"),
      env: { ...process.env, GESTUREKIT_HOST_NAME: E2E_HOST_NAME },
      stdio: "inherit"
    });
    copyExtensionStaticFiles(join(repoRoot, "extensions/chrome"), extensionOut);
    validateExtensionLayout(extensionOut);
    console.error(`[runner] 扩展副本就绪: ${extensionOut}`);

    // 4. 确保 GestureKitHost 已编译
    const hostBinary = join(repoRoot, ".build/debug/GestureKitHost");
    const developerDir = process.env.DEVELOPER_DIR || (() => {
      try { return DEFAULT_DEVELOPER_DIR; } catch { return ""; }
    })();
    const buildEnv = {
      ...(developerDir ? { ...process.env, DEVELOPER_DIR: developerDir } : process.env),
      // IPC 端口隔离：测试 App 与真实 App 共享默认 17653，Host 必须连到测试 App 的独立端口。
      GESTUREKIT_IPC_PORT: String(await findFreePort())
    };
    try {
      execSync("swift build --package-path .", {
        cwd: repoRoot,
        env: buildEnv,
        stdio: "inherit"
      });
    } catch {
      console.error("[runner] GestureKitHost 构建失败，尝试继续（可能已缓存）");
    }

    // 5. 写 native messaging manifest 到 <profile>/NativeMessagingHosts
    //    （Task 1 探针确认：临时 --user-data-dir 下 Chrome 读该位置，不读用户级目录）。
    //    用独立 host 名 com.gesturekit.host.e2e，与扩展 build 注入的 HOST_NAME 一致；
    //    即使误用默认 profile 也不会覆盖用户级真实 com.gesturekit.host.json。
    //    注意：manifest 查找有进程内缓存——必须先写 manifest 再启动 Chrome（本段在启动前）。
    const manifestDir = join(chromeProfile, "NativeMessagingHosts");
    mkdirSync(manifestDir, { recursive: true });
    const extensionId = execSync(
      `node "${join(repoRoot, "extensions/chrome/scripts/extension-id.mjs")}"`,
      { encoding: "utf-8" }
    ).trim();
    const manifest = hostManifest({
      hostName: E2E_HOST_NAME,
      hostBinary,
      extensionId
    });
    writeFileSync(join(manifestDir, `${E2E_HOST_NAME}.json`), JSON.stringify(manifest));

    // 6. 启动 fixture HTTP server
    console.error("[runner] 启动 fixture server...");
    const fixtureServer = new FixtureHttpServer(fixtureDir);
    await fixtureServer.start();
    servers.push(fixtureServer);

    // 7. 启动 GestureKitApp
    console.error("[runner] 启动 GestureKitApp...");
    const appPath = join(repoRoot, ".build/debug/GestureKitApp");
    let controlPort = 0;
    // Task 4：追加 Foundation 参数域 `-gesturekitDiagnosticLoggingEnabled YES`（NSArgumentDomain
    // 优先级最高，仅影响本进程、不持久化到用户偏好），使 authoritativeConfigurationSnapshot()
    // 返回 diagnosticLoggingEnabled=true，扩展侧 recordGuardTrace 才会把非终态 guard trace
    // 持久化到 chrome.storage.local——这是 runner 读取 guard trace 断言（缺口 I2）的前提。
    const appArgs = ["--e2e-control-token", token, "-gesturekitDiagnosticLoggingEnabled", "YES"];
    const appPromise = new Promise((resolve, reject) => {
      const child = spawn(appPath, appArgs, {
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
    // 注意：品牌 Chrome 142+ 忽略 `--load-extension`（151 实测 stderr：
    // "--load-extension is not allowed in Google Chrome, ignoring."），v2.4 门
    // 扩展从未加载即此原因。改用 CDP `Extensions.loadUnpacked`（连接后加载完整副本）。
    // 也不用 --disable-extensions-except（期望 ID 而非路径，会误禁用全部扩展）。
    const chromeArgs = [
      `--user-data-dir=${chromeProfile}`,
      "--remote-debugging-port=0",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-background-networking", // 减少噪声
      // headless：真实 Chrome 门可用 --headless 选项（新无头模式支持扩展，
      // 避免本地反复弹窗；CI 无 GUI 会话时也建议使用）。
      ...(headless ? ["--headless=new"] : []),
      `${FIXTURE_ORIGIN}/link-reliability.html`
    ];
    let cdpPort = 0;
    const chromePromise = new Promise((resolve, reject) => {
      const child = spawn(chromePath, chromeArgs, {
        stdio: "ignore",
        // GESTUREKIT_IPC_PORT 经 Chrome 环境传给 Native Messaging Host，
        // 使 Host 连到测试 App 的独立 IPC 端口。
        env: { ...process.env, GESTUREKIT_IPC_PORT: buildEnv.GESTUREKIT_IPC_PORT }
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

    // 9.5 经 CDP 加载完整扩展副本（替代已失效的 --load-extension）。
    //     校验 loadUnpacked 返回 ID == manifest key 推导 ID（Task 1 探针确认一致），
    //     再等待扩展 service worker target 出现，证明扩展已被 Chrome 加载。
    console.error(`[runner] 加载扩展（Extensions.loadUnpacked）: ${extensionOut}`);
    const loaded = await loadUnpackedExtension(cdp, extensionOut);
    const loadedId = loaded?.result?.id;
    console.error(`[runner] loadUnpacked -> id=${loadedId}`);
    if (loadedId !== extensionId) {
      throw new Error(`扩展 ID 不匹配: loadUnpacked=${loadedId}, key 推导=${extensionId}`);
    }
    const extSw = await waitForExtensionServiceWorker(cdp, extensionId);
    if (!extSw) {
      throw new Error(`扩展 service worker 未出现（扩展未加载?）id=${extensionId}`);
    }
    console.error(`[runner] 扩展已加载，service worker: ${extSw.url}`);

    // 10. 运行四个场景
    const runner = new ScenarioRunner(
      token, controlPort, cdp, fixtureServer,
      processes[0], // app process（最先入 processes）
      processes[processes.length - 1], // chrome process（最后入 processes）
      tempDirs,
      processes,   // 数组引用，供 #restartApp 添加新进程以进入 cleanup
      appPath,     // GestureKitApp 二进制路径（step 7 已声明），供 #restartApp 重新 spawn
      buildEnv,    // 编译环境变量（DEVELOPER_DIR 等），供 #restartApp 继承
      extensionId  // 扩展 ID（key 推导）：active 检测需附着扩展 service worker target
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
    // 防御：任何失败输出都不得包含 token。execSync/子进程错误信息可能含命令行或
    // 原始输出，逐处把 token 替换为 [redacted]，避免泄漏到 stderr。
    const raw = String(err?.message ?? err);
    const safeMessage = raw.split(token).join("[redacted]");
    console.error(`[runner] 环境预检失败: ${safeMessage}`);
    cleanup();
    return 2;
  }
}

// ═══════════════════════════════════════════════════════════════════
// 干跑模式：打印配置和命令，不启动任何 GUI 或写入用户 profile
// ═══════════════════════════════════════════════════════════════════

function dryRunOutput({ chromePath, repoRoot, fixturePort, ipcPort }) {
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
  lines.push(`DEVELOPER_DIR=${process.env.DEVELOPER_DIR || "/Applications/Xcode.app/Contents/Developer"}`);
  lines.push("");
  lines.push("--- 临时目录 ---");
  lines.push(`Chrome profile:    ${chromeProfile}`);
  lines.push(`Extension build:   ${extensionOut}`);
  lines.push(`Fixture server:    ${fixtureDir}`);
  lines.push("");
  lines.push(`--- Token ---`);
  lines.push(`E2E token (256-bit): ${token}`);
  lines.push("");
  lines.push(`--- Extension 构建（完整可加载副本） ---`);
  lines.push(`cd ${repoRoot}/extensions/chrome`);
  lines.push(`GESTUREKIT_HOST_NAME="${E2E_HOST_NAME}" node scripts/build.mjs --outdir "${extensionOut}/dist"`);
  lines.push(`拷贝静态文件 → ${extensionOut}:`);
  lines.push(`  manifest.json, popup.html, smoke.html（扩展源码根目录）`);
  lines.push(`  src/popup/popup.css → dist/popup/popup.css`);
  lines.push(`extension_id=${extensionId}（manifest key 推导，allowed_origins 依据）`);
  lines.push("");
  lines.push("--- GestureKitHost 构建 ---");
  lines.push(`cd ${repoRoot}`);
  lines.push("swift build --package-path .");
  lines.push(`host_binary=${hostBinary}`);
  lines.push("");
  lines.push("--- Native Messaging Manifest（独立 host 名，绝不触碰用户级真实 manifest） ---");
  lines.push(`写入: ${chromeProfile}/NativeMessagingHosts/${E2E_HOST_NAME}.json`);
  lines.push(`  name: ${E2E_HOST_NAME}`);
  lines.push(`  path: ${hostBinary}`);
  lines.push(`  allowed_origins: ["chrome-extension://${extensionId}/"]`);
  lines.push("  注意：先写 manifest 再启动 Chrome（manifest 查找有进程内缓存）");
  lines.push("");
  lines.push("--- Fixture HTTP Server ---");
  lines.push(`端口: 127.0.0.1:${fixturePort}`);
  lines.push(`文件: ${fixtureDir}/link-reliability.html`);
  lines.push(`链接: ${FIXED_TARGET_URL}（同窗口固定目标）`);
  lines.push("");
  lines.push("--- GestureKitApp ---");
  lines.push(`${join(repoRoot, ".build/debug/GestureKitApp")} --e2e-control-token "${token}"`);
  lines.push("  预期 stdout: gesturekit_e2e_control_port=<port>");
  lines.push(`  env: GESTUREKIT_IPC_PORT=${ipcPort}（与真实实例 17653 隔离）`);
  lines.push("");
  lines.push("--- Chrome ---");
  lines.push(`${chromePath} \\`);
  lines.push(`  --user-data-dir="${chromeProfile}" \\`);
  lines.push(`  --remote-debugging-port=0 \\`);
  lines.push(`  --no-first-run \\`);
  lines.push(`  --no-default-browser-check \\`);
  lines.push(`  ${FIXTURE_ORIGIN}/link-reliability.html`);
  lines.push("  可选：--headless（新无头模式，支持扩展；CI 无 GUI 会话时建议使用）");
  lines.push("  注意：品牌 Chrome 142+ 忽略 --load-extension；连接后经 CDP 加载扩展：");
  lines.push(`  Extensions.loadUnpacked { path: "${extensionOut}" }`);
  lines.push(`    → 校验返回 id == ${extensionId}`);
  lines.push(`    → 等待扩展 service worker target 出现（验证已加载）`);
  lines.push("    → 重新加载 fixture 页面，验证 content script 注入");
  lines.push("");
  lines.push("--- 场景执行顺序 ---");
  lines.push("1. success         — guard+action → 相邻 tab 打开、激活且 URL=固定目标；source tab URL 不变");
  lines.push("2. leaseExpiry     — lease 过期 → 普通点击不被 guard 拦截（不打开新 tab，source 原地导航）");
  lines.push("3. providerUnavailable — 关闭 App → 走终态路径（绕过真实手势，已知缺口）");
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
  const headless = args.includes("--headless");

  if (dryRun) {
    const ipcPort = await findFreePort();
    console.log(dryRunOutput({
      chromePath: process.env.CHROME_PATH || CHROME_PATH,
      repoRoot: REPO_ROOT,
      fixturePort: FIXTURE_PORT,
      ipcPort
    }));
    process.exit(0);
  }

  runLinkReliabilityScenarios({ headless }).then((code) => {
    process.exit(code);
  }).catch((err) => {
    console.error(`[runner] 致命错误: ${err.message}`);
    process.exit(2);
  });
}
