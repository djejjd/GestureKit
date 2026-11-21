import Foundation
import GestureKitCore
import XCTest
@testable import GestureKitApp

/// 系统三指拖移与 GestureKit 三指滑动共用输入时的兼容性回归。
@MainActor
final class ThreeFingerInteractionCompatibilityTests: XCTestCase {
    private struct Harness {
        let runtime: GestureKitRuntime
        let shield: ThreeFingerRecordingShield
        let outbound: ThreeFingerOutboundRecorder
        let credentialDirectory: URL
        let defaultsSuite: String
    }

    func testSystemThreeFingerDragRemovesDragSelectionFromNativeAndPageGuards() throws {
        let harness = try makeHarness(systemThreeFingerDragEnabled: true)
        defer { cleanup(harness) }

        _ = harness.runtime.processFrameForTesting(frame(0, 3, x: 0.4))

        XCTAssertTrue(harness.shield.armed.isEmpty, "系统三指拖移开启时不得武装三指原生拖移护盾")
        let payload = try guardArmPayload(from: harness.outbound)
        XCTAssertFalse(payload.features.contains("drag_selection"))
        XCTAssertTrue(payload.features.contains("link_click"), "点按链接保护应继续兼容")
    }

    func testSystemThreeFingerDragOffPreservesExistingThreeFingerShield() throws {
        let harness = try makeHarness(systemThreeFingerDragEnabled: false)
        defer { cleanup(harness) }

        _ = harness.runtime.processFrameForTesting(frame(0, 3, x: 0.4))

        XCTAssertEqual(harness.shield.armed.count, 1)
        let payload = try guardArmPayload(from: harness.outbound)
        XCTAssertTrue(payload.features.contains("drag_selection"))
    }

    func testSystemThreeFingerDragDoesNotDisableFourFingerDragProtection() throws {
        let harness = try makeHarness(systemThreeFingerDragEnabled: true)
        defer { cleanup(harness) }
        try harness.runtime.updateGestureBinding(
            gestureDefinitionID: "four-finger-swipe-left",
            actionID: .browserTabActivateNext,
            enabled: true
        )

        _ = harness.runtime.processFrameForTesting(frame(0, 4, x: 0.4))

        XCTAssertEqual(harness.shield.armed.count, 1)
        let payload = try guardArmPayload(from: harness.outbound)
        XCTAssertTrue(payload.features.contains("drag_selection"))
    }

    func testSlowThreeFingerDragSelectionDoesNotDispatchSwipeAction() throws {
        let harness = try makeHarness(systemThreeFingerDragEnabled: true)
        defer { cleanup(harness) }

        _ = harness.runtime.processFrameForTesting(frame(0.0, 3, x: 0.30))
        _ = harness.runtime.processFrameForTesting(frame(0.2, 3, x: 0.40))
        _ = harness.runtime.processFrameForTesting(frame(0.8, 3, x: 0.50))
        let event = harness.runtime.processFrameForTesting(frame(0.9, 0))

        XCTAssertNil(event?.gesture)
        XCTAssertNil(harness.outbound.latest(of: .contextRequest))
        XCTAssertNil(harness.outbound.latest(of: .actionRequest))
    }

    /// 预览策略：系统三指拖移开启时，无 DOM 证据的三指横向滑动无法与拖选可靠区分，
    /// 因此保留识别结果但不进入 context/action，避免切换标签页。
    func testFastHorizontalThreeFingerSwipeIsSuppressedWhenSystemDragEnabled() throws {
        let harness = try makeHarness(systemThreeFingerDragEnabled: true)
        defer { cleanup(harness) }

        _ = harness.runtime.processFrameForTesting(frame(0.0, 3, x: 0.30))
        _ = harness.runtime.processFrameForTesting(frame(0.16, 3, x: 0.44))
        let event = harness.runtime.processFrameForTesting(frame(0.26, 0))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
        XCTAssertNil(harness.outbound.latest(of: .contextRequest))
        XCTAssertNil(harness.outbound.latest(of: .actionRequest))
        let discarded = harness.outbound.all(of: .interactionGuardRelease).contains { envelope in
            guard case .interactionGuardRelease(let payload) = envelope.payload else { return false }
            return payload.disposition == .discard
        }
        XCTAssertTrue(discarded, "被抑制的三指 swipe 必须以 discard 终态释放页面 guard")
    }

    func testSystemDragOffStillDispatchesFastThreeFingerSwipe() throws {
        let harness = try makeHarness(systemThreeFingerDragEnabled: false)
        defer { cleanup(harness) }

        _ = harness.runtime.processFrameForTesting(frame(0.0, 3, x: 0.30))
        _ = harness.runtime.processFrameForTesting(frame(0.16, 3, x: 0.44))
        let event = harness.runtime.processFrameForTesting(frame(0.26, 0))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
        XCTAssertNotNil(harness.outbound.latest(of: .contextRequest))
    }

    func testSystemDragDoesNotSuppressThreeFingerTap() throws {
        let harness = try makeHarness(systemThreeFingerDragEnabled: true)
        defer { cleanup(harness) }

        _ = harness.runtime.processFrameForTesting(frame(0.0, 3, x: 0.40))
        let event = harness.runtime.processFrameForTesting(frame(0.45, 0))

        XCTAssertEqual(event?.gesture, .threeFingerTap)
        XCTAssertNotNil(harness.outbound.latest(of: .contextRequest))
    }

    func testSystemDragDoesNotSuppressFourFingerSwipe() throws {
        let harness = try makeHarness(systemThreeFingerDragEnabled: true)
        defer { cleanup(harness) }
        try harness.runtime.updateGestureBinding(
            gestureDefinitionID: "four-finger-swipe-right",
            actionID: .browserTabActivateNext,
            enabled: true
        )

        _ = harness.runtime.processFrameForTesting(frame(0.0, 4, x: 0.30))
        _ = harness.runtime.processFrameForTesting(frame(0.16, 4, x: 0.44))
        let event = harness.runtime.processFrameForTesting(frame(0.26, 0))

        XCTAssertEqual(event?.gesture, .fourFingerSwipeRight)
        XCTAssertNotNil(harness.outbound.latest(of: .contextRequest))
    }

    private func makeHarness(systemThreeFingerDragEnabled: Bool) throws -> Harness {
        let credentialDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreeFingerInteraction-\(UUID().uuidString)")
        let credentials = ProviderCredentialStore(directory: credentialDirectory)
        let sessions = ProviderSessionRegistry(credentialStore: credentials)
        let outbound = ThreeFingerOutboundRecorder()
        let connectionID = UUID()
        let installID = "three-finger-interaction-test"
        let hello = ProviderHelloPayload(installId: installID, protocolVersions: [2], environment: "test")
        let nonce = try sessions.beginAuthentication(hello)
        let response = ProviderAuthenticator(secret: try credentials.secret(for: installID))
            .response(for: installID, nonce: nonce)
        _ = try sessions.authenticate(
            installId: installID,
            response: response,
            connectionID: connectionID,
            sink: { outbound.append($0) }
        )

        let defaultsSuite = "three-finger-interaction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        let shield = ThreeFingerRecordingShield()
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            settingsStore: UserDefaultsSettingsStore(defaults: defaults),
            logger: GestureKitLogger(terminalWriter: { _ in }),
            providerSessions: sessions,
            appContextResolver: AppContextResolver(bundleIdProvider: { "com.google.Chrome" }),
            providerOutboundSink: { outbound.append($0) },
            dragInputShield: shield,
            threeFingerDragEnabled: { systemThreeFingerDragEnabled }
        )
        return Harness(
            runtime: runtime,
            shield: shield,
            outbound: outbound,
            credentialDirectory: credentialDirectory,
            defaultsSuite: defaultsSuite
        )
    }

    private func guardArmPayload(from outbound: ThreeFingerOutboundRecorder) throws -> InteractionGuardPayload {
        let envelope = try XCTUnwrap(outbound.latest(of: .interactionGuardArm))
        guard case .interactionGuardArm(let payload) = envelope.payload else {
            throw TestFailure("missing interaction guard payload")
        }
        return payload
    }

    private func frame(_ time: Double, _ count: Int, x: Float = 0.4) -> TouchFrame {
        TouchFrame(
            time: time,
            activeTouches: (0..<count).map { TouchSample(id: Int32($0), x: x, y: 0.4) }
        )
    }

    private func cleanup(_ harness: Harness) {
        UserDefaults(suiteName: harness.defaultsSuite)?
            .removePersistentDomain(forName: harness.defaultsSuite)
        try? FileManager.default.removeItem(at: harness.credentialDirectory)
    }
}

private struct TestFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

@MainActor
private final class ThreeFingerRecordingShield: DragInputShield {
    var armed: [String] = []
    func start() {}
    func arm(sessionID: String) { armed.append(sessionID) }
    func finish(sessionID: String) {}
    func cancel(reason: String) {}
    func stop() {}
}

private final class ThreeFingerOutboundRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProviderEnvelope] = []

    func append(_ envelope: ProviderEnvelope) {
        lock.lock()
        values.append(envelope)
        lock.unlock()
    }

    func latest(of type: ProviderMessageType) -> ProviderEnvelope? {
        lock.lock()
        defer { lock.unlock() }
        return values.last { $0.type == type }
    }

    func all(of type: ProviderMessageType) -> [ProviderEnvelope] {
        lock.lock()
        defer { lock.unlock() }
        return values.filter { $0.type == type }
    }
}
