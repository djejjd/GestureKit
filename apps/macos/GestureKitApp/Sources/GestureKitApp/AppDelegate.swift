import AppKit
import GestureKitCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GestureKitRuntime?
    private var control: RuntimeControl?
    private var menuBar: MenuBarController?
    private var controlCenter: ControlCenterWindowController?
    private let settingsStore = UserDefaultsSettingsStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        runtime = GestureKitRuntime(menuBarHandler: { [weak self] event in
            self?.menuBar?.apply(event: event)
        }, settingsStore: settingsStore)
        let control = RuntimeControl(runtime: runtime!)
        self.control = control
        let menuBar = MenuBarController(control: control) { [weak self] in
            self?.showControlCenter()
        }
        self.menuBar = menuBar
        controlCenter = ControlCenterWindowController(control: control, dataSource: makeControlCenterDataSource())

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

    private func makeControlCenterDataSource() -> any ControlCenterDataSource {
        guard let journal = try? OperationJournal(path: journalURL().path) else {
            return PreviewControlCenterDataSource()
        }
        return RuntimeControlCenterDataSource(
            journal: journal,
            configurationStore: settingsStore,
            health: { [weak self] in self?.runtime?.controlCenterHealth ?? .preparing }
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
    }
}
