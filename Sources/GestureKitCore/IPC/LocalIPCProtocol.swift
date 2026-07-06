import Foundation

public struct LocalIPCEnvelope: Codable, Equatable, Sendable {
    public let message: GestureKitMessage

    public var id: String { message.id }

    public init(message: GestureKitMessage) {
        self.message = message
    }

    public static func gesture(
        id: String,
        timestamp: Int64,
        gesture: GestureType,
        appBundleId: String,
        touchX: Double? = nil
    ) -> LocalIPCEnvelope {
        LocalIPCEnvelope(message: .gestureEvent(
            id: id,
            timestamp: timestamp,
            payload: GestureEventPayload(gesture: gesture, appBundleId: appBundleId, confidence: 1, touchX: touchX)
        ))
    }
}

public enum LocalIPCProtocol {
    public static func encodeLine(_ envelope: LocalIPCEnvelope) throws -> String {
        let data = try JSONEncoder.gestureKit.encode(envelope.message)
        return String(decoding: data, as: UTF8.self)
    }

    public static func decodeLine(_ line: String) throws -> LocalIPCEnvelope {
        let data = Data(line.utf8)
        return LocalIPCEnvelope(message: try JSONDecoder.gestureKit.decode(GestureKitMessage.self, from: data))
    }
}
