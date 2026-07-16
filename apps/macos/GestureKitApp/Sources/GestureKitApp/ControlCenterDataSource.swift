import Foundation
import GestureKitCore

/// 控制中心的只读数据边界；Task 10B 将以真实运行时适配器替换预览实现。
@MainActor
protocol ControlCenterDataSource {
    func overview() -> ControlCenterOverview
    func operationPage(limit: Int) -> OperationPageState
    func clearOperationListDisplay() throws
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

    func clearOperationListDisplay() throws {}

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
        guard let timelines = try? journal.query(OperationFilter(), limit: limit) else {
            return OperationPageState(items: [], selectedOperationID: nil, message: "暂时无法读取操作记录", canLoadMore: false)
        }
        let items = timelines.map(presentOperation)
        return OperationPageState(
            items: items,
            selectedOperationID: items.first?.id,
            message: items.isEmpty ? "暂无操作记录" : nil,
            canLoadMore: false
        )
    }

    func clearOperationListDisplay() throws { try journal.clearOperationListDisplay() }

    func providerPage() -> ProviderPageState {
        let currentHealth = health()
        var cards = [providerCard(currentHealth)]
        switch currentHealth {
        case .connected(let capabilities, let configurationApplied):
            if capabilities.isEmpty {
                cards.append(.init(title: "可用能力", detail: "正在确认浏览器能力", severity: .informational))
            } else {
                for capability in capabilities.sorted(by: { $0.rawValue < $1.rawValue }) {
                    cards.append(.init(title: "可用能力", detail: displayActionName(capability), severity: .informational))
                }
            }
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
        guard let configuration = try? configurationStore.loadAppConfiguration() else {
            return PresetPageState(cards: [.init(title: "手势与操作", detail: "正在准备配置数据", severity: .informational)])
        }
        let supported = configuration.rules.filter { ["link-open-adjacent", "swipe-left-next-tab", "swipe-right-previous-tab"].contains($0.id) }
        return PresetPageState(
            cards: [.init(title: "配置版本", detail: "版本 \(configuration.configurationVersion)", severity: .informational)],
            bindings: supported.map { .init(id: $0.id, gesture: displayGestureNameForBinding($0.gestureDefinitionId), action: displayActionName($0.actionId), enabled: $0.enabled) },
            sensitivity: configuration.recognition.swipeSensitivity
        )
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
            title: operationDisplayTitle(for: timeline),
            presentation: .init(title: diagnostic.title, detail: detail, suggestion: diagnostic.suggestion),
            eventCount: timeline.events.count,
            lastEventAt: Date(timeIntervalSince1970: TimeInterval(timeline.lastEventAt) / 1_000),
            evidenceTimeline: operationEvidenceTimelineLines(for: timeline)
        )
    }

    private func providerCard(_ health: ControlCenterHealth) -> ControlCenterStatusCard {
        switch health {
        case .connected(_, let applied):
            return .init(title: "Chrome Provider", detail: applied == true ? "Chrome Provider 已连接" : "当前预设正在同步", severity: applied == true ? .informational : .warning)
        case .disconnected:
            return .init(title: "Chrome Provider", detail: "Chrome 连接已中断", severity: .warning)
        case .preparing:
            return .init(title: "Chrome Provider", detail: "正在检查 Chrome 连接", severity: .informational)
        case .stopped:
            return .init(title: "Chrome Provider", detail: "手势监听已停止", severity: .warning)
        case .listeningUnavailable:
            return .init(title: "Chrome Provider", detail: "等待手势监听恢复后检查连接", severity: .warning)
        }
    }

    private func severity(for presentation: OperationPresentation) -> PresentationSeverity {
        presentation.title == "操作已完成" ? .informational : .warning
    }

    private func operationDisplayTitle(for timeline: OperationTimeline) -> String {
        guard let request = timeline.events.first(where: { $0.type == .actionRequest }),
              case .actionRequest(let descriptor) = request.payload else {
            return "浏览器操作"
        }
        let gesture = displayGestureName(descriptor.parameters["gesture"])
        let action = displayActionName(descriptor.actionId)
        return gesture.map { "\($0) · \(action)" } ?? action
    }
}

private func displayGestureNameForBinding(_ id: String) -> String {
    switch id {
    case "three-finger-tap": return "三指点按链接"
    case "three-finger-swipe-left": return "三指左滑"
    case "three-finger-swipe-right": return "三指右滑"
    default: return "手势"
    }
}

func operationEvidenceTimelineLines(for timeline: OperationTimeline) -> [String] {
    timeline.events.enumerated().map { index, event in
        let step = index + 1
        switch event.payload {
        case .actionRequest(let descriptor):
            let gesture = displayGestureName(descriptor.parameters["gesture"]) ?? "未知手势"
            return "\(step). 已识别\(gesture)，准备\(displayActionName(descriptor.actionId))"
        case .actionAccepted:
            return "\(step). Provider 已接收并记录本次请求"
        case .actionResult(let result):
            let outcome = displayActionOutcomeName(result.outcome)
            if let reason = result.reason {
                return "\(step). 浏览器返回结果：\(outcome)（\(displayActionReasonName(reason))）"
            }
            return "\(step). 浏览器返回结果：\(outcome)"
        default:
            return "\(step). \(event.type.rawValue)"
        }
    }
}

private func displayGestureName(_ rawValue: String?) -> String? {
    switch rawValue {
    case "three_finger_tap": return "三指点按"
    case "three_finger_swipe_left": return "三指左滑"
    case "three_finger_swipe_right": return "三指右滑"
    default: return rawValue
    }
}

private func displayActionName(_ actionId: StandardActionID) -> String {
    switch actionId {
    case .browserLinkOpenAdjacent: return "链接在新标签页打开"
    case .browserTabActivatePrevious: return "切换左侧标签页"
    case .browserTabActivateNext: return "切换右侧标签页"
    case .browserTabCloseCurrent: return "关闭当前标签页"
    case .browserHistoryBack: return "后退"
    case .browserHistoryForward: return "前进"
    case .browserPageReload: return "刷新页面"
    }
}

private func displayActionOutcomeName(_ outcome: ActionResultOutcome) -> String {
    switch outcome {
    case .succeeded: return "成功"
    case .failed: return "失败"
    case .resultUnknown: return "结果暂时无法确认"
    }
}

private func displayActionReasonName(_ reason: ActionResultReason) -> String {
    switch reason {
    case .completed: return "已完成"
    case .guardUnavailable: return "页面保护不可用"
    case .guardExpired: return "页面保护已过期"
    case .contextExpired: return "上下文已过期"
    case .targetNotFound: return "未找到目标"
    case .providerTimeout: return "Provider 超时"
    case .providerDisconnected: return "Provider 断开"
    case .storageFull: return "存储已满"
    case .capabilityUnavailable: return "能力不可用"
    case .chromeApiError: return "Chrome API 错误"
    case .invalidTarget: return "目标无效"
    case .deadlineExceeded: return "超过截止时间"
    case .recoveryTimeout: return "恢复超时"
    }
}
