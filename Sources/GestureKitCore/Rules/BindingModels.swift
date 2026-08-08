import Foundation

// ============================================================
// BindingModels — 手势定义与动作绑定模型
// ============================================================
//
// 本文件定义 GestureDefinition 和版本化配置使用的领域类型，
// 以及从 StandardActionID 到具体 Provider 动作的绑定关系。
//
// 这些模型为后续 V1 配置驱动的规则系统提供类型基础。
// 当前 Task 3 添加 StandardActionID 的引用和 GestureDefinition 骨架。

// StandardActionID 定义在 Provider/ProviderProtocolV2.swift 中，
// 本文件通过类型别名提供便捷引用（防止 Core 其他模块直接 import Provider 目录）。

/// 标准动作 ID 的类型别名。定义见 ProviderProtocolV2.swift。
public typealias ActionID = StandardActionID

// MARK: - Gesture Definition

/// 组合手势定义的原语类型。
///
/// 当前 V1 支持 tap 和 swipe 两种原语。新增原语（如 rotate、press）
/// 需要同时修改 PrimitiveRecognizer。
public enum GesturePrimitive: String, Codable, Sendable, Equatable, CaseIterable {
    /// 点按原语
    case tap
    /// 滑动原语
    case swipe
}

/// 手势触发的触控板区域。
///
/// V1 的边缘点按和中间双击基于此区域分类。
public enum GestureRegion: String, Codable, Sendable, Equatable, CaseIterable {
    /// 触控板任意区域
    case any
    /// 触控板左侧边缘
    case leftEdge = "left_edge"
    /// 触控板右侧边缘
    case rightEdge = "right_edge"
    /// 触控板中间区域
    case center
}

/// 手势滑动方向。
public enum GestureDirection: String, Codable, Sendable, Equatable, CaseIterable {
    case left
    case right
}

/// 组合手势定义。
///
/// 使用数据驱动方式表达手势组合，允许后续通过配置增加简单组合
/// 而不修改识别代码。当前 V1 不交付完整 DIY 编辑器，但模型
/// 为后续扩展预留。
///
/// 示例：三指点按链接
/// ```
/// GestureDefinition(
///     id: "three-finger-tap-link",
///     primitive: .tap,
///     fingers: 3,
///     repetitions: 1,
///     maxIntervalMs: nil,
///     direction: nil,
///     region: .any,
///     maxDurationMs: 180
/// )
/// ```
public struct GestureDefinition: Codable, Sendable, Equatable {
    /// 手势标识，用于引用和匹配
    public let id: String
    /// 原语类型（tap 或 swipe）
    public let primitive: GesturePrimitive
    /// 手指数
    public let fingers: Int
    /// 重复次数（1=单击，2=双击，3=三击）
    public let repetitions: Int
    /// 组合间隔（毫秒）。nil 表示不适用（如单次手势）
    public let maxIntervalMs: Int?
    /// 滑动方向。仅 swipe 原语需要
    public let direction: GestureDirection?
    /// 触发区域
    public let region: GestureRegion
    /// 单次手势最长持续时间（毫秒）
    public let maxDurationMs: Int

    public init(
        id: String,
        primitive: GesturePrimitive,
        fingers: Int,
        repetitions: Int,
        maxIntervalMs: Int?,
        direction: GestureDirection?,
        region: GestureRegion,
        maxDurationMs: Int
    ) {
        self.id = id
        self.primitive = primitive
        self.fingers = fingers
        self.repetitions = repetitions
        self.maxIntervalMs = maxIntervalMs
        self.direction = direction
        self.region = region
        self.maxDurationMs = maxDurationMs
    }
}

// MARK: - 用户绑定覆盖

/// 用户对默认绑定的增量覆盖。`id` 引用默认绑定（`DefaultRules.v1Bindings`）的稳定标识；
/// `nil` 字段表示保持默认值。
///
/// - `enabled`：`false` 表示禁用该条（合并时移除）；`true`/`nil` 保持默认。
/// - `actionId`：非 `nil` 表示把默认动作覆盖为指定标准动作。
/// - `gestureDefinitionId`：非 `nil` 且无同手势默认绑定时，表示「新增绑定」——
///   为无默认绑定的预设手势（二指/四指）创建一条有效绑定规则。
public struct BindingOverride: Codable, Sendable, Equatable {
    public let id: String
    /// 非 `nil` 表示新增绑定（针对无默认绑定的手势），而不是覆盖默认绑定。
    public let gestureDefinitionId: String?
    public let enabled: Bool?
    public let actionId: StandardActionID?

    public init(id: String, gestureDefinitionId: String? = nil, enabled: Bool?, actionId: StandardActionID?) {
        self.id = id
        self.gestureDefinitionId = gestureDefinitionId
        self.enabled = enabled
        self.actionId = actionId
    }
}

/// 用户绑定配置：默认绑定 + 增量覆盖。
///
/// 缺省（空覆盖）时完全回退默认绑定；对某条 `removing` 即恢复该条默认。
/// 合并规则：
/// - 无覆盖的默认绑定原样保留；
/// - `enabled == false` 的覆盖 → 移除该条；
/// - `actionId != nil` 的覆盖 → 以覆盖动作替换默认动作；
/// - 其余字段（priority/contextConstraints/actionParameters）一律保留默认。
/// - 携带 `gestureDefinitionId` 且未被默认绑定覆盖的覆盖 → 新增一条绑定规则
///   （动作必填、启用开关生效）。
public struct UserBindingConfiguration: Codable, Sendable, Equatable {
    public let overrides: [BindingOverride]

    public init(overrides: [BindingOverride] = []) {
        self.overrides = overrides
    }

    /// 合并默认绑定与用户覆盖，返回生效绑定列表（优先级保留）。
    /// 同 id 的重复覆盖取后者（持久化数据防脏：不因重复 id 崩溃）。
    public func effectiveBindings(defaults: [BindingRule]) -> [BindingRule] {
        let overridesByID = Dictionary(overrides.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var result = defaults.compactMap { rule in
            guard let override = overridesByID[rule.id] else { return rule }
            if override.enabled == false { return nil }
            return BindingRule(
                id: rule.id,
                gestureDefinitionId: rule.gestureDefinitionId,
                // 用户显式改动作（actionId 非 nil）时清空默认上下文约束，让动作在任意处触发；
                // 仅改启用态（actionId 为 nil）时保留默认约束（如三指点按仅在链接上）。
                contextConstraints: override.actionId == nil ? rule.contextConstraints : [:],
                actionId: override.actionId ?? rule.actionId,
                actionParameters: rule.actionParameters,
                priority: rule.priority,
                enabled: override.enabled ?? rule.enabled
            )
        }
        // 用户新增绑定：为无默认绑定的预设手势创建规则。
        // 动作是绑定的必要条件；禁用态（enabled == false）表示不生效。
        for override in overrides {
            guard let gestureDefinitionId = override.gestureDefinitionId,
                  override.enabled != false,
                  let actionId = override.actionId else { continue }
            // 已被默认绑定覆盖的手势不重复新增（默认绑定优先）。
            guard !result.contains(where: { $0.gestureDefinitionId == gestureDefinitionId }) else { continue }
            result.append(BindingRule(
                id: override.id,
                gestureDefinitionId: gestureDefinitionId,
                contextConstraints: [:],
                actionId: actionId,
                actionParameters: [:],
                priority: 100,
                enabled: override.enabled ?? true
            ))
        }
        return result
    }

    /// 写入/替换一条覆盖；覆盖记录按 id 幂等更新。
    public func updating(_ override: BindingOverride) -> UserBindingConfiguration {
        var merged = overrides
        if let index = merged.firstIndex(where: { $0.id == override.id }) {
            merged[index] = override
        } else {
            merged.append(override)
        }
        return UserBindingConfiguration(overrides: merged)
    }

    /// 移除某条覆盖，使该绑定回退默认。
    public func removing(id: String) -> UserBindingConfiguration {
        UserBindingConfiguration(overrides: overrides.filter { $0.id != id })
    }
}

// MARK: - Binding Rule

/// 动作绑定规则，将手势定义 + 上下文约束映射为标准动作。
///
/// 每条规则包含匹配条件和目标 ActionDescriptor 的模板。
/// 规则引擎据此选择最终执行的动作。Chrome 专用 ActionType 不得出现
/// 在规则输入或输出中。
public struct BindingRule: Codable, Sendable, Equatable {
    /// 规则标识
    public let id: String
    /// 要匹配的手势定义 ID
    public let gestureDefinitionId: String
    /// 上下文约束，如 ["targetKind": "standard_link"]
    public let contextConstraints: [String: String]
    /// 目标标准动作 ID
    public let actionId: StandardActionID
    /// 动作参数模板
    public let actionParameters: [String: String]
    /// 规则优先级（数值越大优先级越高）
    public let priority: Int
    /// 是否启用
    public let enabled: Bool

    public init(
        id: String,
        gestureDefinitionId: String,
        contextConstraints: [String: String],
        actionId: StandardActionID,
        actionParameters: [String: String],
        priority: Int,
        enabled: Bool
    ) {
        self.id = id
        self.gestureDefinitionId = gestureDefinitionId
        self.contextConstraints = contextConstraints
        self.actionId = actionId
        self.actionParameters = actionParameters
        self.priority = priority
        self.enabled = enabled
    }
}
