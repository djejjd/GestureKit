public struct RuleEngine: RuleResolving, Sendable {
    private let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public init() { self.init(rules: DefaultRules.v1) }

    /// 唯一的 provider-neutral 动作决策入口。BindingResolver 是内部细节，
    /// 规则层只输出协议标准动作描述，不输出 Chrome ActionType。
    public func resolve(gesture: ComposedGesture, context: ProviderContextSnapshot) -> ActionDescriptor? {
        BindingResolver.resolve(gesture: gesture, context: context)
    }

    public func match(gesture: GestureType, context: RuleContext) -> RuleMatch? {
        rules
            .filter { $0.enabled }
            .filter { $0.gesture.type == gesture }
            .filter { $0.scope.matches(context) }
            .sorted { left, right in
                if left.priority != right.priority {
                    return left.priority > right.priority
                }
                if left.scope.specificity != right.scope.specificity {
                    return left.scope.specificity > right.scope.specificity
                }
                return left.id < right.id
            }
            .first
            .map { RuleMatch(rule: $0, action: $0.action) }
    }
}

private enum BindingResolver {
    static func resolve(gesture: ComposedGesture, context: ProviderContextSnapshot) -> ActionDescriptor? {
        let actionId: StandardActionID
        let targetRef: String?
        switch gesture {
        case .threeFingerTap:
            guard context.targetKind == .standardLink, let ref = context.targetRef else { return nil }
            actionId = .browserLinkOpenAdjacent
            targetRef = ref
        case .threeFingerTapLeftEdge: actionId = .browserTabActivatePrevious; targetRef = nil
        case .threeFingerTapRightEdge: actionId = .browserTabActivateNext; targetRef = nil
        case .threeFingerDoubleTapCenter: actionId = .browserTabCloseCurrent; targetRef = nil
        case .threeFingerSwipeLeft: actionId = .browserTabActivateNext; targetRef = nil
        case .threeFingerSwipeRight: actionId = .browserTabActivatePrevious; targetRef = nil
        }
        return ActionDescriptor(actionId: actionId, contextId: context.contextId, targetRef: targetRef, parameters: [:], deadline: context.deadline)
    }
}
