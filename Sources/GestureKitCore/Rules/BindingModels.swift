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
