import Foundation

/// 组合器交给规则层的 provider-neutral 手势语义。
public enum ComposedGesture: String, Codable, Equatable, Sendable, CaseIterable {
    case threeFingerTap = "three_finger_tap"
    case threeFingerTapLeftEdge = "three_finger_tap_left_edge"
    case threeFingerTapRightEdge = "three_finger_tap_right_edge"
    case threeFingerDoubleTapCenter = "three_finger_double_tap_center"
    case threeFingerSwipeLeft = "three_finger_swipe_left"
    case threeFingerSwipeRight = "three_finger_swipe_right"

    public var gestureDefinitionID: String {
        switch self {
        case .threeFingerTap: "three-finger-tap"
        case .threeFingerTapLeftEdge: "three-finger-tap-left-edge"
        case .threeFingerTapRightEdge: "three-finger-tap-right-edge"
        case .threeFingerDoubleTapCenter: "three-finger-double-tap-center"
        case .threeFingerSwipeLeft: "three-finger-swipe-left"
        case .threeFingerSwipeRight: "three-finger-swipe-right"
        }
    }
}

/// Provider 传来的、规则求值所需的标准事实；不包含浏览器 API 或页面内容。
public struct ProviderContextSnapshot: Equatable, Sendable {
    public let contextId: String
    public let targetKind: ContextTargetKind
    public let targetRef: String?
    /// action 的 wall-clock 截止时间，由边界层提供。
    public let deadline: Int64

    public init(contextId: String, targetKind: ContextTargetKind, targetRef: String?, deadline: Int64) {
        self.contextId = contextId
        self.targetKind = targetKind
        self.targetRef = targetRef
        self.deadline = deadline
    }

    public init(snapshot: ContextSnapshotPayload, deadline: Int64) {
        self.init(contextId: snapshot.contextId, targetKind: snapshot.targetKind, targetRef: snapshot.targetRef, deadline: deadline)
    }
}

public protocol RuleResolving: Sendable {
    func resolve(gesture: ComposedGesture, context: ProviderContextSnapshot) -> ActionDescriptor?
}

public enum BrowserKind: String, Codable, Equatable, Sendable {
    case chrome
    case other
}

public enum ElementType: String, Codable, Equatable, Sendable {
    case any
    case link
}

public struct RuleContext: Codable, Equatable, Sendable {
    public let appBundleId: String
    public let browserKind: BrowserKind
    public let elementType: ElementType

    public init(appBundleId: String, browserKind: BrowserKind, elementType: ElementType) {
        self.appBundleId = appBundleId
        self.browserKind = browserKind
        self.elementType = elementType
    }
}

public struct RuleScope: Codable, Equatable, Sendable {
    public let appBundleId: String?
    public let browserKind: BrowserKind?
    public let elementType: ElementType?

    public init(appBundleId: String?, browserKind: BrowserKind?, elementType: ElementType?) {
        self.appBundleId = appBundleId
        self.browserKind = browserKind
        self.elementType = elementType
    }

    public func matches(_ context: RuleContext) -> Bool {
        if let appBundleId, appBundleId != context.appBundleId { return false }
        if let browserKind, browserKind != context.browserKind { return false }
        if let elementType, elementType != .any, elementType != context.elementType { return false }
        return true
    }

    public var specificity: Int {
        var value = 0
        if appBundleId != nil { value += 10 }
        if browserKind != nil { value += 5 }
        if let elementType, elementType != .any { value += 3 }
        return value
    }
}

public struct RuleGesture: Codable, Equatable, Sendable {
    public let type: GestureType

    public init(type: GestureType) {
        self.type = type
    }
}

public struct RuleAction: Codable, Equatable, Sendable {
    public let type: ActionType

    public init(type: ActionType) {
        self.type = type
    }
}

public struct Rule: Codable, Equatable, Sendable {
    public let id: String
    public var enabled: Bool
    public let priority: Int
    public let scope: RuleScope
    public let gesture: RuleGesture
    public let action: RuleAction

    public init(id: String, enabled: Bool, priority: Int, scope: RuleScope, gesture: RuleGesture, action: RuleAction) {
        self.id = id
        self.enabled = enabled
        self.priority = priority
        self.scope = scope
        self.gesture = gesture
        self.action = action
    }
}

public struct RuleMatch: Equatable, Sendable {
    public let rule: Rule
    public let action: RuleAction

    public init(rule: Rule, action: RuleAction) {
        self.rule = rule
        self.action = action
    }
}
