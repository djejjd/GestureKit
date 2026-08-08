import Foundation

public struct GestureRecognizer: Sendable {
    private struct Centroid {
        let x: Float
        let y: Float
    }

    private struct Session {
        let startedAt: TimeInterval
        let startCentroid: Centroid
        let fingerCount: Int
        var latestCentroid: Centroid
    }

    private var session: Session?
    private var settings: GestureRecognitionSettings
    /// 当前活跃手势定义集。识别器按定义集的 fingerCount 匹配帧手指数，
    /// 并在 classify 时按命中定义的 primitive/direction 输出语义。
    private var definitions: [GestureDefinition]
    /// A higher touch count belongs to another gesture. After a terminal count
    /// drop, do not reenter until the remaining touches lift.
    private var requiresAllTouchesLift = false

    public init(
        settings: GestureRecognitionSettings = .standard,
        definitions: [GestureDefinition] = DefaultRules.defaultGestureDefinitions
    ) {
        self.settings = settings
        self.definitions = definitions
    }

    public mutating func updateSettings(_ settings: GestureRecognitionSettings) {
        self.settings = settings
        session = nil
        requiresAllTouchesLift = false
    }

    /// 切换活跃手势定义集（配置更新时调用）。清空进行中的 session，
    /// 避免旧定义集的候选复用新定义集状态。
    public mutating func updateDefinitions(_ definitions: [GestureDefinition]) {
        self.definitions = definitions
        session = nil
        requiresAllTouchesLift = false
    }

    private var activeFingerCounts: Set<Int> {
        Set(definitions.map(\.fingers))
    }

    public mutating func observe(_ frame: TouchFrame) -> [GestureSessionEvent] {
        let fingerCount = frame.activeTouches.count
        if requiresAllTouchesLift {
            if fingerCount == 0 {
                requiresAllTouchesLift = false
            }
            return []
        }
        if let activeSession = session, fingerCount > activeSession.fingerCount {
            session = nil
            requiresAllTouchesLift = true
            // 通知协调器结束已启动的候选，避免后续手势复用陈旧 session。
            return [.primitiveRejected(rejected(activeSession, endedAt: frame.time))]
        }
        if let activeSession = session,
           fingerCount > 0,
           fingerCount < activeSession.fingerCount {
            session = nil
            requiresAllTouchesLift = true
            let gesture = classify(activeSession, endedAt: frame.time)
            return gesture.gesture == nil ? [.primitiveRejected(gesture)] : [.primitiveClassified(gesture)]
        }
        if activeFingerCounts.contains(fingerCount), let centroid = Self.centroid(of: frame.activeTouches) {
            if var existing = session {
                existing.latestCentroid = centroid
                session = existing
                return []
            } else {
                session = Session(startedAt: frame.time, startCentroid: centroid, fingerCount: fingerCount, latestCentroid: centroid)
                return [.candidateStarted(GestureCandidate(startedAt: frame.time, centroidX: centroid.x, centroidY: centroid.y, fingerCount: fingerCount))]
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

        let gesture: GestureType?
        if duration <= 0.45 && distance <= 0.06 {
            gesture = outputGesture(fingerCount: session.fingerCount, primitive: .tap, direction: nil)
        } else if isQuickFlick && horizontalEnough {
            gesture = outputGesture(fingerCount: session.fingerCount, primitive: .swipe, direction: dx < 0 ? .left : .right)
        } else {
            gesture = nil
        }
        guard let gesture else {
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
        return RecognizedGesture(
            gesture: gesture,
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

    /// 按 session 手指数 + 运动原语/方向，仅在活跃定义集声明了该组合时输出语义手势。
    /// 未声明的组合（如二指点按）返回 nil，由调用方收敛为不稳定。
    private func outputGesture(fingerCount: Int, primitive: GesturePrimitive, direction: GestureDirection?) -> GestureType? {
        guard let gesture = Self.gestureType(fingerCount: fingerCount, primitive: primitive, direction: direction) else { return nil }
        let isDefined = definitions.contains { definition in
            definition.fingers == fingerCount
                && definition.primitive == primitive
                && (primitive == .tap || definition.direction == direction)
        }
        return isDefined ? gesture : nil
    }

    private static func gestureType(fingerCount: Int, primitive: GesturePrimitive, direction: GestureDirection?) -> GestureType? {
        switch (fingerCount, primitive, direction) {
        case (2, .swipe, .some(.left)): return .twoFingerSwipeLeft
        case (2, .swipe, .some(.right)): return .twoFingerSwipeRight
        case (3, .tap, _): return .threeFingerTap
        case (3, .swipe, .some(.left)): return .threeFingerSwipeLeft
        case (3, .swipe, .some(.right)): return .threeFingerSwipeRight
        case (4, .tap, _): return .fourFingerTap
        case (4, .swipe, .some(.left)): return .fourFingerSwipeLeft
        case (4, .swipe, .some(.right)): return .fourFingerSwipeRight
        default: return nil
        }
    }

    private func rejected(_ session: Session, endedAt: TimeInterval) -> RecognizedGesture {
        let duration = endedAt - session.startedAt
        let dx = session.latestCentroid.x - session.startCentroid.x
        let dy = session.latestCentroid.y - session.startCentroid.y
        return RecognizedGesture(
            gesture: nil,
            status: .gestureUnstable,
            reason: .unknown,
            durationMs: Int((duration * 1000).rounded()),
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
