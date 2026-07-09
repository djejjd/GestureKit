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
    private let docsBaseURL: URL?

    init(runtime: GestureKitRuntime, docsBaseURL: URL? = RuntimeControl.resolveDocsBaseURL()) {
        self.runtime = runtime
        self.docsBaseURL = docsBaseURL
    }

    static func resolveDocsBaseURL() -> URL? {
        if let envRepo = ProcessInfo.processInfo.environment["GESTUREKIT_REPO_ROOT"], !envRepo.isEmpty {
            return URL(fileURLWithPath: envRepo).appendingPathComponent("docs")
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs")
        if FileManager.default.fileExists(atPath: cwd.path) {
            return cwd
        }
        return nil
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
        guard let url = docsURL(for: "operations/gesturekit-v1-local-install.md") else { return }
        NSWorkspace.shared.open(url)
    }

    func openTroubleshootingGuide() {
        guard let url = docsURL(for: "operations/gesturekit-v1-troubleshooting.md") else { return }
        NSWorkspace.shared.open(url)
    }

    private func docsURL(for relativePath: String) -> URL? {
        guard let base = docsBaseURL else { return nil }
        let url = base.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
