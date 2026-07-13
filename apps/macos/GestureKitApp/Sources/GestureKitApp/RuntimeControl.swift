import AppKit
import Foundation

@MainActor
protocol RuntimeControlling: AnyObject {
    func pauseListening()
    func resumeListening()
    func quitApplication()
    func openLogDirectory()
    func refreshConfigurationSnapshot()
}

@MainActor
final class RuntimeControl: RuntimeControlling {
    private weak var runtime: GestureKitRuntime?

    init(runtime: GestureKitRuntime) {
        self.runtime = runtime
    }

    func pauseListening() {
        runtime?.pause()
    }

    func resumeListening() {
        runtime?.resume()
    }

    func quitApplication() {
        runtime?.stop()
        NSApplication.shared.terminate(nil)
    }

    func openLogDirectory() {
        let logDir = ("~/Library/Logs/GestureKit" as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: logDir))
    }

    func refreshConfigurationSnapshot() {
        runtime?.refreshConfigurationSnapshot()
    }
}
