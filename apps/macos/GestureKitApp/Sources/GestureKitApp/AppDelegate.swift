import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GestureKitRuntime?
    private var control: RuntimeControl?
    private var menuBar: MenuBarController?
    private var controlCenter: ControlCenterWindowController?
    private var journal: OperationJournal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        runtime = GestureKitRuntime(menuBarHandler: { [weak self] event in
            self?.menuBar?.apply(event: event)
        })
        let control = RuntimeControl(runtime: runtime!)
        self.control = control
        let menuBar = MenuBarController(control: control) { [weak self] in
            self?.showControlCenter()
        }
        self.menuBar = menuBar
        journal = makeJournal()
        controlCenter = ControlCenterWindowController(control: control, journal: journal)

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

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
    }

    /// 创建应用级操作账本；目录不可写时保留 UI，但不阻断手势监听启动。
    private func makeJournal() -> OperationJournal? {
        let fileManager = FileManager.default
        guard let supportDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let directory = supportDirectory.appendingPathComponent("GestureKit", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return try OperationJournal(path: directory.appendingPathComponent("operation-journal.sqlite").path)
        } catch {
            return nil
        }
    }
}
