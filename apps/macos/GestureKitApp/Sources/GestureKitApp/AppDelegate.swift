import AppKit
import GestureKitCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GestureKitRuntime?
    private var control: RuntimeControl?
    private var menuBar: MenuBarController?
    private var controlCenter: ControlCenterWindowController?
    private let settingsStore = UserDefaultsSettingsStore()
    private var operationJournal: (any OperationJournaling)?
    private let e2eControlToken: String?
    private var singleInstanceLockFD: Int32?

    init(e2eControlToken: String?) {
        self.e2eControlToken = e2eControlToken
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护：flock 独占锁已被持有说明已有实例在运行，退出重复实例。
        guard let singleInstanceLockFD = SingleInstanceGuard.acquireLock() else {
            print("GestureKitApp 已在运行，退出重复实例")
            NSApp.terminate(nil)
            return
        }
        self.singleInstanceLockFD = singleInstanceLockFD

        let journal = try? OperationJournal(path: journalURL().path)
        operationJournal = journal
        runtime = GestureKitRuntime(menuBarHandler: { [weak self] event in
            self?.menuBar?.apply(event: event)
        }, settingsStore: settingsStore, operationJournal: journal, controlCenterOpenHandler: { [weak self] in
            self?.showControlCenter()
        }, e2eControlToken: e2eControlToken)
        let control = RuntimeControl(runtime: runtime!)
        self.control = control
        let menuBar = MenuBarController(control: control) { [weak self] in
            self?.showControlCenter()
        }
        self.menuBar = menuBar
        controlCenter = ControlCenterWindowController(
            control: control,
            dataSource: makeControlCenterDataSource(journal: journal),
            onWindowClose: { [weak self] in self?.controlCenterWindowDidClose() }
        )

        installMainMenu()

        runtime?.start()

        // 开发预览开关：正常启动仍保持菜单栏 accessory 行为。
        if ProcessInfo.processInfo.environment["GESTUREKIT_SHOW_CONTROL_CENTER"] == "1" {
            DispatchQueue.main.async { [weak self] in self?.showControlCenter() }
        }
    }

    private func showControlCenter() {
        // 打开窗口时切到 .regular，让控制中心成为行为正常的应用窗口：可被切走、能退到其它窗口后面。
        NSApp.setActivationPolicy(.regular)
        controlCenter?.showWindow(nil)
        controlCenter?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 窗口处于 .regular 期间点击 Dock 图标时重新打开控制中心。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlCenter()
        return true
    }

    private func controlCenterWindowDidClose() {
        // 控制中心是唯一窗口，关闭后回到菜单栏 accessory 形态并归还焦点。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
            self.menuBar?.refreshForPolicySwitch()
        }
    }

    /// 提供最小 App 菜单：切到 .regular 后 App 会成为活跃应用，避免空菜单占顶栏。
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "关于 GestureKit",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 GestureKit", action: #selector(quitFromMenu), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func quitFromMenu() {
        control?.quitApplication()
    }

    private func makeControlCenterDataSource(journal: (any OperationJournaling)?) -> any ControlCenterDataSource {
        guard let journal else {
            return PreviewControlCenterDataSource()
        }
        return RuntimeControlCenterDataSource(
            journal: journal,
            configurationStore: settingsStore,
            health: { [weak self] in self?.runtime?.controlCenterHealth ?? .preparing },
            loadUserBindings: { [weak self] in (try self?.settingsStore.loadBindingOverrides()) ?? [] },
            updateBinding: { [weak self] id, enabled in try self?.runtime?.updateBinding(id: id, enabled: enabled) },
            updateGestureBinding: { [weak self] gid, actionID, enabled in
                try self?.runtime?.updateGestureBinding(gestureDefinitionID: gid, actionID: actionID, enabled: enabled)
            },
            updateSensitivity: { [weak self] value in try self?.runtime?.updateSensitivity(value) },
            restoreDefaults: { [weak self] in try self?.runtime?.restoreDefaultConfiguration() }
        )
    }

    private func journalURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestureKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("operations.sqlite")
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
        SingleInstanceGuard.releaseLock(fd: singleInstanceLockFD)
        singleInstanceLockFD = nil
    }
}
