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
        controlCenter = ControlCenterWindowController(control: control, dataSource: makeControlCenterDataSource(journal: journal))

        runtime?.start()

        // 开发预览开关：正常启动仍保持菜单栏 accessory 行为。
        if ProcessInfo.processInfo.environment["GESTUREKIT_SHOW_CONTROL_CENTER"] == "1" {
            DispatchQueue.main.async { [weak self] in self?.showControlCenter() }
        }
    }

    private func showControlCenter() {
        controlCenter?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
