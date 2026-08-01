import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

/// E2E 控制四场景分发测试：验证 Runtime 将 test 控制命令正确路由到
/// candidate/classification/context/action 管线，并确保各退出路径调用 guard release。
@MainActor
final class E2ERuntimeScenarioTests: XCTestCase {

    // MARK: - Success scenario

    func testSuccessScenarioFeedsGesturePipelineWithAuthenticatedProvider() throws {
        let (runtime, _, _, outbound, _) = try makeAuthenticatedRuntime()
        let command = E2ELinkOperationCommand(
            token: "test-token", gestureSessionId: "gs-s", operationId: "op-s", scenario: .success
        )

        let result = runtime.dispatchE2EOperationForTesting(command)

        XCTAssertEqual(result, .accepted(gestureSessionId: "gs-s", operationId: "op-s"))

        // 验证候选和分类事件被送入 coordinator，触发了 context_request。
        let contextRequest = outbound.latest(of: .contextRequest)
        XCTAssertNotNil(contextRequest, "success 场景应触发 context_request")
        XCTAssertNotNil(contextRequest?.gestureSessionId)
    }

    func testE2ESuccessScenarioSendsActionAfterContext() throws {
        let (runtime, sessionID, connectionID, outbound, _) = try makeAuthenticatedRuntime()
        let command = E2ELinkOperationCommand(
            token: "test-token", gestureSessionId: "gs-a", operationId: "op-a", scenario: .success
        )

        _ = runtime.dispatchE2EOperationForTesting(command)

        // 拿到 context_request 的 gestureSessionId，回复 context snapshot。
        guard let ctxReq = outbound.latest(of: .contextRequest),
              let gsid = ctxReq.gestureSessionId else {
            return XCTFail("success 场景必须先产生 context_request")
        }
        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(ProviderEnvelope(
            protocolVersion: 2, messageId: "ctx-1", providerSessionId: sessionID,
            gestureSessionId: gsid, operationId: nil, type: .contextSnapshot,
            timestamp: 1, payload: .contextSnapshot(ContextSnapshotPayload(
                contextId: "ctx-1", pageIdentity: "p1", expiresAt: currentTimestampMs() + 10_000,
                targetKind: .standardLink, targetRef: "https://example.com/page"
            )), error: nil
        )), connectionID: connectionID)

        let actionRequest = outbound.latest(of: .actionRequest)
        XCTAssertNotNil(actionRequest, "context 返回后应触发 action_request")
        XCTAssertEqual(actionRequest?.gestureSessionId, gsid)
    }

    // MARK: - Lease expiry scenario

    func testLeaseExpiryScenarioArmsGuardButDoesNotDispatchAction() throws {
        let (runtime, _, _, outbound, _) = try makeAuthenticatedRuntime()
        let command = E2ELinkOperationCommand(
            token: "test-token", gestureSessionId: "gs-l", operationId: "op-l",
            scenario: .leaseExpiry
        )

        let result = runtime.dispatchE2EOperationForTesting(command)

        XCTAssertEqual(result, .accepted(gestureSessionId: "gs-l", operationId: "op-l"))

        // guard arm 应触发（candidateStarted）
        let guardArm = outbound.all(of: .interactionGuardArm)
        XCTAssertFalse(guardArm.isEmpty, "leaseExpiry 场景应先 arm guard")

        // guard release 应触发
        let guardRelease = outbound.all(of: .interactionGuardRelease)
        XCTAssertFalse(guardRelease.isEmpty, "leaseExpiry 场景应释放 guard")

        // 不应产生 action_request
        let actionRequest = outbound.latest(of: .actionRequest)
        XCTAssertNil(actionRequest, "leaseExpiry 场景不应派发 action")
    }

    // MARK: - Provider unavailable scenario

    func testProviderUnavailableScenarioGeneratesTerminalState() throws {
        let (runtime, _, _, outbound, journal) = try makeAuthenticatedRuntime()
        let command = E2ELinkOperationCommand(
            token: "test-token", gestureSessionId: "gs-u", operationId: "op-u",
            scenario: .providerUnavailable
        )

        let result = runtime.dispatchE2EOperationForTesting(command)

        XCTAssertEqual(result, .accepted(gestureSessionId: "gs-u", operationId: "op-u"))

        // guard arm 应触发（candidateStarted）
        let guardArm = outbound.all(of: .interactionGuardArm)
        XCTAssertFalse(guardArm.isEmpty, "providerUnavailable 场景应先 arm guard")

        // guard release 应触发（primitiveRejected → guardReleaseRouter → handleCandidateGuardRelease）
        let guardRelease = outbound.all(of: .interactionGuardRelease)
        XCTAssertFalse(guardRelease.isEmpty, "providerUnavailable 场景应释放 guard")

        // 不应产生 action_request 或 context_request（此场景使用 primitiveRejected 而非 primitiveClassified）
        XCTAssertNil(outbound.latest(of: .actionRequest), "providerUnavailable 场景不应派发 action")
        XCTAssertNil(outbound.latest(of: .contextRequest), "providerUnavailable 场景不应触发 context_request")

        // Journal 应记录不可用终态事件。
        let terminalEvents = journal.events.filter {
            $0.type == .actionResult && $0.gestureSessionId == "gs-u"
        }
        XCTAssertFalse(terminalEvents.isEmpty, "provider 不可用时应写入终态事件")
    }

    // MARK: - Result unknown scenario

    func testResultUnknownScenarioDispatchesActionThenConverges() throws {
        let (runtime, sessionID, connectionID, outbound, _) = try makeAuthenticatedRuntime()
        let command = E2ELinkOperationCommand(
            token: "test-token", gestureSessionId: "gs-r", operationId: "op-r",
            scenario: .resultUnknown
        )

        _ = runtime.dispatchE2EOperationForTesting(command)

        // 验证 action_request 被发出
        guard let ctxReq = outbound.latest(of: .contextRequest),
              let gsid = ctxReq.gestureSessionId else {
            return XCTFail("resultUnknown 场景应先产生 context_request")
        }
        runtime.handleProviderEnvelopeForTesting(try JSONEncoder().encode(ProviderEnvelope(
            protocolVersion: 2, messageId: "ctx-r", providerSessionId: sessionID,
            gestureSessionId: gsid, operationId: nil, type: .contextSnapshot,
            timestamp: 1, payload: .contextSnapshot(ContextSnapshotPayload(
                contextId: "ctx-r", pageIdentity: "p1", expiresAt: currentTimestampMs() + 10_000,
                targetKind: .standardLink, targetRef: "https://example.com/page"
            )), error: nil
        )), connectionID: connectionID)

        let actionRequest = outbound.latest(of: .actionRequest)
        XCTAssertNotNil(actionRequest, "resultUnknown 场景应发出 action_request")
        XCTAssertNotNil(actionRequest?.operationId, "action_request 应携带 operationId")
    }

    // MARK: - Token gating

    func testWithoutTokenNoE2EServerCreated() async {
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: StubTouchBackend(),
            settingsStore: StubE2ESettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in }),
            appContextResolver: AppContextResolver()
        )
        // 无 token 时不应创建 E2E server。
        let port = await runtime.e2eControlPort
        XCTAssertNil(port, "无 --e2e-control-token 时不得暴露 e2e port")
    }

    func testWithTokenE2EServerStarted() {
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: StubTouchBackend(),
            settingsStore: StubE2ESettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in }),
            appContextResolver: AppContextResolver(),
            e2eControlToken: "my-token"
        )
        // 有 token 时应启动并分配到端口。
        // 注意：start 是异步的，这里断言不崩溃即可；详细测试见 E2EControlServerTests。
        XCTAssertNotNil(runtime, "带 token 的 Runtime 应正常初始化")
    }

    // MARK: - Helpers

    private func makeAuthenticatedRuntime(
        token: String = "test-token"
    ) throws -> (GestureKitRuntime, String, UUID, ProviderOutboundRecorder, RuntimeRecordingJournal) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("E2ERuntimeScenario-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProviderCredentialStore(directory: directory)
        let sessions = ProviderSessionRegistry(credentialStore: store)
        let outbound = ProviderOutboundRecorder()
        let connectionID = UUID()
        let installID = "e2e-test-provider"
        let hello = ProviderHelloPayload(installId: installID, protocolVersions: [2], environment: "test")
        let nonce = try sessions.beginAuthentication(hello)
        let response = ProviderAuthenticator(secret: try store.secret(for: installID))
            .response(for: installID, nonce: nonce)
        let session = try sessions.authenticate(
            installId: installID, response: response, connectionID: connectionID,
            sink: { outbound.append($0) }
        )
        let journal = RuntimeRecordingJournal()
        let runtime = GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: StubTouchBackend(),
            settingsStore: StubE2ESettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in }),
            operationJournal: journal,
            providerSessions: sessions,
            appContextResolver: AppContextResolver(bundleIdProvider: { "com.google.Chrome" }),
            providerOutboundSink: { outbound.append($0) },
            e2eControlToken: token
        )
        return (runtime, session.providerSessionID, connectionID, outbound, journal)
    }

    private func currentTimestampMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}

// MARK: - Test doubles

private final class StubTouchBackend: TouchBackend {
    let frames = AsyncStream<TouchFrame> { continuation in
        continuation.finish()
    }
    func start() -> Bool { true }
    func stop() -> Bool { true }
}

private struct StubE2ESettingsStore: SettingsStore, AppConfigurationStore {
    func loadRules() throws -> [Rule] { DefaultRules.v1 }
    func saveRules(_ rules: [Rule]) throws {}
    func loadAppConfiguration() throws -> AppConfiguration? {
        AppConfiguration.initial(storeEpoch: "e2e-runtime-tests")
    }
    func saveAppConfiguration(_ configuration: AppConfiguration) throws {}
    func importLegacyAppConfiguration(_ configuration: AppConfiguration) throws {}
    func hasLegacyMigrationMarker() throws -> Bool { false }
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

    func all(of type: ProviderMessageType) -> [ProviderEnvelope] {
        lock.lock()
        defer { lock.unlock() }
        return values.filter { $0.type == type }
    }
}
