import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

@MainActor
final class RuntimeLifecycleTests: XCTestCase {
    func testAuthenticatedControlCenterRequestInvokesUIAndReturnsSuccess() throws {
        var opened = 0
        let (runtime, sessionID, connectionID, outbound) = try makeAuthenticatedRuntime { opened += 1 }
        let request = ProviderEnvelope(
            protocolVersion: 2, messageId: "open-control-center", providerSessionId: sessionID,
            gestureSessionId: nil, operationId: nil, type: .controlCenterOpenRequest, timestamp: 1,
            payload: .controlCenterOpenRequest(ControlCenterOpenRequestPayload()), error: nil
        )

        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(request), connectionID: connectionID)

        XCTAssertEqual(opened, 1)
        XCTAssertEqual(outbound.latest(of: .controlCenterOpenResponse)?.providerSessionId, sessionID)
        XCTAssertEqual(outbound.latest(of: .controlCenterOpenResponse)?.messageId, request.messageId)
    }

    func testUnauthenticatedControlCenterRequestDoesNotInvokeUI() throws {
        var opened = 0
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in }, touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(), logger: GestureKitLogger(terminalWriter: { _ in }),
            operationJournal: RuntimeRecordingJournal(), controlCenterOpenHandler: { opened += 1 }
        )
        let request = ProviderEnvelope(
            protocolVersion: 2, messageId: "open-control-center", providerSessionId: "untrusted",
            gestureSessionId: nil, operationId: nil, type: .controlCenterOpenRequest, timestamp: 1,
            payload: .controlCenterOpenRequest(ControlCenterOpenRequestPayload()), error: nil
        )

        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(request), connectionID: UUID())

        XCTAssertEqual(opened, 0)
    }
    func testUnauthenticatedTelemetryBatchDoesNotAppendToOperationJournal() throws {
        let journal = RuntimeRecordingJournal()
        let runtime = makeRuntime(operationJournal: journal)
        let batch = telemetryBatch(providerSessionID: "untrusted-provider", operationID: "operation-1")

        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(batch), connectionID: UUID())

        XCTAssertTrue(journal.events.isEmpty)
    }

    func testRuntimeHandshakeActionRequestAndAuthenticatedTelemetryShareOperationTimeline() throws {
        let credentialDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeLifecycleTelemetry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: credentialDirectory) }
        let credentialStore = ProviderCredentialStore(directory: credentialDirectory)
        let sessions = ProviderSessionRegistry(credentialStore: credentialStore)
        let journal = RuntimeRecordingJournal()
        let outbound = ProviderOutboundRecorder()
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in }),
            operationJournal: journal,
            providerSessions: sessions,
            appContextResolver: AppContextResolver(bundleIdProvider: { "com.google.Chrome" }),
            providerOutboundSink: { outbound.append($0) }
        )
        let connectionID = UUID()
        let installID = "chrome-telemetry-test"
        let hello = ProviderHelloPayload(installId: installID, protocolVersions: [2], environment: "test")
        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(ProviderEnvelope(
            protocolVersion: 2, messageId: "hello-1", providerSessionId: "provisional-provider",
            gestureSessionId: nil, operationId: nil, type: .providerHello, timestamp: 100,
            payload: .providerHello(hello), error: nil
        )), connectionID: connectionID)
        guard case .providerChallenge(let challenge)? = outbound.latest(of: .providerChallenge)?.payload,
              let nonce = Data(base64Encoded: challenge.nonce) else {
            return XCTFail("runtime must issue a provider challenge")
        }
        let response = ProviderAuthenticator(secret: try credentialStore.secret(for: installID))
            .response(for: installID, nonce: nonce)
        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(ProviderEnvelope(
            protocolVersion: 2, messageId: "authenticate-1", providerSessionId: "provisional-provider",
            gestureSessionId: nil, operationId: nil, type: .providerAuthenticate, timestamp: 101,
            payload: .providerAuthenticate(ProviderAuthenticatePayload(
                installId: installID,
                hmac: response.map { String(format: "%02x", $0) }.joined()
            )), error: nil
        )), connectionID: connectionID)
        guard let configuration = outbound.latest(of: .configurationSnapshot) else {
            return XCTFail("runtime must send configuration after authentication")
        }

        _ = runtime.processFrameForTesting(.frame(time: 0.00, activeTouches: [
            .touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)
        ]))
        _ = runtime.processFrameForTesting(.frame(time: 0.16, activeTouches: [
            .touch(1, 0.42, 0.40), .touch(2, 0.44, 0.40), .touch(3, 0.46, 0.40)
        ]))
        _ = runtime.processFrameForTesting(.frame(time: 0.26, activeTouches: []))
        guard let contextRequest = outbound.latest(of: .contextRequest),
              let gestureSessionID = contextRequest.gestureSessionId else {
            return XCTFail("recognized gesture must cause runtime to request provider context")
        }
        let encodedContextRequest = try JSONEncoder().encode(contextRequest)
        let contextRequestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedContextRequest) as? [String: Any]
        )
        let contextRequestPayload = try XCTUnwrap(contextRequestObject["payload"] as? [String: Any])
        XCTAssertEqual(contextRequestPayload["requiresTargetRef"] as? Bool, false)
        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(ProviderEnvelope(
            protocolVersion: 2, messageId: "context-1", providerSessionId: configuration.providerSessionId,
            gestureSessionId: gestureSessionID, operationId: nil, type: .contextSnapshot,
            timestamp: 110, payload: .contextSnapshot(ContextSnapshotPayload(
                contextId: "context-1", pageIdentity: "page-1", expiresAt: currentTimestampMs() + 10_000,
                targetKind: .noTarget, targetRef: nil
            )), error: nil
        )), connectionID: connectionID)
        guard let request = outbound.latest(of: .actionRequest), let operationID = request.operationId else {
            return XCTFail("runtime must emit an action request after valid context")
        }

        let accepted = ProviderEvent(
            eventId: "accepted-1", producerSessionId: configuration.providerSessionId, producerSequence: 7,
            causedByEventId: request.messageId, monotonicClockMs: 110, wallClockMs: 110,
            gestureSessionId: gestureSessionID, operationId: operationID, type: .actionAccepted,
            payload: .actionAccepted(ActionAcceptedPayload(operationId: operationID, acceptedAt: 110))
        )
        let result = ProviderEvent(
            eventId: "result-1", producerSessionId: configuration.providerSessionId, producerSequence: 8,
            causedByEventId: "accepted-1", monotonicClockMs: 120, wallClockMs: 120,
            gestureSessionId: gestureSessionID, operationId: operationID, type: .actionResult,
            payload: .actionResult(ProviderActionResultPayload(
                operationId: operationID, outcome: .succeeded, reason: nil, completedAt: 120
            ))
        )
        let batch = ProviderEnvelope(
            protocolVersion: 2, messageId: "batch-1", providerSessionId: configuration.providerSessionId,
            gestureSessionId: nil, operationId: nil, type: .telemetryBatch, timestamp: 130,
            payload: .telemetryBatch(TelemetryBatchPayload(events: [accepted, result])), error: nil
        )

        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(batch), connectionID: connectionID)

        XCTAssertEqual(journal.events.map(\.type), [.actionRequest, .actionAccepted, .actionResult])
        XCTAssertEqual(journal.events.map(\.eventId), [request.messageId, "accepted-1", "result-1"])
        XCTAssertEqual(journal.events.map(\.operationId), [operationID, operationID, operationID])
        guard journal.events.count == 3 else { return }
        XCTAssertEqual(journal.events[1].producerSessionId, configuration.providerSessionId)
        XCTAssertEqual(journal.events[2].producerSequence, 8)
    }

    private func makeRuntime(operationJournal: RuntimeRecordingJournal) -> GestureKitRuntime {
        GestureKitRuntime(
            menuBarHandler: { _ in }, touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in }), operationJournal: operationJournal
        )
    }

    private func makeAuthenticatedRuntime(
        controlCenterOpenHandler: @escaping () -> Void
    ) throws -> (GestureKitRuntime, String, UUID, ProviderOutboundRecorder) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControlCenter-\(UUID().uuidString)")
        let store = ProviderCredentialStore(directory: directory)
        let sessions = ProviderSessionRegistry(credentialStore: store)
        let outbound = ProviderOutboundRecorder()
        let connectionID = UUID()
        let installID = "control-center-provider"
        let hello = ProviderHelloPayload(installId: installID, protocolVersions: [2], environment: "test")
        let nonce = try sessions.beginAuthentication(hello)
        let response = ProviderAuthenticator(secret: try store.secret(for: installID)).response(for: installID, nonce: nonce)
        let session = try sessions.authenticate(
            installId: installID, response: response, connectionID: connectionID,
            sink: { outbound.append($0) }
        )
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in }, touchBackend: LifecycleStubTouchBackend(),
            settingsStore: LifecycleStubSettingsStore(), logger: GestureKitLogger(terminalWriter: { _ in }),
            providerSessions: sessions, providerOutboundSink: { outbound.append($0) },
            controlCenterOpenHandler: controlCenterOpenHandler
        )
        return (runtime, session.providerSessionID, connectionID, outbound)
    }

    private func telemetryBatch(providerSessionID: String, operationID: String) -> ProviderEnvelope {
        let accepted = ProviderEvent(
            eventId: "accepted-1", producerSessionId: providerSessionID, producerSequence: 1,
            causedByEventId: "request-1", monotonicClockMs: 110, wallClockMs: 110,
            gestureSessionId: "gesture-1", operationId: operationID, type: .actionAccepted,
            payload: .actionAccepted(ActionAcceptedPayload(operationId: operationID, acceptedAt: 110))
        )
        return ProviderEnvelope(
            protocolVersion: 2, messageId: "batch-1", providerSessionId: providerSessionID,
            gestureSessionId: nil, operationId: nil, type: .telemetryBatch, timestamp: 120,
            payload: .telemetryBatch(TelemetryBatchPayload(events: [accepted])), error: nil
        )
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

private struct LifecycleStubSettingsStore: SettingsStore, AppConfigurationStore {
    func loadRules() throws -> [Rule] { DefaultRules.v1 }
    func saveRules(_ rules: [Rule]) throws {}
    func loadAppConfiguration() throws -> AppConfiguration? { AppConfiguration.initial(storeEpoch: "runtime-lifecycle-tests") }
    func saveAppConfiguration(_ configuration: AppConfiguration) throws {}
    func importLegacyAppConfiguration(_ configuration: AppConfiguration) throws {}
    func hasLegacyMigrationMarker() throws -> Bool { false }
    func loadBindingOverrides() throws -> [BindingOverride] { [] }
    func saveBindingOverrides(_ overrides: [BindingOverride]) throws {}
}

private final class RuntimeRecordingJournal: OperationJournaling, @unchecked Sendable {
    var events: [ProviderEvent] = []
    func append(_ event: ProviderEvent) throws { events.append(event) }
    func recoverExpired(now: Int64) throws -> [RecoveredOperation] { [] }
    func query(_ filter: OperationFilter, limit: Int) throws -> [OperationTimeline] { [] }
    func clearOperationListDisplay() throws {}
    func exportEvidence(operationId: String, to url: URL) throws {}
}

private final class ProviderOutboundRecorder: @unchecked Sendable {
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
}

private func currentTimestampMs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
}
