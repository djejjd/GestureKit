import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  assertAdjacentActivatedTab, redactSummary, pageEvaluate, pageNavigate, findPageTarget,
  E2E_HOST_NAME, extensionStaticFiles, copyExtensionStaticFiles, validateExtensionLayout,
  loadUnpackedExtension, waitForExtensionServiceWorker, hostManifest, verifyContentScriptInjected,
  queryActiveTabs, markActiveByUrl, hasAdjacentTargetTab, waitForTabs,
  leaseExpirySourceNavigated, parseGuardTraceStages, hasGuardTraceStage,
  matchGuardStageMessage, guardTraceSessionsInWindow, findTabIdByUrl,
  hasForwardedGuardArmed, hasGuardBlockedClick
} from "./run-link-reliability.mjs";

// Step 1: runner 失败测试 — 测试 helper 函数在校验和脱敏时拒绝非法输入。
// 在 runner 实现前这些 import 会抛 MODULE_NOT_FOUND，满足 Step 2 的 FAIL 预期。

describe("assertAdjacentActivatedTab", () => {
  it("accepts when target is the only other page tab and active", () => {
    assert.doesNotThrow(() =>
      assertAdjacentActivatedTab(
        [
          { id: "source", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
          { id: "target", url: "https://example.test/e2e-target", active: true }
        ],
        "source"
      )
    );
  });

  it("rejects when more than two page tabs exist", () => {
    assert.throws(
      () =>
        assertAdjacentActivatedTab(
          [
            { id: "source", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
            { id: "other", url: "about:blank", active: false },
            { id: "target", url: "https://example.test/e2e-target", active: true }
          ],
          "source"
        ),
      // 三 tab 场景应拒绝（fixture 临时 profile 仅应有 source + target）
      /(?:exactly.*two tab|恰好.*两个)/
    );
  });

  it("rejects when no tab is active", () => {
    assert.throws(
      () =>
        assertAdjacentActivatedTab(
          [
            { id: "source", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
            { id: "target", url: "https://example.test/e2e-target", active: false }
          ],
          "source"
        ),
      /active/
    );
  });

  it("rejects when source tab is active (新 tab 应获得焦点)", () => {
    assert.throws(
      () =>
        assertAdjacentActivatedTab(
          [
            { id: "source", url: "http://127.0.0.1:4567/link-reliability.html", active: true },
            { id: "target", url: "https://example.test/e2e-target", active: false }
          ],
          "source"
        ),
      /source.*active|active.*source|不应.*active/
    );
  });

  it("rejects when source tab not found", () => {
    assert.throws(
      () =>
        assertAdjacentActivatedTab(
          [
            { id: "tab1", url: "about:blank", active: false },
            { id: "tab2", url: "https://example.test/e2e-target", active: true }
          ],
          "source"
        ),
      /(?:未找到|not found|source tab)/
    );
  });

  it("accepts when the adjacent tab URL matches the fixed target", () => {
    assert.doesNotThrow(() =>
      assertAdjacentActivatedTab(
        [
          { id: "source", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
          { id: "target", url: "https://example.test/e2e-target", active: true }
        ],
        "source",
        "https://example.test/e2e-target"
      )
    );
  });

  it("rejects when the adjacent tab URL does not match the fixed target", () => {
    assert.throws(
      () =>
        assertAdjacentActivatedTab(
          [
            { id: "source", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
            { id: "target", url: "https://example.test/wrong-target", active: true }
          ],
          "source",
          "https://example.test/e2e-target"
        ),
      /e2e-target/
    );
  });
});

describe("redactSummary", () => {
  it("redacts query and token-like values from failure summaries", () => {
    const result = redactSummary({
      scenario: "success",
      gestureSessionId: "g",
      operationId: "o",
      terminalStatus: "failed?token=raw&secret=abc",
      failureStage: "guard?token=leaked",
      durationMs: 1
    });
    const json = JSON.stringify(result);
    assert.ok(!json.includes("token=raw"));
    assert.ok(!json.includes("secret=abc"));
    assert.ok(!json.includes("token=leaked"));
  });

  it("preserves non-secret fields unchanged", () => {
    const result = redactSummary({
      scenario: "leaseExpiry",
      gestureSessionId: "gs-123",
      operationId: "op-456",
      terminalStatus: "succeeded",
      failureStage: null,
      durationMs: 500
    });
    assert.equal(result.scenario, "leaseExpiry");
    assert.equal(result.gestureSessionId, "gs-123");
    assert.equal(result.operationId, "op-456");
    assert.equal(result.terminalStatus, "succeeded");
    assert.equal(result.failureStage, null);
    assert.equal(result.durationMs, 500);
  });
});

describe("pageEvaluate", () => {
  it("calls cdp.send with Runtime.evaluate, expression, returnByValue, and sessionId", async () => {
    const calls = [];
    const mockCdp = {
      send: (method, params, sessionId) => {
        calls.push({ method, params, sessionId });
        return Promise.resolve({});
      }
    };
    await pageEvaluate(mockCdp, "1 + 1", "session-123");
    assert.equal(calls.length, 1);
    assert.equal(calls[0].method, "Runtime.evaluate");
    assert.equal(calls[0].params.expression, "1 + 1");
    assert.equal(calls[0].params.returnByValue, true);
    assert.equal(calls[0].sessionId, "session-123");
  });

  it("passes null sessionId when not provided", async () => {
    const calls = [];
    const mockCdp = {
      send: (method, params, sessionId) => {
        calls.push({ method, params, sessionId });
        return Promise.resolve({});
      }
    };
    await pageEvaluate(mockCdp, "document.title", null);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].method, "Runtime.evaluate");
    assert.equal(calls[0].params.expression, "document.title");
    assert.equal(calls[0].sessionId, null);
  });
});

describe("pageNavigate", () => {
  it("calls cdp.send with Page.navigate, url, and sessionId", async () => {
    const calls = [];
    const mockCdp = {
      send: (method, params, sessionId) => {
        calls.push({ method, params, sessionId });
        return Promise.resolve({});
      }
    };
    await pageNavigate(mockCdp, "http://example.com", "session-456");
    assert.equal(calls.length, 1);
    assert.equal(calls[0].method, "Page.navigate");
    assert.equal(calls[0].params.url, "http://example.com");
    assert.equal(calls[0].sessionId, "session-456");
  });

  it("passes null sessionId when not provided", async () => {
    const calls = [];
    const mockCdp = {
      send: (method, params, sessionId) => {
        calls.push({ method, params, sessionId });
        return Promise.resolve({});
      }
    };
    await pageNavigate(mockCdp, "about:blank", null);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].method, "Page.navigate");
    assert.equal(calls[0].params.url, "about:blank");
    assert.equal(calls[0].sessionId, null);
  });
});

describe("findPageTarget", () => {
  // CDP 命令响应形如 { id, result: { targetInfos: [...] } }；runner 必须读取
  // result 下的 targetInfos 而非顶层字段（send 返回完整消息）。
  it("returns the page target whose url includes the substring (reads result.targetInfos)", () => {
    const targets = {
      id: 1,
      result: {
        targetInfos: [
          { type: "page", targetId: "A", url: "http://127.0.0.1:4567/link-reliability.html" },
          { type: "page", targetId: "B", url: "https://example.test/other" }
        ]
      }
    };
    const page = findPageTarget(targets, "link-reliability");
    assert.equal(page.targetId, "A");
  });

  it("returns null when no page target matches", () => {
    const targets = {
      id: 1,
      result: { targetInfos: [{ type: "page", targetId: "B", url: "https://example.test/other" }] }
    };
    assert.equal(findPageTarget(targets, "link-reliability"), null);
  });

  it("returns null when response lacks result.targetInfos", () => {
    assert.equal(findPageTarget({ id: 1 }, "link-reliability"), null);
    assert.equal(findPageTarget({ id: 1, result: {} }, "link-reliability"), null);
  });

  it("ignores non-page targets", () => {
    const targets = {
      id: 1,
      result: {
        targetInfos: [
          { type: "service_worker", targetId: "SW", url: "http://127.0.0.1:4567/link-reliability" },
          { type: "page", targetId: "P", url: "http://127.0.0.1:4567/link-reliability.html" }
        ]
      }
    };
    assert.equal(findPageTarget(targets, "link-reliability").targetId, "P");
  });
});

// Task 2: 扩展加载修复 —— 完整副本拷贝、dist 布局校验、loadUnpacked、独立 host 名 manifest
describe("E2E_HOST_NAME", () => {
  it("uses an independent E2E host name that never collides with the production host", () => {
    assert.equal(E2E_HOST_NAME, "com.gesturekit.host.e2e");
    assert.notEqual(E2E_HOST_NAME, "com.gesturekit.host");
  });
});

describe("extensionStaticFiles", () => {
  it("maps manifest/popup/smoke to the copy root and popup.css into dist/popup", () => {
    const files = extensionStaticFiles();
    assert.equal(files["manifest.json"], "manifest.json");
    assert.equal(files["popup.html"], "popup.html");
    assert.equal(files["smoke.html"], "smoke.html");
    assert.equal(files["src/popup/popup.css"], "dist/popup/popup.css");
  });
});

describe("copyExtensionStaticFiles", () => {
  it("copies static files into a loadable extension copy layout", () => {
    const base = mkdtempSync(join(tmpdir(), "gesturekit-e2e-copy-"));
    const src = join(base, "src-ext");
    const out = join(base, "out-ext");
    try {
      mkdirSync(join(src, "src/popup"), { recursive: true });
      writeFileSync(join(src, "manifest.json"), "{}");
      writeFileSync(join(src, "popup.html"), "<p>popup</p>");
      writeFileSync(join(src, "smoke.html"), "<p>smoke</p>");
      writeFileSync(join(src, "src/popup/popup.css"), "body { color: red; }");

      const copied = copyExtensionStaticFiles(src, out);
      assert.equal(copied.length, 4);
      for (const f of ["manifest.json", "popup.html", "smoke.html"]) {
        assert.ok(existsSync(join(out, f)), `${f} 应被拷贝到扩展副本根目录`);
      }
      assert.ok(existsSync(join(out, "dist/popup/popup.css")), "popup.css 应拷到 dist/popup/popup.css");
      assert.equal(readFileSync(join(out, "dist/popup/popup.css"), "utf-8"), "body { color: red; }");
    } finally {
      rmSync(base, { recursive: true, force: true });
    }
  });
});

describe("validateExtensionLayout", () => {
  it("passes when every manifest-referenced dist/... file exists in the copy", () => {
    const base = mkdtempSync(join(tmpdir(), "gesturekit-e2e-layout-"));
    const out = join(base, "ext");
    try {
      mkdirSync(out, { recursive: true });
      writeFileSync(join(out, "manifest.json"), JSON.stringify({
        background: { service_worker: "dist/background/background.js" },
        action: { default_popup: "popup.html" },
        content_scripts: [{ js: ["dist/content/pointerTracker.js"] }]
      }));
      writeFileSync(join(out, "popup.html"), "<p>x</p>");
      mkdirSync(join(out, "dist/background"), { recursive: true });
      writeFileSync(join(out, "dist/background/background.js"), "");
      mkdirSync(join(out, "dist/content"), { recursive: true });
      writeFileSync(join(out, "dist/content/pointerTracker.js"), "");

      const refs = validateExtensionLayout(out);
      assert.ok(refs.includes("dist/background/background.js"));
      assert.ok(refs.includes("dist/content/pointerTracker.js"));
      assert.ok(refs.includes("popup.html"));
    } finally {
      rmSync(base, { recursive: true, force: true });
    }
  });

  it("throws when a manifest-referenced dist/... file is missing (布局不匹配)", () => {
    const base = mkdtempSync(join(tmpdir(), "gesturekit-e2e-layout-missing-"));
    const out = join(base, "ext");
    try {
      mkdirSync(out, { recursive: true });
      writeFileSync(join(out, "manifest.json"), JSON.stringify({
        background: { service_worker: "dist/background/background.js" }
      }));
      assert.throws(() => validateExtensionLayout(out), /dist\/background\/background\.js/);
    } finally {
      rmSync(base, { recursive: true, force: true });
    }
  });
});

describe("loadUnpackedExtension", () => {
  it("calls cdp.send with Extensions.loadUnpacked and the copy path", async () => {
    const calls = [];
    const mockCdp = {
      send: (method, params) => {
        calls.push({ method, params });
        return Promise.resolve({ id: 1, result: { id: "pdegbjhgibenmgaaplhnpbnhaaipndoh" } });
      }
    };
    const res = await loadUnpackedExtension(mockCdp, "/tmp/gesturekit-e2e-ext");
    assert.equal(calls.length, 1);
    assert.equal(calls[0].method, "Extensions.loadUnpacked");
    assert.deepEqual(calls[0].params, { path: "/tmp/gesturekit-e2e-ext" });
    assert.equal(res.result.id, "pdegbjhgibenmgaaplhnpbnhaaipndoh");
  });
});

describe("waitForExtensionServiceWorker", () => {
  it("returns the service_worker target whose url includes the extension id", async () => {
    const calls = [];
    const mockCdp = {
      send: async () => {
        calls.push("getTargets");
        if (calls.length === 1) {
          return { result: { targetInfos: [{ type: "page", targetId: "P", url: "http://x" }] } };
        }
        return {
          result: {
            targetInfos: [
              { type: "page", targetId: "P", url: "http://x" },
              { type: "service_worker", targetId: "SW", url: "chrome-extension://pdegbjhgibenmgaaplhnpbnhaaipndoh/dist/background/background.js" }
            ]
          }
        };
      }
    };
    const sw = await waitForExtensionServiceWorker(mockCdp, "pdegbjhgibenmgaaplhnpbnhaaipndoh", 5000);
    assert.equal(sw.targetId, "SW");
    assert.ok(calls.length >= 2);
  });

  it("returns null when no matching service worker appears within the timeout", async () => {
    const mockCdp = {
      send: async () => ({ result: { targetInfos: [{ type: "page", targetId: "P", url: "http://x" }] } })
    };
    const sw = await waitForExtensionServiceWorker(mockCdp, "abc", 100);
    assert.equal(sw, null);
  });
});

describe("hostManifest", () => {
  it("uses the independent E2E host name and key-derived allowed_origins", () => {
    const m = hostManifest({
      hostName: E2E_HOST_NAME,
      hostBinary: "/tmp/GestureKitHost",
      extensionId: "pdegbjhgibenmgaaplhnpbnhaaipndoh"
    });
    assert.equal(m.name, "com.gesturekit.host.e2e");
    assert.equal(m.description, "GestureKit E2E Native Messaging Host (temporary)");
    assert.equal(m.path, "/tmp/GestureKitHost");
    assert.equal(m.type, "stdio");
    assert.deepEqual(m.allowed_origins, ["chrome-extension://pdegbjhgibenmgaaplhnpbnhaaipndoh/"]);
  });
});

describe("verifyContentScriptInjected", () => {
  it("returns the pointer tracker state from the isolated world when a context appears", async () => {
    const calls = [];
    const mockCdp = {
      events: [
        { method: "Runtime.executionContextCreated", params: { context: { id: 7, auxData: { type: "isolated" } } } }
      ],
      send: async (method, params, sessionId) => {
        calls.push({ method, params, sessionId });
        return { result: { result: { value: { hasLastPointer: false, linkClickProtectionEnabled: false } } } };
      }
    };
    const state = await verifyContentScriptInjected(mockCdp, "sess-1", 2000);
    assert.deepEqual(state, { hasLastPointer: false, linkClickProtectionEnabled: false });
    assert.equal(calls.length, 1);
    assert.equal(calls[0].method, "Runtime.evaluate");
    assert.equal(calls[0].params.contextId, 7);
    assert.equal(calls[0].sessionId, "sess-1");
  });

  it("returns null when no isolated context appears within the timeout", async () => {
    const mockCdp = {
      events: [],
      send: async () => ({ result: { result: { value: null } } })
    };
    const state = await verifyContentScriptInjected(mockCdp, "sess-1", 100);
    assert.equal(state, null);
  });
});

// Task 3: success 场景 active 检测修复 —— 经 CDP 附着扩展 service worker target，
// 在 SW 上下文执行 chrome.tabs.query({active:true}) 取真实 active tab，替换
// document.hasFocus()（后台无 GUI 焦点时对全部 tab 恒 false）。
describe("queryActiveTabs", () => {
  // CDP 真实响应形状：Runtime.evaluate(returnByValue + awaitPromise) 返回
  // { id, result: { result: { value: [...] } } }；value 即 chrome.tabs.query 解析出的 tabs 数组。
  it("runs chrome.tabs.query({active:true}) in the SW session and returns the resolved tabs array", async () => {
    const calls = [];
    const mockCdp = {
      send: async (method, params, sessionId) => {
        calls.push({ method, params, sessionId });
        return {
          result: {
            result: {
              value: [{ id: 5, url: "https://example.test/e2e-target", active: true }]
            }
          }
        };
      }
    };
    const tabs = await queryActiveTabs(mockCdp, "sw-sess");
    assert.deepEqual(tabs, [{ id: 5, url: "https://example.test/e2e-target", active: true }]);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].method, "Runtime.evaluate");
    assert.equal(calls[0].params.expression, "chrome.tabs.query({ active: true })");
    assert.equal(calls[0].params.returnByValue, true);
    assert.equal(calls[0].params.awaitPromise, true);
    assert.equal(calls[0].sessionId, "sw-sess");
  });

  it("returns [] when the evaluate response lacks the value (defensive)", async () => {
    const mockCdp = {
      send: async () => ({ result: { result: {} } })
    };
    const tabs = await queryActiveTabs(mockCdp, "s");
    assert.deepEqual(tabs, []);
  });
});

describe("markActiveByUrl", () => {
  it("marks the page target whose URL matches an active tab URL as active", () => {
    const pageTargets = [
      { targetId: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", type: "page" },
      { targetId: "TGT", url: "https://example.test/e2e-target", type: "page" }
    ];
    const activeTabs = [{ id: 5, url: "https://example.test/e2e-target", active: true }];
    const tabs = markActiveByUrl(pageTargets, activeTabs);
    assert.deepEqual(tabs, [
      { id: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
      { id: "TGT", url: "https://example.test/e2e-target", active: true }
    ]);
  });

  it("marks all tabs non-active when no active tab URL matches a page target", () => {
    const pageTargets = [
      { targetId: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", type: "page" }
    ];
    const tabs = markActiveByUrl(pageTargets, [{ id: 9, url: "about:blank", active: true }]);
    assert.deepEqual(tabs, [
      { id: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", active: false }
    ]);
  });

  // 真实运行发现：新 tab 打开后 TargetInfo.url 立即更新到固定目标，但 chrome.tabs
  // 的 url 要等导航 commit（status:"loading" 期间 url 为空，目标在 pendingUrl）。
  // active 判定必须同时匹配 url 与 pendingUrl，否则加载中的活动 tab 会被判为非 active。
  it("matches an active tab that is still loading via pendingUrl", () => {
    const pageTargets = [
      { targetId: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", type: "page" },
      { targetId: "TGT", url: "https://example.test/e2e-target", type: "page" }
    ];
    const activeTabs = [{
      id: 5, url: "", pendingUrl: "https://example.test/e2e-target",
      active: true, selected: true, status: "loading"
    }];
    const tabs = markActiveByUrl(pageTargets, activeTabs);
    assert.deepEqual(tabs, [
      { id: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
      { id: "TGT", url: "https://example.test/e2e-target", active: true }
    ]);
  });
});

describe("hasAdjacentTargetTab", () => {
  // TargetInfo.url 更新有延迟（实测最慢 ~4s）；本谓词用于轮询：目标 tab URL 是否
  // 已更新到固定目标（且不是 source tab 自身被原地导航）。
  it("is true when a non-source tab has the expected target URL", () => {
    const tabs = [
      { id: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
      { id: "TGT", url: "https://example.test/e2e-target", active: true }
    ];
    assert.equal(hasAdjacentTargetTab(tabs, "SRC", "https://example.test/e2e-target"), true);
  });

  it("is false while the adjacent tab URL has not updated yet", () => {
    const tabs = [
      { id: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
      { id: "TGT", url: "about:blank", active: true }
    ];
    assert.equal(hasAdjacentTargetTab(tabs, "SRC", "https://example.test/e2e-target"), false);
  });

  it("is false when only the source tab exists (guard not armed / source navigated)", () => {
    const tabs = [{ id: "SRC", url: "https://example.test/e2e-target", active: true }];
    assert.equal(hasAdjacentTargetTab(tabs, "SRC", "https://example.test/e2e-target"), false);
  });
});

describe("waitForTabs", () => {
  it("polls getTabs until the predicate is satisfied", async () => {
    let count = 0;
    const getTabs = async () => {
      count++;
      if (count === 1) {
        return [{ id: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", active: true }];
      }
      return [
        { id: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
        { id: "TGT", url: "https://example.test/e2e-target", active: true }
      ];
    };
    const tabs = await waitForTabs(
      getTabs,
      (t) => hasAdjacentTargetTab(t, "SRC", "https://example.test/e2e-target"),
      2000
    );
    assert.ok(tabs);
    assert.equal(tabs[1].url, "https://example.test/e2e-target");
    assert.ok(count >= 2);
  });

  it("returns null when the predicate is never satisfied within the timeout", async () => {
    const tabs = await waitForTabs(
      async () => [{ id: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", active: true }],
      (t) => hasAdjacentTargetTab(t, "SRC", "https://example.test/e2e-target"),
      100
    );
    assert.equal(tabs, null);
  });
});

// Task 4: leaseExpiry 语义与 guard trace 断言。
// 探针/实测确认：linkClickProtectionEnabled 生产恒 false，guard lease 过期或显式
// release 后 interactionGuard.active() 返回 null，普通点击本就不被拦截。leaseExpiry
// 的成功判据是"source 原地导航到固定目标、无新 tab"，且必须由 guard trace 证明
// guard 曾被 arm（链路存活）而点击时已无 guard——否则"点击放行"与"链路断裂恰好
// 放行"无法区分（缺口 I2）。
describe("leaseExpirySourceNavigated", () => {
  it("is true when the source tab URL equals the fixed target", () => {
    const tabs = [
      { id: "SRC", url: "https://example.test/e2e-target", active: true },
      { id: "OTHER", url: "http://127.0.0.1:4567/link-reliability.html", active: false }
    ];
    assert.equal(leaseExpirySourceNavigated(tabs, "SRC", "https://example.test/e2e-target"), true);
  });

  it("is false while the source tab has not navigated yet (TargetInfo.url 延迟)", () => {
    const tabs = [
      { id: "SRC", url: "http://127.0.0.1:4567/link-reliability.html", active: true },
      { id: "OTHER", url: "https://example.test/e2e-target", active: false }
    ];
    assert.equal(leaseExpirySourceNavigated(tabs, "SRC", "https://example.test/e2e-target"), false);
  });

  it("is false when the source tab is missing", () => {
    const tabs = [{ id: "OTHER", url: "https://example.test/e2e-target", active: true }];
    assert.equal(leaseExpirySourceNavigated(tabs, "SRC", "https://example.test/e2e-target"), false);
  });
});

describe("findTabIdByUrl", () => {
  // Task 4：leaseExpiry 前须把 source（fixture）tab 激活，否则 guard arm 路由到 success
  // 打开的目标 tab（无 content script）→ forward_failed。按 url/pendingUrl 找 chrome tab id。
  it("finds the chrome tab id by matching url", () => {
    const tabs = [
      { id: 5, url: "http://127.0.0.1:4567/link-reliability.html", active: false },
      { id: 7, url: "https://example.test/e2e-target", active: true }
    ];
    assert.equal(findTabIdByUrl(tabs, "http://127.0.0.1:4567/link-reliability.html"), 5);
  });

  it("matches a loading tab via pendingUrl (url 尚未 commit 时为空)", () => {
    const tabs = [{ id: 9, url: "", pendingUrl: "http://127.0.0.1:4567/link-reliability.html", active: true }];
    assert.equal(findTabIdByUrl(tabs, "http://127.0.0.1:4567/link-reliability.html"), 9);
  });

  it("returns null when no tab matches or input is not an array", () => {
    assert.equal(findTabIdByUrl([{ id: 7, url: "https://example.test/e2e-target" }], "http://127.0.0.1:4567/link-reliability.html"), null);
    assert.equal(findTabIdByUrl(null, "http://127.0.0.1:4567/link-reliability.html"), null);
    assert.equal(findTabIdByUrl(undefined, "http://127.0.0.1:4567/link-reliability.html"), null);
  });
});

describe("parseGuardTraceStages", () => {
  // 真实 message 形如 `guard_stage session=<gsid> stage=<stage> detail=<detail>`
  //（background.ts appendGuardTrace），存于 chrome.storage.local 的 gesturekitDiagnostics。
  const diagnostics = [
    { message: "guard_stage session=gs-1 stage=forwarding detail=content_script" },
    { message: "guard_stage session=gs-1 stage=armed detail=content_script_ack" },
    { message: "guard_stage session=gs-1 stage=forwarded detail=guard_armed" },
    { message: "guard_stage session=gs-2 stage=armed detail=content_script_ack" },
    { message: "settings applied version=7" }
  ];

  it("filters the session's guard_stage messages and extracts stage/detail", () => {
    const stages = parseGuardTraceStages(diagnostics, "gs-1");
    assert.deepEqual(stages, [
      { stage: "forwarding", detail: "content_script" },
      { stage: "armed", detail: "content_script_ack" },
      { stage: "forwarded", detail: "guard_armed" }
    ]);
  });

  it("returns [] for non-array input", () => {
    assert.deepEqual(parseGuardTraceStages(null, "gs-1"), []);
    assert.deepEqual(parseGuardTraceStages(undefined, "gs-1"), []);
  });

  it("returns [] when the session has no guard_stage entries", () => {
    assert.deepEqual(parseGuardTraceStages(diagnostics, "gs-999"), []);
  });
});

describe("matchGuardStageMessage", () => {
  it("parses a guard_stage message into sessionId/stage/detail", () => {
    assert.deepEqual(
      matchGuardStageMessage("guard_stage session=gs-1 stage=armed detail=content_script_ack"),
      { sessionId: "gs-1", stage: "armed", detail: "content_script_ack" }
    );
  });

  it("returns null for non-guard_stage messages and non-strings", () => {
    assert.equal(matchGuardStageMessage("settings applied version=7"), null);
    assert.equal(matchGuardStageMessage(undefined), null);
    assert.equal(matchGuardStageMessage(null), null);
  });
});

describe("guardTraceSessionsInWindow", () => {
  // 真实场景：runner 的 command gestureSessionId 与 App 内部 coordinator session ID 不同，
  // guard trace 断言按"arm 发生在命令发出之后"的时间窗口匹配，而非按 gsid 精确匹配。
  const diagnostics = [
    { timestamp: 1000, message: "guard_stage session=early stage=armed detail=content_script_ack" },
    { timestamp: 2000, message: "guard_stage session=cur stage=forwarding detail=content_script" },
    { timestamp: 2001, message: "guard_stage session=cur stage=armed detail=content_script_ack" },
    { timestamp: 2002, message: "guard_stage session=cur stage=forwarded detail=guard_armed" },
    { timestamp: 3000, message: "guard_stage session=late stage=click_blocked detail=active_guard" }
  ];

  it("groups guard_stage entries by session, keeping only timestamp >= afterMs", () => {
    const sessions = guardTraceSessionsInWindow(diagnostics, 1500);
    assert.equal(sessions.length, 2);
    const cur = sessions.find((s) => s.sessionId === "cur");
    assert.ok(cur, "窗口内应含 cur session");
    assert.deepEqual(cur.stages.map((s) => s.stage), ["forwarding", "armed", "forwarded"]);
    assert.equal(sessions.some((s) => s.sessionId === "early"), false, "窗口前的 session 应被排除");
  });

  it("returns [] for non-array input", () => {
    assert.deepEqual(guardTraceSessionsInWindow(null, 0), []);
    assert.deepEqual(guardTraceSessionsInWindow(undefined, 0), []);
  });

  it("returns [] when no guard_stage entry is within the window", () => {
    assert.deepEqual(guardTraceSessionsInWindow(diagnostics, 100000), []);
  });
});

describe("hasGuardTraceStage", () => {
  it("is true when the given stage is present", () => {
    assert.equal(hasGuardTraceStage([{ stage: "armed", detail: "content_script_ack" }], "armed"), true);
  });

  it("is false when the stage is absent or the list is empty", () => {
    assert.equal(hasGuardTraceStage([{ stage: "armed", detail: "x" }], "lease_expired"), false);
    assert.equal(hasGuardTraceStage([], "armed"), false);
  });
});

describe("hasForwardedGuardArmed", () => {
  // I2 断言的核心谓词：content script 只在 interactionGuard.arm() 后才回 guard_armed，
  // 因此 `forwarding` + `forwarded:guard_armed` 是"guard 确实被 arm"的直接证据。
  // 不依赖 `armed` 阶段——实测该阶段会与 background 并发持久化竞态丢失。
  it("is true when the session has forwarding and forwarded:guard_armed", () => {
    const stages = [
      { stage: "forwarding", detail: "content_script" },
      { stage: "forwarded", detail: "guard_armed" }
    ];
    assert.equal(hasForwardedGuardArmed(stages), true);
  });

  it("is false without forwarding (arm 未路由到 content script)", () => {
    const stages = [{ stage: "forwarded", detail: "guard_armed" }];
    assert.equal(hasForwardedGuardArmed(stages), false);
  });

  it("is false when forwarded detail is not guard_armed (content script 未 arm)", () => {
    const stages = [
      { stage: "forwarding", detail: "content_script" },
      { stage: "forward_failed", detail: "content_script_unavailable" }
    ];
    assert.equal(hasForwardedGuardArmed(stages), false);
  });

  it("is false for empty or non-array input", () => {
    assert.equal(hasForwardedGuardArmed([]), false);
    assert.equal(hasForwardedGuardArmed(null), false);
  });
});

describe("hasGuardBlockedClick", () => {
  it("is true when the click was intercepted (click_blocked or lease_expired)", () => {
    assert.equal(hasGuardBlockedClick([{ stage: "click_blocked", detail: "active_guard" }]), true);
    assert.equal(hasGuardBlockedClick([{ stage: "lease_expired", detail: "original_navigation_restored" }]), true);
  });

  it("is false when the click passed through unblocked", () => {
    const stages = [
      { stage: "forwarding", detail: "content_script" },
      { stage: "forwarded", detail: "guard_armed" }
    ];
    assert.equal(hasGuardBlockedClick(stages), false);
    assert.equal(hasGuardBlockedClick([]), false);
  });
});
