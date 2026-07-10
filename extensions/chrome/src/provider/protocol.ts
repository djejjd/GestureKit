// ============================================================
// GestureKit Provider Protocol v2 — TypeScript 类型与运行时校验
// ============================================================
//
// 本文件定义 Provider 与 App 之间 v2 协议的类型定义和运行时校验函数。
// 字段名和枚举值必须与 JSON Schema（packages/protocol/schemas/provider-v2.schema.json）
// 和 Swift Codable 模型（Sources/GestureKitCore/Provider/ProviderProtocolV2.swift）一致。
//
// 设计原则：
// - Provider-neutral：不引用 Chrome API 或 Chrome 专用动作枚举。
// - 运行时校验：decodeProviderEnvelope 在解析时校验 protocolVersion == 2，
//   拒绝 legacy v1（version: 1）消息。
// - 跨语言一致：所有枚举值使用与 Swift/JSON Schema 相同的字符串值。

// MARK: - 常量

/** Provider Protocol v2 的协议主版本号。 */
export const PROVIDER_PROTOCOL_VERSION = 2 as const;

// MARK: - 标准动作 ID

/**
 * Provider Protocol v2 的标准动作 ID。
 * 所有 V1 手势行为映射到这组标准化动作。
 *
 * V1 映射：
 * - 三指点按链接 → browser.link.open_adjacent
 * - 左边缘点按 → browser.tab.activate_previous
 * - 右边缘点按 → browser.tab.activate_next
 * - 中间双击 → browser.tab.close_current
 * - 三指左轻扫 → browser.tab.activate_next
 * - 三指右轻扫 → browser.tab.activate_previous
 */
export type StandardActionID =
  | "browser.link.open_adjacent"
  | "browser.tab.activate_previous"
  | "browser.tab.activate_next"
  | "browser.tab.close_current"
  | "browser.history.back"
  | "browser.history.forward"
  | "browser.page.reload";

// MARK: - 消息类型

/**
 * Provider Protocol v2 支持的消息类型。
 * 所有值使用 snake_case 以保持与 JSON 协议字段一致。
 */
export type ProviderMessageType =
  | "provider_hello"
  | "provider_challenge"
  | "provider_authenticate"
  | "capability_snapshot"
  | "context_request"
  | "context_snapshot"
  | "configuration_snapshot"
  | "configuration_ack"
  | "action_request"
  | "action_accepted"
  | "action_result"
  | "telemetry_batch"
  | "telemetry_ack"
  | "health_probe"
  | "health_response"
  | "operation_status_request"
  | "operation_status_response";

// MARK: - 上下文目标类型

/**
 * Context snapshot 的目标分类。
 * 仅 standard_link 允许绑定 browser.link.open_adjacent 动作。
 */
export type ContextTargetKind =
  | "standard_link"
  | "no_target"
  | "page_unavailable";

// MARK: - Provider 错误

/** Provider Protocol v2 的结构化错误。 */
export interface ProviderError {
  /** 错误码，如 "provider_storage_full" */
  code: string;
  /** 人类可读的错误说明（仅用于诊断） */
  message: string;
}

// MARK: - Action Descriptor

/**
 * 标准动作描述，由 RuleEngine 在规则匹配后生成。
 * Provider 必须验证上下文未过期且页面身份匹配后才执行动作。
 */
export interface ActionDescriptor {
  /** 标准动作 ID */
  actionId: StandardActionID;
  /** 此前通过 context_snapshot 获得的上下文 ID */
  contextId: string;
  /** Provider 内部的不透明目标引用（仅链接动作需要）。可为 null */
  targetRef: string | null;
  /** 动作参数，如 { activate: "true" } */
  parameters: Record<string, string>;
  /** 动作截止时间（Unix 毫秒时间戳） */
  deadline: number;
}

// MARK: - Context Snapshot Payload

/**
 * context_snapshot 的 payload。
 *
 * 约束：只允许携带 contextId、页面身份、过期时间、
 * 标准 target facts 和不透明 targetRef；不得包含 URL query/hash、
 * DOM 文本、id/class、Cookie、表单值或自由文本 details。
 */
export interface ContextSnapshotPayload {
  /** 本次上下文快照的唯一 ID */
  contextId: string;
  /** 页面身份标识，通常为脱敏后的页面 host */
  pageIdentity: string;
  /** 上下文过期时间（Unix 毫秒时间戳） */
  expiresAt: number;
  /** 指针命中结果的枚举分类 */
  targetKind: ContextTargetKind;
  /** Provider 内部的不透明目标引用。仅在 targetKind=standard_link 时有值 */
  targetRef: string | null;
}

// MARK: - Provider Envelope 与 Event

/**
 * Provider Protocol v2 的传输层信封。
 *
 * 所有 App 与 Provider 之间的通信都使用此信封封装。
 * Provider v2 边界必须在解码时校验 protocolVersion == 2。
 */
export interface ProviderEnvelope {
  /** 协议主版本号。Provider v2 边界仅接受 2。 */
  protocolVersion: typeof PROVIDER_PROTOCOL_VERSION;
  /** 消息级别唯一标识 */
  messageId: string;
  /** Provider 认证会话 ID */
  providerSessionId: string;
  /** 关联的手势会话 ID。可为 null */
  gestureSessionId: string | null;
  /** 关联的幂等操作 ID。可为 null */
  operationId: string | null;
  /** 消息类型 */
  type: ProviderMessageType;
  /** 消息产生时的 Unix 毫秒时间戳 */
  timestamp: number;
  /** 消息体。具体结构由 type 字段决定 */
  payload: ActionDescriptor | ContextSnapshotPayload | Record<string, unknown>;
  /** 结构化错误。成功消息为 null */
  error: ProviderError | null;
}

/**
 * Provider 产生的不可变阶段事件，是操作证据链的最小单元。
 *
 * 用于 operation journal 和 outbox，携带完整的溯源信息。
 */
export interface ProviderEvent {
  /** 全局唯一事件 ID */
  eventId: string;
  /** 产生此事件的 producer 会话 ID */
  producerSessionId: string;
  /** 生产者侧的单调递增序号 */
  producerSequence: number;
  /** 跨进程因果关系。首事件可为 null */
  causedByEventId: string | null;
  /** 单调时钟（毫秒），用于跨进程时序比对 */
  monotonicClockMs: number;
  /** wall-clock（Unix 毫秒时间戳） */
  wallClockMs: number;
  /** 关联的手势会话 ID */
  gestureSessionId: string | null;
  /** 关联的幂等操作 ID */
  operationId: string | null;
  /** 事件对应的消息类型 */
  type: ProviderMessageType;
  /** 事件 payload */
  payload: ActionDescriptor | ContextSnapshotPayload | Record<string, unknown>;
}

// MARK: - 运行时校验

/**
 * Provider Protocol v2 支持的消息类型列表，用于运行时校验。
 */
const VALID_MESSAGE_TYPES: readonly ProviderMessageType[] = [
  "provider_hello",
  "provider_challenge",
  "provider_authenticate",
  "capability_snapshot",
  "context_request",
  "context_snapshot",
  "configuration_snapshot",
  "configuration_ack",
  "action_request",
  "action_accepted",
  "action_result",
  "telemetry_batch",
  "telemetry_ack",
  "health_probe",
  "health_response",
  "operation_status_request",
  "operation_status_response",
];

const VALID_MESSAGE_TYPE_SET = new Set<string>(VALID_MESSAGE_TYPES);

/**
 * 校验并解码 Provider Protocol v2 信封。
 *
 * 执行以下运行时校验：
 * 1. 拒绝 legacy v1（检查 version/1 和 protocolVersion/1 两种形式）
 * 2. 校验 protocolVersion == 2
 * 3. 校验必填字段非空
 * 4. 校验消息类型为合法值
 *
 * @param data - 待校验的原始对象
 * @returns 类型化的 ProviderEnvelope
 * @throws 如果协议版本不匹配、缺少必填字段或类型不合法
 */
export function decodeProviderEnvelope(data: unknown): ProviderEnvelope {
  if (typeof data !== "object" || data === null) {
    throw new Error("decodeProviderEnvelope: 输入必须为非 null 对象");
  }

  const record = data as Record<string, unknown>;

  // === 拒绝 legacy v1 ===
  // V1 使用 "version" 而非 "protocolVersion"。检测到 version 字段即拒绝。
  if (record["version"] !== undefined) {
    throw new Error(
      "decodeProviderEnvelope: legacy v1 消息不被 Provider v2 边界接受（protocolVersion 字段应为 2，而非 version）"
    );
  }

  // === 校验 protocolVersion ===
  if (record["protocolVersion"] === undefined) {
    throw new Error("decodeProviderEnvelope: 缺少必填字段 protocolVersion");
  }
  if (record["protocolVersion"] !== PROVIDER_PROTOCOL_VERSION) {
    throw new Error(
      `decodeProviderEnvelope: Provider v2 边界拒绝 protocolVersion=${record["protocolVersion"]}，期望 ${PROVIDER_PROTOCOL_VERSION}`
    );
  }

  // === 校验必填字段 ===
  const requiredFields = ["messageId", "providerSessionId", "type", "timestamp", "payload", "error"];
  for (const field of requiredFields) {
    if (record[field] === undefined) {
      throw new Error(`decodeProviderEnvelope: 缺少必填字段 ${field}`);
    }
  }

  // === 校验消息类型 ===
  const type = record["type"];
  if (typeof type !== "string" || !VALID_MESSAGE_TYPE_SET.has(type as string)) {
    throw new Error(
      `decodeProviderEnvelope: 不支持的 message type: ${String(type)}`
    );
  }

  // === 校验 timestamp ===
  const ts = record["timestamp"];
  if (typeof ts !== "number" || ts < 0) {
    throw new Error(
      `decodeProviderEnvelope: timestamp 必须为非负整数，实际为 ${String(ts)}`
    );
  }

  return data as ProviderEnvelope;
}
