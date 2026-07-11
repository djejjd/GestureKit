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
        controlCenter = ControlCenterWindowController(control: control)

        runtime?.start()
    }

    private func showControlCenter() {
        controlCenter?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
    }
}
