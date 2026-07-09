import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

@MainActor
final class RuntimeLifecycleTests: XCTestCase {
    func testRuntimePublishesListeningAndStoppedStates() {
        var statuses: [AppRuntimeStatus] = []
        let runtime = GestureKitRuntime(
            statusHandler: { statuses.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.start()
        runtime.stop()

        XCTAssertEqual(statuses.first?.listeningState, .listening)
        XCTAssertEqual(statuses.last?.listeningState, .stopped)
    }

    func testRuntimePublishesConnectionStateWhenDisconnected() {
        var statuses: [AppRuntimeStatus] = []
        let runtime = GestureKitRuntime(
            statusHandler: { statuses.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.start()
        runtime.stop()

        XCTAssertEqual(statuses.last?.connectionState, .disconnected)
    }

    func testRuntimePublishesLogFilePathHint() {
        var statuses: [AppRuntimeStatus] = []
        let runtime = GestureKitRuntime(
            statusHandler: { statuses.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.start()

        XCTAssertTrue(statuses.first?.logFilePathHint.contains("GestureKitApp.log") ?? false)
    }

    func testRuntimeInitialStatusIsStarting() {
        var statuses: [AppRuntimeStatus] = []
        let runtime = GestureKitRuntime(
            statusHandler: { statuses.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.start()

        XCTAssertEqual(statuses.first?.listeningState, .listening)
    }

    func testRefreshStatusPublishesDisconnectedWhenNoClientsConnected() {
        var statuses: [AppRuntimeStatus] = []
        let runtime = GestureKitRuntime(
            statusHandler: { statuses.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.refreshStatus()

        XCTAssertEqual(statuses.last?.connectionState, .disconnected)
    }

    func testStartIsIdempotent() {
        var statuses: [AppRuntimeStatus] = []
        let runtime = GestureKitRuntime(
            statusHandler: { statuses.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.start()
        let countAfterFirst = statuses.count
        runtime.start()
        let countAfterSecond = statuses.count

        // second start should not crash and should still report listening
        XCTAssertEqual(countAfterSecond, countAfterFirst)
        XCTAssertEqual(statuses.last?.listeningState, .listening)
    }

    func testStopIsIdempotent() {
        var statuses: [AppRuntimeStatus] = []
        let runtime = GestureKitRuntime(
            statusHandler: { statuses.append($0) },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in })
        )

        runtime.start()
        runtime.stop()
        let countAfterFirstStop = statuses.count
        runtime.stop()
        let countAfterSecondStop = statuses.count

        // second stop should not crash and should still report stopped
        XCTAssertEqual(countAfterSecondStop, countAfterFirstStop)
        XCTAssertEqual(statuses.last?.listeningState, .stopped)
    }
}

private final class LifecycleStubTouchBackend: TouchBackend {
    let frames = AsyncStream<TouchFrame> { continuation in
        continuation.finish()
    }

    func start() -> Bool { true }
    func stop() -> Bool { true }
}

private struct LifecycleStubSettingsStore: SettingsStore {
    func loadRules() throws -> [Rule] {
        DefaultRules.v1
    }

    func saveRules(_ rules: [Rule]) throws {}
}
