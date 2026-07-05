public enum DefaultRules {
    public static let v1: [Rule] = [
        Rule(
            id: "chrome-open-link-background",
            enabled: true,
            priority: 100,
            scope: RuleScope(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .link),
            gesture: RuleGesture(type: .threeFingerTap),
            action: RuleAction(type: .openLinkBackground)
        ),
        Rule(
            id: "chrome-activate-left-tab",
            enabled: true,
            priority: 90,
            scope: RuleScope(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .any),
            gesture: RuleGesture(type: .threeFingerSwipeLeft),
            action: RuleAction(type: .activateLeftTab)
        ),
        Rule(
            id: "chrome-activate-right-tab",
            enabled: true,
            priority: 90,
            scope: RuleScope(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .any),
            gesture: RuleGesture(type: .threeFingerSwipeRight),
            action: RuleAction(type: .activateRightTab)
        )
    ]
}
