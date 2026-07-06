import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var runtime: GestureKitRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "GestureKit"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Status: Starting", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        runtime = GestureKitRuntime(statusHandler: { [weak item] status in
            item?.button?.title = status
        })
        runtime?.start()
    }

    @objc private func quit() {
        runtime?.stop()
        NSApplication.shared.terminate(nil)
    }
}
