import Foundation
import GestureKitCore

@MainActor
final class GestureKitRuntime {
    private let statusHandler: (String) -> Void
    private var recognizer = GestureRecognizer()
    private let ruleEngine: RuleEngine
    private let appContextResolver = AppContextResolver()
    private let touchBackend: any TouchBackend
    private let settingsStore: any SettingsStore
    private let logger: GestureKitLogger
    private var listeningTask: Task<Void, Never>?
    private var eventServer: LocalEventServer?

    init(
        statusHandler: @escaping (String) -> Void,
        touchBackend: any TouchBackend = MultitouchSupportBackend(),
        settingsStore: any SettingsStore = UserDefaultsSettingsStore(),
        logger: GestureKitLogger = GestureKitLogger()
    ) {
        self.statusHandler = statusHandler
        self.touchBackend = touchBackend
        self.settingsStore = settingsStore
        self.logger = logger
        self.ruleEngine = RuleEngine(rules: (try? settingsStore.loadRules()) ?? DefaultRules.v1)
    }

    func start() {
        do {
            let server = try LocalEventServer(logger: logger)
            server.start()
            eventServer = server
        } catch {
            statusHandler("GestureKit: IPC Error")
            logger.error("ipc_listener_start_failed error=\"\(error)\"")
        }

        statusHandler("GestureKit: On")
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
        statusHandler("GestureKit: Off")
        logger.info("app_stopped", terminal: true)
    }

    private func startTouchListening() {
        listeningTask = Task { @MainActor in
            for await frame in touchBackend.frames {
                guard !Task.isCancelled else { return }
                guard let event = recognizer.observe(frame) else { continue }
                guard let gesture = event.gesture else {
                    logger.debug(gestureMetrics("gesture_unstable", event: event), rateLimitKey: "gesture_unstable")
                    continue
                }
                logger.info(gestureMetrics("gesture_recognized gesture=\(gesture.rawValue)", event: event))
                handle(event)
            }
        }

        guard touchBackend.start() else {
            statusHandler("GestureKit: Input Error")
            logger.error("touch_backend_start_failed")
            return
        }
        logger.info("touch_backend_started")
    }

    private func handle(_ event: RecognizedGesture) {
        guard let gesture = event.gesture else { return }
        let elementType: ElementType = gesture == .threeFingerTap ? .link : .any
        let context = appContextResolver.currentContext(elementType: elementType)
        guard ruleEngine.match(gesture: gesture, context: context) != nil else {
            statusHandler(context.browserKind == .chrome ? "GestureKit: No Rule" : "GestureKit: Unsupported App")
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
        statusHandler("GestureKit: \(gesture.rawValue)")
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

    private func loggerFilePathHint() -> String {
        "~/Library/Logs/GestureKit/GestureKitApp.log"
    }
}
