import XCTest
@testable import GestureKitCore

final class RecognitionPlanTests: XCTestCase {
    func testLinkBindingDerivesLinkClickGuardForItsGestureDefinition() throws {
        let configuration = AppConfiguration.initial(storeEpoch: "plan")

        let plan = try RecognitionPlan(configuration: configuration)

        XCTAssertTrue(plan.features(for: "three-finger-tap").contains(.linkClick))
        XCTAssertFalse(plan.features(for: "three-finger-swipe-left").contains(.linkClick))
    }

    func testCandidateFeaturesUseDefinitionsInsteadOfGestureNames() throws {
        let plan = try RecognitionPlan(configuration: .initial(storeEpoch: "plan"))

        XCTAssertEqual(plan.candidateFeatures(fingerCount: 3), [.linkClick, .dragSelection])
        XCTAssertEqual(plan.candidateFeatures(fingerCount: 2), [])
    }

    func testSwipeGuardDoesNotDependOnLinkBinding() throws {
        let configuration = try AppConfiguration.initial(storeEpoch: "plan")
            .updatingBinding(id: "link-open-adjacent", enabled: false)
        let plan = try RecognitionPlan(configuration: configuration)
        XCTAssertEqual(plan.candidateFeatures(fingerCount: 3), [.dragSelection])
        XCTAssertEqual(plan.features(for: "three-finger-swipe-left"), [.dragSelection])
    }

    func testLinkClickFeatureUsesProtocolWireValue() {
        XCTAssertEqual(InteractionGuardFeature.linkClick.rawValue, "link_click")
    }
}
