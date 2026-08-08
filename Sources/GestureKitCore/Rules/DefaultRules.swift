public enum DefaultRules {
    public static let v1GestureDefinitions: [GestureDefinition] = [
        .init(id: "three-finger-tap", primitive: .tap, fingers: 3, repetitions: 1, maxIntervalMs: nil, direction: nil, region: .any, maxDurationMs: 180),
        .init(id: "three-finger-tap-left-edge", primitive: .tap, fingers: 3, repetitions: 1, maxIntervalMs: nil, direction: nil, region: .leftEdge, maxDurationMs: 180),
        .init(id: "three-finger-tap-right-edge", primitive: .tap, fingers: 3, repetitions: 1, maxIntervalMs: nil, direction: nil, region: .rightEdge, maxDurationMs: 180),
        .init(id: "three-finger-double-tap-center", primitive: .tap, fingers: 3, repetitions: 2, maxIntervalMs: 300, direction: nil, region: .center, maxDurationMs: 180),
        .init(id: "three-finger-swipe-left", primitive: .swipe, fingers: 3, repetitions: 1, maxIntervalMs: nil, direction: .left, region: .any, maxDurationMs: 300),
        .init(id: "three-finger-swipe-right", primitive: .swipe, fingers: 3, repetitions: 1, maxIntervalMs: nil, direction: .right, region: .any, maxDurationMs: 300)
    ]

    /// V2.5 开放预设手势集：二指左右滑动、四指轻点/滑动。
    /// 二指上下滑动（滚动）为系统刚需，不占用；四指默认由系统「切换桌面空间」占用，
    /// 是否启用由系统手势检测/引导决定（见设计 §7）。
    public static let v2PresetGestureDefinitions: [GestureDefinition] = [
        .init(id: "two-finger-swipe-left", primitive: .swipe, fingers: 2, repetitions: 1, maxIntervalMs: nil, direction: .left, region: .any, maxDurationMs: 300),
        .init(id: "two-finger-swipe-right", primitive: .swipe, fingers: 2, repetitions: 1, maxIntervalMs: nil, direction: .right, region: .any, maxDurationMs: 300),
        .init(id: "four-finger-tap", primitive: .tap, fingers: 4, repetitions: 1, maxIntervalMs: nil, direction: nil, region: .any, maxDurationMs: 180),
        .init(id: "four-finger-swipe-left", primitive: .swipe, fingers: 4, repetitions: 1, maxIntervalMs: nil, direction: .left, region: .any, maxDurationMs: 300),
        .init(id: "four-finger-swipe-right", primitive: .swipe, fingers: 4, repetitions: 1, maxIntervalMs: nil, direction: .right, region: .any, maxDurationMs: 300)
    ]

    /// V2.5 默认活跃手势定义集：既有 V1 三指手势 + 开放预设（二指/四指）。
    public static let defaultGestureDefinitions: [GestureDefinition] =
        v1GestureDefinitions + v2PresetGestureDefinitions

    /// V1 的 provider-neutral 预设绑定。旧 `v1` 仅为存量设置迁移保留；
    /// 新路径一律经 `RuleEngine.resolve` 输出标准 ActionDescriptor。
    public static let v1Bindings: [BindingRule] = [
        binding("link-open-adjacent", "three-finger-tap", ["targetKind": "standard_link"], .browserLinkOpenAdjacent),
        binding("left-edge-previous-tab", "three-finger-tap-left-edge", [:], .browserTabActivatePrevious),
        binding("right-edge-next-tab", "three-finger-tap-right-edge", [:], .browserTabActivateNext),
        binding("center-double-tap-close", "three-finger-double-tap-center", [:], .browserTabCloseCurrent),
        binding("swipe-left-next-tab", "three-finger-swipe-left", [:], .browserTabActivateNext),
        binding("swipe-right-previous-tab", "three-finger-swipe-right", [:], .browserTabActivatePrevious)
    ]

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

    private static func binding(_ id: String, _ gestureDefinitionId: String, _ contextConstraints: [String: String], _ actionId: StandardActionID) -> BindingRule {
        BindingRule(id: id, gestureDefinitionId: gestureDefinitionId, contextConstraints: contextConstraints, actionId: actionId, actionParameters: [:], priority: 100, enabled: true)
    }
}
