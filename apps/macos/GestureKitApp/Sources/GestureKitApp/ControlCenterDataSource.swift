import Foundation

/// 控制中心的只读数据边界；Task 10B 将以真实运行时适配器替换预览实现。
@MainActor
protocol ControlCenterDataSource {
    func overview() -> ControlCenterOverview
    func operationPage(limit: Int) -> OperationPageState
    func providerPage() -> ProviderPageState
    func privacyPage() -> PrivacyPageState
}

/// UI 框架阶段使用的安全占位数据，避免将尚未接入的能力显示为正常运行。
@MainActor
final class PreviewControlCenterDataSource: ControlCenterDataSource {
    func overview() -> ControlCenterOverview {
        ControlCenterOverview(
            runtime: ControlCenterStatusCard(title: "运行状态", detail: "正在准备 GestureKit", severity: .informational),
            provider: ControlCenterStatusCard(title: "Provider", detail: "Chrome 尚未连接", severity: .warning),
            latestOperation: ControlCenterStatusCard(title: "最近一次操作", detail: "暂无已记录操作", severity: .informational),
            attention: nil
        )
    }

    func operationPage(limit: Int) -> OperationPageState {
        OperationPageState.empty
    }

    func providerPage() -> ProviderPageState {
        ProviderPageState(cards: [
            ControlCenterStatusCard(title: "Chrome Provider", detail: "Chrome 尚未连接", severity: .warning),
            ControlCenterStatusCard(title: "可用能力", detail: "连接后显示浏览器能力", severity: .informational)
        ])
    }

    func privacyPage() -> PrivacyPageState {
        PrivacyPageState(cards: [
            ControlCenterStatusCard(title: "本地诊断", detail: "正在准备存储信息", severity: .informational),
            ControlCenterStatusCard(title: "不会记录", detail: "网页正文、Cookie 和查询参数", severity: .informational)
        ])
    }
}
