import Dispatch
import Foundation
import OpenMultitouchSupport

private enum GestureCandidate: String {
    case tap = "three_finger_tap"
    case swipeLeft = "three_finger_swipe_left"
    case swipeRight = "three_finger_swipe_right"
}

private struct Centroid {
    let x: Float
    let y: Float
}

private struct ThreeFingerSession {
    let startedAt: Date
    let startCentroid: Centroid
    var latestCentroid: Centroid
    var maxFingerCount: Int
}

private struct CandidateCounts {
    private(set) var tap = 0
    private(set) var swipeLeft = 0
    private(set) var swipeRight = 0
    private(set) var unclear = 0

    mutating func record(_ candidate: GestureCandidate) {
        switch candidate {
        case .tap:
            tap += 1
        case .swipeLeft:
            swipeLeft += 1
        case .swipeRight:
            swipeRight += 1
        }
    }

    mutating func recordUnclear() {
        unclear += 1
    }

    var summary: String {
        "counts tap=\(tap) left=\(swipeLeft) right=\(swipeRight) unclear=\(unclear)"
    }
}

private final class InterruptSignal {
    private let source: DispatchSourceSignal
    private var continuation: CheckedContinuation<Void, Never>?

    init() {
        signal(SIGINT, SIG_IGN)
        source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            source.setEventHandler { [weak self] in
                guard let self else { return }
                source.cancel()
                self.continuation?.resume()
                self.continuation = nil
            }
            source.resume()
        }
    }
}

private final class ObservationState {
    private var lastPrintedFingerCount: Int?
    private var lastSummaryAt = Date.distantPast
    private var threeFingerSession: ThreeFingerSession?
    private var candidateCounts = CandidateCounts()

    func observe(_ touches: [OMSTouchData]) {
        let activeTouches = Self.activeTouches(from: touches)
        let fingerCount = activeTouches.count
        let centroid = Self.centroid(of: activeTouches)

        if shouldPrintSummary(fingerCount: fingerCount) {
            printSummary(fingerCount: fingerCount, centroid: centroid, touches: activeTouches)
        }

        updateThreeFingerSession(fingerCount: fingerCount, centroid: centroid)
    }

    private func shouldPrintSummary(fingerCount: Int) -> Bool {
        let now = Date()
        let countChanged = lastPrintedFingerCount != fingerCount
        let periodicThreeFingerUpdate = fingerCount == 3 && now.timeIntervalSince(lastSummaryAt) >= 0.25

        if countChanged || periodicThreeFingerUpdate {
            lastPrintedFingerCount = fingerCount
            lastSummaryAt = now
            return true
        }
        return false
    }

    private func updateThreeFingerSession(fingerCount: Int, centroid: Centroid?) {
        if fingerCount == 3, let centroid {
            if var session = threeFingerSession {
                session.latestCentroid = centroid
                session.maxFingerCount = max(session.maxFingerCount, fingerCount)
                threeFingerSession = session
            } else {
                threeFingerSession = ThreeFingerSession(
                    startedAt: Date(),
                    startCentroid: centroid,
                    latestCentroid: centroid,
                    maxFingerCount: fingerCount
                )
                print(String(format: "[candidate:start] fingers=3 centroid=(%.3f, %.3f)", centroid.x, centroid.y))
            }
            return
        }

        guard let session = threeFingerSession else { return }
        threeFingerSession = nil
        classify(session)
    }

    private func classify(_ session: ThreeFingerSession) {
        let duration = Date().timeIntervalSince(session.startedAt)
        let dx = session.latestCentroid.x - session.startCentroid.x
        let dy = session.latestCentroid.y - session.startCentroid.y
        let distance = hypotf(dx, dy)
        let horizontalEnough = abs(dx) >= 0.12 && abs(dx) > abs(dy) * 1.2

        if duration <= 0.45 && distance <= 0.06 {
            printCandidate(.tap, duration: duration, dx: dx, dy: dy, distance: distance)
        } else if horizontalEnough {
            printCandidate(dx < 0 ? .swipeLeft : .swipeRight, duration: duration, dx: dx, dy: dy, distance: distance)
        } else {
            candidateCounts.recordUnclear()
            let line = String(
                format: "[candidate:unclear] fingers=3 duration_ms=%.0f dx=%.3f dy=%.3f distance=%.3f",
                duration * 1000,
                dx,
                dy,
                distance
            )
            print("\(line) [\(candidateCounts.summary)]")
        }
    }

    private func printCandidate(
        _ candidate: GestureCandidate,
        duration: TimeInterval,
        dx: Float,
        dy: Float,
        distance: Float
    ) {
        candidateCounts.record(candidate)
        let line = String(
            format: "[candidate:%@] duration_ms=%.0f dx=%.3f dy=%.3f distance=%.3f",
            candidate.rawValue,
            duration * 1000,
            dx,
            dy,
            distance
        )
        print("\(line) [\(candidateCounts.summary)]")
    }

    private func printSummary(fingerCount: Int, centroid: Centroid?, touches: [OMSTouchData]) {
        let centroidText: String
        if let centroid {
            centroidText = String(format: "(%.3f, %.3f)", centroid.x, centroid.y)
        } else {
            centroidText = "none"
        }

        let states = touches.map(\.state.rawValue).joined(separator: ",")
        print("[event] normalized_finger_count=\(fingerCount) centroid=\(centroidText) states=[\(states)]")
    }

    private static func activeTouches(from touches: [OMSTouchData]) -> [OMSTouchData] {
        touches.filter { touch in
            switch touch.state {
            case .starting, .making, .touching, .breaking:
                return true
            case .notTouching, .hovering, .lingering, .leaving:
                return false
            }
        }
    }

    private static func centroid(of touches: [OMSTouchData]) -> Centroid? {
        guard !touches.isEmpty else { return nil }
        let total = touches.reduce((x: Float(0), y: Float(0))) { partial, touch in
            (partial.x + touch.position.x, partial.y + touch.position.y)
        }
        let count = Float(touches.count)
        return Centroid(x: total.x / count, y: total.y / count)
    }
}

@main
struct TrackpadInputProbe {
    static func main() async {
        let manager = OMSManager.shared
        let state = ObservationState()
        let interruptSignal = InterruptSignal()

        print("TrackpadInputProbe")
        print("backend=OpenMultitouchSupport module=OpenMultitouchSupport product=OpenMultitouchSupport")
        print("privacy=no raw input is written to disk")

        let observationTask = Task {
            for await touchData in manager.touchDataStream {
                state.observe(touchData)
            }
        }

        guard manager.startListening() else {
            observationTask.cancel()
            print("backend_unavailable: OpenMultitouchSupport could not start listening on the default multitouch device.")
            print("Check macOS version, sandbox state, and whether this Mac has an available trackpad.")
            Foundation.exit(2)
        }

        print("device_status=default_multitouch_listener_started is_listening=\(manager.isListening)")
        print("manual_check=perform three-finger tap, three-finger left swipe, and three-finger right swipe.")
        print("Press Ctrl-C to stop.")

        await interruptSignal.wait()

        let stopped = manager.stopListening()
        observationTask.cancel()
        print("device_status=listener_stopped stopped=\(stopped)")
    }
}
