import XCTest
@testable import GestureKitCore

final class RuleEngineTests: XCTestCase {
    func testLinkContextResolvesOpenAdjacentAction() {
        let engine = RuleEngine(rules: DefaultRules.v1)
        let context = ProviderContextSnapshot(
            contextId: "context-link",
            targetKind: .standardLink,
            targetRef: "opaque-link",
            deadline: 1_000
        )

        XCTAssertEqual(
            engine.resolve(gesture: .threeFingerTap, context: context)?.actionId,
            .browserLinkOpenAdjacent
        )
    }

    func testTapOnChromeLinkMatchesOpenLinkRule() {
        let engine = RuleEngine(rules: DefaultRules.v1)
        let context = RuleContext(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .link)

        let match = engine.match(gesture: .threeFingerTap, context: context)

        XCTAssertEqual(match?.rule.id, "chrome-open-link-background")
        XCTAssertEqual(match?.action.type, .openLinkBackground)
    }

    func testSwipeLeftOnChromeAnyElementMatchesLeftTabRule() {
        let engine = RuleEngine(rules: DefaultRules.v1)
        let context = RuleContext(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .any)

        let match = engine.match(gesture: .threeFingerSwipeLeft, context: context)

        XCTAssertEqual(match?.rule.id, "chrome-activate-left-tab")
        XCTAssertEqual(match?.action.type, .activateLeftTab)
    }

    func testUnsupportedAppDoesNotMatch() {
        let engine = RuleEngine(rules: DefaultRules.v1)
        let context = RuleContext(appBundleId: "com.apple.Safari", browserKind: .other, elementType: .link)

        XCTAssertNil(engine.match(gesture: .threeFingerTap, context: context))
    }

    func testDisabledRuleIsIgnored() {
        var rule = DefaultRules.v1[0]
        rule.enabled = false
        let engine = RuleEngine(rules: [rule])
        let context = RuleContext(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .link)

        XCTAssertNil(engine.match(gesture: .threeFingerTap, context: context))
    }

    func testHigherPriorityWinsBeforeStableIdTieBreaker() {
        let low = Rule(
            id: "b-low",
            enabled: true,
            priority: 10,
            scope: RuleScope(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .link),
            gesture: RuleGesture(type: .threeFingerTap),
            action: RuleAction(type: .activateLeftTab)
        )
        let high = Rule(
            id: "a-high",
            enabled: true,
            priority: 20,
            scope: RuleScope(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .link),
            gesture: RuleGesture(type: .threeFingerTap),
            action: RuleAction(type: .openLinkBackground)
        )
        let engine = RuleEngine(rules: [low, high])
        let context = RuleContext(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .link)

        XCTAssertEqual(engine.match(gesture: .threeFingerTap, context: context)?.rule.id, "a-high")
    }
}
