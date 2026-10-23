import XCTest
import GestureKitCore
@testable import GestureKitApp

@MainActor
final class RuntimeDragShieldTests: XCTestCase {
    private func runtime(chrome: Bool = true) -> (GestureKitRuntime, RecordingDragShield, UserDefaultsSettingsStore) {
        let defaults = UserDefaults(suiteName: "drag-shield-\(UUID().uuidString)")!
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let shield = RecordingDragShield()
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in }, settingsStore: store,
            logger: GestureKitLogger(terminalWriter: { _ in }),
            appContextResolver: AppContextResolver(bundleIdProvider: { chrome ? "com.google.Chrome" : "com.apple.finder" }),
            dragInputShield: shield
        )
        return (runtime, shield, store)
    }

    func testSwipeArmsWithoutLinkBindingAndKeepsProtectionUntilAllFingersLift() throws {
        let (runtime, shield, _) = runtime()
        try runtime.updateBinding(id: "link-open-adjacent", enabled: false)
        _ = runtime.processFrameForTesting(frame(0, 3))
        XCTAssertEqual(shield.armed.count, 1)
        let id = shield.armed[0]
        _ = runtime.processFrameForTesting(frame(0.1, 3, x: 0.7))
        _ = runtime.processFrameForTesting(frame(0.15, 2, x: 0.7))
        XCTAssertEqual(shield.finished, [])
        _ = runtime.processFrameForTesting(frame(0.2, 0))
        XCTAssertEqual(shield.finished, [id])
    }

    func testDisabledSwipesAndNonChromeNeverArm() throws {
        let (runtime, shield, _) = runtime()
        try runtime.updateBinding(id: "swipe-left-next-tab", enabled: false)
        try runtime.updateBinding(id: "swipe-right-previous-tab", enabled: false)
        _ = runtime.processFrameForTesting(frame(0, 3))
        XCTAssertTrue(shield.armed.isEmpty)
        let (other, otherShield, _) = self.runtime(chrome: false)
        _ = other.processFrameForTesting(frame(0, 3))
        XCTAssertTrue(otherShield.armed.isEmpty)
    }

    func testPauseCancelsCandidateAndRequiresLiftBeforeNextOperation() {
        let (runtime, shield, _) = runtime()
        _ = runtime.processFrameForTesting(frame(0, 3))
        runtime.pause()
        runtime.resume()
        _ = runtime.processFrameForTesting(frame(0.1, 3, x: 0.7))
        XCTAssertEqual(shield.armed.count, 1)
        _ = runtime.processFrameForTesting(frame(0.2, 0))
        _ = runtime.processFrameForTesting(frame(0.3, 3))
        XCTAssertEqual(shield.armed.count, 2)
        XCTAssertTrue(shield.cancelled.contains("paused"))
    }

    func testConfigurationChangeCancelsAndDoesNotReenterSamePhysicalOperation() throws {
        let (runtime, shield, _) = runtime()
        _ = runtime.processFrameForTesting(frame(0, 3))
        try runtime.updateSensitivity(.sensitive)
        _ = runtime.processFrameForTesting(frame(0.1, 3))
        XCTAssertEqual(shield.armed.count, 1)
        _ = runtime.processFrameForTesting(frame(0.2, 0))
        _ = runtime.processFrameForTesting(frame(0.3, 3))
        XCTAssertEqual(shield.armed.count, 2)
        XCTAssertTrue(shield.cancelled.contains("configuration_changed"))
    }

    func testHigherUnsupportedFingerCountFinishesGuardAndCannotReenterUntilLift() {
        let (runtime, shield, _) = runtime()
        _ = runtime.processFrameForTesting(frame(0, 3))
        let id = shield.armed[0]
        _ = runtime.processFrameForTesting(frame(0.1, 5))
        XCTAssertEqual(shield.finished, [id])
        _ = runtime.processFrameForTesting(frame(0.2, 3))
        XCTAssertEqual(shield.armed.count, 1)
        _ = runtime.processFrameForTesting(frame(0.3, 0))
        _ = runtime.processFrameForTesting(frame(0.4, 3))
        XCTAssertEqual(shield.armed.count, 2)
    }

    func testStopClearsShieldEvenBeforeRuntimeStart() {
        let (runtime, shield, _) = runtime()
        _ = runtime.processFrameForTesting(frame(0, 3))
        runtime.stop()
        XCTAssertEqual(shield.stops, 1)
    }

    private func frame(_ time: Double, _ count: Int, x: Float = 0.4) -> TouchFrame {
        TouchFrame(time: time, activeTouches: (0..<count).map { TouchSample(id: Int32($0), x: x, y: 0.4) })
    }
}

@MainActor
private final class RecordingDragShield: DragInputShield {
    var armed: [String] = []
    var finished: [String] = []
    var cancelled: [String] = []
    var stops = 0
    func start() {}
    func arm(sessionID: String) { armed.append(sessionID) }
    func finish(sessionID: String) { finished.append(sessionID) }
    func cancel(reason: String) { cancelled.append(reason) }
    func stop() { stops += 1 }
}
