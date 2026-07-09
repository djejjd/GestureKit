import AppKit
import Foundation

@MainActor
protocol RuntimeControlling: AnyObject {
    func startListening()
    func stopListening()
    func refreshStatus()
    func quitApplication()
    func openLogDirectory()
    func openInstallGuide()
    func openTroubleshootingGuide()
}

@MainActor
final class RuntimeControl: RuntimeControlling {
    private weak var runtime: GestureKitRuntime?

    init(runtime: GestureKitRuntime) {
        self.runtime = runtime
    }

    func startListening() {
        runtime?.start()
    }

    func stopListening() {
        runtime?.stop()
    }

    func refreshStatus() {
        runtime?.refreshStatus()
    }

    func quitApplication() {
        runtime?.stop()
        NSApplication.shared.terminate(nil)
    }

    func openLogDirectory() {
        let logDir = ("~/Library/Logs/GestureKit" as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: logDir))
    }

    func openInstallGuide() {
        guard let url = repoDocsURL()?.appendingPathComponent("operations/gesturekit-v1-local-install.md") else { return }
        NSWorkspace.shared.open(url)
    }

    func openTroubleshootingGuide() {
        guard let url = repoDocsURL()?.appendingPathComponent("operations/gesturekit-v1-troubleshooting.md") else { return }
        NSWorkspace.shared.open(url)
    }

    private func repoDocsURL() -> URL? {
        let envRepo = ProcessInfo.processInfo.environment["GESTUREKIT_REPO_ROOT"]
        if let envRepo, !envRepo.isEmpty {
            return URL(fileURLWithPath: envRepo).appendingPathComponent("docs")
        }
        let cwd = FileManager.default.currentDirectoryPath
        let candidate = URL(fileURLWithPath: cwd).appendingPathComponent("docs")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }
}
