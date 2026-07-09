import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

@MainActor
final class RuntimeLifecycleTests: XCTestCase {
    func testStartEmitsAppStartedLog() {
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )
        runtime.start()
        // Should not crash; gesture emission tested via processFrameForTesting
    }

    func testPauseStopsGestureProcessing() {
        var events: [AppMenuBarEvent] = []
        let runtime = GestureKitRuntime(
            menuBarHandler: { events.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.pause()

        XCTAssertEqual(events.last?.type, .paused)
        XCTAssertTrue(runtime.isCurrentlyPaused)
    }

    func testResumeRestoresGestureProcessing() {
        var events: [AppMenuBarEvent] = []
        let runtime = GestureKitRuntime(
            menuBarHandler: { events.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.pause()
        runtime.resume()

        XCTAssertEqual(events.last?.type, .resumed)
        XCTAssertFalse(runtime.isCurrentlyPaused)
    }

    func testRecognizedGestureEmitsEvent() {
        var events: [AppMenuBarEvent] = []
        let runtime = GestureKitRuntime(
            menuBarHandler: { events.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        // Use larger dx to trigger gesture recognition with default standard settings
        _ = runtime.processFrameForTesting(.frame(time: 0.00, activeTouches: [
            .touch(1, 0.30, 0.40),
            .touch(2, 0.32, 0.40),
            .touch(3, 0.34, 0.40)
        ]))
        _ = runtime.processFrameForTesting(.frame(time: 0.16, activeTouches: [
            .touch(1, 0.42, 0.40),
            .touch(2, 0.44, 0.40),
            .touch(3, 0.46, 0.40)
        ]))
        let event = runtime.processFrameForTesting(.frame(time: 0.26, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
        let recognized = events.first { e in
            if case .gestureRecognized = e.type { return true }
            return false
        }
        XCTAssertNotNil(recognized)
    }

    func testUnstableGestureEmitsWarningEvent() {
        var events: [AppMenuBarEvent] = []
        let runtime = GestureKitRuntime(
            menuBarHandler: { events.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.start()
        _ = runtime.processFrameForTesting(.frame(time: 0.00, activeTouches: [
            .touch(1, 0.30, 0.40),
            .touch(2, 0.32, 0.40),
            .touch(3, 0.34, 0.40)
        ]))
        _ = runtime.processFrameForTesting(.frame(time: 0.16, activeTouches: [
            .touch(1, 0.37, 0.40),
            .touch(2, 0.39, 0.40),
            .touch(3, 0.41, 0.40)
        ]))
        _ = runtime.processFrameForTesting(.frame(time: 0.26, activeTouches: []))

        let warning = events.first { e in
            if case .gestureWarning = e.type { return true }
            return false
        }
        XCTAssertNotNil(warning)
    }

    func testPausedRuntimeDoesNotProcessFrames() {
        var events: [AppMenuBarEvent] = []
        let runtime = GestureKitRuntime(
            menuBarHandler: { events.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.start()
        runtime.pause()
        // Clear events from startup and pause
        events.removeAll()

        _ = runtime.processFrameForTesting(.frame(time: 0.00, activeTouches: [
            .touch(1, 0.30, 0.40),
            .touch(2, 0.32, 0.40),
            .touch(3, 0.34, 0.40)
        ]))
        _ = runtime.processFrameForTesting(.frame(time: 0.16, activeTouches: [
            .touch(1, 0.38, 0.40),
            .touch(2, 0.40, 0.40),
            .touch(3, 0.42, 0.40)
        ]))
        _ = runtime.processFrameForTesting(.frame(time: 0.26, activeTouches: []))

        // No gesture events while paused
        XCTAssertTrue(events.isEmpty)
    }
}

private final class LifecycleStubTouchBackend: TouchBackend {
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

private struct LifecycleStubSettingsStore: SettingsStore {
    func loadRules() throws -> [Rule] { DefaultRules.v1 }
    func saveRules(_ rules: [Rule]) throws {}
}
