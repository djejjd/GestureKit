import XCTest
@testable import GestureKitCore

final class LocalIPCProtocolTests: XCTestCase {
    func testGestureEventEnvelopeEncodesAsSingleLineJSON() throws {
        let envelope = LocalIPCEnvelope.gesture(
            id: "ipc-1",
            timestamp: 100,
            gesture: .threeFingerTap,
            appBundleId: "com.google.Chrome"
        )

        let line = try LocalIPCProtocol.encodeLine(envelope)

        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains("\"type\":\"gesture_event\""))
    }

    func testEnvelopeDecodesFromLine() throws {
        let line = #"{"version":1,"id":"ipc-1","type":"gesture_event","timestamp":100,"payload":{"gesture":"three_finger_tap","appBundleId":"com.google.Chrome","confidence":1},"error":null}"#

        let envelope = try LocalIPCProtocol.decodeLine(line)

        XCTAssertEqual(envelope.id, "ipc-1")
        XCTAssertEqual(envelope.message.payload, .gestureEvent(GestureEventPayload(gesture: .threeFingerTap, appBundleId: "com.google.Chrome", confidence: 1)))
    }
}
