// ============================================================
// GestureKit Provider Protocol v2 — TypeScript 类型与运行时校验
// ============================================================
//
// 本文件定义 Provider 与 App 之间 v2 协议的类型定义和运行时校验函数。
// 字段名和枚举值必须与 JSON Schema 和 Swift Codable 模型一致。
//
// 设计原则：
// - Provider-neutral：不引用 Chrome API 或 Chrome 专用动作枚举。
// - 运行时校验：decodeProviderEnvelope 在解析时按 type → payload 映射
//   表严格分发，type-payload 不匹配直接拒绝。
// - Fail-closed：拒绝 protocolVersion≠2、空必填字段、非法 timestamp、
//   未知 type、type-payload 不匹配、缺失 operationId。
// - 跨语言一致：所有枚举值使用与 Swift/JSON Schema 相同的字符串值。

// MARK: - 常量

/** Provider Protocol v2 的协议主版本号。 */
export const PROVIDER_PROTOCOL_VERSION = 2 as const;

// MARK: - 标准动作 ID

/**
 * Provider Protocol v2 的标准动作 ID（7 种）。
 * 所有 V1 手势行为映射到这组标准化动作。
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

/** Provider Protocol v2 支持的消息类型（19 种）。 */
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
  | "operation_status_response"
  | "control_center_open_request"
  | "control_center_open_response";

// MARK: - 终端状态与原因枚举

/** action_result 的终端状态枚举。 */
export type ActionResultOutcome = "succeeded" | "failed" | "result_unknown";

/** ActionResult 的结构化原因枚举。 */
export type ActionResultReason =
  | "completed"
  | "guard_unavailable"
  | "guard_expired"
  | "context_expired"
  | "target_not_found"
  | "provider_timeout"
  | "provider_disconnected"
  | "storage_full"
  | "capability_unavailable"
  | "chrome_api_error"
  | "invalid_target"
  | "deadline_exceeded"
  | "recovery_timeout";

// MARK: - 上下文目标分类

export type ContextTargetKind =
  | "standard_link"
  | "no_target"
  | "page_unavailable";

// MARK: - 全部 17 种 Payload 类型定义

// ---------- 认证握手 ----------

export interface ProviderHelloPayload {
  installId: string;
  protocolVersions: number[];
  environment: string;
}

export interface ProviderChallengePayload {
  nonce: string;
  expiresAt: number;
}

export interface ProviderAuthenticatePayload {
  installId: string;
  hmac: string;
}

// ---------- 能力与上下文 ----------

export interface CapabilitySnapshotPayload {
  capabilities: StandardActionID[];
  capabilityVersion: number;
}

export interface ContextRequestPayload {
  gestureSessionId: string;
  requiresTargetRef: boolean;
  deadline: number;
}

export interface ContextSnapshotPayload {
  contextId: string;
  pageIdentity: string;
  expiresAt: number;
  targetKind: ContextTargetKind;
  targetRef: string | null;
}

// ---------- 配置 ----------

export interface ConfigurationSnapshotPayload {
  storeEpoch: string;
  schemaVersion: number;
  configurationVersion: number;
  configJSON: string;
}

export interface ConfigurationAckPayload {
  appliedVersion: number;
  applied: boolean;
}

// ---------- 动作执行 ----------

export interface ActionDescriptor {
  actionId: StandardActionID;
  contextId: string;
  targetRef: string | null;
  parameters: Record<string, string>;
  deadline: number;
}

export interface ActionAcceptedPayload {
  operationId: string;
  acceptedAt: number;
}

/** action_result 的 payload：Provider 返回显式 outcome、原因和完成时间。 */
export interface ProviderActionResultPayload {
  operationId: string;
  outcome: ActionResultOutcome;
  reason: ActionResultReason | null;
  completedAt: number;
}

// ---------- Telemetry ----------

export interface TelemetryBatchPayload {
  events: ProviderEvent[];
}

export interface TelemetryAckPayload {
  acknowledgedEventIds: string[];
}

// ---------- 健康与状态 ----------

export interface HealthProbePayload {
  probeSequence: number;
  sentAt: number;
}

export interface HealthResponsePayload {
  probeSequence: number;
  healthy: boolean;
}

export interface OperationStatusRequestPayload {
  operationId: string;
}

export interface OperationStatusResponsePayload {
  operationId: string;
  outcome: ActionResultOutcome;
}

export interface ControlCenterOpenRequestPayload {}

export interface ControlCenterOpenResponsePayload {
  opened: boolean;
}

// MARK: - Payload 联合类型

/**
 * Provider Protocol v2 的 payload 联合类型。
 * 具体类型由 envelope 的 type 字段通过映射表确定。
 */
export type ProviderPayload =
  | ProviderHelloPayload
  | ProviderChallengePayload
  | ProviderAuthenticatePayload
  | CapabilitySnapshotPayload
  | ContextRequestPayload
  | ContextSnapshotPayload
  | ConfigurationSnapshotPayload
  | ConfigurationAckPayload
  | ActionDescriptor
  | ActionAcceptedPayload
  | ProviderActionResultPayload
  | TelemetryBatchPayload
  | TelemetryAckPayload
  | HealthProbePayload
  | HealthResponsePayload
  | OperationStatusRequestPayload
  | OperationStatusResponsePayload
  | ControlCenterOpenRequestPayload
  | ControlCenterOpenResponsePayload;

// MARK: - Type → Payload 映射表

/**
 * 消息类型到 payload 类型的映射表。
 * 所有 19 种消息类型必须有对应条目，type-payload 不匹配直接拒绝。
 */
type PayloadFieldKind = "string" | "integer" | "boolean" | "stringArray" | "integerArray" | "object" | "stringMap" | "actionId" | "targetKind" | "outcome" | "reason" | "eventArray";

interface PayloadShape {
  required: Record<string, PayloadFieldKind>;
  optional?: Record<string, PayloadFieldKind>;
}

/** 单一跨语言 payload 白名单：字段名、是否必填和基础值类型均在此定义。 */
const PAYLOAD_TYPE_MAP: Record<ProviderMessageType, PayloadShape> = {
  provider_hello: { required: { installId: "string", protocolVersions: "integerArray", environment: "string" } },
  provider_challenge: { required: { nonce: "string", expiresAt: "integer" } },
  provider_authenticate: { required: { installId: "string", hmac: "string" } },
  capability_snapshot: { required: { capabilities: "stringArray", capabilityVersion: "integer" } },
  context_request: { required: { gestureSessionId: "string", requiresTargetRef: "boolean", deadline: "integer" } },
  context_snapshot: { required: { contextId: "string", pageIdentity: "string", expiresAt: "integer", targetKind: "targetKind" }, optional: { targetRef: "string" } },
  configuration_snapshot: { required: { storeEpoch: "string", schemaVersion: "integer", configurationVersion: "integer", configJSON: "string" } },
  configuration_ack: { required: { appliedVersion: "integer", applied: "boolean" } },
  action_request: { required: { actionId: "actionId", contextId: "string", parameters: "stringMap", deadline: "integer" }, optional: { targetRef: "string" } },
  action_accepted: { required: { operationId: "string", acceptedAt: "integer" } },
  action_result: { required: { operationId: "string", outcome: "outcome", completedAt: "integer" }, optional: { reason: "reason" } },
  telemetry_batch: { required: { events: "eventArray" } },
  telemetry_ack: { required: { acknowledgedEventIds: "stringArray" } },
  health_probe: { required: { probeSequence: "integer", sentAt: "integer" } },
  health_response: { required: { probeSequence: "integer", healthy: "boolean" } },
  operation_status_request: { required: { operationId: "string" } },
  operation_status_response: { required: { operationId: "string", outcome: "outcome" } },
  control_center_open_request: { required: {} },
  control_center_open_response: { required: { opened: "boolean" } },
};

// MARK: - Provider Error

export interface ProviderError {
  code: string;
  message: string;
}

// MARK: - Provider Envelope & Event

/**
 * Provider Protocol v2 的传输层信封。
 * 所有 App 与 Provider 之间的通信都使用此信封封装。
 */
export interface ProviderEnvelope {
  protocolVersion: typeof PROVIDER_PROTOCOL_VERSION;
  messageId: string;
  providerSessionId: string;
  gestureSessionId: string | null;
  operationId: string | null;
  type: ProviderMessageType;
  timestamp: number;
  payload: ProviderPayload;
  error: ProviderError | null;
}

/**
 * Provider 产生的不可变阶段事件，是操作证据链的最小单元。
 */
export interface ProviderEvent {
  eventId: string;
  producerSessionId: string;
  producerSequence: number;
  causedByEventId: string | null;
  monotonicClockMs: number;
  wallClockMs: number;
  gestureSessionId: string | null;
  operationId: string | null;
  type: ProviderMessageType;
  payload: ProviderPayload;
}

// MARK: - 合法消息类型集合

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
  "control_center_open_request",
  "control_center_open_response",
];

const VALID_MESSAGE_TYPE_SET = new Set<string>(VALID_MESSAGE_TYPES);

/** ActionResult 合法 outcome 值集合。 */
const VALID_OUTCOMES = new Set<string>(["succeeded", "failed", "result_unknown"]);

// MARK: - 运行时校验

/**
 * 校验 payload 与 type 是否匹配——payload 对象必须包含
 * 映射表中该 type 对应的全部关键字段。
 */
function validateTypePayloadMatch(
  type: ProviderMessageType,
  payload: Record<string, unknown>
): void {
  const shape = PAYLOAD_TYPE_MAP[type];
  if (!shape) {
    throw new Error(`decodeProviderEnvelope: 未知 message type: "${type}"`);
  }
  for (const [key, fieldKind] of Object.entries(shape.required)) {
    if (!(key in payload)) {
      throw new Error(
        `decodeProviderEnvelope: type="${type}" 与 payload 不匹配，缺少必填键 "${key}"`
      );
    }
    validatePayloadField(type, key, payload[key], fieldKind);
  }
  for (const [key, fieldKind] of Object.entries(shape.optional ?? {})) {
    if (key in payload && payload[key] !== null) {
      validatePayloadField(type, key, payload[key], fieldKind);
    }
  }
  const allowedKeys = new Set([...Object.keys(shape.required), ...Object.keys(shape.optional ?? {})]);
  const unknownKeys = Object.keys(payload).filter((key) => !allowedKeys.has(key));
  if (unknownKeys.length > 0) {
    throw new Error(`decodeProviderEnvelope: type="${type}" 的 payload 包含未声明字段: ${unknownKeys.join(",")}`);
  }
}

/** 校验白名单字段的基础 JSON 类型，避免仅凭键存在就进入可信边界。 */
function validatePayloadField(type: ProviderMessageType, key: string, value: unknown, kind: PayloadFieldKind): void {
  const isInteger = (v: unknown) => typeof v === "number" && Number.isFinite(v) && Number.isInteger(v) && v >= 0;
  const isStringArray = (v: unknown) => Array.isArray(v) && v.every((item) => typeof item === "string");
  const valid = (() => {
    switch (kind) {
      case "string": return typeof value === "string" && value.length > 0;
      case "integer": return isInteger(value);
      case "boolean": return typeof value === "boolean";
      case "stringArray": return isStringArray(value);
      case "integerArray": return Array.isArray(value) && value.every(isInteger);
      case "object": return typeof value === "object" && value !== null && !Array.isArray(value);
      case "stringMap": return typeof value === "object" && value !== null && !Array.isArray(value) && Object.values(value as Record<string, unknown>).every((item) => typeof item === "string");
      case "actionId": return typeof value === "string" && ["browser.link.open_adjacent", "browser.tab.activate_previous", "browser.tab.activate_next", "browser.tab.close_current", "browser.history.back", "browser.history.forward", "browser.page.reload"].includes(value);
      case "targetKind": return value === "standard_link" || value === "no_target" || value === "page_unavailable";
      case "outcome": return typeof value === "string" && VALID_OUTCOMES.has(value);
      case "reason": return typeof value === "string";
      case "eventArray": return Array.isArray(value) && value.every((item) => typeof item === "object" && item !== null);
    }
  })();
  if (!valid) {
    throw new Error(`decodeProviderEnvelope: type="${type}" 的 payload.${key} 非法`);
  }
}

/**
 * 校验 timestamp 是否为有限非负整数。
 */
function validateTimestamp(value: unknown): asserts value is number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || !Number.isInteger(value)) {
    throw new Error(
      `decodeProviderEnvelope: timestamp 必须为有限非负整数，实际为 ${String(value)}`
    );
  }
}

/**
 * 校验 action_* 类型消息必须有非空 operationId。
 */
function validateActionOperationId(
  type: ProviderMessageType,
  operationId: unknown
): void {
  const actionTypes: ProviderMessageType[] = ["action_request", "action_accepted", "action_result"];
  if (actionTypes.includes(type)) {
    if (typeof operationId !== "string" || operationId.length === 0) {
      throw new Error(
        `decodeProviderEnvelope: ${type} 必须携带非空 operationId`
      );
    }
  }
}

/**
 * 校验并解码 Provider Protocol v2 信封。
 *
 * 执行以下运行时 fail-closed 校验：
 * 1. 拒绝 legacy v1（检查 version/1 和 protocolVersion/1 两种形式）
 * 2. 校验 protocolVersion == 2
 * 3. 校验 messageId 和 providerSessionId 非空
 * 4. 校验消息类型为合法值
 * 5. 校验 timestamp 为有限非负整数
 * 6. type → payload 映射表严格分发
 * 7. action_* 类型必须有 operationId
 * 8. action_result 的 outcome 为合法枚举值
 * 9. error 键必须存在（值可为 null）
 *
 * @param data - 待校验的原始对象
 * @returns 类型化的 ProviderEnvelope
 * @throws 如果协议版本不匹配、缺少必填字段、类型不合法或 type-payload 不匹配
 */
export function decodeProviderEnvelope(data: unknown): ProviderEnvelope {
  if (typeof data !== "object" || data === null) {
    throw new Error("decodeProviderEnvelope: 输入必须为非 null 对象");
  }

  const record = data as Record<string, unknown>;

  // === 拒绝 legacy v1 ===
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

  // === 校验必填字段非空 ===
  for (const field of ["messageId", "providerSessionId"]) {
    const v = record[field];
    if (typeof v !== "string" || v.length === 0) {
      throw new Error(`decodeProviderEnvelope: ${field} 必须为非空字符串`);
    }
  }

  // === 校验 type ===
  const type = record["type"];
  if (typeof type !== "string" || !VALID_MESSAGE_TYPE_SET.has(type as string)) {
    throw new Error(
      `decodeProviderEnvelope: 不支持的 message type: "${String(type)}"`
    );
  }
  const msgType = type as ProviderMessageType;

  // === 校验 timestamp ===
  validateTimestamp(record["timestamp"]);

  // === error 键必须存在 ===
  if (!("error" in record)) {
    throw new Error("decodeProviderEnvelope: 缺少必填字段 error");
  }
  if (record["error"] !== null) {
    const error = record["error"];
    if (typeof error !== "object" || error === null || typeof (error as Record<string, unknown>)["code"] !== "string" || typeof (error as Record<string, unknown>)["message"] !== "string") {
      throw new Error("decodeProviderEnvelope: error 必须为 null 或含 code/message 的对象");
    }
  }

  // === 校验 payload 与 type 匹配 ===
  const payload = record["payload"];
  if (typeof payload !== "object" || payload === null) {
    throw new Error("decodeProviderEnvelope: payload 必须为非 null 对象");
  }
  validateTypePayloadMatch(msgType, payload as Record<string, unknown>);

  // === 校验 action_* 的 operationId ===
  validateActionOperationId(msgType, record["operationId"]);

  return data as unknown as ProviderEnvelope;
}
