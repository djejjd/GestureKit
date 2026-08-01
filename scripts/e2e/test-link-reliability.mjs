import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { assertAdjacentActivatedTab, redactSummary, pageEvaluate, pageNavigate } from "./run-link-reliability.mjs";

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
