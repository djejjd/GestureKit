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
    case probeRequest = "probe_request"
    case probeResponse = "probe_response"
    case gestureEvent = "gesture_event"
    case actionResult = "action_result"
    case settingsUpdate = "settings_update"
    case settingsAck = "settings_ack"
    case diagnosticEvent = "diagnostic_event"
    case error
    case heartbeat
}

public enum DiagnosticSource: String, Codable, Equatable, Sendable {
    case app
    case host
    case extensionSource = "extension"
}

public enum DiagnosticEventKind: String, Codable, Equatable, Sendable {
    case gesture
    case action
    case connection
    case settings
}

public enum GestureFailureReason: String, Codable, Equatable, Sendable {
    case success
    case distanceTooShort = "distance_too_short"
    case tooSlow = "too_slow"
    case tooFast = "too_fast"
    case horizontalRatioTooLow = "horizontal_ratio_too_low"
    case cooldown
    case notChrome = "not_chrome"
    case nativeHostDisconnected = "native_host_disconnected"
    case pageUnavailable = "page_unavailable"
    case noTarget = "no_target"
    case unknown
}

public struct GestureEventPayload: Codable, Equatable, Sendable {
    public let gesture: GestureType
    public let appBundleId: String
    public let confidence: Double?
    public let touchX: Double?
    public let durationMs: Int?

    public init(gesture: GestureType, appBundleId: String, confidence: Double?, touchX: Double? = nil, durationMs: Int? = nil) {
        self.gesture = gesture
        self.appBundleId = appBundleId
        self.confidence = confidence
        self.touchX = touchX
        self.durationMs = durationMs
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

public struct ProbeRequestPayload: Codable, Equatable, Sendable {
    public let source: String

    public init(source: String) {
        self.source = source
    }
}

public struct ProbeResponsePayload: Codable, Equatable, Sendable {
    public let hostConnected: Bool
    public let appConnected: Bool
    public let appSessionId: String?
    public let message: String?

    public init(hostConnected: Bool, appConnected: Bool, appSessionId: String? = nil, message: String?) {
        self.hostConnected = hostConnected
        self.appConnected = appConnected
        self.appSessionId = appSessionId
        self.message = message
    }
}

public struct SettingsUpdatePayload: Codable, Equatable, Sendable {
    public let swipeSensitivity: SwipeSensitivity
    public let swipeMinDistance: Float
    public let swipeHorizontalRatio: Float
    public let swipeMinDurationMs: Int
    public let swipeMaxDurationMs: Int

    public init(
        swipeSensitivity: SwipeSensitivity,
        swipeMinDistance: Float,
        swipeHorizontalRatio: Float,
        swipeMinDurationMs: Int,
        swipeMaxDurationMs: Int
    ) {
        self.swipeSensitivity = swipeSensitivity
        self.swipeMinDistance = swipeMinDistance
        self.swipeHorizontalRatio = swipeHorizontalRatio
        self.swipeMinDurationMs = swipeMinDurationMs
        self.swipeMaxDurationMs = swipeMaxDurationMs
    }

    public var recognitionSettings: GestureRecognitionSettings {
        GestureRecognitionSettings(
            swipeSensitivity: swipeSensitivity,
            swipeMinDistance: swipeMinDistance,
            swipeHorizontalRatio: swipeHorizontalRatio,
            swipeMinDurationMs: swipeMinDurationMs,
            swipeMaxDurationMs: swipeMaxDurationMs
        )
    }
}

public struct SettingsAckPayload: Codable, Equatable, Sendable {
    public let applied: Bool
    public let swipeSensitivity: SwipeSensitivity
    public let appSessionId: String
    public let recognitionSettings: GestureRecognitionSettings
    public let message: String?

    public init(
        applied: Bool,
        swipeSensitivity: SwipeSensitivity,
        appSessionId: String,
        recognitionSettings: GestureRecognitionSettings,
        message: String? = nil
    ) {
        self.applied = applied
        self.swipeSensitivity = swipeSensitivity
        self.appSessionId = appSessionId
        self.recognitionSettings = recognitionSettings
        self.message = message
    }
}

public struct DiagnosticEventPayload: Codable, Equatable, Sendable {
    public let source: DiagnosticSource
    public let kind: DiagnosticEventKind
    public let gesture: GestureType?
    public let action: ActionType?
    public let status: ActionStatus?
    public let reason: GestureFailureReason
    public let swipeSensitivity: SwipeSensitivity?
    public let dx: Double?
    public let dy: Double?
    public let distance: Double?
    public let durationMs: Int?
    public let horizontalRatio: Double?
    public let thresholds: GestureRecognitionSettings?
    public let message: String?

    public init(
        source: DiagnosticSource,
        kind: DiagnosticEventKind,
        gesture: GestureType?,
        action: ActionType?,
        status: ActionStatus?,
        reason: GestureFailureReason,
        swipeSensitivity: SwipeSensitivity?,
        dx: Double?,
        dy: Double?,
        distance: Double?,
        durationMs: Int?,
        horizontalRatio: Double?,
        thresholds: GestureRecognitionSettings?,
        message: String?
    ) {
        self.source = source
        self.kind = kind
        self.gesture = gesture
        self.action = action
        self.status = status
        self.reason = reason
        self.swipeSensitivity = swipeSensitivity
        self.dx = dx
        self.dy = dy
        self.distance = distance
        self.durationMs = durationMs
        self.horizontalRatio = horizontalRatio
        self.thresholds = thresholds
        self.message = message
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
        case probeRequest(ProbeRequestPayload)
        case probeResponse(ProbeResponsePayload)
        case gestureEvent(GestureEventPayload)
        case actionResult(ActionResultPayload)
        case settingsUpdate(SettingsUpdatePayload)
        case settingsAck(SettingsAckPayload)
        case diagnosticEvent(DiagnosticEventPayload)
        case object([String: String])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let payload = try? container.decode(ProbeRequestPayload.self) {
                self = .probeRequest(payload)
            } else if let payload = try? container.decode(ProbeResponsePayload.self) {
                self = .probeResponse(payload)
            } else if let payload = try? container.decode(GestureEventPayload.self) {
                self = .gestureEvent(payload)
            } else if let payload = try? container.decode(ActionResultPayload.self) {
                self = .actionResult(payload)
            } else if let payload = try? container.decode(SettingsUpdatePayload.self) {
                self = .settingsUpdate(payload)
            } else if let payload = try? container.decode(SettingsAckPayload.self) {
                self = .settingsAck(payload)
            } else if let payload = try? container.decode(DiagnosticEventPayload.self) {
                self = .diagnosticEvent(payload)
            } else {
                self = .object(try container.decode([String: String].self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .probeRequest(let payload):
                try container.encode(payload)
            case .probeResponse(let payload):
                try container.encode(payload)
            case .gestureEvent(let payload):
                try container.encode(payload)
            case .actionResult(let payload):
                try container.encode(payload)
            case .settingsUpdate(let payload):
                try container.encode(payload)
            case .settingsAck(let payload):
                try container.encode(payload)
            case .diagnosticEvent(let payload):
                try container.encode(payload)
            case .object(let payload):
                try container.encode(payload)
            }
        }
    }

    public static func probeRequest(id: String, timestamp: Int64, payload: ProbeRequestPayload) -> GestureKitMessage {
        GestureKitMessage(version: 1, id: id, type: .probeRequest, timestamp: timestamp, payload: .probeRequest(payload), error: nil)
    }

    public static func probeResponse(id: String, timestamp: Int64, payload: ProbeResponsePayload) -> GestureKitMessage {
        GestureKitMessage(version: 1, id: id, type: .probeResponse, timestamp: timestamp, payload: .probeResponse(payload), error: nil)
    }

    public static func gestureEvent(id: String, timestamp: Int64, payload: GestureEventPayload) -> GestureKitMessage {
        GestureKitMessage(version: 1, id: id, type: .gestureEvent, timestamp: timestamp, payload: .gestureEvent(payload), error: nil)
    }

    public static func settingsAck(id: String, timestamp: Int64, payload: SettingsAckPayload) -> GestureKitMessage {
        GestureKitMessage(version: 1, id: id, type: .settingsAck, timestamp: timestamp, payload: .settingsAck(payload), error: nil)
    }

    public static func diagnosticEvent(id: String, timestamp: Int64, payload: DiagnosticEventPayload) -> GestureKitMessage {
        GestureKitMessage(version: 1, id: id, type: .diagnosticEvent, timestamp: timestamp, payload: .diagnosticEvent(payload), error: nil)
    }

    public var actionResultPayload: ActionResultPayload? {
        guard case .actionResult(let payload) = payload else { return nil }
        return payload
    }

    public var probeRequestPayload: ProbeRequestPayload? {
        guard case .probeRequest(let payload) = payload else { return nil }
        return payload
    }

    public var probeResponsePayload: ProbeResponsePayload? {
        guard case .probeResponse(let payload) = payload else { return nil }
        return payload
    }

    public var settingsUpdatePayload: SettingsUpdatePayload? {
        guard case .settingsUpdate(let payload) = payload else { return nil }
        return payload
    }

    public var settingsAckPayload: SettingsAckPayload? {
        guard case .settingsAck(let payload) = payload else { return nil }
        return payload
    }

    public var diagnosticEventPayload: DiagnosticEventPayload? {
        guard case .diagnosticEvent(let payload) = payload else { return nil }
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
        switch type {
        case .probeRequest:
            payload = .probeRequest(try container.decode(ProbeRequestPayload.self, forKey: .payload))
        case .probeResponse:
            payload = .probeResponse(try container.decode(ProbeResponsePayload.self, forKey: .payload))
        case .gestureEvent:
            payload = .gestureEvent(try container.decode(GestureEventPayload.self, forKey: .payload))
        case .actionResult:
            payload = .actionResult(try container.decode(ActionResultPayload.self, forKey: .payload))
        case .settingsUpdate:
            payload = .settingsUpdate(try container.decode(SettingsUpdatePayload.self, forKey: .payload))
        case .settingsAck:
            payload = .settingsAck(try container.decode(SettingsAckPayload.self, forKey: .payload))
        case .diagnosticEvent:
            payload = .diagnosticEvent(try container.decode(DiagnosticEventPayload.self, forKey: .payload))
        case .hello, .error, .heartbeat:
            payload = try container.decode(Payload.self, forKey: .payload)
        }
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
