import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

@MainActor
final class RuntimeSettingsTests: XCTestCase {
    func testSettingsUpdateAppliesSwipeSensitivityToRecognizer() {
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
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

    func testStartupLoadsPersistedRecognitionSettings() throws {
        let defaults = UserDefaults(suiteName: "GestureKitTests.runtimeStartupRecognition")!
        defaults.removePersistentDomain(forName: "GestureKitTests.runtimeStartupRecognition")
        let store = UserDefaultsSettingsStore(defaults: defaults)
        try store.saveAppConfiguration(.init(
            storeEpoch: "runtime-startup",
            schemaVersion: 3,
            configurationVersion: 1,
            rules: DefaultRules.v1Bindings,
            recognition: .sensitive
        ))
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: StubTouchBackend(),
            settingsStore: store,
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        _ = runtime.observeForTesting(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = runtime.observeForTesting(.frame(time: 0.16, activeTouches: [.touch(1, 0.38, 0.40), .touch(2, 0.40, 0.40), .touch(3, 0.42, 0.40)]))

        XCTAssertEqual(runtime.observeForTesting(.frame(time: 0.26, activeTouches: []))?.gesture, .threeFingerSwipeRight)
    }

    func testApplyingConfigurationUpdatesRecognizerImmediately() {
        let runtime = GestureKitRuntime(menuBarHandler: { _ in }, touchBackend: StubTouchBackend(), settingsStore: StubSettingsStore(), logger: GestureKitLogger(terminalWriter: { _ in }))
        runtime.apply(configuration: .init(storeEpoch: "runtime-apply", schemaVersion: 3, configurationVersion: 2, rules: DefaultRules.v1Bindings, recognition: .sensitive))

        _ = runtime.observeForTesting(.frame(time: 0, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = runtime.observeForTesting(.frame(time: 0.16, activeTouches: [.touch(1, 0.38, 0.40), .touch(2, 0.40, 0.40), .touch(3, 0.42, 0.40)]))

        XCTAssertEqual(runtime.observeForTesting(.frame(time: 0.26, activeTouches: []))?.gesture, .threeFingerSwipeRight)
    }

    func testSettingsAckIncludesCurrentRuntimeSession() {
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
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

        XCTAssertEqual(ack.appSessionId.count > 0, true)
        XCTAssertEqual(ack.recognitionSettings.swipeSensitivity, .sensitive)
    }

    func testLegacySettingsUpdateIsRejectedAfterMigrationMarker() throws {
        let defaults = UserDefaults(suiteName: "GestureKitTests.runtimeLegacySettings")!
        defaults.removePersistentDomain(forName: "GestureKitTests.runtimeLegacySettings")
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: StubTouchBackend(),
            settingsStore: UserDefaultsSettingsStore(defaults: defaults),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )
        let payload = SettingsUpdatePayload(
            swipeSensitivity: .sensitive,
            swipeMinDistance: 0.075,
            swipeHorizontalRatio: 1.25,
            swipeMinDurationMs: 50,
            swipeMaxDurationMs: 480
        )

        XCTAssertTrue(runtime.applyLegacySettingsUpdateForTesting(payload).applied)
        XCTAssertFalse(runtime.applyLegacySettingsUpdateForTesting(payload).applied)
    }

    func testProviderSnapshotComesFromPersistedAppAuthority() throws {
        let defaults = UserDefaults(suiteName: "GestureKitTests.runtimeProviderConfiguration")!
        defaults.removePersistentDomain(forName: "GestureKitTests.runtimeProviderConfiguration")
        UserDefaults.standard.set(true, forKey: GestureKitLogger.diagnosticLoggingDefaultsKey)
        defer {
            UserDefaults.standard.removeObject(forKey: GestureKitLogger.diagnosticLoggingDefaultsKey)
        }
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: StubTouchBackend(),
            settingsStore: UserDefaultsSettingsStore(defaults: defaults),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        let snapshot = try runtime.configurationSnapshotForProviderForTesting()
        let persisted = try XCTUnwrap(UserDefaultsSettingsStore(defaults: defaults).loadAppConfiguration())

        XCTAssertEqual(snapshot.storeEpoch, persisted.storeEpoch)
        XCTAssertEqual(snapshot.configurationVersion, persisted.configurationVersion)
        XCTAssertTrue(snapshot.diagnosticLoggingEnabled)
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: Data(snapshot.configJSON.utf8)), persisted)
    }

    func testProbeResponseIncludesAppSessionId() {
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: StubTouchBackend(),
            settingsStore: StubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        let message = runtime.handleProbeRequestForTesting(id: "probe-1")

        XCTAssertEqual(message.type, .probeResponse)
        XCTAssertNotNil(message.probeResponsePayload?.appSessionId)
        XCTAssertEqual((message.probeResponsePayload?.appSessionId?.count ?? 0) > 0, true)
    }

    func testUnstableSwipeDoesNotPublishDiagnosticEvent() {
        var diagnostics: [LocalIPCEnvelope] = []
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: StubTouchBackend(),
            settingsStore: StubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in }),
            diagnosticSink: { diagnostics.append($0) }
        )

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

        XCTAssertEqual(diagnostics.count, 0)
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
