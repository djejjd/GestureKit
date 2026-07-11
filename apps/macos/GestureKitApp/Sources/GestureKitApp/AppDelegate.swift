import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GestureKitRuntime?
    private var control: RuntimeControl?
    private var menuBar: MenuBarController?
    private var controlCenter: ControlCenterWindowController?

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
        controlCenter = ControlCenterWindowController(control: control, dataSource: PreviewControlCenterDataSource())

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
}
