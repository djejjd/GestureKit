public struct RuleEngine: Sendable {
    private let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
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
