import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

@MainActor
final class RuntimeSettingsTests: XCTestCase {
    func testSettingsUpdateAppliesSwipeSensitivityToRecognizer() {
        let runtime = GestureKitRuntime(
            statusHandler: { _ in },
            touchBackend: StubTouchBackend(),
            settingsStore: StubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        let ack = runtime.applySettingsUpdate(SettingsUpdatePayload(
            swipeSensitivity: .sensitive,
            swipeMinDistance: 0.075,
            swipeHorizontalRatio: 1.25,
            swipeMinDurationMs: 50,
            swipeMaxDurationMs: 480
        ))
        _ = runtime.observeForTesting(.frame(time: 0.00, activeTouches: [
            .touch(1, 0.30, 0.40),
            .touch(2, 0.32, 0.40),
            .touch(3, 0.34, 0.40)
        ]))
        _ = runtime.observeForTesting(.frame(time: 0.16, activeTouches: [
            .touch(1, 0.38, 0.40),
            .touch(2, 0.40, 0.40),
            .touch(3, 0.42, 0.40)
        ]))
        let event = runtime.observeForTesting(.frame(time: 0.26, activeTouches: []))

        XCTAssertTrue(ack.applied)
        XCTAssertEqual(ack.swipeSensitivity, .sensitive)
        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
    }
}

private final class StubTouchBackend: TouchBackend {
    let frames = AsyncStream<TouchFrame> { continuation in
        continuation.finish()
    }

    func start() -> Bool { true }
    func stop() -> Bool { true }
}

private extension TouchSample {
    static func touch(_ id: Int32, _ x: Float, _ y: Float) -> TouchSample {
        TouchSample(id: id, x: x, y: y)
    }
}

private struct StubSettingsStore: SettingsStore {
    func loadRules() throws -> [Rule] {
        DefaultRules.v1
    }

    func saveRules(_ rules: [Rule]) throws {}
}
