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
    private var listeningTask: Task<Void, Never>?
    private var eventServer: LocalEventServer?

    init(
        statusHandler: @escaping (String) -> Void,
        touchBackend: any TouchBackend = MultitouchSupportBackend(),
        settingsStore: any SettingsStore = UserDefaultsSettingsStore()
    ) {
        self.statusHandler = statusHandler
        self.touchBackend = touchBackend
        self.settingsStore = settingsStore
        self.ruleEngine = RuleEngine(rules: (try? settingsStore.loadRules()) ?? DefaultRules.v1)
    }

    func start() {
        do {
            let server = try LocalEventServer()
            server.start()
            eventServer = server
        } catch {
            statusHandler("GestureKit: IPC Error")
        }

        statusHandler("GestureKit: On")
        startTouchListening()
    }

    func stop() {
        listeningTask?.cancel()
        listeningTask = nil
        eventServer?.stop()
        eventServer = nil
        _ = touchBackend.stop()
        statusHandler("GestureKit: Off")
    }

    private func startTouchListening() {
        listeningTask = Task { @MainActor in
            for await frame in touchBackend.frames {
                guard !Task.isCancelled else { return }
                guard let event = recognizer.observe(frame), let gesture = event.gesture else { continue }
                handle(gesture)
            }
        }

        guard touchBackend.start() else {
            statusHandler("GestureKit: Input Error")
            return
        }
    }

    private func handle(_ gesture: GestureType) {
        let elementType: ElementType = gesture == .threeFingerTap ? .link : .any
        let context = appContextResolver.currentContext(elementType: elementType)
        guard ruleEngine.match(gesture: gesture, context: context) != nil else {
            statusHandler(context.browserKind == .chrome ? "GestureKit: No Rule" : "GestureKit: Unsupported App")
            return
        }
        let envelope = LocalIPCEnvelope.gesture(
            id: UUID().uuidString,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            gesture: gesture,
            appBundleId: context.appBundleId
        )
        eventServer?.publish(envelope)
        statusHandler("GestureKit: \(gesture.rawValue)")
    }
}
