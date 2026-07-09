import Foundation
import GestureKitCore

@MainActor
final class GestureKitRuntime {
    private let statusHandler: (AppRuntimeStatus) -> Void
    private var recognizer = GestureRecognizer()
    private let ruleEngine: RuleEngine
    private let appContextResolver = AppContextResolver()
    private let touchBackend: any TouchBackend
    private let settingsStore: any SettingsStore
    private let logger: GestureKitLogger
    private let diagnosticSink: (LocalIPCEnvelope) -> Void
    private var listeningTask: Task<Void, Never>?
    private var eventServer: LocalEventServer?
    private let appSessionId: String
    private var currentStatus: AppRuntimeStatus

    init(
        statusHandler: @escaping (AppRuntimeStatus) -> Void,
        touchBackend: any TouchBackend = MultitouchSupportBackend(),
        settingsStore: any SettingsStore = UserDefaultsSettingsStore(),
        logger: GestureKitLogger = GestureKitLogger(),
        diagnosticSink: @escaping (LocalIPCEnvelope) -> Void = { _ in }
    ) {
        self.statusHandler = statusHandler
        self.touchBackend = touchBackend
        self.settingsStore = settingsStore
        self.logger = logger
        self.diagnosticSink = diagnosticSink
        self.ruleEngine = RuleEngine(rules: (try? settingsStore.loadRules()) ?? DefaultRules.v1)
        self.appSessionId = UUID().uuidString
        self.currentStatus = AppRuntimeStatus(
            listeningState: .starting,
            connectionState: .unknown,
            lastGesture: nil,
            lastError: nil,
            logFilePathHint: "~/Library/Logs/GestureKit/GestureKitApp.log"
        )
    }

    func start() {
        do {
            let server = try LocalEventServer(logger: logger) { [weak self] envelope in
                Task { @MainActor [weak self] in
                    self?.handleIPCEnvelope(envelope)
                }
            }
            server.onConnectionCountChanged = { [weak self] count in
                Task { @MainActor [weak self] in
                    self?.publishStatus(connectionState: count > 0 ? .connected(clientCount: count) : .disconnected)
                }
            }
            server.start()
            eventServer = server
        } catch {
            publishStatus(listeningState: .ipcError, lastError: "ipc_listener_start_failed")
            logger.error("ipc_listener_start_failed error=\"\(error)\"")
            return
        }

        publishStatus(listeningState: .listening)
        logger.info(
            "app_started log_file=\"\(loggerFilePathHint())\" debug=\(ProcessInfo.processInfo.environment["GESTUREKIT_DEBUG"] == "1")",
            terminal: true
        )
        startTouchListening()
    }

    func stop() {
        listeningTask?.cancel()
        listeningTask = nil
        eventServer?.stop()
        eventServer = nil
        _ = touchBackend.stop()
        publishStatus(listeningState: .stopped, connectionState: .disconnected)
        logger.info("app_stopped", terminal: true)
    }

    func refreshStatus() {
        let connectionCount = eventServer?.connectionCount() ?? 0
        publishStatus(connectionState: connectionCount > 0 ? .connected(clientCount: connectionCount) : .disconnected)
    }

    private func publishStatus(
        listeningState: AppListeningState? = nil,
        connectionState: AppConnectionState? = nil,
        lastGesture: String? = nil,
        lastError: String? = nil
    ) {
        currentStatus = AppRuntimeStatus(
            listeningState: listeningState ?? currentStatus.listeningState,
            connectionState: connectionState ?? currentStatus.connectionState,
            lastGesture: lastGesture ?? currentStatus.lastGesture,
            lastError: lastError,
            logFilePathHint: loggerFilePathHint()
        )
        statusHandler(currentStatus)
    }

    private func startTouchListening() {
        listeningTask = Task { @MainActor in
            for await frame in touchBackend.frames {
                guard !Task.isCancelled else { return }
                _ = processFrame(frame)
            }
        }

        guard touchBackend.start() else {
            publishStatus(listeningState: .inputError, lastError: "touch_backend_start_failed")
            logger.error("touch_backend_start_failed")
            return
        }
        logger.info("touch_backend_started")
    }

    @discardableResult
    private func processFrame(_ frame: TouchFrame) -> RecognizedGesture? {
        guard let event = recognizer.observe(frame) else { return nil }
        publishDiagnostic(for: event)
        guard let gesture = event.gesture else {
            logger.debug(gestureMetrics("gesture_unstable", event: event), rateLimitKey: "gesture_unstable")
            return event
        }
        logger.info(gestureMetrics("gesture_recognized gesture=\(gesture.rawValue)", event: event))
        handle(event)
        return event
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
        let envelope = LocalIPCEnvelope.gesture(
            id: UUID().uuidString,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            gesture: gesture,
            appBundleId: context.appBundleId,
            touchX: event.centroidX.map(Double.init),
            durationMs: event.durationMs
        )
        let connectionCount = eventServer?.publish(envelope) ?? 0
        if connectionCount == 0 {
            logger.warn(
                "gesture_published_without_client gesture=\(gesture.rawValue) appBundleId=\(context.appBundleId) connections=0",
                rateLimitKey: "published_without_client"
            )
        } else {
            logger.info("gesture_published gesture=\(gesture.rawValue) appBundleId=\(context.appBundleId) connections=\(connectionCount)")
        }
        publishStatus(lastGesture: gesture.rawValue)
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

    func observeForTesting(_ frame: TouchFrame) -> RecognizedGesture? {
        recognizer.observe(frame)
    }

    func processFrameForTesting(_ frame: TouchFrame) -> RecognizedGesture? {
        processFrame(frame)
    }

    func handleProbeRequestForTesting(id: String) -> GestureKitMessage {
        handleProbeRequest(id).message
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
            let details = payload.details?.map { "\($0.key)=\($0.value)" }.joined(separator: " ") ?? ""
            logger.info(
                "action_result action=\(payload.action.rawValue) status=\(payload.status.rawValue) \(details)",
                rateLimitKey: "action_result_\(payload.action.rawValue)"
            )
            return
        }

        guard let payload = envelope.message.settingsUpdatePayload else {
            return
        }
        let ack = applySettingsUpdate(payload)
        let ackEnvelope = LocalIPCEnvelope(message: .settingsAck(
            id: envelope.id,
            timestamp: currentTimestampMs(),
            payload: ack
        ))
        _ = eventServer?.publish(ackEnvelope)
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
        case .threeFingerTap:
            return .openLinkBackground
        case .threeFingerSwipeLeft:
            return .activateLeftTab
        case .threeFingerSwipeRight:
            return .activateRightTab
        }
    }

    private func horizontalRatio(dx: Float, dy: Float) -> Double? {
        guard dy != 0 else { return 999 }
        return Double(abs(dx / dy))
    }

    private func loggerFilePathHint() -> String {
        "~/Library/Logs/GestureKit/GestureKitApp.log"
    }

    private func currentTimestampMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
