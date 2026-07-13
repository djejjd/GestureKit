import XCTest
@testable import GestureKitApp
@testable import GestureKitCore

@MainActor
final class GestureSessionCoordinatorTests: XCTestCase {
    func testCandidateImmediatelyJournalsAndRoutesGuard() {
        var journaled: [String] = []
        var routed: [String] = []
        let coordinator = GestureSessionCoordinator(
            guardJournal: { journaled.append($0) },
            guardRouter: { routed.append($0) }
        )

        let sessionId = coordinator.handle(.candidateStarted(GestureCandidate(startedAt: 0, centroidX: 0.5, centroidY: 0.5)))

        XCTAssertNotNil(sessionId)
        XCTAssertEqual(journaled, [sessionId!])
        XCTAssertEqual(routed, [sessionId!])
    }
}
