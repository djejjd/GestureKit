import Foundation
import GestureKitCore

private enum AppConfigurationUnavailable: Error {
    case storeUnavailable
}

@MainActor
final class GestureKitRuntime {
    private let menuBarHandler: (AppMenuBarEvent) -> Void
    private var recognizer = GestureRecognizer()
    private var ruleEngine: RuleEngine
    private let appContextResolver: AppContextResolver
    private let touchBackend: any TouchBackend
    private let settingsStore: any SettingsStore
    private let configurationMigration: ConfigurationMigration?
    private let logger: GestureKitLogger
    /// 与控制中心共用的操作账本；仅记录已进入 Provider 操作生命周期的事件。
    private let operationJournal: (any OperationJournaling)?
    private let diagnosticSink: (LocalIPCEnvelope) -> Void
    private var listeningTask: Task<Void, Never>?
    private var eventServer: LocalEventServer?
    private let providerSessions: ProviderSessionRegistry
    /// 测试 transport 边界时捕获真实出站消息；生产环境保持 nil。
    private let providerOutboundSink: ProviderSessionSink?
    private let controlCenterOpenHandler: () -> Void
    private let appSessionId: String
    private var internalState = AppInternalStatus()
    private var isPaused = false
    private var pendingRequests: [String: (action: String, timestamp: Int64)] = [:]
    /// E2E 测试控制服务；仅当启动参数包含非空 token 时创建。
    private var e2eServer: E2EControlServer?
    /// 组合器：把原始原语（3 种）组合为带区域和重复含义的手势（6 种）。
    private lazy var gestureCoordinator: GestureSessionCoordinator = GestureSessionCoordinator(
        ruleEngine: ruleEngine,
        guardJournal: { [weak self] id in
            self?.logger.debug("candidate_started id=\(id)")
        },
        guardRouter: { [weak self] id, candidate in
            self?.handleCandidateGuardArm(sessionID: id, fingerCount: candidate.fingerCount)
        },
        guardReleaseRouter: { [weak self] id in
            self?.handleCandidateGuardRelease(sessionID: id)
        },
        contextRouter: { [weak self] sessionID, deadline in
            self?.handleCoordinatorContextRequest(sessionID: sessionID, deadline: deadline)
        },
        actionRouter: { [weak self] sessionID, action in
            self?.handleCoordinatorAction(sessionID: sessionID, action: action)
        },
        logger: logger
    )
    /// coordinator context_request 的 pending 表：用于验证 Provider 回复的合法性。
    private var pendingCoordinatorSessions: [String: (providerSessionID: String, deadline: Int64)] = [:]
    /// coordinator 回调中需要知道原始手势类型以判断 requiresTargetRef。
    /// 候选不重叠（一次只可能有一个候选），因此按 lastCandidateSessionID 索引即可。
    private var pendingCoordinatorGestureInfo: [String: GestureType] = [:]
    /// 当前候选对应的 coordinator session ID，供后续 classification 事件关联。
    private var lastCandidateSessionID: String?
    private var configurationAppliedByProvider: Bool?
    private var operationJournalSequence: Int64 = 0

    init(
        menuBarHandler: @escaping (AppMenuBarEvent) -> Void,
        touchBackend: any TouchBackend = MultitouchSupportBackend(),
        settingsStore: any SettingsStore = UserDefaultsSettingsStore(),
        logger: GestureKitLogger = GestureKitLogger(),
        operationJournal: (any OperationJournaling)? = nil,
        providerSessions: ProviderSessionRegistry = ProviderSessionRegistry(),
        appContextResolver: AppContextResolver = AppContextResolver(),
        providerOutboundSink: ProviderSessionSink? = nil,
        controlCenterOpenHandler: @escaping () -> Void = {},
        diagnosticSink: @escaping (LocalIPCEnvelope) -> Void = { _ in },
        e2eControlToken: String? = nil
    ) {
        self.menuBarHandler = menuBarHandler
        self.touchBackend = touchBackend
        self.settingsStore = settingsStore
        let migration = (settingsStore as? any AppConfigurationStore)
            .map(ConfigurationMigration.init(store:))
        self.configurationMigration = migration
        let configuration = try? migration?.authoritativeConfiguration()
        self.recognizer = GestureRecognizer(settings: configuration?.recognition ?? .standard)
        self.logger = logger
        self.operationJournal = operationJournal
        self.providerSessions = providerSessions
        self.appContextResolver = appContextResolver
        self.providerOutboundSink = providerOutboundSink
        self.controlCenterOpenHandler = controlCenterOpenHandler
        self.diagnosticSink = diagnosticSink
        self.ruleEngine = configuration.map(RuleEngine.init(configuration:))
            ?? RuleEngine(rules: (try? settingsStore.loadRules()) ?? DefaultRules.v1)
        self.appSessionId = UUID().uuidString

        // E2E 测试控制边界：仅当启动参数包含非空 token 时暴露。
        if let token = e2eControlToken, !token.isEmpty {
            let server = E2EControlServer(token: token) { [weak self] command in
                guard let self else {
                    return .rejected(reason: "e2e_runtime_unavailable")
                }
                return await self.dispatchE2EOperation(command)
            }
            self.e2eServer = server
            Task {
                do {
                    try await server.start()
                } catch {
                    logger.error("e2e_control_server_start_failed error=\"\(error)\"")
                }
            }
        }
    }

    func start() {
        guard listeningTask == nil, eventServer == nil else { return }
        do {
            let server = try LocalEventServer(logger: logger) { [weak self] envelope in
                Task { @MainActor [weak self] in
                    self?.handleIPCEnvelope(envelope)
                }
            }
            server.onRawMessage = { [weak self, weak server] connectionID, data in
                guard let server else { return }
                Task { @MainActor [weak self] in
                    self?.handleProviderEnvelope(data, connectionID: connectionID, server: server)
                }
            }
            server.onConnectionRemoved = { [weak self] connectionID in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.providerSessions.invalidateSession(for: connectionID)
                    let dropped = self.pendingCoordinatorSessions.count
                    self.pendingCoordinatorSessions.removeAll()
                    if dropped > 0 {
                        self.logger.warn("provider_session_invalidated connection_lost dropped_pending_contexts=\(dropped)")
                    }
                }
            }
            server.start()
            eventServer = server
        } catch {
            internalState.listeningState = .ipcError
            emit(event: AppMenuBarEvent(type: .appError(reason: AppErrorReason.internalError.rawValue)))
            logger.error("ipc_listener_start_failed error=\"\(error)\"")
            return
        }

        internalState.listeningState = .running
        logger.info(
            "app_started log_file=\"\(loggerFilePathHint())\" debug=\(ProcessInfo.processInfo.environment["GESTUREKIT_DEBUG"] == "1")",
            terminal: true
        )
        startTouchListening()
    }

    func stop() {
        guard listeningTask != nil || eventServer != nil else {
            internalState.listeningState = .stopped
            return
        }
        listeningTask?.cancel()
        listeningTask = nil
        eventServer?.stop()
        eventServer = nil
        _ = touchBackend.stop()
        internalState.listeningState = .stopped
        logger.info("app_stopped", terminal: true)
    }

    func pause() {
        isPaused = true
        emit(event: AppMenuBarEvent(type: .paused))
        logger.info("paused")
    }

    func resume() {
        isPaused = false
        emit(event: AppMenuBarEvent(type: .resumed))
        logger.info("resumed")
    }

    private func emit(event: AppMenuBarEvent) {
        menuBarHandler(event)
    }

    private func startTouchListening() {
        listeningTask = Task { @MainActor in
            for await frame in touchBackend.frames {
                guard !Task.isCancelled else { return }
                guard !isPaused else { continue }
                _ = processFrame(frame)
            }
        }

        guard touchBackend.start() else {
            listeningTask?.cancel()
            listeningTask = nil
            eventServer?.stop()
            eventServer = nil
            internalState.listeningState = .inputError
            emit(event: AppMenuBarEvent(type: .appError(reason: AppErrorReason.listenerStopped.rawValue)))
            logger.error("touch_backend_start_failed")
            return
        }
        logger.info("touch_backend_started")
    }

    @discardableResult
    private func processFrame(_ frame: TouchFrame) -> RecognizedGesture? {
        guard !isPaused else { return nil }
        let sessionEvents = recognizer.observe(frame)
        // 所有事件（candidateStarted、primitiveClassified、primitiveRejected）先送 coordinator
        // 由它完成区域分类、双击仲裁，再通过 contextRouter/actionRouter 回调驱动后续流程。
        for sessionEvent in sessionEvents {
            switch sessionEvent {
            case .candidateStarted:
                lastCandidateSessionID = gestureCoordinator.handle(sessionEvent)
            case .primitiveClassified(let recognized):
                if let sessionID = lastCandidateSessionID {
                    pendingCoordinatorGestureInfo[sessionID] = recognized.gesture
                }
                gestureCoordinator.handle(sessionEvent)
            case .primitiveRejected:
                if let sessionID = lastCandidateSessionID {
                    pendingCoordinatorGestureInfo.removeValue(forKey: sessionID)
                }
                gestureCoordinator.handle(sessionEvent)
                lastCandidateSessionID = nil
            }
        }
        // 降级诊断和菜单栏事件仍从原始 RecognizedGesture 发出
        guard let event = sessionEvents.compactMap(\.recognizedGesture).first else { return nil }
        guard let gesture = event.gesture else {
            let reason = warningReason(from: event)
            emit(event: AppMenuBarEvent(type: .gestureWarning(reason: reason.rawValue)))
            logger.debug(gestureMetrics("gesture_unstable", event: event), rateLimitKey: "gesture_unstable")
            return event
        }
        publishDiagnostic(for: event)
        emit(event: AppMenuBarEvent(type: .gestureRecognized(gesture: gesture.rawValue)))
        logger.info(gestureMetrics("gesture_recognized gesture=\(gesture.rawValue)", event: event))
        return event
    }

    private func warningReason(from event: RecognizedGesture) -> AppWarningReason {
        switch event.reason {
        case .distanceTooShort: return .dxTooShort
        case .tooSlow: return .tooSlow
        case .tooFast: return .tooLong
        case .horizontalRatioTooLow: return .dyTooLarge
        case .cooldown: return .cooldown
        default: return .unknown
        }
    }

    func applySettingsUpdate(_ payload: SettingsUpdatePayload) -> SettingsAckPayload {
        recognizer.updateSettings(payload.recognitionSettings)
        logger.info(
            "settings_applied swipeSensitivity=\(payload.swipeSensitivity.rawValue) swipeMinDistance=\(payload.swipeMinDistance)",
            rateLimitKey: "settings_applied"
        )
        publishDiagnostic(DiagnosticEventPayload(
            source: .app,
            kind: .settings,
            gesture: nil,
            action: nil,
            status: .success,
            reason: .success,
            swipeSensitivity: payload.swipeSensitivity,
            dx: nil,
            dy: nil,
            distance: nil,
            durationMs: nil,
            horizontalRatio: nil,
            thresholds: payload.recognitionSettings,
            message: "settings_applied"
        ))
        return SettingsAckPayload(
            applied: true,
            swipeSensitivity: payload.swipeSensitivity,
            appSessionId: appSessionId,
            recognitionSettings: payload.recognitionSettings
        )
    }

    func apply(configuration: AppConfiguration) {
        recognizer.updateSettings(configuration.recognition)
        ruleEngine = RuleEngine(configuration: configuration)
        gestureCoordinator.updateRuleEngine(ruleEngine)
        refreshConfigurationSnapshot()
    }

    func updateBinding(id: String, enabled: Bool) throws {
        guard let configurationMigration else { throw AppConfigurationUnavailable.storeUnavailable }
        let configuration = try configurationMigration.authoritativeConfiguration()
        let updated = try configuration.updatingBinding(id: id, enabled: enabled)
        try (settingsStore as? any AppConfigurationStore)?.saveAppConfiguration(updated)
        apply(configuration: updated)
    }

    func updateSensitivity(_ sensitivity: SwipeSensitivity) throws {
        guard let configurationMigration else { throw AppConfigurationUnavailable.storeUnavailable }
        let updated = try configurationMigration.authoritativeConfiguration().updatingSensitivity(sensitivity)
        try (settingsStore as? any AppConfigurationStore)?.saveAppConfiguration(updated)
        apply(configuration: updated)
    }

    func restoreDefaultConfiguration() throws {
        guard let configurationMigration else { throw AppConfigurationUnavailable.storeUnavailable }
        let current = try configurationMigration.authoritativeConfiguration()
        let restored = AppConfiguration(
            storeEpoch: current.storeEpoch,
            schemaVersion: 3,
            configurationVersion: current.configurationVersion + 1,
            rules: DefaultRules.v1Bindings,
            recognition: .standard
        )
        try (settingsStore as? any AppConfigurationStore)?.saveAppConfiguration(restored)
        apply(configuration: restored)
    }

    /// 仅用于 v1 -> v2 的一次性切换；marker 已存在时旧设置写入必须失败关闭。
    private func applyLegacySettingsUpdate(_ payload: SettingsUpdatePayload) -> SettingsAckPayload {
        guard let configurationMigration,
              (try? configurationMigration.isLegacyImportPending()) == true else {
            return SettingsAckPayload(
                applied: false,
                swipeSensitivity: payload.swipeSensitivity,
                appSessionId: appSessionId,
                recognitionSettings: payload.recognitionSettings,
                message: "legacy_settings_write_rejected"
            )
        }
        do {
            _ = try configurationMigration.importLegacy(recognition: payload.recognitionSettings)
            recognizer.updateSettings(payload.recognitionSettings)
            return SettingsAckPayload(
                applied: true,
                swipeSensitivity: payload.swipeSensitivity,
                appSessionId: appSessionId,
                recognitionSettings: payload.recognitionSettings
            )
        } catch {
            return SettingsAckPayload(
                applied: false,
                swipeSensitivity: payload.swipeSensitivity,
                appSessionId: appSessionId,
                recognitionSettings: payload.recognitionSettings,
                message: "legacy_settings_write_rejected"
            )
        }
    }

    func observeForTesting(_ frame: TouchFrame) -> RecognizedGesture? {
        recognizer.observe(frame).compactMap(\.recognizedGesture).first
    }

    func processFrameForTesting(_ frame: TouchFrame) -> RecognizedGesture? {
        processFrame(frame)
    }

    func handleProbeRequestForTesting(id: String) -> GestureKitMessage {
        handleProbeRequest(id).message
    }

    func applyLegacySettingsUpdateForTesting(_ payload: SettingsUpdatePayload) -> SettingsAckPayload {
        applyLegacySettingsUpdate(payload)
    }

    func configurationSnapshotForProviderForTesting() throws -> ConfigurationSnapshotPayload {
        try authoritativeConfigurationSnapshot()
    }

    var isCurrentlyPaused: Bool { isPaused }

    /// 控制中心只读取此健康摘要，不接触 Provider 凭据或会话标识。
    var controlCenterHealth: ControlCenterHealth {
        let state = internalState.listeningState
        let session = providerSessions.activeSession()
        logger.info("health_check state=\(String(describing: state)) hasSession=\(session != nil)")
        switch state {
        case .inputError, .ipcError:
            return .listeningUnavailable
        case .idle:
            return .preparing
        case .stopped:
            return .stopped
        case .running:
            guard let session else { return .disconnected }
            return .connected(capabilities: session.capabilities, configurationApplied: configurationAppliedByProvider)
        }
    }

    private func handleProbeRequest(_ id: String) -> LocalIPCEnvelope {
        LocalIPCEnvelope(message: .probeResponse(
            id: id,
            timestamp: currentTimestampMs(),
            payload: ProbeResponsePayload(
                hostConnected: true,
                appConnected: true,
                appSessionId: appSessionId,
                message: "app_ready"
            )
        ))
    }

    private func handleIPCEnvelope(_ envelope: LocalIPCEnvelope) {
        if envelope.message.type == .probeRequest {
            _ = eventServer?.publish(handleProbeRequest(envelope.id))
            return
        }

        if envelope.message.type == .actionResult, let payload = envelope.message.actionResultPayload {
            let details = payload.details?.map { "\($0.key)=\(detailValueText($0.value))" }.joined(separator: " ") ?? ""
            logger.info(
                "action_result action=\(payload.action.rawValue) status=\(payload.status.rawValue) \(details)",
                rateLimitKey: "action_result_\(payload.action.rawValue)"
            )
            logger.debug(
                "chrome_action_result requestId=\(envelope.id) action=\(payload.action.rawValue) status=\(payload.status.rawValue)",
                rateLimitKey: "chrome_action_result_\(envelope.id)",
                interval: 0.5
            )
            handleActionResult(envelope.id, action: payload.action.rawValue, status: payload.status.rawValue, detailsText: details)
            return
        }

        guard let payload = envelope.message.settingsUpdatePayload else {
            return
        }
        let ack = applyLegacySettingsUpdate(payload)
        let ackEnvelope = LocalIPCEnvelope(message: .settingsAck(
            id: envelope.id,
            timestamp: currentTimestampMs(),
            payload: ack
        ))
        _ = eventServer?.publish(ackEnvelope)
    }

    /// v2 认证消息只在 transport 边界处理；未认证连接不能进入旧动作或配置处理路径。
    func handleProviderEnvelopeForTesting(_ data: Data, connectionID: UUID) {
        handleProviderEnvelope(data, connectionID: connectionID, server: nil)
    }

    private func handleProviderEnvelope(_ data: Data, connectionID: UUID, server: LocalEventServer?) {
        guard let envelope = try? JSONDecoder().decode(ProviderEnvelope.self, from: data) else {
            logger.warn("provider_v2_decode_rejected", rateLimitKey: "provider_v2_decode_rejected")
            return
        }
        switch (envelope.type, envelope.payload) {
        case (.providerHello, .providerHello(let hello)):
            guard let nonce = try? providerSessions.beginAuthentication(hello) else { return }
            let challenge = ProviderEnvelope(protocolVersion: 2, messageId: UUID().uuidString, providerSessionId: envelope.providerSessionId, gestureSessionId: nil, operationId: nil, type: .providerChallenge, timestamp: currentTimestampMs(), payload: .providerChallenge(ProviderChallengePayload(nonce: nonce.base64EncodedString(), expiresAt: currentTimestampMs() + 30_000)), error: nil)
            try? server?.send(challenge, to: connectionID)
            providerOutboundSink?(challenge)
        case (.providerAuthenticate, .providerAuthenticate(let authentication)):
            guard let response = Data(hexEncoded: authentication.hmac) else { return }
            let providerOutboundSink = self.providerOutboundSink
            guard (try? providerSessions.authenticate(
                installId: authentication.installId,
                response: response,
                connectionID: connectionID,
                sink: { [weak server] outbound in
                try? server?.send(outbound, to: connectionID)
                providerOutboundSink?(outbound)
                }
            )) != nil else { return }
            configurationAppliedByProvider = false
            refreshConfigurationSnapshot()
        case (.configurationAck, .configurationAck(let acknowledgement)):
            guard let session = providerSessions.activeSession(),
                  envelope.providerSessionId == session.providerSessionID,
                  providerSessions.session(session.providerSessionID, belongsTo: connectionID),
                  let configuration = try? configurationMigration?.authoritativeConfiguration(),
                  acknowledgement.appliedVersion == configuration.configurationVersion else { return }
            logger.info(
                "provider_configuration_ack applied=\(acknowledgement.applied) version=\(acknowledgement.appliedVersion)",
                rateLimitKey: "provider_configuration_ack"
            )
            configurationAppliedByProvider = acknowledgement.applied
        case (.capabilitySnapshot, .capabilitySnapshot(let snapshot)):
            guard let session = providerSessions.activeSession(),
                  envelope.providerSessionId == session.providerSessionID else { return }
            _ = providerSessions.updateCapabilities(snapshot, for: session.providerSessionID, connectionID: connectionID)
        case (.contextSnapshot, .contextSnapshot(let snapshot)):
            let gsid = envelope.gestureSessionId
            let pend = gsid.flatMap { pendingCoordinatorSessions[$0] }
            let act = providerSessions.activeSession()
            let found = gsid != nil && pend != nil
            let hasSession = act != nil
            let sessMatch = pend != nil && act != nil && pend!.providerSessionID == act!.providerSessionID && envelope.providerSessionId == act!.providerSessionID
            let connOk = act.map { providerSessions.session($0.providerSessionID, belongsTo: connectionID) } ?? false
            let errOk = envelope.error == nil
            let expOk = snapshot.expiresAt >= currentTimestampMs()
            let deadOk = pend.map { $0.deadline >= currentTimestampMs() } ?? false
            guard let gestureSessionId = gsid, let pending = pend, let session = act,
                  pending.providerSessionID == session.providerSessionID,
                  envelope.providerSessionId == session.providerSessionID,
                  connOk, errOk, expOk, deadOk else {
                logger.info("context_snapshot_reject id=\(gsid ?? "nil") found=\(found) session=\(hasSession) sessMatch=\(sessMatch) connOk=\(connOk) errOk=\(errOk) expOk=\(expOk) deadOk=\(deadOk)")
                return
            }
            pendingCoordinatorSessions.removeValue(forKey: gestureSessionId)
            logger.info("context_snapshot_ok id=\(gestureSessionId) target=\(snapshot.targetKind.rawValue)")
            let context = ProviderContextSnapshot(
                contextId: snapshot.contextId,
                targetKind: snapshot.targetKind,
                targetRef: snapshot.targetRef,
                deadline: currentTimestampMs() + 1500
            )
            gestureCoordinator.receiveContext(context, for: gestureSessionId)
        case (.actionAccepted, .actionAccepted), (.actionResult, .actionResult):
            guard let session = providerSessions.activeSession(),
                  envelope.providerSessionId == session.providerSessionID,
                  providerSessions.session(session.providerSessionID, belongsTo: connectionID) else { return }
            let operationId = envelope.operationId ?? ""
            let gestureSessionId = envelope.gestureSessionId ?? ""
            logger.debug(
                "provider_event type=\(envelope.type.rawValue) operationId=\(operationId) gestureSessionId=\(gestureSessionId)",
                rateLimitKey: "provider_event_\(envelope.type.rawValue)"
            )
            if case (.actionResult, .actionResult(let resultPayload)) = (envelope.type, envelope.payload) {
                logger.info("action_result_outcome operationId=\(operationId) outcome=\(resultPayload.outcome.rawValue) reason=\(resultPayload.reason?.rawValue ?? "nil")")
                if resultPayload.reason == .guardUnavailable || resultPayload.reason == .guardExpired {
                    logger.warn(
                        "link_operation_summary operationId=\(operationId) sessionId=\(gestureSessionId) outcome=\(resultPayload.outcome.rawValue) guard=\(resultPayload.reason?.rawValue ?? "unknown") action=not_dispatched",
                        rateLimitKey: "link_operation_guard_failure_\(operationId)",
                        interval: 0
                    )
                }
            }
            appendOperationLifecycleEvent(envelope)
        case (.telemetryBatch, .telemetryBatch(let batch)):
            guard let session = providerSessions.activeSession(),
                  envelope.providerSessionId == session.providerSessionID,
                  providerSessions.session(session.providerSessionID, belongsTo: connectionID) else { return }
            appendTelemetryLifecycleEvents(batch.events)
        case (.controlCenterOpenRequest, .controlCenterOpenRequest):
            guard let session = providerSessions.activeSession(),
                  envelope.providerSessionId == session.providerSessionID,
                  providerSessions.session(session.providerSessionID, belongsTo: connectionID) else { return }
            controlCenterOpenHandler()
            let response = ProviderEnvelope(
                protocolVersion: 2, messageId: envelope.messageId,
                providerSessionId: session.providerSessionID, gestureSessionId: nil, operationId: nil,
                type: .controlCenterOpenResponse, timestamp: currentTimestampMs(),
                payload: .controlCenterOpenResponse(ControlCenterOpenResponsePayload(opened: true)), error: nil
            )
            try? providerSessions.send(response, to: session.providerSessionID)
        default:
            logger.warn("provider_v2_unauthorized_message", rateLimitKey: "provider_v2_unauthorized_message")
        }
    }

    /// 将已验证的 Provider 操作消息追加到控制中心读取的同一账本。
    func appendOperationLifecycleEvent(_ envelope: ProviderEnvelope) {
        guard let operationJournal, envelope.operationId != nil else { return }
        operationJournalSequence += 1
        let operationId = envelope.operationId ?? ""
        let gestureSessionId = envelope.gestureSessionId ?? ""
        logger.debug(
            "operation_journal_append type=\(envelope.type.rawValue) operationId=\(operationId) gestureSessionId=\(gestureSessionId) sequence=\(operationJournalSequence)",
            rateLimitKey: "operation_journal_append_\(envelope.type.rawValue)"
        )
        let event = ProviderEvent(
            eventId: envelope.messageId,
            producerSessionId: appSessionId,
            producerSequence: operationJournalSequence,
            causedByEventId: nil,
            monotonicClockMs: envelope.timestamp,
            wallClockMs: envelope.timestamp,
            gestureSessionId: envelope.gestureSessionId,
            operationId: envelope.operationId,
            type: envelope.type,
            payload: envelope.payload
        )
        do {
            try operationJournal.append(event)
        } catch {
            logger.error("operation_journal_append_failed error=\"\(error)\"")
        }
    }

    /// telemetry_batch 的事件已经由 Provider 生成并带有独立的溯源字段，入账时不得重写。
    private func appendTelemetryLifecycleEvents(_ events: [ProviderEvent]) {
        guard let operationJournal else { return }
        for event in events {
            do {
                try operationJournal.append(event)
            } catch {
                logger.error("operation_journal_append_failed error=\"\(error)\"")
            }
        }
    }

    private func authoritativeConfigurationSnapshot() throws -> ConfigurationSnapshotPayload {
        guard let configurationMigration else { throw AppConfigurationUnavailable.storeUnavailable }
        let configuration = try configurationMigration.authoritativeConfiguration()
        let data = try JSONEncoder.gestureKit.encode(configuration)
        return ConfigurationSnapshotPayload(
            storeEpoch: configuration.storeEpoch,
            schemaVersion: configuration.schemaVersion,
            configurationVersion: configuration.configurationVersion,
            diagnosticLoggingEnabled: UserDefaults.standard.bool(forKey: GestureKitLogger.diagnosticLoggingDefaultsKey),
            configJSON: String(decoding: data, as: UTF8.self)
        )
    }

    // MARK: - E2E control dispatch

    /// 仅测试用：暴露当前 E2E server 端口；无 token 时返回 nil。
    var e2eControlPort: UInt16? {
        get async { await e2eServer?.port }
    }

    /// 测试入口：将 E2E 命令直接交给 dispatch，不走网络层。
    func dispatchE2EOperationForTesting(_ command: E2ELinkOperationCommand) -> E2EControlResult {
        dispatchE2EOperationSync(command)
    }

    /// 同步版 dispatch（测试入口使用），不等待异步管线完成。
    private func dispatchE2EOperationSync(_ command: E2ELinkOperationCommand) -> E2EControlResult {
        let now = Date().timeIntervalSince1970

        switch command.scenario {
        case .success:
            let candidate = GestureCandidate(
                startedAt: now, centroidX: 0.5, centroidY: 0.5, fingerCount: 3
            )
            if let sessionID = gestureCoordinator.handle(.candidateStarted(candidate)) {
                lastCandidateSessionID = sessionID
                pendingCoordinatorGestureInfo[sessionID] = .threeFingerTap
                let recognized = RecognizedGesture(
                    gesture: .threeFingerTap,
                    status: .success,
                    reason: .success,
                    durationMs: 100,
                    dx: 0, dy: 0,
                    centroidX: 0.5, centroidY: 0.5
                )
                gestureCoordinator.handle(.primitiveClassified(recognized))
            }
            return .accepted(gestureSessionId: command.gestureSessionId, operationId: command.operationId)

        case .leaseExpiry:
            // 只 arm guard，不分类不派发 action；用 primitiveRejected 释放 guard。
            let candidate = GestureCandidate(
                startedAt: now, centroidX: 0.5, centroidY: 0.5, fingerCount: 3
            )
            if let sessionID = gestureCoordinator.handle(.candidateStarted(candidate)) {
                lastCandidateSessionID = sessionID
                let rejected = RecognizedGesture(
                    gesture: nil,
                    status: .error,
                    reason: .unknown,
                    durationMs: 100,
                    dx: 0, dy: 0
                )
                gestureCoordinator.handle(.primitiveRejected(rejected))
                lastCandidateSessionID = nil
            }
            return .accepted(gestureSessionId: command.gestureSessionId, operationId: command.operationId)

        case .providerUnavailable:
            // 无 provider 上下文：走 candidate → primitiveRejected 触发 guardReleaseRouter
            // → handleCandidateGuardRelease + 清理 coordinator activeSessions。
            // 写入不可用终态到 Journal。
            let candidate = GestureCandidate(
                startedAt: now, centroidX: 0.5, centroidY: 0.5, fingerCount: 3
            )
            if let sessionID = gestureCoordinator.handle(.candidateStarted(candidate)) {
                lastCandidateSessionID = sessionID
                let rejected = RecognizedGesture(
                    gesture: nil,
                    status: .error,
                    reason: .unknown,
                    durationMs: 100,
                    dx: 0, dy: 0
                )
                gestureCoordinator.handle(.primitiveRejected(rejected))
                // 无 interleaving await：candidateStarted 后立即 primitiveRejected 释放，
                // 无需先写 pendingCoordinatorGestureInfo 再删（死写，已移除）。
                pendingCoordinatorGestureInfo.removeValue(forKey: sessionID)
                lastCandidateSessionID = nil
            }
            writeProviderUnavailableTerminalState(
                gestureSessionId: command.gestureSessionId, operationId: command.operationId
            )
            return .accepted(gestureSessionId: command.gestureSessionId, operationId: command.operationId)

        case .resultUnknown:
            // 走完整链路派发 action，但最终回执由 deadline recovery 收敛。
            let candidate = GestureCandidate(
                startedAt: now, centroidX: 0.5, centroidY: 0.5, fingerCount: 3
            )
            if let sessionID = gestureCoordinator.handle(.candidateStarted(candidate)) {
                lastCandidateSessionID = sessionID
                pendingCoordinatorGestureInfo[sessionID] = .threeFingerTap
                let recognized = RecognizedGesture(
                    gesture: .threeFingerTap,
                    status: .success,
                    reason: .success,
                    durationMs: 100,
                    dx: 0, dy: 0,
                    centroidX: 0.5, centroidY: 0.5
                )
                gestureCoordinator.handle(.primitiveClassified(recognized))
            }
            return .accepted(gestureSessionId: command.gestureSessionId, operationId: command.operationId)
        }
    }

    /// actor 上下文的异步版 dispatch，供 E2EControlServer 回调使用。
    private func dispatchE2EOperation(_ command: E2ELinkOperationCommand) async -> E2EControlResult {
        dispatchE2EOperationSync(command)
    }

    /// provider 不可用终态写入 Journal。
    private func writeProviderUnavailableTerminalState(gestureSessionId: String, operationId: String) {
        guard let operationJournal else { return }
        operationJournalSequence += 1
        let event = ProviderEvent(
            eventId: UUID().uuidString,
            producerSessionId: appSessionId,
            producerSequence: operationJournalSequence,
            causedByEventId: nil,
            monotonicClockMs: currentTimestampMs(),
            wallClockMs: currentTimestampMs(),
            gestureSessionId: gestureSessionId,
            operationId: operationId,
            type: .actionResult,
            payload: .actionResult(ProviderActionResultPayload(
                operationId: operationId,
                outcome: .resultUnknown,
                reason: .guardExpired,
                completedAt: currentTimestampMs()
            ))
        )
        do {
            try operationJournal.append(event)
        } catch {
            logger.error("operation_journal_append_failed error=\"\(error)\"")
        }
    }

    /// coordinator 请求上下文：查活跃 Provider → 发 context_request。
    /// deadline 来自 coordinator 的单调时钟，但 provider 使用 wall clock；
    /// 因此 pending 校验和 provider 载荷都换算为 wall clock。
    private func handleCoordinatorContextRequest(sessionID: String, deadline: Int64) {
        guard let session = providerSessions.activeSession() else {
            logger.warn("authenticated_provider_unavailable", rateLimitKey: "authenticated_provider_unavailable")
            return
        }
        let wallDeadline = currentTimestampMs() + GestureSessionCoordinator.contextBudgetMs
        pendingCoordinatorSessions[sessionID] = (session.providerSessionID, wallDeadline)
        let gestureType = pendingCoordinatorGestureInfo[sessionID]?.rawValue ?? "unknown"
        let requiresTargetRef = pendingCoordinatorGestureInfo[sessionID] == .threeFingerTap
        let request = ProviderEnvelope(
            protocolVersion: 2, messageId: UUID().uuidString,
            providerSessionId: session.providerSessionID, gestureSessionId: sessionID,
            operationId: nil, type: .contextRequest, timestamp: currentTimestampMs(),
            payload: .contextRequest(ContextRequestPayload(
                gestureSessionId: sessionID,
                requiresTargetRef: requiresTargetRef,
                deadline: wallDeadline
            )), error: nil
        )
        do {
            try providerSessions.send(request, to: session.providerSessionID)
            logger.debug("coordinator_context_request gesture=\(gestureType) requiresTargetRef=\(requiresTargetRef) sessionId=\(sessionID)")
        } catch {
            pendingCoordinatorSessions.removeValue(forKey: sessionID)
            logger.warn("provider_context_send_failed gesture=\(gestureType)", rateLimitKey: "provider_context_send_failed")
        }
    }

    /// 候选刚出现便把由绑定配置导出的 guard 特征交给 Provider。这里不传手势名，
    /// 避免 Chrome 端依赖手指数或任何本地识别规则。
    private func handleCandidateGuardArm(sessionID: String, fingerCount: Int) {
        guard let session = providerSessions.activeSession(),
              let configuration = try? configurationMigration?.authoritativeConfiguration(),
              let plan = try? RecognitionPlan(configuration: configuration) else { return }
        let features = plan.candidateFeatures(fingerCount: fingerCount).map(\.rawValue).sorted()
        guard !features.isEmpty else { return }
        let deadline = currentTimestampMs() + 750
        let message = ProviderEnvelope(
            protocolVersion: 2, messageId: UUID().uuidString,
            providerSessionId: session.providerSessionID, gestureSessionId: sessionID,
            operationId: nil, type: .interactionGuardArm, timestamp: currentTimestampMs(),
            payload: .interactionGuardArm(InteractionGuardPayload(
                gestureSessionId: sessionID, features: features, deadline: deadline
            )), error: nil
        )
        do {
            try providerSessions.send(message, to: session.providerSessionID)
            logger.debug("candidate_guard_arm features=\(features.joined(separator: ",")) sessionId=\(sessionID)")
        } catch {
            logger.warn("candidate_guard_arm_send_failed", rateLimitKey: "candidate_guard_arm_send_failed")
        }
    }

    private func handleCandidateGuardRelease(sessionID: String) {
        guard let session = providerSessions.activeSession() else { return }
        let message = ProviderEnvelope(
            protocolVersion: 2, messageId: UUID().uuidString,
            providerSessionId: session.providerSessionID, gestureSessionId: sessionID,
            operationId: nil, type: .interactionGuardRelease, timestamp: currentTimestampMs(),
            payload: .interactionGuardRelease(InteractionGuardPayload(
                gestureSessionId: sessionID, features: [], deadline: currentTimestampMs()
            )), error: nil
        )
        try? providerSessions.send(message, to: session.providerSessionID)
    }

    /// coordinator 已解析出一个动作：发 action_request + 记入操作账本。
    private func handleCoordinatorAction(sessionID: String, action: ActionDescriptor) {
        guard let session = providerSessions.activeSession() else { return }
        var parameters = action.parameters
        if let version = try? configurationMigration?.authoritativeConfiguration().configurationVersion {
            parameters["configurationVersion"] = "\(version)"
        }
        let configuredAction = ActionDescriptor(actionId: action.actionId, contextId: action.contextId, targetRef: action.targetRef, parameters: parameters, deadline: action.deadline)
        let operationId = UUID().uuidString
        let request = ProviderEnvelope(
            protocolVersion: 2, messageId: UUID().uuidString,
            providerSessionId: session.providerSessionID, gestureSessionId: sessionID,
            operationId: operationId, type: .actionRequest, timestamp: currentTimestampMs(),
            payload: .actionRequest(configuredAction), error: nil
        )
        do {
            try providerSessions.send(request, to: session.providerSessionID)
            logger.info("coordinator_action_request action=\(configuredAction.actionId.rawValue) operationId=\(operationId) sessionId=\(sessionID)")
        } catch {
            logger.warn("action_request_send_failed operationId=\(operationId) action=\(action.actionId.rawValue)")
            return
        }
        appendOperationLifecycleEvent(request)
    }

    func refreshConfigurationSnapshot() {
        guard let session = providerSessions.activeSession() else { return }
        guard let snapshot = try? authoritativeConfigurationSnapshot() else { return }
        configurationAppliedByProvider = false
        let outbound = ProviderEnvelope(
            protocolVersion: 2,
            messageId: UUID().uuidString,
            providerSessionId: session.providerSessionID,
            gestureSessionId: nil,
            operationId: nil,
            type: .configurationSnapshot,
            timestamp: currentTimestampMs(),
            payload: .configurationSnapshot(snapshot),
            error: nil
        )
        try? providerSessions.send(outbound, to: session.providerSessionID)
        logger.debug(
            "configuration_snapshot_refreshed diagnosticLoggingEnabled=\(snapshot.diagnosticLoggingEnabled) providerSessionId=\(session.providerSessionID)",
            rateLimitKey: "configuration_snapshot_refreshed"
        )
    }

    private func scheduleExecutionTimeout(requestId: String, action: String, timestamp: Int64) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(1_500_000_000))
            guard let self, pendingRequests[requestId] != nil else { return }
            pendingRequests.removeValue(forKey: requestId)
            emit(event: AppMenuBarEvent(type: .chromeExecuted(
                action: action,
                success: false,
                detail: "执行超时"
            )))
            logger.warn("execution_timeout requestId=\(requestId) action=\(action)", rateLimitKey: "execution_timeout")
        }
    }

    private func handleActionResult(_ requestId: String, action: String, status: String, detailsText: String) {
        guard pendingRequests[requestId] != nil else { return }
        pendingRequests.removeValue(forKey: requestId)
        if status == "gesture_unstable" || status == "no_target" {
            logger.info("execution_result requestId=\(requestId) action=\(action) status=\(status) (no flash) \(detailsText)")
            return
        }
        let success = status == "success"
        let detail: String? = success ? nil : chromeActionFailureText(for: status)
        emit(event: AppMenuBarEvent(type: .chromeExecuted(action: action, success: success, detail: detail)))
        logger.info("execution_result requestId=\(requestId) action=\(action) success=\(success) \(detailsText)")
    }

    private func gestureMetrics(_ prefix: String, event: RecognizedGesture) -> String {
        let distance = hypotf(event.dx, event.dy)
        return String(
            format: "%@ duration_ms=%d dx=%.3f dy=%.3f distance=%.3f",
            prefix,
            event.durationMs,
            event.dx,
            event.dy,
            distance
        )
    }

    private func publishDiagnostic(for event: RecognizedGesture) {
        publishDiagnostic(DiagnosticEventPayload(
            source: .app,
            kind: .gesture,
            gesture: event.gesture,
            action: event.gesture.flatMap(actionType(for:)),
            status: event.status,
            reason: event.reason,
            swipeSensitivity: event.thresholds?.swipeSensitivity,
            dx: Double(event.dx),
            dy: Double(event.dy),
            distance: Double(hypotf(event.dx, event.dy)),
            durationMs: event.durationMs,
            horizontalRatio: horizontalRatio(dx: event.dx, dy: event.dy),
            thresholds: event.thresholds,
            message: nil
        ))
    }

    private func publishDiagnostic(_ payload: DiagnosticEventPayload) {
        let envelope = LocalIPCEnvelope(message: .diagnosticEvent(
            id: UUID().uuidString,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: payload
        ))
        _ = eventServer?.publish(envelope)
        diagnosticSink(envelope)
    }

    private func actionType(for gesture: GestureType) -> ActionType? {
        switch gesture {
        case .threeFingerTap: return .openLinkBackground
        case .threeFingerSwipeLeft: return .activateLeftTab
        case .threeFingerSwipeRight: return .activateRightTab
        }
    }

    private func horizontalRatio(dx: Float, dy: Float) -> Double? {
        guard dy != 0 else { return 999 }
        return Double(abs(dx / dy))
    }

    private func loggerFilePathHint() -> String {
        "~/Library/Logs/GestureKit/GestureKitApp.log"
    }

    private func detailValueText(_ value: DetailValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        }
    }

    private func currentTimestampMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

private extension Data {
    /// Provider Protocol v2 规定认证 HMAC 使用十六进制编码，拒绝奇数长度或非法字符。
    init?(hexEncoded value: String) {
        guard value.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
