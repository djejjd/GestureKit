import Foundation

public struct TouchSample: Equatable, Sendable {
    public let id: Int32
    public let x: Float
    public let y: Float

    public init(id: Int32, x: Float, y: Float) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public struct TouchFrame: Equatable, Sendable {
    public let time: TimeInterval
    public let activeTouches: [TouchSample]

    public init(time: TimeInterval, activeTouches: [TouchSample]) {
        self.time = time
        self.activeTouches = activeTouches
    }

    public static func frame(time: TimeInterval, activeTouches: [TouchSample]) -> TouchFrame {
        TouchFrame(time: time, activeTouches: activeTouches)
    }
}

public struct RecognizedGesture: Equatable, Sendable {
    public let gesture: GestureType?
    public let status: ActionStatus
    public let durationMs: Int
    public let dx: Float
    public let dy: Float
    public let centroidX: Float?
    public let centroidY: Float?

    public init(
        gesture: GestureType?,
        status: ActionStatus,
        durationMs: Int,
        dx: Float,
        dy: Float,
        centroidX: Float? = nil,
        centroidY: Float? = nil
    ) {
        self.gesture = gesture
        self.status = status
        self.durationMs = durationMs
        self.dx = dx
        self.dy = dy
        self.centroidX = centroidX
        self.centroidY = centroidY
    }
}
