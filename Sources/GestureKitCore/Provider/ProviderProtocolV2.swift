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

// MARK: - 协议版本

/// Provider Protocol v2 的协议主版本号。
/// Provider v2 边界仅接受 protocolVersion == 2 的消息。
public let PROVIDER_PROTOCOL_VERSION: Int = 2

// MARK: - 消息类型

/// Provider Protocol v2 支持的消息类型枚举。
///
/// 所有消息类型使用 snake_case 命名以保持与 JSON 协议字段一致。
/// 每种消息类型对应特定的 payload 结构：
/// - `provider_hello` / `provider_challenge` / `provider_authenticate`：认证握手
/// - `capability_snapshot`：Provider 能力声明
/// - `context_request` / `context_snapshot`：上下文请求与响应
/// - `configuration_snapshot` / `configuration_ack`：配置下发与确认
/// - `action_request` / `action_accepted` / `action_result`：动作执行生命周期
/// - `telemetry_batch` / `telemetry_ack`：批量事件上报与确认
/// - `health_probe` / `health_response`：健康检查
/// - `operation_status_request` / `operation_status_response`：重连后操作状态查询
public enum ProviderMessageType: String, Codable, Sendable, CaseIterable, Equatable {
    case providerHello = "provider_hello"
    case providerChallenge = "provider_challenge"
    case providerAuthenticate = "provider_authenticate"
    case capabilitySnapshot = "capability_snapshot"
    case contextRequest = "context_request"
    case contextSnapshot = "context_snapshot"
    case configurationSnapshot = "configuration_snapshot"
    case configurationAck = "configuration_ack"
    case actionRequest = "action_request"
    case actionAccepted = "action_accepted"
    case actionResult = "action_result"
    case telemetryBatch = "telemetry_batch"
    case telemetryAck = "telemetry_ack"
    case healthProbe = "health_probe"
    case healthResponse = "health_response"
    case operationStatusRequest = "operation_status_request"
    case operationStatusResponse = "operation_status_response"
}

// MARK: - 结构化错误

/// Provider Protocol v2 的结构化错误。
///
/// 使用 code/message 组合表达错误细节。code 供程序判断错误类型，
/// message 供日志和诊断使用。message 不得直接显示在用户界面。
public struct ProviderError: Codable, Sendable, Equatable {
    /// 错误码，如 "provider_storage_full"、"app_unavailable"
    public let code: String
    /// 人类可读的错误说明（仅用于诊断，不直接显示在 UI）
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - 标准动作 ID

/// Provider Protocol v2 的标准动作 ID。
///
/// 所有 V1 手势行为映射到这组标准化动作。Provider 通过能力清单
/// 声明支持哪些动作，Core 的 RuleEngine 不直接引用 Chrome 专用枚举。
///
/// V1 映射关系：
/// - 三指点按链接 → browser.link.open_adjacent
/// - 左边缘点按 → browser.tab.activate_previous
/// - 右边缘点按 → browser.tab.activate_next
/// - 中间双击 → browser.tab.close_current
/// - 三指左轻扫 → browser.tab.activate_next
/// - 三指右轻扫 → browser.tab.activate_previous
public enum StandardActionID: String, Codable, Sendable, Equatable, CaseIterable {
    /// 在当前标签页右侧打开目标链接
    case browserLinkOpenAdjacent = "browser.link.open_adjacent"
    /// 切换到左侧标签页
    case browserTabActivatePrevious = "browser.tab.activate_previous"
    /// 切换到右侧标签页
    case browserTabActivateNext = "browser.tab.activate_next"
    /// 关闭当前标签页
    case browserTabCloseCurrent = "browser.tab.close_current"
    /// 页面历史后退
    case browserHistoryBack = "browser.history.back"
    /// 页面历史前进
    case browserHistoryForward = "browser.history.forward"
    /// 刷新当前页面
    case browserPageReload = "browser.page.reload"
}

// MARK: - 动作描述

/// 标准动作描述，由 RuleEngine 在规则匹配后生成。
///
/// ActionDescriptor 引用此前通过 context_snapshot 获得的 contextId，
/// Provider 必须验证上下文未过期且页面身份匹配后才执行动作。
///
/// 设计约束：
/// - actionId 是 Provider 能力清单中的标准动作，Provider 不可重新换绑
/// - targetRef 是不透明值，仅 Provider 内部可解析为具体浏览器资源
/// - deadline 是执行截止时间，超时后 Provider 应拒绝执行而非阻塞
public struct ActionDescriptor: Codable, Sendable, Equatable {
    /// 标准动作 ID
    public let actionId: StandardActionID
    /// 此前通过 context_snapshot 获得的上下文 ID
    public let contextId: String
    /// Provider 内部的不透明目标引用（仅链接动作需要）
    public let targetRef: String?
    /// 动作参数，例如 `["activate": "true"]` 表示新标签自动激活
    public let parameters: [String: String]
    /// 动作截止时间（Unix 毫秒时间戳），超过此时间 Provider 应拒绝执行
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

// MARK: - Context Snapshot

/// 上下文快照的目标分类枚举。
///
/// Provider 通过 context_snapshot 告知 App 当前指针命中结果的类型。
/// 仅 `standard_link` 允许绑定 `browser.link.open_adjacent` 动作。
public enum ContextTargetKind: String, Codable, Sendable, Equatable {
    /// 指针命中了标准 <a href> 链接
    case standardLink = "standard_link"
    /// 指针未命中任何可打开目标
    case noTarget = "no_target"
    /// 当前页面不可用（不可注入、不支持 URL scheme 等）
    case pageUnavailable = "page_unavailable"
}

/// Context snapshot 的 payload。
///
/// 上下文快照是 App 进行规则匹配所需的当前页面事实。
/// 约束：只允许携带 contextId、页面身份、过期时间、标准 target facts
/// 和不透明 targetRef；不得包含 URL query/hash、DOM 文本、id/class、
/// Cookie、表单值或自由文本 details。
public struct ContextSnapshotPayload: Codable, Sendable, Equatable {
    /// 本次上下文快照的唯一 ID，供后续 ActionDescriptor 引用
    public let contextId: String
    /// 页面身份标识。通常为脱敏后的页面 host，供 RuleEngine 判断页面类型
    public let pageIdentity: String
    /// 上下文过期时间（Unix 毫秒时间戳）。之后 contextId 不再有效
    public let expiresAt: Int64
    /// 指针命中结果的枚举分类
    public let targetKind: ContextTargetKind
    /// Provider 内部的不透明目标引用。仅在 targetKind == standardLink 时有值
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

// MARK: - Payload 联合类型

/// ProviderEnvelope 的 payload 联合类型。
///
/// 解码时依据 ProviderEnvelope.type 字段分发到对应的具体 payload 类型。
/// 当前 Task 3 实现 action_request 和 context_snapshot 两种核心 payload，
/// 其余消息类型的 payload 将在后续任务中补充。
public enum ProviderPayload: Codable, Sendable, Equatable {
    /// action_request 的 payload：ActionDescriptor
    case actionRequest(ActionDescriptor)
    /// context_snapshot 的 payload：ContextSnapshotPayload
    case contextSnapshot(ContextSnapshotPayload)

    // MARK: Convenience accessors

    /// 如果 payload 为 actionRequest，返回关联的 ActionDescriptor；否则返回 nil
    public var actionRequest: ActionDescriptor? {
        guard case .actionRequest(let v) = self else { return nil }
        return v
    }

    /// 如果 payload 为 contextSnapshot，返回关联的 ContextSnapshotPayload；否则返回 nil
    public var contextSnapshot: ContextSnapshotPayload? {
        guard case .contextSnapshot(let v) = self else { return nil }
        return v
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case actionId, contextId, targetRef, parameters, deadline
        case pageIdentity, expiresAt, targetKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // 优先尝试解码为 ActionDescriptor（包含 actionId + deadline 字段）
        if let actionRequest = try? container.decode(ActionDescriptor.self) {
            self = .actionRequest(actionRequest)
        } else if let contextSnapshot = try? container.decode(ContextSnapshotPayload.self) {
            self = .contextSnapshot(contextSnapshot)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解码 ProviderPayload：不支持的消息类型或字段不完整"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .actionRequest(let value):
            try container.encode(value)
        case .contextSnapshot(let value):
            try container.encode(value)
        }
    }
}

// MARK: - 协议信封

/// Provider Protocol v2 的传输层信封。
///
/// 所有 App 与 Provider 之间的通信都使用此信封封装。Provider v2 边界
/// 必须在解码时校验 protocolVersion == 2，拒绝所有 legacy v1 消息。
public struct ProviderEnvelope: Codable, Sendable, Equatable {
    /// 协议主版本号。Provider v2 边界仅接受 2。
    public let protocolVersion: Int
    /// 消息级别唯一标识（非操作标识）。用于传输去重和 ACK。
    public let messageId: String
    /// Provider 认证会话 ID，由 App 在认证握手后分配。
    public let providerSessionId: String
    /// 关联的手势会话 ID。非手势上下文（如配置同步）可为 nil。
    public let gestureSessionId: String?
    /// 关联的幂等操作 ID。action_request 消息必填；非操作消息可为 nil。
    public let operationId: String?
    /// 消息类型。解码器依据此字段分发 payload 解码。
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

    // MARK: Codable — 自定义解码以实现语义校验

    /// 自定义编码键，使用 snake_case 匹配 JSON 字段名。
    private enum CodingKeys: String, CodingKey {
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

        // 解码并校验 protocolVersion
        let version = try container.decode(Int.self, forKey: .protocolVersion)
        guard version == PROVIDER_PROTOCOL_VERSION else {
            throw ProviderProtocolError.invalidProtocolVersion(
                got: version,
                expected: PROVIDER_PROTOCOL_VERSION
            )
        }
        protocolVersion = version

        messageId = try container.decode(String.self, forKey: .messageId)
        providerSessionId = try container.decode(String.self, forKey: .providerSessionId)
        gestureSessionId = try container.decodeIfPresent(String.self, forKey: .gestureSessionId)
        operationId = try container.decodeIfPresent(String.self, forKey: .operationId)
        type = try container.decode(ProviderMessageType.self, forKey: .type)
        timestamp = try container.decode(Int64.self, forKey: .timestamp)
        payload = try container.decode(ProviderPayload.self, forKey: .payload)
        error = try container.decodeIfPresent(ProviderError.self, forKey: .error)
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
        try container.encode(payload, forKey: .payload)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

// MARK: - Provider Event

/// Provider 产生的不可变阶段事件，是操作证据链的最小单元。
///
/// ProviderEvent 用于 operation journal 和 outbox，携带完整的溯源信息，
/// 支持在不依赖现场的情况下通过 eventId 因果链重建操作时序。
///
/// 必填字段：
/// - eventId：全局唯一事件 ID
/// - producerSessionId：产生此事件的 producer 会话 ID
/// - producerSequence：生产者侧的单调递增序号，用于检测缺口和乱序
/// - causedByEventId：跨进程因果关系，首事件可为 nil
/// - monotonicClockMs：单调时钟（毫秒），用于跨进程时序比对
/// - wallClockMs：wall-clock（Unix 毫秒时间戳）
/// - gestureSessionId：关联的手势会话 ID
/// - operationId：关联的幂等操作 ID
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

// MARK: - 协议错误

/// Provider Protocol v2 解码时可能抛出的语义校验错误。
///
/// 与 DecodingError 不同，此类错误表示 JSON 结构正确但语义不通过校验。
public enum ProviderProtocolError: Error, Equatable {
    /// protocolVersion 不为 2
    case invalidProtocolVersion(got: Int, expected: Int)
}

extension ProviderProtocolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidProtocolVersion(let got, let expected):
            return "Provider Protocol v2 边界拒绝 protocolVersion=\(got)，期望 \(expected)"
        }
    }
}
