import Foundation

/// 与 GestureKit 手势绑定的 macOS 系统触控板手势设置。
///
/// 键名在以下两个偏好域中定义（内置触控板 + 蓝牙触控板）：
/// - `com.apple.AppleMultitouchTrackpad`
/// - `com.apple.driver.AppleBluetoothMultitouch.trackpad`
enum SystemGestureSetting: String, CaseIterable {
    /// 「在页面间轻扫」使用双指（TrackpadTwoFingerHorizSwipeGesture）。
    case twoFingerPageSwipe = "two_finger_page_swipe"
    /// 「在页面间轻扫」使用三指（TrackpadThreeFingerHorizSwipeGesture）。
    case threeFingerPageSwipe = "three_finger_page_swipe"
    /// 「在应用之间轻扫」使用四指（TrackpadFourFingerHorizSwipeGesture）。
    case fourFingerAppSwipe = "four_finger_app_swipe"
}

/// 读取真实 macOS 触控板偏好，判断系统手势是否占用。测试通过注入固定返回值替代。
enum TrackpadPreferenceReader {
    /// 读取两个偏好域，任一对应键 > 0 即视为系统已占用该手势。
    static func isEnabled(_ setting: SystemGestureSetting) -> Bool {
        for domain in preferenceDomains {
            guard let plist = NSDictionary(contentsOfFile: preferencesPath(domain)) else { continue }
            for key in keys(for: setting) {
                if (plist[key] as? Int ?? 0) > 0 { return true }
            }
        }
        return false
    }

    private static let preferenceDomains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad"
    ]

    private static func keys(for setting: SystemGestureSetting) -> [String] {
        switch setting {
        case .twoFingerPageSwipe: return ["TrackpadTwoFingerHorizSwipeGesture"]
        case .threeFingerPageSwipe: return ["TrackpadThreeFingerHorizSwipeGesture"]
        case .fourFingerAppSwipe: return ["TrackpadFourFingerHorizSwipeGesture"]
        }
    }

    private static func preferencesPath(_ domain: String) -> String {
        ("~/Library/Preferences/\(domain).plist" as NSString).expandingTildeInPath
    }
}
