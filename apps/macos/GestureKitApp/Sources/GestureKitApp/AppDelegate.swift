import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: GestureKitRuntime?
    private var control: RuntimeControl?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        runtime = GestureKitRuntime(menuBarHandler: { [weak self] event in
            self?.menuBar?.apply(event: event)
        })
        let control = RuntimeControl(runtime: runtime!)
        self.control = control
        let menuBar = MenuBarController(control: control)
        self.menuBar = menuBar

        runtime?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
    }
}
