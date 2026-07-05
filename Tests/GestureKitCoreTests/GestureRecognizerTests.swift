import XCTest
@testable import GestureKitCore

final class GestureRecognizerTests: XCTestCase {
    func testThreeFingerTapIsRecognized() {
        var recognizer = GestureRecognizer()

        XCTAssertNil(recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)])))
        let event = recognizer.observe(.frame(time: 0.18, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerTap)
    }

    func testPhysicalLeftSwipeIsRecognized() {
        var recognizer = GestureRecognizer()

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.70, 0.40), .touch(2, 0.72, 0.40), .touch(3, 0.74, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.48, 0.40), .touch(2, 0.50, 0.40), .touch(3, 0.52, 0.40)]))
        let event = recognizer.observe(.frame(time: 0.34, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeLeft)
    }

    func testPhysicalRightSwipeIsRecognized() {
        var recognizer = GestureRecognizer()

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.55, 0.40), .touch(2, 0.57, 0.40), .touch(3, 0.59, 0.40)]))
        let event = recognizer.observe(.frame(time: 0.34, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
    }

    func testUnclearGestureIsReported() {
        var recognizer = GestureRecognizer()

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.30), .touch(2, 0.32, 0.32), .touch(3, 0.34, 0.34)]))
        _ = recognizer.observe(.frame(time: 0.80, activeTouches: [.touch(1, 0.36, 0.42), .touch(2, 0.38, 0.44), .touch(3, 0.40, 0.46)]))
        let event = recognizer.observe(.frame(time: 0.90, activeTouches: []))

        XCTAssertEqual(event?.status, .gestureUnstable)
    }
}

private extension TouchSample {
    static func touch(_ id: Int32, _ x: Float, _ y: Float) -> TouchSample {
        TouchSample(id: id, x: x, y: y)
    }
}
