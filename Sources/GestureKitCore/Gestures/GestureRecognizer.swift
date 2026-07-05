import Foundation

public struct GestureRecognizer: Sendable {
    private struct Centroid {
        let x: Float
        let y: Float
    }

    private struct Session {
        let startedAt: TimeInterval
        let startCentroid: Centroid
        var latestCentroid: Centroid
    }

    private var session: Session?

    public init() {}

    public mutating func observe(_ frame: TouchFrame) -> RecognizedGesture? {
        let fingerCount = frame.activeTouches.count
        if fingerCount == 3, let centroid = Self.centroid(of: frame.activeTouches) {
            if var existing = session {
                existing.latestCentroid = centroid
                session = existing
            } else {
                session = Session(startedAt: frame.time, startCentroid: centroid, latestCentroid: centroid)
            }
            return nil
        }

        guard let completed = session else { return nil }
        session = nil
        return classify(completed, endedAt: frame.time)
    }

    private func classify(_ session: Session, endedAt: TimeInterval) -> RecognizedGesture {
        let duration = endedAt - session.startedAt
        let dx = session.latestCentroid.x - session.startCentroid.x
        let dy = session.latestCentroid.y - session.startCentroid.y
        let distance = hypotf(dx, dy)
        let durationMs = Int((duration * 1000).rounded())
        let horizontalEnough = abs(dx) >= 0.12 && abs(dx) > abs(dy) * 1.2

        if duration <= 0.45 && distance <= 0.06 {
            return RecognizedGesture(gesture: .threeFingerTap, status: .success, durationMs: durationMs, dx: dx, dy: dy)
        }
        if horizontalEnough {
            return RecognizedGesture(gesture: dx < 0 ? .threeFingerSwipeLeft : .threeFingerSwipeRight, status: .success, durationMs: durationMs, dx: dx, dy: dy)
        }
        return RecognizedGesture(gesture: nil, status: .gestureUnstable, durationMs: durationMs, dx: dx, dy: dy)
    }

    private static func centroid(of touches: [TouchSample]) -> Centroid? {
        guard !touches.isEmpty else { return nil }
        let total = touches.reduce((x: Float(0), y: Float(0))) { partial, sample in
            (partial.x + sample.x, partial.y + sample.y)
        }
        let count = Float(touches.count)
        return Centroid(x: total.x / count, y: total.y / count)
    }
}
