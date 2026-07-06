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
        statusHandler("GestureKit: On")
        startTouchListening()
    }

    func stop() {
        listeningTask?.cancel()
        listeningTask = nil
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
        statusHandler("GestureKit: \(gesture.rawValue)")
    }
}
