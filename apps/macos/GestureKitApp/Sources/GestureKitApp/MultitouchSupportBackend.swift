import Foundation
import GestureKitCore
import OpenMultitouchSupport

final class MultitouchSupportBackend: TouchBackend {
    var frames: AsyncStream<TouchFrame> {
        AsyncStream { continuation in
            let task = Task {
                for await touchData in OMSManager.shared.touchDataStream {
                    let frame = TouchFrame(
                        time: Date().timeIntervalSince1970,
                        activeTouches: touchData.compactMap(Self.touchSample)
                    )
                    continuation.yield(frame)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func start() -> Bool {
        OMSManager.shared.startListening()
    }

    func stop() -> Bool {
        OMSManager.shared.stopListening()
    }

    private static func touchSample(_ touch: OMSTouchData) -> TouchSample? {
        switch touch.state {
        case .starting, .making, .touching, .breaking:
            return TouchSample(id: touch.id, x: touch.position.x, y: touch.position.y)
        case .notTouching, .hovering, .lingering, .leaving:
            return nil
        }
    }
}
