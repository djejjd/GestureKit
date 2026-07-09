import AppKit

@MainActor
final class MenuBarController {
    private let item: NSStatusItem
    private let menu: NSMenu
    private let statusItem: NSMenuItem
    private let control: any RuntimeControlling
    private var currentState: AppMenuBarState = .normal
    private var flashTimer: Timer?
    private var pauseTimer: Timer?
    private var baseIcon: NSImage?

    init(control: any RuntimeControlling) {
        self.control = control

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = NSImage(contentsOf: Bundle.module.url(forResource: "menu_icon", withExtension: "svg")!) {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            baseIcon = icon
            item.button?.image = icon
        }
        item.button?.title = ""

        menu = NSMenu()

        statusItem = NSMenuItem(title: "GestureKit 正常运行", action: nil, keyEquivalent: "")
        menu.addItem(statusItem)

        let gestureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        gestureItem.isHidden = true
        gestureItem.tag = 1
        menu.addItem(gestureItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("暂停手势 10 分钟", #selector(togglePause)))
        menu.addItem(actionItem("打开日志目录", #selector(openLogs)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("退出", #selector(quit)))
        item.menu = menu
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func apply(event: AppMenuBarEvent) {
        switch event.type {
        case .gestureRecognized(let gesture):
            handleGestureRecognized(gesture: gesture)
        case .gestureWarning(let reason):
            handleGestureWarning(reason: reason)
        case .appError(let reason):
            handleAppError(reason: reason)
        case .appRecovered:
            handleAppRecovered()
        case .paused:
            handlePaused()
        case .resumed:
            handleResumed()
        }
    }

    private func handleGestureRecognized(gesture: String) {
        guard !isErrorOrPaused else { return }
        let label = gestureLabelMap[gesture] ?? gesture
        currentState = .gestureRecognized(gesture: gesture)
        setTint(.green)
        statusItem.title = "GestureKit 正常运行"
        setGestureText("最近手势：\(label)已识别")
        scheduleFlashReset()
    }

    private var isErrorOrPaused: Bool {
        if case .appError = currentState { return true }
        if case .paused = currentState { return true }
        return false
    }

    private func handleGestureWarning(reason: String) {
        guard !isErrorOrPaused else { return }
        currentState = .gestureWarning(reason: reason)
        setTint(.yellow)
        statusItem.title = "GestureKit 正常运行"
        let text = warningText(for: reason)
        setGestureText("上次手势未生效：\(text)")
        scheduleFlashReset()
    }

    private func handleAppError(reason: String) {
        currentState = .appError(reason: reason)
        setTint(.red)
        statusItem.title = "GestureKit 异常"
        let text = errorText(for: reason)
        setGestureText(text)
        cancelFlashReset()
    }

    private func handleAppRecovered() {
        currentState = .normal
        setTint(.default)
        statusItem.title = "GestureKit 正常运行"
        setGestureText(nil)
    }

    private func handlePaused() {
        currentState = .paused
        setTint(.gray)
        statusItem.title = "GestureKit 已暂停"
        setGestureText(nil)
        updatePauseMenuItem(isPaused: true)
        cancelFlashReset()
    }

    private func handleResumed() {
        currentState = .normal
        setTint(.default)
        statusItem.title = "GestureKit 正常运行"
        setGestureText(nil)
        updatePauseMenuItem(isPaused: false)
    }

    private func setTint(_ color: MenuBarIconTint) {
        guard let icon = baseIcon?.copy() as? NSImage else { return }
        icon.isTemplate = (color == .default)
        if !icon.isTemplate {
            icon.lockFocus()
            color.nsColor.set()
            NSRect(origin: .zero, size: icon.size).fill(using: .sourceAtop)
            icon.unlockFocus()
        }
        item.button?.image = icon
    }

    private func setGestureText(_ text: String?) {
        if let item = menu.item(withTag: 1) {
            if let text {
                item.title = text
                item.isHidden = false
            } else {
                item.isHidden = true
            }
        }
    }

    private func scheduleFlashReset() {
        cancelFlashReset()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetToNormal()
            }
        }
    }

    private func cancelFlashReset() {
        flashTimer?.invalidate()
        flashTimer = nil
    }

    private func resetToNormal() {
        switch currentState {
        case .gestureRecognized, .gestureWarning:
            currentState = .normal
            setTint(.default)
            setGestureText(nil)
        default:
            break
        }
    }

    private func updatePauseMenuItem(isPaused: Bool) {
        for item in menu.items {
            if item.action == #selector(togglePause) {
                item.title = isPaused ? "恢复手势" : "暂停手势 10 分钟"
                break
            }
        }
    }

    @objc private func togglePause() {
        if case .paused = currentState {
            control.resumeListening()
        } else {
            control.pauseListening()
        }
    }

    @objc private func openLogs() { control.openLogDirectory() }
    @objc private func quit() { control.quitApplication() }

    func currentStateForTesting() -> AppMenuBarState { currentState }
    func statusTextForTesting() -> String { statusItem.title }

    func triggerGestureRecognizedForTesting(gesture: String) {
        apply(event: AppMenuBarEvent(type: .gestureRecognized(gesture: gesture)))
    }
    func triggerGestureWarningForTesting(reason: String) {
        apply(event: AppMenuBarEvent(type: .gestureWarning(reason: reason)))
    }
    func triggerAppErrorForTesting(reason: String) {
        apply(event: AppMenuBarEvent(type: .appError(reason: reason)))
    }
    func triggerPausedForTesting() {
        apply(event: AppMenuBarEvent(type: .paused))
    }
    func triggerResumedForTesting() {
        apply(event: AppMenuBarEvent(type: .resumed))
    }
}

enum MenuBarIconTint {
    case `default`
    case green
    case yellow
    case red
    case gray

    var nsColor: NSColor {
        switch self {
        case .default: return .controlTextColor
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .red: return .systemRed
        case .gray: return .systemGray
        }
    }
}

private func warningText(for reason: String) -> String {
    if let r = AppWarningReason(rawValue: reason) {
        return appWarningReasonTextMap[r] ?? reason
    }
    return "未识别为有效手势"
}

private func errorText(for reason: String) -> String {
    if let r = AppErrorReason(rawValue: reason) {
        return appErrorReasonTextMap[r] ?? reason
    }
    return reason
}
