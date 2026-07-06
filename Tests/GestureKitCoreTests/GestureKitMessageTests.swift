import XCTest
@testable import GestureKitCore

final class GestureKitMessageTests: XCTestCase {
    func testGestureEventMessageEncodesContractShape() throws {
        let message = GestureKitMessage.gestureEvent(
            id: "event-1",
            timestamp: 1_782_200_000_000,
            payload: GestureEventPayload(
                gesture: .threeFingerTap,
                appBundleId: "com.google.Chrome",
                confidence: 0.94,
                touchX: 0.25
            )
        )

        let data = try JSONEncoder.gestureKit.encode(message)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"version\":1"))
        XCTAssertTrue(json.contains("\"id\":\"event-1\""))
        XCTAssertTrue(json.contains("\"type\":\"gesture_event\""))
        XCTAssertTrue(json.contains("\"gesture\":\"three_finger_tap\""))
        XCTAssertTrue(json.contains("\"appBundleId\":\"com.google.Chrome\""))
        XCTAssertTrue(json.contains("\"touchX\":0.25"))
        XCTAssertTrue(json.contains("\"error\":null"))
    }

    func testActionResultDecodesKnownFailureStatus() throws {
        let data = Data("""
        {"version":1,"id":"result-1","type":"action_result","timestamp":10,"payload":{"action":"activate_left_tab","status":"edge_reached","details":{"index":"0"}},"error":null}
        """.utf8)

        let message = try JSONDecoder.gestureKit.decode(GestureKitMessage.self, from: data)

        XCTAssertEqual(message.id, "result-1")
        XCTAssertEqual(message.type, .actionResult)
        XCTAssertEqual(message.actionResultPayload?.status, .edgeReached)
    }
}
