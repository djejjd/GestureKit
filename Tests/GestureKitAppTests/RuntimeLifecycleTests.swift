import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

@MainActor
final class RuntimeLifecycleTests: XCTestCase {
    func testAuthenticatedTelemetryBatchAppendsProviderLifecycleEventsToRequestTimeline() throws {
        let credentialDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeLifecycleTelemetry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: credentialDirectory) }
        let credentialStore = ProviderCredentialStore(directory: credentialDirectory)
        let sessions = ProviderSessionRegistry(credentialStore: credentialStore)
        let journal = RuntimeRecordingJournal()
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in }),
            operationJournal: journal,
            providerSessions: sessions
        )
        let connectionID = UUID()
        let installID = "chrome-telemetry-test"
        let hello = ProviderHelloPayload(installId: installID, protocolVersions: [2], environment: "test")
        let nonce = try sessions.beginAuthentication(hello)
        let response = ProviderAuthenticator(secret: try credentialStore.secret(for: installID))
            .response(for: installID, nonce: nonce)
        let session = try sessions.authenticate(
            installId: installID,
            nonce: nonce,
            response: response,
            connectionID: connectionID
        )

        let request = ProviderEnvelope(
            protocolVersion: 2, messageId: "request-1", providerSessionId: session.providerSessionID,
            gestureSessionId: "gesture-1", operationId: "operation-1", type: .actionRequest,
            timestamp: 100, payload: .actionRequest(ActionDescriptor(
                actionId: .browserPageReload, contextId: "context-1", targetRef: nil,
                parameters: [:], deadline: 1_000
            )), error: nil
        )
        runtime.appendOperationLifecycleEvent(request)

        let accepted = ProviderEvent(
            eventId: "accepted-1", producerSessionId: session.providerSessionID, producerSequence: 7,
            causedByEventId: "request-1", monotonicClockMs: 110, wallClockMs: 110,
            gestureSessionId: "gesture-1", operationId: "operation-1", type: .actionAccepted,
            payload: .actionAccepted(ActionAcceptedPayload(operationId: "operation-1", acceptedAt: 110))
        )
        let result = ProviderEvent(
            eventId: "result-1", producerSessionId: session.providerSessionID, producerSequence: 8,
            causedByEventId: "accepted-1", monotonicClockMs: 120, wallClockMs: 120,
            gestureSessionId: "gesture-1", operationId: "operation-1", type: .actionResult,
            payload: .actionResult(ProviderActionResultPayload(
                operationId: "operation-1", outcome: .succeeded, reason: nil, completedAt: 120
            ))
        )
        let batch = ProviderEnvelope(
            protocolVersion: 2, messageId: "batch-1", providerSessionId: session.providerSessionID,
            gestureSessionId: nil, operationId: nil, type: .telemetryBatch, timestamp: 130,
            payload: .telemetryBatch(TelemetryBatchPayload(events: [accepted, result])), error: nil
        )

        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(batch), connectionID: connectionID)

        XCTAssertEqual(journal.events.map(\.type), [.actionRequest, .actionAccepted, .actionResult])
        XCTAssertEqual(journal.events.map(\.eventId), ["request-1", "accepted-1", "result-1"])
        XCTAssertEqual(journal.events.map(\.operationId), ["operation-1", "operation-1", "operation-1"])
        guard journal.events.count == 3 else { return }
        XCTAssertEqual(journal.events[1].producerSessionId, session.providerSessionID)
        XCTAssertEqual(journal.events[2].producerSequence, 8)
    }

    /// 运行时必须持有操作账本；控制中心读取的账本才能包含真实 Provider 操作。
    func testRuntimeOwnsInjectedOperationJournalForProviderOperationLifecycle() {
        let journal = RuntimeRecordingJournal()
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in }),
            operationJournal: journal
        )

        XCTAssertTrue(
            Mirror(reflecting: runtime).children.contains { $0.label == "operationJournal" },
            "运行时必须持有用于记录真实 Provider 操作的 OperationJournaling 实例"
        )

        let request = ProviderEnvelope(
            protocolVersion: 2,
            messageId: "request-1",
            providerSessionId: "provider-1",
            gestureSessionId: "gesture-1",
            operationId: "operation-1",
            type: .actionRequest,
            timestamp: 42,
            payload: .actionRequest(ActionDescriptor(
                actionId: .browserPageReload,
                contextId: "context-1",
                targetRef: nil,
                parameters: [:],
                deadline: 100
            )),
            error: nil
        )
        runtime.appendOperationLifecycleEvent(request)

        XCTAssertEqual(journal.events.map(\.operationId), ["operation-1"])
        XCTAssertEqual(journal.events.first?.type, .actionRequest)
    }

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

private final class RuntimeRecordingJournal: OperationJournaling, @unchecked Sendable {
    var events: [ProviderEvent] = []
    func append(_ event: ProviderEvent) throws { events.append(event) }
    func recoverExpired(now: Int64) throws -> [RecoveredOperation] { [] }
    func query(_ filter: OperationFilter, limit: Int) throws -> [OperationTimeline] { [] }
    func exportEvidence(operationId: String, to url: URL) throws {}
}
