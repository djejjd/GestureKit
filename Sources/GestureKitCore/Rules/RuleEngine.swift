public struct RuleEngine: RuleResolving, Sendable {
    private let rules: [Rule]
    private let bindings: [BindingRule]

    public init(rules: [Rule]) {
        self.rules = rules
        self.bindings = []
    }

    public init() {
        self.rules = DefaultRules.v1
        self.bindings = DefaultRules.v1Bindings
    }

    /// 用户可配绑定入口：默认绑定 + 用户覆盖合并后参与决策。
    /// 覆盖为空时完全回退默认绑定。
    public init(
        overrides: [BindingOverride] = [],
        defaultBindings: [BindingRule] = DefaultRules.v1Bindings
    ) {
        self.rules = DefaultRules.v1
        self.bindings = UserBindingConfiguration(overrides: overrides)
            .effectiveBindings(defaults: defaultBindings)
    }

    public init(configuration: AppConfiguration) {
        self.rules = []
        self.bindings = configuration.rules
    }

    /// 唯一的 provider-neutral 动作决策入口。BindingResolver 是内部细节，
    /// 规则层只输出协议标准动作描述，不输出 Chrome ActionType。
    public func resolve(gesture: ComposedGesture, context: ProviderContextSnapshot) -> ActionDescriptor? {
        if !bindings.isEmpty {
            return BindingResolver.resolve(
                bindings: bindings,
                gesture: gesture,
                context: context
            )
        }
        return BindingResolver.resolve(gesture: gesture, context: context)
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
    static func resolve(
        bindings: [BindingRule],
        gesture: ComposedGesture,
        context: ProviderContextSnapshot
    ) -> ActionDescriptor? {
        let binding = bindings
            .filter { $0.enabled && $0.gestureDefinitionId == gesture.gestureDefinitionID }
            .filter { binding in
                binding.contextConstraints.allSatisfy { key, value in
                    switch key {
                    case "targetKind": return value == context.targetKind.rawValue
                    default: return false
                    }
                }
            }
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.id < rhs.id : lhs.priority > rhs.priority
            }
            .first

        guard let binding else { return nil }
        let targetRef = binding.actionId == .browserLinkOpenAdjacent ? context.targetRef : nil
        guard binding.actionId != .browserLinkOpenAdjacent || targetRef != nil else { return nil }
        return ActionDescriptor(
            actionId: binding.actionId,
            contextId: context.contextId,
            targetRef: targetRef,
            parameters: binding.actionParameters,
            deadline: context.deadline
        )
    }

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
        // V2.5 预设手势集：无硬编码默认动作，仅经绑定解析；legacy fallback 不产出动作。
        case .twoFingerSwipeLeft, .twoFingerSwipeRight, .fourFingerTap, .fourFingerSwipeLeft, .fourFingerSwipeRight:
            return nil
        }
        return ActionDescriptor(actionId: actionId, contextId: context.contextId, targetRef: targetRef, parameters: [:], deadline: context.deadline)
    }
}
