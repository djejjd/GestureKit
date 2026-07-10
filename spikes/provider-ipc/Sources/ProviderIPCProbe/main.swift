import Foundation
import GestureKitCore

/// 运行认证 Unix socket Spike，并输出可归档的结构化结果。
@main
struct ProviderIPCProbeMain {
    /// 将成功结果输出为单行 JSON，便于脚本和研究记录消费。
    static func main() {
        do {
            let result = try runProviderIPCProbe()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
        } catch {
            fputs("provider_ipc_probe_failed error=\(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
