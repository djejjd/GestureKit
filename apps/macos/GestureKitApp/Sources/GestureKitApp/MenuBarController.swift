import AppKit

@MainActor
final class MenuBarController {
    private let item: NSStatusItem
    private let menu: NSMenu
    private let listeningItem = NSMenuItem(title: "监听：启动中", action: nil, keyEquivalent: "")
    private let connectionItem = NSMenuItem(title: "连接：未知", action: nil, keyEquivalent: "")
    private let gestureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let errorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let control: any RuntimeControlling

    init(control: any RuntimeControlling) {
        self.control = control

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "GestureKit"

        menu = NSMenu()
        menu.addItem(listeningItem)
        menu.addItem(connectionItem)
        menu.addItem(gestureItem)
        gestureItem.isHidden = true
        menu.addItem(errorItem)
        errorItem.isHidden = true
        menu.addItem(NSMenuItem.separator())

        menu.addItem(actionItem("刷新状态", #selector(refresh)))
        menu.addItem(actionItem("启动监听", #selector(startListeningAction)))
        menu.addItem(actionItem("停止监听", #selector(stopListeningAction)))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(actionItem("打开日志目录", #selector(openLogs)))
        menu.addItem(actionItem("打开安装说明", #selector(openInstall)))
        menu.addItem(actionItem("打开排障文档", #selector(openTroubleshooting)))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(actionItem("退出", #selector(quit)))
        item.menu = menu
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func apply(status: AppRuntimeStatus) {
        item.button?.title = "GestureKit"
        listeningItem.title = "监听：\(listeningLabel(status.listeningState))"
        connectionItem.title = "连接：\(connectionLabel(status.connectionState))"

        if let gesture = status.lastGesture {
            gestureItem.title = "最近手势：\(gestureLabel(gesture))"
            gestureItem.isHidden = false
        } else {
            gestureItem.isHidden = true
        }

        if let error = status.lastError, !error.isEmpty {
            errorItem.title = "最近错误：\(error)"
            errorItem.isHidden = false
        } else {
            errorItem.isHidden = true
        }
    }

    func statusTitlesForTesting() -> [String] {
        var titles = [listeningItem.title, connectionItem.title]
        if !gestureItem.isHidden { titles.append(gestureItem.title) }
        if !errorItem.isHidden { titles.append(errorItem.title) }
        return titles.filter { !$0.isEmpty }
    }

    @objc private func refresh() { control.refreshStatus() }
    @objc private func startListeningAction() { control.startListening() }
    @objc private func stopListeningAction() { control.stopListening() }
    @objc private func openLogs() { control.openLogDirectory() }
    @objc private func openInstall() { control.openInstallGuide() }
    @objc private func openTroubleshooting() { control.openTroubleshootingGuide() }
    @objc private func quit() { control.quitApplication() }

    func triggerRefreshForTesting() { control.refreshStatus() }
    func triggerOpenTroubleshootingForTesting() { control.openTroubleshootingGuide() }
    func triggerStopForTesting() { control.stopListening() }
    func triggerStartForTesting() { control.startListening() }
}

private func listeningLabel(_ state: AppListeningState) -> String {
    switch state {
    case .starting: return "启动中"
    case .listening: return "运行中"
    case .stopped: return "已停止"
    case .inputError: return "输入错误"
    case .ipcError: return "IPC 错误"
    }
}

private func connectionLabel(_ state: AppConnectionState) -> String {
    switch state {
    case .unknown: return "未知"
    case .disconnected: return "未连接"
    case .connected(let count): return "已连接(\(count))"
    }
}

private func gestureLabel(_ raw: String) -> String {
    switch raw {
    case "three_finger_tap": return "点按"
    case "three_finger_swipe_left": return "左轻扫"
    case "three_finger_swipe_right": return "右轻扫"
    default: return raw
    }
}
