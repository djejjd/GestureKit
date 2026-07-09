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
    case chromeExecuted(action: String, success: Bool, detail: String?)
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

public func chromeActionSuccessText(for action: String) -> String {
    switch action {
    case "activate_left_tab": return "已切换到左侧标签页"
    case "activate_right_tab": return "已切换到右侧标签页"
    case "close_tab": return "已关闭当前标签页"
    case "open_link_background": return "链接已在新标签页打开"
    default: return "Chrome 动作已执行"
    }
}

public func chromeActionFailureText(for status: String) -> String {
    switch status {
    case "edge_reached": return "没有可切换的标签页"
    case "page_unavailable": return "当前页面不可用"
    case "no_target": return "当前位置未检测到链接"
    case "no_recent_pointer": return "无最近鼠标位置"
    case "unsupported_url_scheme": return "链接类型不支持"
    case "app_unavailable": return "Extension 未连接"
    case "native_host_disconnected": return "Native Host 已断开"
    default: return "Chrome 执行失败"
    }
}
