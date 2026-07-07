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
                touchX: 0.25,
                durationMs: 96
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
        XCTAssertTrue(json.contains("\"durationMs\":96"))
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

    func testSettingsUpdateDecodesSwipeSensitivity() throws {
        let data = Data("""
        {"version":1,"id":"settings-1","type":"settings_update","timestamp":10,"payload":{"swipeSensitivity":"sensitive","swipeMinDistance":0.075,"swipeHorizontalRatio":1.25,"swipeMinDurationMs":50,"swipeMaxDurationMs":480},"error":null}
        """.utf8)

        let message = try JSONDecoder.gestureKit.decode(GestureKitMessage.self, from: data)

        XCTAssertEqual(message.type, .settingsUpdate)
        XCTAssertEqual(message.settingsUpdatePayload?.swipeSensitivity, .sensitive)
        XCTAssertEqual(message.settingsUpdatePayload?.recognitionSettings, .sensitive)
    }

    func testSettingsAckEncodesAppliedSensitivity() throws {
        let message = GestureKitMessage.settingsAck(
            id: "settings-ack-1",
            timestamp: 20,
            payload: SettingsAckPayload(applied: true, swipeSensitivity: .standard)
        )

        let json = String(decoding: try JSONEncoder.gestureKit.encode(message), as: UTF8.self)

        XCTAssertTrue(json.contains("\"type\":\"settings_ack\""))
        XCTAssertTrue(json.contains("\"applied\":true"))
        XCTAssertTrue(json.contains("\"swipeSensitivity\":\"standard\""))
    }
}
