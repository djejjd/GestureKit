import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { assertAdjacentActivatedTab, redactSummary } from "./run-link-reliability.mjs";

// Step 1: runner 失败测试 — 测试 helper 函数在校验和脱敏时拒绝非法输入。
// 在 runner 实现前这些 import 会抛 MODULE_NOT_FOUND，满足 Step 2 的 FAIL 预期。

describe("assertAdjacentActivatedTab", () => {
  it("accepts only an adjacent active fixed-target tab", () => {
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

  it("rejects non-adjacent active tabs", () => {
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
      /adjacent/
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

  it("rejects when source tab is the only active tab", () => {
    assert.throws(
      () =>
        assertAdjacentActivatedTab(
          [
            { id: "source", url: "http://127.0.0.1:4567/link-reliability.html", active: true },
            { id: "target", url: "https://example.test/e2e-target", active: false }
          ],
          "source"
        ),
      /adjacent/
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
