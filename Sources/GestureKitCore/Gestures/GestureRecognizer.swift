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
    private var settings: GestureRecognitionSettings

    public init(settings: GestureRecognitionSettings = .standard) {
        self.settings = settings
    }

    public mutating func updateSettings(_ settings: GestureRecognitionSettings) {
        self.settings = settings
        session = nil
    }

    public mutating func observe(_ frame: TouchFrame) -> [GestureSessionEvent] {
        let fingerCount = frame.activeTouches.count
        if fingerCount == 3, let centroid = Self.centroid(of: frame.activeTouches) {
            if var existing = session {
                existing.latestCentroid = centroid
                session = existing
                return []
            } else {
                session = Session(startedAt: frame.time, startCentroid: centroid, latestCentroid: centroid)
                return [.candidateStarted(GestureCandidate(startedAt: frame.time, centroidX: centroid.x, centroidY: centroid.y))]
            }
        }

        guard let completed = session else { return [] }
        session = nil
        let gesture = classify(completed, endedAt: frame.time)
        return gesture.gesture == nil ? [.primitiveRejected(gesture)] : [.primitiveClassified(gesture)]
    }

    private func classify(_ session: Session, endedAt: TimeInterval) -> RecognizedGesture {
        let duration = endedAt - session.startedAt
        let dx = session.latestCentroid.x - session.startCentroid.x
        let dy = session.latestCentroid.y - session.startCentroid.y
        let distance = hypotf(dx, dy)
        let durationMs = Int((duration * 1000).rounded())
        let minSwipeDuration = Double(settings.swipeMinDurationMs) / 1000
        let maxSwipeDuration = Double(settings.swipeMaxDurationMs) / 1000
        let isQuickFlick = duration >= minSwipeDuration && duration <= maxSwipeDuration
        let horizontalEnough = abs(dx) >= settings.swipeMinDistance
            && abs(dx) >= abs(dy) * settings.swipeHorizontalRatio

        if duration <= 0.45 && distance <= 0.06 {
            return RecognizedGesture(
                gesture: .threeFingerTap,
                status: .success,
                reason: .success,
                durationMs: durationMs,
                dx: dx,
                dy: dy,
                thresholds: settings,
                centroidX: session.startCentroid.x,
                centroidY: session.startCentroid.y
            )
        }
        if isQuickFlick && horizontalEnough {
            return RecognizedGesture(
                gesture: dx < 0 ? .threeFingerSwipeLeft : .threeFingerSwipeRight,
                status: .success,
                reason: .success,
                durationMs: durationMs,
                dx: dx,
                dy: dy,
                thresholds: settings,
                centroidX: session.startCentroid.x,
                centroidY: session.startCentroid.y
            )
        }
        return RecognizedGesture(
            gesture: nil,
            status: .gestureUnstable,
            reason: failureReason(duration: duration, dx: dx, dy: dy),
            durationMs: durationMs,
            dx: dx,
            dy: dy,
            thresholds: settings,
            centroidX: session.startCentroid.x,
            centroidY: session.startCentroid.y
        )
    }

    private func failureReason(duration: TimeInterval, dx: Float, dy: Float) -> GestureFailureReason {
        let minSwipeDuration = Double(settings.swipeMinDurationMs) / 1000
        let maxSwipeDuration = Double(settings.swipeMaxDurationMs) / 1000
        if duration < minSwipeDuration {
            return .tooFast
        }
        if duration > maxSwipeDuration {
            return .tooSlow
        }
        if abs(dx) < settings.swipeMinDistance {
            return .distanceTooShort
        }
        if abs(dx) < abs(dy) * settings.swipeHorizontalRatio {
            return .horizontalRatioTooLow
        }
        return .unknown
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
