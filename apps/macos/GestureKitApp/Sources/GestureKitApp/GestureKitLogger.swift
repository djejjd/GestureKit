import Foundation

final class GestureKitLogger: @unchecked Sendable {
    enum Level: String {
        case debug
        case info
        case warn
        case error
    }

    private let debugEnabled: Bool
    private let logFileURL: URL
    private let maxFileBytes: UInt64
    private let maxFiles: Int
    private let terminalWriter: (String) -> Void
    private let lock = NSLock()
    private var lastEmittedAtByKey: [String: TimeInterval] = [:]
    private var didReportFileError = false

    init(
        debugEnabled: Bool = ProcessInfo.processInfo.environment["GESTUREKIT_DEBUG"] == "1",
        logFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GestureKit/GestureKitApp.log"),
        maxFileBytes: UInt64 = 1_000_000,
        maxFiles: Int = 3,
        terminalWriter: @escaping (String) -> Void = GestureKitLogger.defaultTerminalWriter
    ) {
        self.debugEnabled = debugEnabled
        self.logFileURL = logFileURL
        self.maxFileBytes = maxFileBytes
        self.maxFiles = max(1, maxFiles)
        self.terminalWriter = terminalWriter
    }

    func debug(_ message: String, rateLimitKey: String? = nil, interval: TimeInterval = 2) {
        guard debugEnabled else { return }
        log(.debug, message, rateLimitKey: rateLimitKey, interval: interval)
    }

    func info(_ message: String, rateLimitKey: String? = nil, interval: TimeInterval = 2, terminal: Bool = false) {
        log(.info, message, rateLimitKey: rateLimitKey, interval: interval, forceTerminal: terminal)
    }

    func warn(_ message: String, rateLimitKey: String? = nil, interval: TimeInterval = 2) {
        log(.warn, message, rateLimitKey: rateLimitKey, interval: interval)
    }

    func error(_ message: String, rateLimitKey: String? = nil, interval: TimeInterval = 2) {
        log(.error, message, rateLimitKey: rateLimitKey, interval: interval)
    }

    private func log(
        _ level: Level,
        _ message: String,
        rateLimitKey: String?,
        interval: TimeInterval,
        forceTerminal: Bool = false
    ) {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }

        if let rateLimitKey, shouldSuppress(rateLimitKey, now: now.timeIntervalSince1970, interval: interval) {
            return
        }

        let line = "\(Self.timestamp(now)) level=\(level.rawValue) \(message)\n"
        if forceTerminal || shouldWriteToTerminal(level) {
            writeToTerminal(line)
        }
        writeToFile(line)
    }

    private func shouldSuppress(_ key: String, now: TimeInterval, interval: TimeInterval) -> Bool {
        if let last = lastEmittedAtByKey[key], now - last < interval {
            return true
        }
        lastEmittedAtByKey[key] = now
        return false
    }

    private func writeToTerminal(_ line: String) {
        terminalWriter(line)
    }

    private func writeToFile(_ line: String) {
        do {
            try FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rotateIfNeeded()
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logFileURL)
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } catch {
            reportFileErrorOnce(error)
        }
    }

    private func rotateIfNeeded() throws {
        guard let size = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? UInt64,
              size >= maxFileBytes
        else {
            return
        }

        if maxFiles <= 1 {
            try? FileManager.default.removeItem(at: logFileURL)
            return
        }

        for index in stride(from: maxFiles - 1, through: 1, by: -1) {
            let source = rotatedURL(index == 1 ? nil : index - 1)
            let destination = rotatedURL(index)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.moveItem(at: source, to: destination)
            }
        }
    }

    private func rotatedURL(_ index: Int?) -> URL {
        guard let index else { return logFileURL }
        return logFileURL.deletingLastPathComponent()
            .appendingPathComponent("\(logFileURL.lastPathComponent).\(index)")
    }

    private func reportFileErrorOnce(_ error: Error) {
        guard !didReportFileError else { return }
        didReportFileError = true
        let line = "\(Self.timestamp(Date())) level=error log_file_write_failed error=\"\(error.localizedDescription)\"\n"
        writeToTerminal(line)
    }

    private func shouldWriteToTerminal(_ level: Level) -> Bool {
        switch level {
        case .debug:
            return debugEnabled
        case .info:
            return false
        case .warn, .error:
            return true
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func defaultTerminalWriter(_ line: String) {
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
