import Foundation

public enum AppListeningState: Equatable, Sendable {
    case starting
    case listening
    case stopped
    case inputError
    case ipcError
}

public enum AppConnectionState: Equatable, Sendable {
    case unknown
    case disconnected
    case connected(clientCount: Int)
}

public struct AppRuntimeStatus: Equatable, Sendable {
    public let listeningState: AppListeningState
    public let connectionState: AppConnectionState
    public let lastGesture: String?
    public let lastError: String?
    public let logFilePathHint: String

    public init(
        listeningState: AppListeningState,
        connectionState: AppConnectionState,
        lastGesture: String?,
        lastError: String?,
        logFilePathHint: String
    ) {
        self.listeningState = listeningState
        self.connectionState = connectionState
        self.lastGesture = lastGesture
        self.lastError = lastError
        self.logFilePathHint = logFilePathHint
    }
}
