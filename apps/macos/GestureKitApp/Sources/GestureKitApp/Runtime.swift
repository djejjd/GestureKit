import Foundation
import GestureKitCore

private enum AppConfigurationUnavailable: Error {
    case storeUnavailable
}

@MainActor
final class GestureKitRuntime {
    private let menuBarHandler: (AppMenuBarEvent) -> Void
    private var recognizer = GestureRecognizer()
    private let ruleEngine: RuleEngine
    private let appContextResolver = AppContextResolver()
    private let touchBackend: any TouchBackend
    private let settingsStore: any SettingsStore
    private let configurationMigration: ConfigurationMigration?
    private let logger: GestureKitLogger
    /// 与控制中心共用的操作账本；仅记录已进入 Provider 操作生命周期的事件。
    private let operationJournal: (any OperationJournaling)?
    private let diagnosticSink: (LocalIPCEnvelope) -> Void
    private var listeningTask: Task<Void, Never>?
    private var eventServer: LocalEventServer?
    private let providerSessions = ProviderSessionRegistry()
    private let appSessionId: String
    private var internalState = AppInternalStatus()
    private var isPaused = false
    private var pendingRequests: [String: (action: String, timestamp: Int64)] = [:]
    /// 等待 Provider context_snapshot 的手势；仅认证 v2 session 可写入。
    private var pendingContextGestures: [String: (gesture: GestureType, providerSessionID: String, deadline: Int64)] = [:]
    private let executionTimeoutMs: Int64 = 1500
    private var configurationAppliedByProvider: Bool?
    private var operationJournalSequence: Int64 = 0

    init(
        menuBarHandler: @escaping (AppMenuBarEvent) -> Void,
        touchBackend: any TouchBackend = MultitouchSupportBackend(),
        settingsStore: any SettingsStore = UserDefaultsSettingsStore(),
        logger: GestureKitLogger = GestureKitLogger(),
        operationJournal: (any OperationJournaling)? = nil,
        diagnosticSink: @escaping (LocalIPCEnvelope) -> Void = { _ in }
    ) {
        self.menuBarHandler = menuBarHandler
        self.touchBackend = touchBackend
        self.settingsStore = settingsStore
        self.configurationMigration = (settingsStore as? any AppConfigurationStore)
            .map(ConfigurationMigration.init(store:))
        self.logger = logger
        self.operationJournal = operationJournal
        self.diagnosticSink = diagnosticSink
        self.ruleEngine = RuleEngine(rules: (try? settingsStore.loadRules()) ?? DefaultRules.v1)
        self.appSessionId = UUID().uuidString
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
        handle(event)
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

    private func handle(_ event: RecognizedGesture) {
        guard let gesture = event.gesture else { return }
        let elementType: ElementType = gesture == .threeFingerTap ? .link : .any
        let context = appContextResolver.currentContext(elementType: elementType)
        guard ruleEngine.match(gesture: gesture, context: context) != nil else {
            if context.browserKind == .chrome {
                logger.warn("no_rule gesture=\(gesture.rawValue) appBundleId=\(context.appBundleId)", rateLimitKey: "no_rule_\(gesture.rawValue)")
            } else {
                logger.warn("unsupported_app gesture=\(gesture.rawValue) appBundleId=\(context.appBundleId)", rateLimitKey: "unsupported_app")
            }
            return
        }
        guard let session = providerSessions.activeSession() else {
            logger.warn("authenticated_provider_unavailable", rateLimitKey: "authenticated_provider_unavailable")
            return
        }
        let gestureSessionID = UUID().uuidString
        let now = currentTimestampMs()
        let request = ProviderEnvelope(
            protocolVersion: 2, messageId: UUID().uuidString,
            providerSessionId: session.providerSessionID, gestureSessionId: gestureSessionID,
            operationId: nil, type: .contextRequest, timestamp: now,
            payload: .contextRequest(ContextRequestPayload(gestureSessionId: gestureSessionID, deadline: now + executionTimeoutMs)), error: nil
        )
        do {
            pendingContextGestures[gestureSessionID] = (gesture, session.providerSessionID, now + executionTimeoutMs)
            try providerSessions.send(request, to: session.providerSessionID)
        } catch {
            pendingContextGestures.removeValue(forKey: gestureSessionID)
            logger.warn("provider_context_send_failed", rateLimitKey: "provider_context_send_failed")
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
        switch internalState.listeningState {
        case .inputError, .ipcError:
            return .listeningUnavailable
        case .idle, .stopped:
            return .preparing
        case .running:
            guard let session = providerSessions.activeSession() else { return .disconnected }
            return .connected(capabilityCount: session.capabilities.count, configurationApplied: configurationAppliedByProvider)
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
    private func handleProviderEnvelope(_ data: Data, connectionID: UUID, server: LocalEventServer) {
        guard let envelope = try? JSONDecoder().decode(ProviderEnvelope.self, from: data) else {
            logger.warn("provider_v2_decode_rejected", rateLimitKey: "provider_v2_decode_rejected")
            return
        }
        switch (envelope.type, envelope.payload) {
        case (.providerHello, .providerHello(let hello)):
            guard let nonce = try? providerSessions.beginAuthentication(hello) else { return }
            let challenge = ProviderEnvelope(protocolVersion: 2, messageId: UUID().uuidString, providerSessionId: envelope.providerSessionId, gestureSessionId: nil, operationId: nil, type: .providerChallenge, timestamp: currentTimestampMs(), payload: .providerChallenge(ProviderChallengePayload(nonce: nonce.base64EncodedString(), expiresAt: currentTimestampMs() + 30_000)), error: nil)
            try? server.send(challenge, to: connectionID)
        case (.providerAuthenticate, .providerAuthenticate(let authentication)):
            guard let response = Data(hexEncoded: authentication.hmac) else { return }
            guard let session = try? providerSessions.authenticate(
                installId: authentication.installId,
                response: response,
                connectionID: connectionID,
                sink: { [weak server] outbound in
                try? server?.send(outbound, to: connectionID)
                }
            ) else { return }
            configurationAppliedByProvider = false
            guard let snapshot = try? authoritativeConfigurationSnapshot() else { return }
            let outbound = ProviderEnvelope(
                protocolVersion: 2, messageId: UUID().uuidString,
                providerSessionId: session.providerSessionID, gestureSessionId: nil,
                operationId: nil, type: .configurationSnapshot, timestamp: currentTimestampMs(),
                payload: .configurationSnapshot(snapshot), error: nil
            )
            try? providerSessions.send(outbound, to: session.providerSessionID)
        case (.configurationAck, .configurationAck(let acknowledgement)):
            guard let session = providerSessions.activeSession(),
                  envelope.providerSessionId == session.providerSessionID,
                  providerSessions.session(session.providerSessionID, belongsTo: connectionID) else { return }
            logger.info(
                "provider_configuration_ack applied=\(acknowledgement.applied) version=\(acknowledgement.appliedVersion)",
                rateLimitKey: "provider_configuration_ack"
            )
            configurationAppliedByProvider = acknowledgement.applied
        case (.contextSnapshot, .contextSnapshot(let snapshot)):
            guard let gestureID = envelope.gestureSessionId,
                  let pending = pendingContextGestures[gestureID],
                  let session = providerSessions.activeSession(),
                  pending.providerSessionID == session.providerSessionID,
                  envelope.providerSessionId == session.providerSessionID,
                  providerSessions.session(session.providerSessionID, belongsTo: connectionID),
                  envelope.error == nil,
                  snapshot.expiresAt >= currentTimestampMs(),
                  pending.deadline >= currentTimestampMs() else { return }
            pendingContextGestures.removeValue(forKey: gestureID)
            let gesture = pending.gesture
            let actionID: StandardActionID
            switch gesture {
            case .threeFingerTap:
                guard snapshot.targetKind == .standardLink, let targetRef = snapshot.targetRef else { return }
                actionID = .browserLinkOpenAdjacent
                let action = ActionDescriptor(actionId: actionID, contextId: snapshot.contextId, targetRef: targetRef, parameters: [:], deadline: currentTimestampMs() + executionTimeoutMs)
                let request = ProviderEnvelope(protocolVersion: 2, messageId: UUID().uuidString, providerSessionId: session.providerSessionID, gestureSessionId: gestureID, operationId: UUID().uuidString, type: .actionRequest, timestamp: currentTimestampMs(), payload: .actionRequest(action), error: nil)
                try? providerSessions.send(request, to: session.providerSessionID)
                appendOperationLifecycleEvent(request)
            case .threeFingerSwipeLeft, .threeFingerSwipeRight:
                actionID = gesture == .threeFingerSwipeLeft ? .browserTabActivateNext : .browserTabActivatePrevious
                let action = ActionDescriptor(actionId: actionID, contextId: snapshot.contextId, targetRef: nil, parameters: [:], deadline: currentTimestampMs() + executionTimeoutMs)
                let request = ProviderEnvelope(protocolVersion: 2, messageId: UUID().uuidString, providerSessionId: session.providerSessionID, gestureSessionId: gestureID, operationId: UUID().uuidString, type: .actionRequest, timestamp: currentTimestampMs(), payload: .actionRequest(action), error: nil)
                try? providerSessions.send(request, to: session.providerSessionID)
                appendOperationLifecycleEvent(request)
            }
        case (.actionAccepted, .actionAccepted), (.actionResult, .actionResult):
            guard let session = providerSessions.activeSession(),
                  envelope.providerSessionId == session.providerSessionID,
                  providerSessions.session(session.providerSessionID, belongsTo: connectionID) else { return }
            appendOperationLifecycleEvent(envelope)
        default:
            logger.warn("provider_v2_unauthorized_message", rateLimitKey: "provider_v2_unauthorized_message")
        }
    }

    /// 将已验证的 Provider 操作消息追加到控制中心读取的同一账本。
    func appendOperationLifecycleEvent(_ envelope: ProviderEnvelope) {
        guard let operationJournal, envelope.operationId != nil else { return }
        operationJournalSequence += 1
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

    private func chromeAction(from gesture: GestureType) -> String {
        switch gesture {
        case .threeFingerSwipeLeft: return "activate_right_tab"
        case .threeFingerSwipeRight: return "activate_left_tab"
        case .threeFingerTap: return "open_link_background"
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
            configJSON: String(decoding: data, as: UTF8.self)
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
