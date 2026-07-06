import Foundation

public enum GestureType: String, Codable, Equatable, Sendable {
    case threeFingerTap = "three_finger_tap"
    case threeFingerSwipeLeft = "three_finger_swipe_left"
    case threeFingerSwipeRight = "three_finger_swipe_right"
}

public enum ActionType: String, Codable, Equatable, Sendable {
    case openLinkBackground = "open_link_background"
    case activateLeftTab = "activate_left_tab"
    case activateRightTab = "activate_right_tab"
    case closeTab = "close_tab"
}

public enum ActionStatus: String, Codable, Equatable, Sendable {
    case success
    case edgeReached = "edge_reached"
    case noRecentPointer = "no_recent_pointer"
    case noTarget = "no_target"
    case pageUnavailable = "page_unavailable"
    case unsupportedURLScheme = "unsupported_url_scheme"
    case unsupportedApp = "unsupported_app"
    case nativeHostDisconnected = "native_host_disconnected"
    case appUnavailable = "app_unavailable"
    case extensionUnavailable = "extension_unavailable"
    case gestureUnstable = "gesture_unstable"
    case error
}

public enum MessageType: String, Codable, Equatable, Sendable {
    case hello
    case gestureEvent = "gesture_event"
    case actionResult = "action_result"
    case error
    case heartbeat
}

public struct GestureEventPayload: Codable, Equatable, Sendable {
    public let gesture: GestureType
    public let appBundleId: String
    public let confidence: Double?
    public let touchX: Double?

    public init(gesture: GestureType, appBundleId: String, confidence: Double?, touchX: Double? = nil) {
        self.gesture = gesture
        self.appBundleId = appBundleId
        self.confidence = confidence
        self.touchX = touchX
    }
}

public struct ActionResultPayload: Codable, Equatable, Sendable {
    public let action: ActionType
    public let status: ActionStatus
    public let details: [String: String]?

    public init(action: ActionType, status: ActionStatus, details: [String: String]?) {
        self.action = action
        self.status = status
        self.details = details
    }
}

public struct GestureKitError: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct GestureKitMessage: Codable, Equatable, Sendable {
    public let version: Int
    public let id: String
    public let type: MessageType
    public let timestamp: Int64
    public let payload: Payload
    public let error: GestureKitError?

    private enum CodingKeys: String, CodingKey {
        case version
        case id
        case type
        case timestamp
        case payload
        case error
    }

    public enum Payload: Codable, Equatable, Sendable {
        case gestureEvent(GestureEventPayload)
        case actionResult(ActionResultPayload)
        case object([String: String])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let payload = try? container.decode(GestureEventPayload.self) {
                self = .gestureEvent(payload)
            } else if let payload = try? container.decode(ActionResultPayload.self) {
                self = .actionResult(payload)
            } else {
                self = .object(try container.decode([String: String].self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .gestureEvent(let payload):
                try container.encode(payload)
            case .actionResult(let payload):
                try container.encode(payload)
            case .object(let payload):
                try container.encode(payload)
            }
        }
    }

    public static func gestureEvent(id: String, timestamp: Int64, payload: GestureEventPayload) -> GestureKitMessage {
        GestureKitMessage(version: 1, id: id, type: .gestureEvent, timestamp: timestamp, payload: .gestureEvent(payload), error: nil)
    }

    public var actionResultPayload: ActionResultPayload? {
        guard case .actionResult(let payload) = payload else { return nil }
        return payload
    }

    public init(
        version: Int,
        id: String,
        type: MessageType,
        timestamp: Int64,
        payload: Payload,
        error: GestureKitError?
    ) {
        self.version = version
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(MessageType.self, forKey: .type)
        timestamp = try container.decode(Int64.self, forKey: .timestamp)
        payload = try container.decode(Payload.self, forKey: .payload)
        error = try container.decodeIfPresent(GestureKitError.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(payload, forKey: .payload)
        if let error {
            try container.encode(error, forKey: .error)
        } else {
            try container.encodeNil(forKey: .error)
        }
    }
}

public extension JSONEncoder {
    static var gestureKit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var gestureKit: JSONDecoder {
        JSONDecoder()
    }
}
