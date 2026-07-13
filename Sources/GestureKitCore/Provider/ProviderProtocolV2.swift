import Foundation

// ============================================================
// GestureKit Provider Protocol v2 — 核心类型
// ============================================================
//
// 本文件定义 Provider 与 App 之间的 v2 协议模型，所有消息
// 使用 ProviderEnvelope 封装。legacy GestureKitMessage (version:1)
// 仅存在于 Chrome adapter 迁移边界，与此版本不兼容。
//
// 设计原则：
// - Provider-neutral：不引用 Chrome API、Chrome 专用动作枚举或 connectNative()。
// - 跨语言一致：JSON Schema（packages/protocol/schemas/provider-v2.schema.json）、
//   Swift Codable 模型和 TypeScript 类型三方共享同一组字段名和枚举值。
// - 证据链完备：ProviderEvent 提供完整的 production 溯源信息，
//   支持在不依赖现场的情况下重建操作时序。
// - Fail-closed：解码时拒绝所有类型-载荷不匹配、缺失必填键和非法值，
//   不执行宽容静默降级。

// MARK: - 协议版本

/// Provider Protocol v2 的协议主版本号。
/// Provider v2 边界仅接受 protocolVersion == 2 的消息。
public let PROVIDER_PROTOCOL_VERSION: Int = 2

// MARK: - 消息类型

/// Provider Protocol v2 支持的消息类型枚举。
///
/// 所有消息类型使用 snake_case 命名以保持与 JSON 协议字段一致。
/// 每种消息类型通过 Map 映射到唯一允许的 payload 类型。
public enum ProviderMessageType: String, Codable, Sendable, CaseIterable, Equatable {
    // 认证握手
    case providerHello = "provider_hello"
    case providerChallenge = "provider_challenge"
    case providerAuthenticate = "provider_authenticate"
    // 能力与上下文
    case capabilitySnapshot = "capability_snapshot"
    case contextRequest = "context_request"
    case contextSnapshot = "context_snapshot"
    // 配置
    case configurationSnapshot = "configuration_snapshot"
    case configurationAck = "configuration_ack"
    // 动作执行
    case actionRequest = "action_request"
    case actionAccepted = "action_accepted"
    case actionResult = "action_result"
    // Telemetry
    case telemetryBatch = "telemetry_batch"
    case telemetryAck = "telemetry_ack"
    // 健康与状态
    case healthProbe = "health_probe"
    case healthResponse = "health_response"
    case operationStatusRequest = "operation_status_request"
    case operationStatusResponse = "operation_status_response"
    case controlCenterOpenRequest = "control_center_open_request"
    case controlCenterOpenResponse = "control_center_open_response"
}

// MARK: - 结构化错误

/// Provider Protocol v2 的结构化错误。code 供程序判断错误类型，
/// message 供日志和诊断使用，不得直接显示在用户界面。
public struct ProviderError: Codable, Sendable, Equatable {
    /// 错误码，如 "provider_storage_full"、"type_payload_mismatch"
    public let code: String
    /// 人类可读的错误说明（仅用于诊断，不直接显示在 UI）
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - 标准动作 ID

/// Provider Protocol v2 的标准动作 ID（7 个）。
public enum StandardActionID: String, Codable, Sendable, Equatable, CaseIterable {
    case browserLinkOpenAdjacent = "browser.link.open_adjacent"
    case browserTabActivatePrevious = "browser.tab.activate_previous"
    case browserTabActivateNext = "browser.tab.activate_next"
    case browserTabCloseCurrent = "browser.tab.close_current"
    case browserHistoryBack = "browser.history.back"
    case browserHistoryForward = "browser.history.forward"
    case browserPageReload = "browser.page.reload"
}

// MARK: - 动作结果

/// action_result 的终端状态枚举。Journal 仅依据此字段写终态。
public enum ActionResultOutcome: String, Codable, Sendable, Equatable, CaseIterable {
    /// 操作成功完成
    case succeeded
    /// 操作明确失败（对应 Reason 说明原因）
    case failed
    /// 结果无法在 deadline 前确定（如 Provider 断开）
    case resultUnknown = "result_unknown"
}

/// ActionResult 的原因枚举，为 ActionFailed/ResultUnknown 提供结构化解释，
/// 不依赖自由文本 message。
public enum ActionResultReason: String, Codable, Sendable, Equatable {
    // 成功场景
    case completed
    // 失败原因
    case guardUnavailable = "guard_unavailable"
    case guardExpired = "guard_expired"
    case contextExpired = "context_expired"
    case targetNotFound = "target_not_found"
    case providerTimeout = "provider_timeout"
    case providerDisconnected = "provider_disconnected"
    case storageFull = "storage_full"
    case capabilityUnavailable = "capability_unavailable"
    case chromeApiError = "chrome_api_error"
    case invalidTarget = "invalid_target"
    // 不确定结果原因
    case deadlineExceeded = "deadline_exceeded"
    case recoveryTimeout = "recovery_timeout"
}

// MARK: - 上下文目标分类

/// Context snapshot 目标分类。仅 standardLink 允许绑定 browser.link.open_adjacent。
public enum ContextTargetKind: String, Codable, Sendable, Equatable {
    case standardLink = "standard_link"
    case noTarget = "no_target"
    case pageUnavailable = "page_unavailable"
}

// ============================================================
// MARK: - 全部 17 种 Payload 定义
// ============================================================

// ---------- 认证握手 ----------

/// provider_hello 的 payload：Provider 声明身份、协议版本和运行环境。
public struct ProviderHelloPayload: Codable, Sendable, Equatable {
    /// Provider 安装 ID
    public let installId: String
    /// Provider 实现的协议版本范围
    public let protocolVersions: [Int]
    /// 运行环境标识（如 "chrome-extension-3.x"）
    public let environment: String

    public init(installId: String, protocolVersions: [Int], environment: String) {
        self.installId = installId
        self.protocolVersions = protocolVersions
        self.environment = environment
    }
}

/// provider_challenge 的 payload：App 向 Provider 发送随机 challenge。
public struct ProviderChallengePayload: Codable, Sendable, Equatable {
    /// 随机 nonce（Base64 编码）
    public let nonce: String
    /// Challenge 过期时间（Unix 毫秒时间戳）
    public let expiresAt: Int64

    public init(nonce: String, expiresAt: Int64) {
        self.nonce = nonce
        self.expiresAt = expiresAt
    }
}

/// provider_authenticate 的 payload：Provider 回应 HMAC challenge。
public struct ProviderAuthenticatePayload: Codable, Sendable, Equatable {
    /// 安装 ID
    public let installId: String
    /// HMAC-SHA256(secret, nonce) 的十六进制编码结果
    public let hmac: String

    public init(installId: String, hmac: String) {
        self.installId = installId
        self.hmac = hmac
    }
}

// ---------- 能力与上下文 ----------

/// capability_snapshot 的 payload：Provider 声明当前支持的标准动作和上下文能力。
public struct CapabilitySnapshotPayload: Codable, Sendable, Equatable {
    /// Provider 支持的标准动作 ID 列表
    public let capabilities: [StandardActionID]
    /// Provider 能力版本号
    public let capabilityVersion: Int

    public init(capabilities: [StandardActionID], capabilityVersion: Int) {
        self.capabilities = capabilities
        self.capabilityVersion = capabilityVersion
    }
}

/// context_request 的 payload：App 请求完成规则匹配所需的当前环境事实。
public struct ContextRequestPayload: Codable, Sendable, Equatable {
    /// 关联的手势会话 ID
    public let gestureSessionId: String
    /// 是否需要不透明链接目标；标签页动作只需要当前页面上下文。
    public let requiresTargetRef: Bool
    /// 请求过期时间（Unix 毫秒时间戳）
    public let deadline: Int64

    public init(gestureSessionId: String, requiresTargetRef: Bool, deadline: Int64) {
        self.gestureSessionId = gestureSessionId
        self.requiresTargetRef = requiresTargetRef
        self.deadline = deadline
    }
}

/// context_snapshot 的 payload：Provider 返回带 contextId、页面身份、采集时间和过期时间的只读事实。
/// 约束：只允许携带 contextId、页面身份、过期时间、标准 target facts 和不透明 targetRef；
/// 不得包含 URL query/hash、DOM 文本、id/class、Cookie、表单值或自由文本 details。
public struct ContextSnapshotPayload: Codable, Sendable, Equatable {
    /// 本次上下文快照的唯一 ID，供后续 ActionDescriptor 引用
    public let contextId: String
    /// 页面身份标识。通常为脱敏后的页面 host，供 RuleEngine 判断页面类型
    public let pageIdentity: String
    /// 上下文过期时间（Unix 毫秒时间戳）。之后 contextId 不再有效
    public let expiresAt: Int64
    /// 指针命中结果的枚举分类
    public let targetKind: ContextTargetKind
    /// Provider 内部的不透明目标引用。仅在 targetKind == standardLink 时有值。
    /// Web 环境中表达为对应链接元素 offset/label hash，不能可逆还原为 URL
    public let targetRef: String?

    public init(
        contextId: String,
        pageIdentity: String,
        expiresAt: Int64,
        targetKind: ContextTargetKind,
        targetRef: String?
    ) {
        self.contextId = contextId
        self.pageIdentity = pageIdentity
        self.expiresAt = expiresAt
        self.targetKind = targetKind
        self.targetRef = targetRef
    }
}

// ---------- 配置 ----------

/// configuration_snapshot 的 payload：App 下发权威配置快照。
public struct ConfigurationSnapshotPayload: Codable, Sendable, Equatable {
    /// 配置 epoch 标识
    public let storeEpoch: String
    /// Schema 版本
    public let schemaVersion: Int
    /// 单调递增的配置版本号
    public let configurationVersion: Int64
    /// 序列化后的配置内容（JSON 字符串）
    public let configJSON: String

    public init(storeEpoch: String, schemaVersion: Int, configurationVersion: Int64, configJSON: String) {
        self.storeEpoch = storeEpoch
        self.schemaVersion = schemaVersion
        self.configurationVersion = configurationVersion
        self.configJSON = configJSON
    }
}

/// configuration_ack 的 payload：Provider 确认已应用的配置版本。
public struct ConfigurationAckPayload: Codable, Sendable, Equatable {
    /// 已应用的配置版本号
    public let appliedVersion: Int64
    /// 是否成功应用
    public let applied: Bool

    public init(appliedVersion: Int64, applied: Bool) {
        self.appliedVersion = appliedVersion
        self.applied = applied
    }
}

// ---------- 动作执行 ----------

/// 标准动作描述，由 RuleEngine 在规则匹配后生成。
public struct ActionDescriptor: Codable, Sendable, Equatable {
    /// 标准动作 ID
    public let actionId: StandardActionID
    /// 此前通过 context_snapshot 获得的上下文 ID
    public let contextId: String
    /// Provider 内部的不透明目标引用（仅链接动作需要）
    public let targetRef: String?
    /// 动作参数
    public let parameters: [String: String]
    /// 动作截止时间（Unix 毫秒时间戳）
    public let deadline: Int64

    public init(
        actionId: StandardActionID,
        contextId: String,
        targetRef: String?,
        parameters: [String: String],
        deadline: Int64
    ) {
        self.actionId = actionId
        self.contextId = contextId
        self.targetRef = targetRef
        self.parameters = parameters
        self.deadline = deadline
    }
}

/// action_accepted 的 payload：Provider 确认已接管动作。
public struct ActionAcceptedPayload: Codable, Sendable, Equatable {
    /// 关联的操作 ID
    public let operationId: String
    /// 接管时间（Unix 毫秒时间戳）
    public let acceptedAt: Int64

    public init(operationId: String, acceptedAt: Int64) {
        self.operationId = operationId
        self.acceptedAt = acceptedAt
    }
}

/// action_result 的 payload：Provider 返回成功、明确失败或结果未知。
///
/// Journal 只能依据 outcome 字段或自身超时恢复规则写终态，
/// 不得仅凭 action_result 消息类型推断成功。
public struct ProviderActionResultPayload: Codable, Sendable, Equatable {
    /// 操作 ID
    public let operationId: String
    /// 显式终态值
    public let outcome: ActionResultOutcome
    /// 结构化原因，不依赖自由文本 message
    public let reason: ActionResultReason?
    /// 完成时间（Unix 毫秒时间戳）
    public let completedAt: Int64

    public init(operationId: String, outcome: ActionResultOutcome, reason: ActionResultReason?, completedAt: Int64) {
        self.operationId = operationId
        self.outcome = outcome
        self.reason = reason
        self.completedAt = completedAt
    }
}

// ---------- Telemetry ----------

/// telemetry_batch 的 payload：Provider 批量补交阶段事件。
public struct TelemetryBatchPayload: Codable, Sendable, Equatable {
    /// 待补交的事件列表，每条均可独立校验
    public let events: [ProviderEvent]

    public init(events: [ProviderEvent]) {
        self.events = events
    }
}

/// telemetry_ack 的 payload：App 确认已持久化的事件 ID 列表。
public struct TelemetryAckPayload: Codable, Sendable, Equatable {
    /// 已持久化的事件 ID 列表
    public let acknowledgedEventIds: [String]

    public init(acknowledgedEventIds: [String]) {
        self.acknowledgedEventIds = acknowledgedEventIds
    }
}

// ---------- 健康与状态 ----------

/// health_probe 的 payload：探测 Provider 或 App 会话健康。
public struct HealthProbePayload: Codable, Sendable, Equatable {
    /// 探测序列号
    public let probeSequence: Int64
    /// 发出时间（Unix 毫秒时间戳）
    public let sentAt: Int64

    public init(probeSequence: Int64, sentAt: Int64) {
        self.probeSequence = probeSequence
        self.sentAt = sentAt
    }
}

/// health_response 的 payload：响应健康探测。
public struct HealthResponsePayload: Codable, Sendable, Equatable {
    /// 回显探测序列号
    public let probeSequence: Int64
    /// 是否健康
    public let healthy: Bool

    public init(probeSequence: Int64, healthy: Bool) {
        self.probeSequence = probeSequence
        self.healthy = healthy
    }
}

/// operation_status_request 的 payload：重连后查询已接受动作的持久化状态。
public struct OperationStatusRequestPayload: Codable, Sendable, Equatable {
    /// 要查询的操作 ID
    public let operationId: String

    public init(operationId: String) {
        self.operationId = operationId
    }
}

/// operation_status_response 的 payload：回显已知操作的持久化状态。
public struct OperationStatusResponsePayload: Codable, Sendable, Equatable {
    /// 操作 ID
    public let operationId: String
    /// 已知终态
    public let outcome: ActionResultOutcome

    public init(operationId: String, outcome: ActionResultOutcome) {
        self.operationId = operationId
        self.outcome = outcome
    }
}

/// control_center_open_request 不携带任意参数；App 只接受当前认证 Provider 会话的请求。
public struct ControlCenterOpenRequestPayload: Codable, Sendable, Equatable {
    public init() {}
}

/// control_center_open_response 让 Provider 将明确结果回显给 popup。
public struct ControlCenterOpenResponsePayload: Codable, Sendable, Equatable {
    public let opened: Bool
    public init(opened: Bool) { self.opened = opened }
}

// MARK: - Payload 联合类型

/// ProviderEnvelope 的 payload 联合类型，共 19 种。
///
/// 解码通过 dispatchPayload 函数按 type → payload 映射表严格分发，
/// 不使用 try-catch 猜测策略。type-payload 不匹配直接拒绝。
public enum ProviderPayload: Codable, Sendable, Equatable {
    // 认证握手
    case providerHello(ProviderHelloPayload)
    case providerChallenge(ProviderChallengePayload)
    case providerAuthenticate(ProviderAuthenticatePayload)
    // 能力与上下文
    case capabilitySnapshot(CapabilitySnapshotPayload)
    case contextRequest(ContextRequestPayload)
    case contextSnapshot(ContextSnapshotPayload)
    // 配置
    case configurationSnapshot(ConfigurationSnapshotPayload)
    case configurationAck(ConfigurationAckPayload)
    // 动作执行
    case actionRequest(ActionDescriptor)
    case actionAccepted(ActionAcceptedPayload)
    case actionResult(ProviderActionResultPayload)
    // Telemetry
    case telemetryBatch(TelemetryBatchPayload)
    case telemetryAck(TelemetryAckPayload)
    // 健康与状态
    case healthProbe(HealthProbePayload)
    case healthResponse(HealthResponsePayload)
    case operationStatusRequest(OperationStatusRequestPayload)
    case operationStatusResponse(OperationStatusResponsePayload)
    case controlCenterOpenRequest(ControlCenterOpenRequestPayload)
    case controlCenterOpenResponse(ControlCenterOpenResponsePayload)

    // MARK: Convenience accessors

    public var actionRequest: ActionDescriptor? {
        guard case .actionRequest(let v) = self else { return nil }
        return v
    }

    public var contextSnapshot: ContextSnapshotPayload? {
        guard case .contextSnapshot(let v) = self else { return nil }
        return v
    }

    public var actionResult: ProviderActionResultPayload? {
        guard case .actionResult(let v) = self else { return nil }
        return v
    }

    // MARK: Codable — 通过 AnyJSONBox 桥接由 ProviderEnvelope/ProviderEvent 统一处理的
    // 序列化路径。直接调用 JSONEncoder.encode(providerPayload) 时走此路径。

    public init(from decoder: Decoder) throws {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "ProviderPayload 不直接解码——通过 ProviderEnvelope.dispatchPayload 分发"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // 将 payload 转为 JSON 字典 + JSONSerialization Data，再通过 AnyJSONBox 编码
        let dict = payloadAsDictionary()
        let box = AnyJSONBox(dict)
        try container.encode(box)
    }

    /// 将 payload 转为 [String: Any] 字典，供序列化到 Journal/证据包。
    internal func payloadAsDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        let data: Data
        switch self {
        case .providerHello(let v):           data = (try? encoder.encode(v)) ?? Data()
        case .providerChallenge(let v):       data = (try? encoder.encode(v)) ?? Data()
        case .providerAuthenticate(let v):    data = (try? encoder.encode(v)) ?? Data()
        case .capabilitySnapshot(let v):      data = (try? encoder.encode(v)) ?? Data()
        case .contextRequest(let v):          data = (try? encoder.encode(v)) ?? Data()
        case .contextSnapshot(let v):         data = (try? encoder.encode(v)) ?? Data()
        case .configurationSnapshot(let v):   data = (try? encoder.encode(v)) ?? Data()
        case .configurationAck(let v):        data = (try? encoder.encode(v)) ?? Data()
        case .actionRequest(let v):           data = (try? encoder.encode(v)) ?? Data()
        case .actionAccepted(let v):          data = (try? encoder.encode(v)) ?? Data()
        case .actionResult(let v):            data = (try? encoder.encode(v)) ?? Data()
        case .telemetryBatch(let v):          data = (try? encoder.encode(v)) ?? Data()
        case .telemetryAck(let v):            data = (try? encoder.encode(v)) ?? Data()
        case .healthProbe(let v):             data = (try? encoder.encode(v)) ?? Data()
        case .healthResponse(let v):          data = (try? encoder.encode(v)) ?? Data()
        case .operationStatusRequest(let v):  data = (try? encoder.encode(v)) ?? Data()
        case .operationStatusResponse(let v): data = (try? encoder.encode(v)) ?? Data()
        case .controlCenterOpenRequest(let v): data = (try? encoder.encode(v)) ?? Data()
        case .controlCenterOpenResponse(let v): data = (try? encoder.encode(v)) ?? Data()
        }
        guard !data.isEmpty, let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

// MARK: - Payload 分发映射表

// MARK: - JSON 值桥接类型
// ============================================================
// Swift Codable 不原生支持 [String: Any]。AnyJSONBox 通过
// JSONSerialization 桥接，将 JSON 对象捕获为可序列化的值，
// 供 dispatchPayload 通过 Data 重新解码为目标 payload 类型。

/// 捕获任意 JSON 值的桥接类型，支持解码、编码、相等性比较。
internal struct AnyJSONBox: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let obj = try? container.decode([String: AnyJSONBox].self) {
            value = obj.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyJSONBox].self) {
            value = arr.map { $0.value }
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Int64.self) {
            value = num
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解码 JSON 值")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? NSNull { try container.encodeNil() }
        else if let v = value as? Bool { try container.encode(v) }
        else if let v = value as? Int64 { try container.encode(v) }
        else if let v = value as? Int { try container.encode(Int64(v)) }
        else if let v = value as? Double { try container.encode(v) }
        else if let v = value as? String { try container.encode(v) }
        else if let v = value as? [Any] { try container.encode(v.map { AnyJSONBox($0) }) }
        else if let v = value as? [String: Any] { try container.encode(v.mapValues { AnyJSONBox($0) }) }
        else { throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "不可编码的 JSON 值")) }
    }

    static func == (lhs: AnyJSONBox, rhs: AnyJSONBox) -> Bool {
        if let a = lhs.value as? NSNumber, let b = rhs.value as? NSNumber { return a == b }
        if let a = lhs.value as? NSString, let b = rhs.value as? NSString { return a == b }
        if lhs.value is NSNull, rhs.value is NSNull { return true }
        return false
    }
}

/// 将类型映射到对应的 payload Codable 类型，供编码/解码使用。
/// 所有 19 种消息类型必须有对应条目。
public let payloadTypeMap: [ProviderMessageType: Codable.Type] = [
    .providerHello: ProviderHelloPayload.self,
    .providerChallenge: ProviderChallengePayload.self,
    .providerAuthenticate: ProviderAuthenticatePayload.self,
    .capabilitySnapshot: CapabilitySnapshotPayload.self,
    .contextRequest: ContextRequestPayload.self,
    .contextSnapshot: ContextSnapshotPayload.self,
    .configurationSnapshot: ConfigurationSnapshotPayload.self,
    .configurationAck: ConfigurationAckPayload.self,
    .actionRequest: ActionDescriptor.self,
    .actionAccepted: ActionAcceptedPayload.self,
    .actionResult: ProviderActionResultPayload.self,
    .telemetryBatch: TelemetryBatchPayload.self,
    .telemetryAck: TelemetryAckPayload.self,
    .healthProbe: HealthProbePayload.self,
    .healthResponse: HealthResponsePayload.self,
    .operationStatusRequest: OperationStatusRequestPayload.self,
    .operationStatusResponse: OperationStatusResponsePayload.self,
    .controlCenterOpenRequest: ControlCenterOpenRequestPayload.self,
    .controlCenterOpenResponse: ControlCenterOpenResponsePayload.self,
]

// MARK: - 协议信封

/// Provider Protocol v2 的传输层信封。
///
/// 解码时执行严格 fail-closed 校验：
/// - protocolVersion 必须等于 2，否则抛出 invalidProtocolVersion
/// - messageId 和 providerSessionId 不得为空
/// - timestamp 必须为有限非负整数
/// - type 必须为已知值
/// - payload 必须由 type → payload 映射表严格分发，type-payload 不匹配直接拒绝
/// - error 键必须存在（可为 null）
/// - action_request、action_accepted、action_result 必须携带非空 operationId
/// - action_result 的 outcome 必须是合法枚举值
public struct ProviderEnvelope: Codable, Sendable, Equatable {
    /// 协议主版本号。Provider v2 边界仅接受 2。
    public let protocolVersion: Int
    /// 消息级别唯一标识（非操作标识）。用于传输去重和 ACK。
    public let messageId: String
    /// Provider 认证会话 ID，由 App 在认证握手后分配。
    public let providerSessionId: String
    /// 关联的手势会话 ID。非手势上下文可为 nil。
    public let gestureSessionId: String?
    /// 关联的幂等操作 ID。action_*类型消息必填；非操作消息可为 nil。
    public let operationId: String?
    /// 消息类型。
    public let type: ProviderMessageType
    /// 消息产生时的 Unix 毫秒时间戳（wall-clock）。
    public let timestamp: Int64
    /// 消息体。具体结构由 type 字段决定。
    public let payload: ProviderPayload
    /// 结构化错误。成功消息为 nil。
    public let error: ProviderError?

    public init(
        protocolVersion: Int,
        messageId: String,
        providerSessionId: String,
        gestureSessionId: String?,
        operationId: String?,
        type: ProviderMessageType,
        timestamp: Int64,
        payload: ProviderPayload,
        error: ProviderError?
    ) {
        self.protocolVersion = protocolVersion
        self.messageId = messageId
        self.providerSessionId = providerSessionId
        self.gestureSessionId = gestureSessionId
        self.operationId = operationId
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
        self.error = error
    }

    // MARK: Codable

    fileprivate enum CodingKeys: String, CodingKey {
        case protocolVersion
        case messageId
        case providerSessionId
        case gestureSessionId
        case operationId
        case type
        case timestamp
        case payload
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // === protocolVersion 校验 ===
        let version = try container.decode(Int.self, forKey: .protocolVersion)
        guard version == PROVIDER_PROTOCOL_VERSION else {
            throw ProviderProtocolError.invalidProtocolVersion(
                got: version,
                expected: PROVIDER_PROTOCOL_VERSION
            )
        }
        protocolVersion = version

        // === messageId 校验（拒绝空字符串） ===
        let rawMessageId = try container.decode(String.self, forKey: .messageId)
        guard !rawMessageId.isEmpty else {
            throw ProviderProtocolError.emptyField("messageId")
        }
        messageId = rawMessageId

        // === providerSessionId 校验（拒绝空字符串） ===
        let rawProviderSessionId = try container.decode(String.self, forKey: .providerSessionId)
        guard !rawProviderSessionId.isEmpty else {
            throw ProviderProtocolError.emptyField("providerSessionId")
        }
        providerSessionId = rawProviderSessionId

        // === optional 字段 ===
        gestureSessionId = try container.decodeIfPresent(String.self, forKey: .gestureSessionId)
        operationId = try container.decodeIfPresent(String.self, forKey: .operationId)

        // === type 解码及 payload 分发 ===
        type = try container.decode(ProviderMessageType.self, forKey: .type)
        // 先将 payload 提取为原始 JSON 数据，再按 type 分发到对应 payload 类型
        let payloadBox = try container.decode(AnyJSONBox.self, forKey: .payload)
        let payloadJSONData = try JSONSerialization.data(withJSONObject: payloadBox.value, options: [])
        payload = try Self.dispatchPayload(type: type, payloadData: payloadJSONData)

        // === timestamp 校验 ===
        let rawTimestamp = try container.decode(Int64.self, forKey: .timestamp)
        guard rawTimestamp >= 0 else {
            throw ProviderProtocolError.invalidTimestamp(rawTimestamp)
        }
        timestamp = rawTimestamp

        // === error 键必须存在（值可以是 null） ===
        guard container.contains(.error) else {
            throw ProviderProtocolError.missingRequiredField("error")
        }
        error = try container.decodeIfPresent(ProviderError.self, forKey: .error)

        // === 动作相关消息的 operationId 校验 ===
        try Self.validateActionOperationId(type: type, operationId: operationId, payload: payload)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(messageId, forKey: .messageId)
        try container.encode(providerSessionId, forKey: .providerSessionId)
        try container.encodeIfPresent(gestureSessionId, forKey: .gestureSessionId)
        try container.encodeIfPresent(operationId, forKey: .operationId)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        // 按类型分发编码 payload
        try encodePayload(payload, to: &container)
        // error 始终编码（nil → null），满足 JSON Schema required 约束
        try container.encode(error, forKey: .error)
    }

    // MARK: - Payload 分发

    /// 基于 Data 的 payload 分发：接受 payload 的原始 JSON 数据，
    /// 按 type 映射表解码到对应的 ProviderPayload case。通用实现，
    /// 同时供 ProviderEnvelope 和 ProviderEvent 使用。
    public static func dispatchPayload(
        type: ProviderMessageType,
        payloadData: Data
    ) throws -> ProviderPayload {
        guard let payloadCodableType = payloadTypeMap[type] else {
            throw ProviderProtocolError.unknownMessageType(type.rawValue)
        }
        let decoder = JSONDecoder()
        do {
            try validatePayloadFields(type: type, payloadData: payloadData)
            switch payloadCodableType {
            case is ProviderHelloPayload.Type:
                let v = try decoder.decode(ProviderHelloPayload.self, from: payloadData)
                return .providerHello(v)
            case is ProviderChallengePayload.Type:
                let v = try decoder.decode(ProviderChallengePayload.self, from: payloadData)
                return .providerChallenge(v)
            case is ProviderAuthenticatePayload.Type:
                let v = try decoder.decode(ProviderAuthenticatePayload.self, from: payloadData)
                return .providerAuthenticate(v)
            case is CapabilitySnapshotPayload.Type:
                let v = try decoder.decode(CapabilitySnapshotPayload.self, from: payloadData)
                return .capabilitySnapshot(v)
            case is ContextRequestPayload.Type:
                let v = try decoder.decode(ContextRequestPayload.self, from: payloadData)
                return .contextRequest(v)
            case is ContextSnapshotPayload.Type:
                let v = try decoder.decode(ContextSnapshotPayload.self, from: payloadData)
                return .contextSnapshot(v)
            case is ConfigurationSnapshotPayload.Type:
                let v = try decoder.decode(ConfigurationSnapshotPayload.self, from: payloadData)
                return .configurationSnapshot(v)
            case is ConfigurationAckPayload.Type:
                let v = try decoder.decode(ConfigurationAckPayload.self, from: payloadData)
                return .configurationAck(v)
            case is ActionDescriptor.Type:
                let v = try decoder.decode(ActionDescriptor.self, from: payloadData)
                return .actionRequest(v)
            case is ActionAcceptedPayload.Type:
                let v = try decoder.decode(ActionAcceptedPayload.self, from: payloadData)
                return .actionAccepted(v)
            case is ProviderActionResultPayload.Type:
                let v = try decoder.decode(ProviderActionResultPayload.self, from: payloadData)
                return .actionResult(v)
            case is TelemetryBatchPayload.Type:
                let v = try decoder.decode(TelemetryBatchPayload.self, from: payloadData)
                return .telemetryBatch(v)
            case is TelemetryAckPayload.Type:
                let v = try decoder.decode(TelemetryAckPayload.self, from: payloadData)
                return .telemetryAck(v)
            case is HealthProbePayload.Type:
                let v = try decoder.decode(HealthProbePayload.self, from: payloadData)
                return .healthProbe(v)
            case is HealthResponsePayload.Type:
                let v = try decoder.decode(HealthResponsePayload.self, from: payloadData)
                return .healthResponse(v)
            case is OperationStatusRequestPayload.Type:
                let v = try decoder.decode(OperationStatusRequestPayload.self, from: payloadData)
                return .operationStatusRequest(v)
            case is OperationStatusResponsePayload.Type:
                let v = try decoder.decode(OperationStatusResponsePayload.self, from: payloadData)
                return .operationStatusResponse(v)
            case is ControlCenterOpenRequestPayload.Type:
                let v = try decoder.decode(ControlCenterOpenRequestPayload.self, from: payloadData)
                return .controlCenterOpenRequest(v)
            case is ControlCenterOpenResponsePayload.Type:
                let v = try decoder.decode(ControlCenterOpenResponsePayload.self, from: payloadData)
                return .controlCenterOpenResponse(v)
            default:
                throw ProviderProtocolError.unknownMessageType(type.rawValue)
            }
        } catch {
            throw ProviderProtocolError.typePayloadMismatch(type.rawValue, String(describing: error))
        }
    }

    /// 校验 payload 只能包含该消息类型声明的字段，防止 Codable 默认忽略未知键。
    private static func validatePayloadFields(type: ProviderMessageType, payloadData: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw ProviderProtocolError.typePayloadMismatch(type.rawValue, "payload 必须是对象")
        }
        let allowedFields: Set<String>
        switch type {
        case .providerHello: allowedFields = ["installId", "protocolVersions", "environment"]
        case .providerChallenge: allowedFields = ["nonce", "expiresAt"]
        case .providerAuthenticate: allowedFields = ["installId", "hmac"]
        case .capabilitySnapshot: allowedFields = ["capabilities", "capabilityVersion"]
        case .contextRequest: allowedFields = ["gestureSessionId", "requiresTargetRef", "deadline"]
        case .contextSnapshot: allowedFields = ["contextId", "pageIdentity", "expiresAt", "targetKind", "targetRef"]
        case .configurationSnapshot: allowedFields = ["storeEpoch", "schemaVersion", "configurationVersion", "configJSON"]
        case .configurationAck: allowedFields = ["appliedVersion", "applied"]
        case .actionRequest: allowedFields = ["actionId", "contextId", "targetRef", "parameters", "deadline"]
        case .actionAccepted: allowedFields = ["operationId", "acceptedAt"]
        case .actionResult: allowedFields = ["operationId", "outcome", "reason", "completedAt"]
        case .telemetryBatch: allowedFields = ["events"]
        case .telemetryAck: allowedFields = ["acknowledgedEventIds"]
        case .healthProbe: allowedFields = ["probeSequence", "sentAt"]
        case .healthResponse: allowedFields = ["probeSequence", "healthy"]
        case .operationStatusRequest: allowedFields = ["operationId"]
        case .operationStatusResponse: allowedFields = ["operationId", "outcome"]
        case .controlCenterOpenRequest: allowedFields = []
        case .controlCenterOpenResponse: allowedFields = ["opened"]
        }
        let unknownFields = Set(object.keys).subtracting(allowedFields)
        guard unknownFields.isEmpty else {
            throw ProviderProtocolError.typePayloadMismatch(type.rawValue, "包含未声明字段: \(unknownFields.sorted().joined(separator: ","))")
        }
    }

    /// 编码 payload 到容器中。
    private func encodePayload(
        _ payload: ProviderPayload,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        let encodable: Encodable
        switch payload {
        case .providerHello(let v): encodable = v
        case .providerChallenge(let v): encodable = v
        case .providerAuthenticate(let v): encodable = v
        case .capabilitySnapshot(let v): encodable = v
        case .contextRequest(let v): encodable = v
        case .contextSnapshot(let v): encodable = v
        case .configurationSnapshot(let v): encodable = v
        case .configurationAck(let v): encodable = v
        case .actionRequest(let v): encodable = v
        case .actionAccepted(let v): encodable = v
        case .actionResult(let v): encodable = v
        case .telemetryBatch(let v): encodable = v
        case .telemetryAck(let v): encodable = v
        case .healthProbe(let v): encodable = v
        case .healthResponse(let v): encodable = v
        case .operationStatusRequest(let v): encodable = v
        case .operationStatusResponse(let v): encodable = v
        case .controlCenterOpenRequest(let v): encodable = v
        case .controlCenterOpenResponse(let v): encodable = v
        }
        try container.encode(encodable, forKey: .payload)
    }

    /// 校验 action_* 类型消息必须有非空 operationId。
    internal static func validateActionOperationId(
        type: ProviderMessageType,
        operationId: String?,
        payload: ProviderPayload
    ) throws {
        switch type {
        case .actionRequest, .actionAccepted, .actionResult:
            guard let opId = operationId, !opId.isEmpty else {
                throw ProviderProtocolError.missingOperationId(type.rawValue)
            }
        default:
            break
        }
    }
}

// MARK: - ProviderEvent 的 payload 分发辅助函数

/// 从 ProviderEvent 的容器中解码 payload。
/// ProviderEvent 使用独立的 CodingKeys 枚举，因此需要独立的分发包装。
fileprivate func decodeProviderEventPayload(
    type: ProviderMessageType,
    container: KeyedDecodingContainer<ProviderEvent.CodingKeys>
) throws -> ProviderPayload {
    let payloadBox = try container.decode(AnyJSONBox.self, forKey: .payload)
    let payloadJSONData = try JSONSerialization.data(withJSONObject: payloadBox.value, options: [])
    return try ProviderEnvelope.dispatchPayload(type: type, payloadData: payloadJSONData)
}

// MARK: - Provider Event

/// Provider 产生的不可变阶段事件，是操作证据链的最小单元。
///
/// ProviderEvent 携带完整的溯源信息：eventId（全局唯一）、
/// producerSessionId + producerSequence（生产者侧唯一）、
/// causedByEventId（跨进程因果链）、monotonicClockMs + wallClockMs
/// （双时钟时间基准）。
public struct ProviderEvent: Codable, Sendable, Equatable {
    /// 全局唯一事件 ID
    public let eventId: String
    /// 产生此事件的 producer 会话 ID
    public let producerSessionId: String
    /// 生产者侧的单调递增序号，用于检测缺口和乱序
    public let producerSequence: Int64
    /// 跨进程因果关系。标识此事件由哪个事件引起，首事件可为 nil
    public let causedByEventId: String?
    /// 单调时钟（毫秒），用于跨进程时序比对
    public let monotonicClockMs: Int64
    /// wall-clock（Unix 毫秒时间戳）
    public let wallClockMs: Int64
    /// 关联的手势会话 ID
    public let gestureSessionId: String?
    /// 关联的幂等操作 ID
    public let operationId: String?
    /// 事件对应的消息类型
    public let type: ProviderMessageType
    /// 事件 payload
    public let payload: ProviderPayload

    public init(
        eventId: String,
        producerSessionId: String,
        producerSequence: Int64,
        causedByEventId: String?,
        monotonicClockMs: Int64,
        wallClockMs: Int64,
        gestureSessionId: String?,
        operationId: String?,
        type: ProviderMessageType,
        payload: ProviderPayload
    ) {
        self.eventId = eventId
        self.producerSessionId = producerSessionId
        self.producerSequence = producerSequence
        self.causedByEventId = causedByEventId
        self.monotonicClockMs = monotonicClockMs
        self.wallClockMs = wallClockMs
        self.gestureSessionId = gestureSessionId
        self.operationId = operationId
        self.type = type
        self.payload = payload
    }
}

// MARK: - ProviderEvent Codable

extension ProviderEvent {
    fileprivate enum CodingKeys: String, CodingKey {
        case eventId
        case producerSessionId
        case producerSequence
        case causedByEventId
        case monotonicClockMs
        case wallClockMs
        case gestureSessionId
        case operationId
        case type
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try container.decode(String.self, forKey: .eventId)
        producerSessionId = try container.decode(String.self, forKey: .producerSessionId)
        producerSequence = try container.decode(Int64.self, forKey: .producerSequence)
        causedByEventId = try container.decodeIfPresent(String.self, forKey: .causedByEventId)
        monotonicClockMs = try container.decode(Int64.self, forKey: .monotonicClockMs)
        wallClockMs = try container.decode(Int64.self, forKey: .wallClockMs)
        gestureSessionId = try container.decodeIfPresent(String.self, forKey: .gestureSessionId)
        operationId = try container.decodeIfPresent(String.self, forKey: .operationId)
        type = try container.decode(ProviderMessageType.self, forKey: .type)

        // 按事件类型分发 payload（复用 ProviderEnvelope 的分发逻辑）
        payload = try decodeProviderEventPayload(type: type, container: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(producerSessionId, forKey: .producerSessionId)
        try container.encode(producerSequence, forKey: .producerSequence)
        try container.encodeIfPresent(causedByEventId, forKey: .causedByEventId)
        try container.encode(monotonicClockMs, forKey: .monotonicClockMs)
        try container.encode(wallClockMs, forKey: .wallClockMs)
        try container.encodeIfPresent(gestureSessionId, forKey: .gestureSessionId)
        try container.encodeIfPresent(operationId, forKey: .operationId)
        try container.encode(type, forKey: .type)
        // 手动编码 payload
        switch payload {
        case .providerHello(let v): try container.encode(v, forKey: .payload)
        case .providerChallenge(let v): try container.encode(v, forKey: .payload)
        case .providerAuthenticate(let v): try container.encode(v, forKey: .payload)
        case .capabilitySnapshot(let v): try container.encode(v, forKey: .payload)
        case .contextRequest(let v): try container.encode(v, forKey: .payload)
        case .contextSnapshot(let v): try container.encode(v, forKey: .payload)
        case .configurationSnapshot(let v): try container.encode(v, forKey: .payload)
        case .configurationAck(let v): try container.encode(v, forKey: .payload)
        case .actionRequest(let v): try container.encode(v, forKey: .payload)
        case .actionAccepted(let v): try container.encode(v, forKey: .payload)
        case .actionResult(let v): try container.encode(v, forKey: .payload)
        case .telemetryBatch(let v): try container.encode(v, forKey: .payload)
        case .telemetryAck(let v): try container.encode(v, forKey: .payload)
        case .healthProbe(let v): try container.encode(v, forKey: .payload)
        case .healthResponse(let v): try container.encode(v, forKey: .payload)
        case .operationStatusRequest(let v): try container.encode(v, forKey: .payload)
        case .operationStatusResponse(let v): try container.encode(v, forKey: .payload)
        case .controlCenterOpenRequest(let v): try container.encode(v, forKey: .payload)
        case .controlCenterOpenResponse(let v): try container.encode(v, forKey: .payload)
        }
    }
}

// MARK: - 协议错误

/// Provider Protocol v2 解码时的语义校验错误。
public enum ProviderProtocolError: Error, Equatable {
    /// protocolVersion 不为 2
    case invalidProtocolVersion(got: Int, expected: Int)
    /// 必填字段为空字符串
    case emptyField(String)
    /// 必填键缺失（与值为 null 的可选字段区分）
    case missingRequiredField(String)
    /// timestamp 为负数
    case invalidTimestamp(Int64)
    /// 未知或不受支持的消息类型
    case unknownMessageType(String)
    /// type 与 payload 类型不匹配
    case typePayloadMismatch(String, String)
    /// action_* 消息缺少 operationId
    case missingOperationId(String)
}

extension ProviderProtocolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidProtocolVersion(let got, let expected):
            return "Provider Protocol v2 边界拒绝 protocolVersion=\(got)，期望 \(expected)"
        case .emptyField(let field):
            return "Provider Protocol v2 拒绝空 \(field)"
        case .missingRequiredField(let field):
            return "Provider Protocol v2 缺少必填字段 \(field)"
        case .invalidTimestamp(let value):
            return "Provider Protocol v2 拒绝非法 timestamp=\(value)"
        case .unknownMessageType(let typeValue):
            return "Provider Protocol v2 拒绝未知 message type: \"\(typeValue)\""
        case .typePayloadMismatch(let typeValue, let detail):
            return "Provider Protocol v2 拒绝 type-payload 不匹配: type=\(typeValue), detail=\(detail)"
        case .missingOperationId(let typeValue):
            return "Provider Protocol v2 拒绝 \(typeValue) 缺少 operationId"
        }
    }
}
