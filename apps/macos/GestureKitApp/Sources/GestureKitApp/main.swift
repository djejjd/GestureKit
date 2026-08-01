import AppKit

/// 解析 --e2e-control-token <token>；无参数时返回 nil（不暴露控制端口）。
let e2eControlToken: String? = {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--e2e-control-token"), idx + 1 < args.count {
        return args[idx + 1]
    }
    return nil
}()

let app = NSApplication.shared
let delegate = AppDelegate(e2eControlToken: e2eControlToken)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
