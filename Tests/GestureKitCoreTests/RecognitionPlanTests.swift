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

        XCTAssertEqual(plan.candidateFeatures(fingerCount: 3), [.linkClick])
        XCTAssertEqual(plan.candidateFeatures(fingerCount: 2), [])
    }

    func testLinkClickFeatureUsesProtocolWireValue() {
        XCTAssertEqual(InteractionGuardFeature.linkClick.rawValue, "link_click")
    }
}
