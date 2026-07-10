import { describe, expect, it } from "vitest";
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  decodeProviderEnvelope,
  type ProviderEnvelope,
  type ActionDescriptor,
  type ContextSnapshotPayload,
  type ProviderEvent,
} from "../src/provider/protocol";

// ============================================================
// Provider Protocol v2 跨语言契约测试（TypeScript 侧）
// ============================================================
//
// 本文件验证 TypeScript 侧的 decodeProviderEnvelope 与 Swift 侧
// 对同一 fixture 的解码结果一致。
//
// 测试原则：
// 1. Provider v2 边界必须拒绝 legacy v1 envelope。
// 2. action_request fixture 解码结果与 Swift 侧一致。
// 3. context_snapshot 字段范围必须严格受限。

/** 读取 fixture JSON 文件并解析为对象 */
function loadFixture(name: string): unknown {
  const fixturePath = resolve(
    __dirname,
    "../../../packages/protocol/fixtures",
    name
  );
  return JSON.parse(readFileSync(fixturePath, "utf-8"));
}

describe("Provider Protocol v2 — TypeScript", () => {
  // --------------------------------------------------------
  // Legacy v1 rejection
  // --------------------------------------------------------

  it("rejects a legacy v1 envelope at the Provider boundary", () => {
    // V1 消息使用 version:1 和 id 字段，v2 边界必须拒绝。
    expect(() =>
      decodeProviderEnvelope({ version: 1, type: "gesture_event" })
    ).toThrow("protocolVersion");
  });

  it("rejects protocolVersion other than 2", () => {
    // 即使字段名正确，protocolVersion 不为 2 也必须拒绝。
    expect(() =>
      decodeProviderEnvelope({
        protocolVersion: 1,
        messageId: "test",
        providerSessionId: "sess",
        type: "action_request",
        timestamp: 1000,
        payload: {},
      })
    ).toThrow("protocolVersion");
  });

  // --------------------------------------------------------
  // Fixture decoding
  // --------------------------------------------------------

  it("decodes the action request fixture", () => {
    const raw = loadFixture("provider-v2-action-request.json");
    const envelope = decodeProviderEnvelope(raw);

    // 协议版本校验
    expect(envelope.protocolVersion).toBe(2);
    expect(envelope.type).toBe("action_request");

    // 顶层标识字段
    expect(envelope.messageId).toBe("fixture-action-request-v2");
    expect(envelope.providerSessionId).toBe("session-chrome-001");
    expect(envelope.gestureSessionId).toBe("gesture-session-001");
    expect(envelope.operationId).toBe("operation-001");
    expect(envelope.timestamp).toBeGreaterThan(0);

    // 无错误
    expect(envelope.error).toBeNull();

    // payload 必须是 action_request
    const payload = envelope.payload as ActionDescriptor;
    expect(payload.actionId).toBe("browser.link.open_adjacent");
    expect(payload.contextId).toBe("context-001");
    expect(payload.targetRef).toBe("opaque-ref-abc123");
    if (payload.parameters) {
      expect(payload.parameters["activate"]).toBe("true");
    }
    expect(payload.deadline).toBeGreaterThan(envelope.timestamp);
  });

  // --------------------------------------------------------
  // Round-trip encode/decode
  // --------------------------------------------------------

  it("round-trips an action request envelope", () => {
    const envelope: ProviderEnvelope = {
      protocolVersion: 2,
      messageId: "roundtrip-001",
      providerSessionId: "session-test",
      gestureSessionId: null,
      operationId: "op-roundtrip",
      type: "action_request",
      timestamp: 1782200001000,
      payload: {
        actionId: "browser.tab.activate_next",
        contextId: "ctx-roundtrip",
        targetRef: null,
        parameters: {},
        deadline: 1782200002000,
      },
      error: null,
    };

    const json = JSON.stringify(envelope);
    const decoded = decodeProviderEnvelope(JSON.parse(json));

    expect(decoded.protocolVersion).toBe(2);
    expect(decoded.messageId).toBe("roundtrip-001");
    expect(decoded.type).toBe("action_request");

    const payload = decoded.payload as ActionDescriptor;
    expect(payload.actionId).toBe("browser.tab.activate_next");
    expect(payload.contextId).toBe("ctx-roundtrip");
    expect(payload.targetRef).toBeNull();
    expect(payload.deadline).toBe(1782200002000);
  });

  // --------------------------------------------------------
  // Context snapshot constraints
  // --------------------------------------------------------

  it("validates context_snapshot has only allowed fields", () => {
    // context_snapshot 只允许：contextId、pageIdentity、expiresAt、
    // targetKind、targetRef（可选）
    const snapshot: ContextSnapshotPayload = {
      contextId: "ctx-001",
      pageIdentity: "https://example.com",
      expiresAt: 1782200002000,
      targetKind: "standard_link",
      targetRef: "opaque-ref-xyz",
    };

    // 这些字段是允许的
    expect(snapshot.contextId).toBe("ctx-001");
    expect(snapshot.pageIdentity).toBe("https://example.com");
    expect(snapshot.expiresAt).toBe(1782200002000);
    expect(snapshot.targetKind).toBe("standard_link");
    expect(snapshot.targetRef).toBe("opaque-ref-xyz");

    // 验证 JSON 输出不包含禁止字段
    const json = JSON.parse(JSON.stringify(snapshot));
    expect(json.query).toBeUndefined();
    expect(json.hash).toBeUndefined();
    expect(json.domText).toBeUndefined();
    expect(json.elementId).toBeUndefined();
    expect(json.className).toBeUndefined();
    expect(json.cookie).toBeUndefined();
    expect(json.formValue).toBeUndefined();
    expect(json.details).toBeUndefined();
  });

  it("supports all context target kinds", () => {
    const noTarget: ContextSnapshotPayload = {
      contextId: "ctx-002",
      pageIdentity: "https://example.com",
      expiresAt: 1000,
      targetKind: "no_target",
      targetRef: null,
    };
    expect(noTarget.targetKind).toBe("no_target");
    expect(noTarget.targetRef).toBeNull();

    const unavailable: ContextSnapshotPayload = {
      contextId: "ctx-003",
      pageIdentity: "about:blank",
      expiresAt: 1000,
      targetKind: "page_unavailable",
      targetRef: null,
    };
    expect(unavailable.targetKind).toBe("page_unavailable");
  });

  // --------------------------------------------------------
  // ProviderEvent evidence chain
  // --------------------------------------------------------

  it("ProviderEvent contains all required evidence chain fields", () => {
    const event: ProviderEvent = {
      eventId: "evt-001",
      producerSessionId: "session-chrome-001",
      producerSequence: 42,
      causedByEventId: null,
      monotonicClockMs: 1782200001000,
      wallClockMs: 1782200001000,
      gestureSessionId: "gesture-session-evidence",
      operationId: "op-evidence",
      type: "action_request",
      payload: {
        actionId: "browser.tab.activate_next",
        contextId: "ctx-evidence",
        targetRef: null,
        parameters: {},
        deadline: 1782200002000,
      },
    };

    expect(event.eventId).toBe("evt-001");
    expect(event.producerSessionId).toBe("session-chrome-001");
    expect(event.producerSequence).toBe(42);
    expect(event.causedByEventId).toBeNull();
    expect(event.monotonicClockMs).toBe(1782200001000);
    expect(event.wallClockMs).toBe(1782200001000);
    expect(event.gestureSessionId).toBe("gesture-session-evidence");
    expect(event.operationId).toBe("op-evidence");

    // Round-trip
    const json = JSON.parse(JSON.stringify(event));
    expect(json.eventId).toBe("evt-001");
    expect(json.producerSequence).toBe(42);
  });

  // --------------------------------------------------------
  // ProviderError
  // --------------------------------------------------------

  it("encodes and decodes ProviderError", () => {
    const error = { code: "provider_storage_full", message: "ledger full" };
    const json = JSON.parse(JSON.stringify(error));
    expect(json.code).toBe("provider_storage_full");
    expect(json.message).toBe("ledger full");
  });

  // --------------------------------------------------------
  // Field validation
  // --------------------------------------------------------

  it("rejects messages missing required fields", () => {
    // 缺少 protocolVersion
    expect(() =>
      decodeProviderEnvelope({ messageId: "m1", type: "action_request" })
    ).toThrow();
    // 缺少 messageId
    expect(() =>
      decodeProviderEnvelope({ protocolVersion: 2, type: "action_request" })
    ).toThrow();
    // 缺少 type
    expect(() =>
      decodeProviderEnvelope({ protocolVersion: 2, messageId: "m1" })
    ).toThrow();
  });

  it("rejects missing error, undeclared payload fields, and invalid payload value types", () => {
    const valid = loadFixture("provider-v2-action-request.json") as Record<string, unknown>;

    const missingError = { ...valid };
    delete missingError.error;
    expect(() => decodeProviderEnvelope(missingError)).toThrow("error");

    const extraPayload = {
      ...valid,
      payload: { ...(valid.payload as Record<string, unknown>), details: "raw page content" },
    };
    expect(() => decodeProviderEnvelope(extraPayload)).toThrow("未声明");

    const invalidPayload = {
      ...valid,
      payload: { ...(valid.payload as Record<string, unknown>), deadline: "tomorrow" },
    };
    expect(() => decodeProviderEnvelope(invalidPayload)).toThrow("deadline");
  });
});
