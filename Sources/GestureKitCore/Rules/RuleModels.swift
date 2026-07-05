import Foundation

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
