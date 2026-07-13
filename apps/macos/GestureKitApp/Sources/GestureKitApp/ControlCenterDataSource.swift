import Foundation
import GestureKitCore

/// 控制中心的只读数据边界；Task 10B 将以真实运行时适配器替换预览实现。
@MainActor
protocol ControlCenterDataSource {
    func overview() -> ControlCenterOverview
    func operationPage(limit: Int) -> OperationPageState
    func loadMoreOperations()
    func providerPage() -> ProviderPageState
    func privacyPage() -> PrivacyPageState
    func presetPage() -> PresetPageState
    func exportEvidence(operationID: String, to url: URL) throws
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

    func loadMoreOperations() {}

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

    func presetPage() -> PresetPageState {
        PresetPageState(cards: [
            ControlCenterStatusCard(title: "当前预设", detail: "正在准备配置数据", severity: .informational)
        ])
    }

    func exportEvidence(operationID: String, to url: URL) throws {}
}

/// Task 10B 的真实只读适配器：页面只获得脱敏摘要，配置始终从 App 权威存储读取。
@MainActor
final class RuntimeControlCenterDataSource: ControlCenterDataSource {
    private let journal: any OperationJournaling
    private let configurationStore: any AppConfigurationStore
    private let health: () -> ControlCenterHealth
    private var additionalLoadedCount = 0

    init(
        journal: any OperationJournaling,
        configurationStore: any AppConfigurationStore,
        health: @escaping () -> ControlCenterHealth
    ) {
        self.journal = journal
        self.configurationStore = configurationStore
        self.health = health
    }

    func overview() -> ControlCenterOverview {
        let health = health()
        let provider = providerCard(health)
        let latest = operationPage(limit: 1).items.first.map { item in
            ControlCenterStatusCard(title: "最近一次操作", detail: item.presentation.title, severity: severity(for: item.presentation))
        } ?? ControlCenterStatusCard(title: "最近一次操作", detail: "暂无已记录操作", severity: .informational)
        let attention: ControlCenterStatusCard? = switch health {
        case .listeningUnavailable:
            ControlCenterStatusCard(title: "需要处理", detail: "无法开始手势监听", severity: .critical)
        case .disconnected:
            ControlCenterStatusCard(title: "需要处理", detail: "Chrome 连接已中断", severity: .warning)
        case .connected(_, let applied) where applied == false:
            ControlCenterStatusCard(title: "需要处理", detail: "当前预设正在同步", severity: .warning)
        default: nil
        }
        return ControlCenterOverview(runtime: health.runtimeCard, provider: provider, latestOperation: latest, attention: attention)
    }

    func operationPage(limit: Int) -> OperationPageState {
        let requested = limit + additionalLoadedCount
        guard let timelines = try? journal.query(OperationFilter(), limit: requested) else {
            return OperationPageState(items: [], selectedOperationID: nil, message: "暂时无法读取操作记录", canLoadMore: false)
        }
        let items = timelines.map(presentOperation)
        return OperationPageState(
            items: items,
            selectedOperationID: items.first?.id,
            message: items.isEmpty ? "暂无操作记录" : nil,
            canLoadMore: timelines.count == requested
        )
    }

    func loadMoreOperations() { additionalLoadedCount += 20 }

    func providerPage() -> ProviderPageState {
        let currentHealth = health()
        var cards = [providerCard(currentHealth)]
        switch currentHealth {
        case .connected(let capabilityCount, let configurationApplied):
            cards.append(.init(title: "可用能力", detail: "已确认 \(capabilityCount) 项浏览器能力", severity: .informational))
            cards.append(.init(title: "配置应用状态", detail: configurationApplied == true ? "当前预设已应用" : "当前预设正在同步", severity: configurationApplied == true ? .informational : .warning))
        case .disconnected:
            cards.append(.init(title: "配置应用状态", detail: "恢复连接后会自动对账", severity: .warning))
        default:
            break
        }
        return ProviderPageState(cards: cards)
    }

    func privacyPage() -> PrivacyPageState {
        PrivacyPageState(cards: [
            .init(title: "本地诊断", detail: "操作记录保存在本机", severity: .informational),
            .init(title: "不会记录", detail: "网页正文、Cookie、查询参数和链接原始目标", severity: .informational),
            .init(title: "保留提醒", detail: "导出的证据包不受本地自动清理控制", severity: .informational)
        ])
    }

    func presetPage() -> PresetPageState {
        let detail: String
        if ((try? configurationStore.loadAppConfiguration()) ?? nil) != nil {
            detail = "标准浏览预设"
        } else {
            detail = "正在准备配置数据"
        }
        return PresetPageState(cards: [.init(title: "当前预设", detail: detail, severity: .informational)])
    }

    func exportEvidence(operationID: String, to url: URL) throws {
        try journal.exportEvidence(operationId: operationID, to: url)
    }

    private func presentOperation(_ timeline: OperationTimeline) -> OperationListItem {
        let diagnostic = presentDiagnostic(timeline)
        let detail: String = switch timeline.terminalState {
        case .succeeded: "浏览器已确认本次操作完成"
        case .failed: "系统已保存失败阶段的诊断信息"
        case .resultUnknown: "系统未在期限内收到明确结果"
        case .operationInterrupted: "Provider 连接发生变化，系统已保存诊断信息"
        case nil: "系统正在等待浏览器返回结果"
        }
        return OperationListItem(
            id: timeline.operationId,
            title: "浏览器操作",
            presentation: .init(title: diagnostic.title, detail: detail, suggestion: diagnostic.suggestion),
            eventCount: timeline.events.count,
            lastEventAt: Date(timeIntervalSince1970: TimeInterval(timeline.lastEventAt) / 1_000)
        )
    }

    private func providerCard(_ health: ControlCenterHealth) -> ControlCenterStatusCard {
        switch health {
        case .connected:
            return .init(title: "Chrome Provider", detail: "Chrome 已连接", severity: .informational)
        case .disconnected:
            return .init(title: "Chrome Provider", detail: "Chrome 连接已中断", severity: .warning)
        case .preparing:
            return .init(title: "Chrome Provider", detail: "正在检查 Chrome 连接", severity: .informational)
        case .listeningUnavailable:
            return .init(title: "Chrome Provider", detail: "等待手势监听恢复后检查连接", severity: .warning)
        }
    }

    private func severity(for presentation: OperationPresentation) -> PresentationSeverity {
        presentation.title == "操作已完成" ? .informational : .warning
    }
}
