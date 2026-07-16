import AppKit
import Foundation
import GestureKitCore

@MainActor
protocol RuntimeControlling: AnyObject {
    func pauseListening()
    func resumeListening()
    func quitApplication()
    func openLogDirectory()
    func refreshConfigurationSnapshot()
    func updateBinding(id: String, enabled: Bool) throws
    func updateSensitivity(_ sensitivity: SwipeSensitivity) throws
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

    func updateBinding(id: String, enabled: Bool) throws { try runtime?.updateBinding(id: id, enabled: enabled) }
    func updateSensitivity(_ sensitivity: SwipeSensitivity) throws { try runtime?.updateSensitivity(sensitivity) }
}
