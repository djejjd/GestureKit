import Foundation

enum AppInternalListeningState: Equatable, Sendable {
    case idle
    case running
    case stopped
    case inputError
    case ipcError
}

struct AppInternalStatus {
    var listeningState: AppInternalListeningState = .idle
}

public enum AppMenuBarState: Equatable, Sendable {
    case normal
    case gestureRecognized(gesture: String)
    case gestureWarning(reason: String)
    case appError(reason: String)
    case paused
}

public enum AppMenuBarEventType: Equatable, Sendable {
    case gestureRecognized(gesture: String)
    case gestureWarning(reason: String)
    case appError(reason: String)
    case appRecovered
    case paused
    case resumed
}

public struct AppMenuBarEvent: Equatable, Sendable {
    public let type: AppMenuBarEventType
    public let timestamp: Int64

    public init(type: AppMenuBarEventType, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.type = type
        self.timestamp = timestamp
    }
}

public enum AppWarningReason: String, Sendable {
    case dxTooShort = "dx_too_short"
    case dyTooLarge = "dy_too_large"
    case tooSlow = "too_slow"
    case tooLong = "too_long"
    case cooldown = "cooldown"
    case invalidArea = "invalid_area"
    case unknown = "unknown"
}

public enum AppErrorReason: String, Sendable {
    case listenerStopped = "listener_stopped"
    case accessibilityPermissionMissing = "accessibility_permission_missing"
    case configLoadFailed = "config_load_failed"
    case internalError = "internal_error"
}

public let appWarningReasonTextMap: [AppWarningReason: String] = [
    .dxTooShort: "轻扫距离不足",
    .tooSlow: "手势速度偏慢",
    .tooLong: "手势持续时间过长",
    .cooldown: "操作太快，仍在冷却中",
    .dyTooLarge: "轻扫方向不够水平",
    .invalidArea: "触发区域不符合当前规则",
    .unknown: "未识别为有效手势"
]

public let appErrorReasonTextMap: [AppErrorReason: String] = [
    .listenerStopped: "手势监听服务已停止",
    .accessibilityPermissionMissing: "缺少辅助功能权限",
    .configLoadFailed: "配置加载失败",
    .internalError: "App 内部异常"
]

public let gestureLabelMap: [String: String] = [
    "three_finger_tap": "三指点按",
    "three_finger_swipe_left": "三指左滑",
    "three_finger_swipe_right": "三指右滑"
]
