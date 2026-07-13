import XCTest
@testable import GestureKitCore

final class GestureSessionEventTests: XCTestCase {
    func testThreeTouchesEmitCandidateBeforeCompletion() {
        var recognizer = GestureRecognizer()
        let frame = TouchFrame.frame(
            time: 0,
            activeTouches: [
                .touch(1, 0.30, 0.40), .touch(2, 0.30, 0.40), .touch(3, 0.30, 0.40)
            ]
        )

        let events = recognizer.observe(frame)

        XCTAssertEqual(events.first, .candidateStarted(GestureCandidate(
            startedAt: 0,
            centroidX: 0.30,
            centroidY: 0.40
        )))
    }
}

private extension TouchSample {
    static func touch(_ id: Int32, _ x: Float, _ y: Float) -> TouchSample {
        TouchSample(id: id, x: x, y: y)
    }
}
