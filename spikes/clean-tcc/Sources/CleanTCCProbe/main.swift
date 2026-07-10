import ApplicationServices
import Foundation

/// clean-TCC Spike 的权限探针，只读取并请求系统授权状态。
@main
struct CleanTCCProbe {
    /// 输出请求前后的权限预检结果，并短暂保活以便系统展示授权提示。
    static func main() throws {
        printResult(phase: "before_request")

        // 仅请求系统授权，不创建事件 tap，也不采集或写入任何输入数据。
        let inputMonitoringGranted = CGRequestListenEventAccess()
        // 使用公开键值字面量，避免 Swift 6 将 C 框架全局变量视为并发不安全。
        let accessibilityOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(accessibilityOptions)

        print("request_result inputMonitoring=\(inputMonitoringGranted) accessibility=\(accessibilityGranted)")
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        printResult(phase: "after_request")
    }

    /// 使用稳定字段输出当前预检状态，便于人工矩阵归档。
    private static func printResult(phase: String) {
        print(
            "tcc_probe phase=\(phase) inputMonitoring=\(CGPreflightListenEventAccess()) accessibility=\(AXIsProcessTrusted())"
        )
    }
}
