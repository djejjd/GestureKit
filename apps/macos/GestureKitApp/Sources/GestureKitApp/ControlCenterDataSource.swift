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
    func updateBinding(id: String, enabled: Bool) throws
    func updateGestureBinding(gestureDefinitionID: String, actionID: StandardActionID?, enabled: Bool) throws
    func updateSensitivity(_ sensitivity: SwipeSensitivity) throws
    func restoreDefaultConfiguration() throws
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
    func updateBinding(id: String, enabled: Bool) throws {}
    func updateGestureBinding(gestureDefinitionID: String, actionID: StandardActionID?, enabled: Bool) throws {}
    func updateSensitivity(_ sensitivity: SwipeSensitivity) throws {}
    func restoreDefaultConfiguration() throws {}

    func exportEvidence(operationID: String, to url: URL) throws {}
}

/// Task 10B 的真实只读适配器：页面只获得脱敏摘要，配置始终从 App 权威存储读取。
@MainActor
final class RuntimeControlCenterDataSource: ControlCenterDataSource {
    private let journal: any OperationJournaling
    private let configurationStore: any AppConfigurationStore
    private let health: () -> ControlCenterHealth
    private let loadUserBindingsHandler: () throws -> [BindingOverride]
    private let updateBindingHandler: (String, Bool) throws -> Void
    private let updateGestureBindingHandler: (String, StandardActionID?, Bool) throws -> Void
    private let updateSensitivityHandler: (SwipeSensitivity) throws -> Void
    private let restoreDefaultsHandler: () throws -> Void
    private let systemGestureResolver: (SystemGestureSetting) -> Bool

    init(
        journal: any OperationJournaling,
        configurationStore: any AppConfigurationStore,
        health: @escaping () -> ControlCenterHealth,
        loadUserBindings: @escaping () throws -> [BindingOverride] = { [] },
        updateBinding: @escaping (String, Bool) throws -> Void = { _, _ in },
        updateGestureBinding: @escaping (String, StandardActionID?, Bool) throws -> Void = { _, _, _ in },
        updateSensitivity: @escaping (SwipeSensitivity) throws -> Void = { _ in },
        restoreDefaults: @escaping () throws -> Void = {},
        systemGestureResolver: @escaping (SystemGestureSetting) -> Bool = TrackpadPreferenceReader.isEnabled
    ) {
        self.journal = journal
        self.configurationStore = configurationStore
        self.health = health
        self.loadUserBindingsHandler = loadUserBindings
        self.updateBindingHandler = updateBinding
        self.updateGestureBindingHandler = updateGestureBinding
        self.updateSensitivityHandler = updateSensitivity
        self.restoreDefaultsHandler = restoreDefaults
        self.systemGestureResolver = systemGestureResolver
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
        let userBindings = UserBindingConfiguration(overrides: (try? loadUserBindingsHandler()) ?? [])
        let bindings = bindingRows(configuration: configuration, userBindings: userBindings)
        return PresetPageState(
            cards: [
                .init(title: "配置版本", detail: "版本 \(configuration.configurationVersion)", severity: .informational),
                configurationStatusCard(health())
            ],
            bindings: bindings,
            sensitivity: configuration.recognition.swipeSensitivity,
            conflicts: systemGestureConflicts(bindings: bindings)
        )
    }

    /// 将权威手势定义集展开为绑定行：默认绑定手势显示默认/覆盖状态，新手势显示新增/未绑定。
    private func bindingRows(configuration: AppConfiguration, userBindings: UserBindingConfiguration) -> [GestureBindingPresentation] {
        let defaults = DefaultRules.v1Bindings
        return configuration.gestureDefinitions.map { definition in
            let defaultBinding = defaults.first { $0.gestureDefinitionId == definition.id }
            let additionOverride = userBindings.overrides.first { $0.gestureDefinitionId == definition.id }

            let bindingID: String
            let actionID: StandardActionID?
            let enabled: Bool
            let hasUserOverride: Bool

            if let defaultBinding {
                let override = userBindings.overrides.first { $0.id == defaultBinding.id }
                bindingID = defaultBinding.id
                actionID = override?.actionId ?? defaultBinding.actionId
                enabled = override?.enabled ?? defaultBinding.enabled
                hasUserOverride = override != nil
            } else if let additionOverride {
                bindingID = additionOverride.id
                actionID = additionOverride.actionId
                enabled = additionOverride.enabled ?? true
                hasUserOverride = true
            } else {
                bindingID = "user-\(definition.id)"
                actionID = nil
                // 未绑定新手势默认"启用"：用户选动作即视为启用意图，保存时 enabled=true 生效；
                // 若用户想禁用再关开关（保存 enabled=false）。
                enabled = true
                hasUserOverride = false
            }

            return GestureBindingPresentation(
                id: bindingID,
                gestureDefinitionID: definition.id,
                gesture: displayGestureNameForDefinition(definition.id),
                actionID: actionID,
                action: actionID.map { displayActionName($0) } ?? "未绑定",
                enabled: enabled,
                hasUserOverride: hasUserOverride
            )
        }
    }

    /// 用户绑定手势若被系统触控板手势占用，生成引导关闭提示。
    private func systemGestureConflicts(bindings: [GestureBindingPresentation]) -> [SystemGestureConflict] {
        var conflicts: [SystemGestureConflict] = []
        let hasEnabledTwoFinger = bindings.contains {
            $0.enabled && $0.actionID != nil && ($0.gestureDefinitionID == "two-finger-swipe-left" || $0.gestureDefinitionID == "two-finger-swipe-right")
        }
        if hasEnabledTwoFinger && systemGestureResolver(.twoFingerPageSwipe) {
            conflicts.append(SystemGestureConflict(
                id: "two-finger-page-swipe",
                gesture: "二指左/右滑",
                setting: "在页面间轻扫",
                howToDisable: "请在 系统设置 → 触控板 → 更多手势 中关闭「在页面间轻扫」，让二指左右滑由 GestureKit 独占识别。"
            ))
        }
        let hasEnabledFourFinger = bindings.contains {
            $0.enabled && $0.actionID != nil && ($0.gestureDefinitionID == "four-finger-swipe-left" || $0.gestureDefinitionID == "four-finger-swipe-right")
        }
        if hasEnabledFourFinger && systemGestureResolver(.fourFingerAppSwipe) {
            conflicts.append(SystemGestureConflict(
                id: "four-finger-app-swipe",
                gesture: "四指左/右滑",
                setting: "在应用之间轻扫",
                howToDisable: "请在 系统设置 → 触控板 → 更多手势 中关闭「在应用之间轻扫」，让四指左右滑由 GestureKit 识别。"
            ))
        }
        return conflicts
    }

    private func configurationStatusCard(_ health: ControlCenterHealth) -> ControlCenterStatusCard {
        switch health {
        case .connected(_, true): return .init(title: "配置应用状态", detail: "已保存，运行中已应用，Chrome 已确认", severity: .informational)
        case .connected: return .init(title: "配置应用状态", detail: "已保存，运行中已应用，正在等待 Chrome 确认", severity: .warning)
        default: return .init(title: "配置应用状态", detail: "已保存，运行中已应用，等待 Chrome 连接", severity: .warning)
        }
    }
    func updateBinding(id: String, enabled: Bool) throws { try updateBindingHandler(id, enabled) }
    func updateGestureBinding(gestureDefinitionID: String, actionID: StandardActionID?, enabled: Bool) throws {
        try updateGestureBindingHandler(gestureDefinitionID, actionID, enabled)
    }
    func updateSensitivity(_ sensitivity: SwipeSensitivity) throws { try updateSensitivityHandler(sensitivity) }
    func restoreDefaultConfiguration() throws { try restoreDefaultsHandler() }

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
        let title = gesture.map { "\($0) · \(action)" } ?? action
        return descriptor.parameters["configurationVersion"].map { "\(title) · 配置版本 \($0)" } ?? title
    }
}

/// 手势定义 id（kebab-case）→ 中文展示名。
func displayGestureNameForDefinition(_ id: String) -> String {
    switch id {
    case "three-finger-tap": return "三指点按"
    case "three-finger-tap-left-edge": return "三指点按（左侧）"
    case "three-finger-tap-right-edge": return "三指点按（右侧）"
    case "three-finger-double-tap-center": return "三指双击"
    case "three-finger-swipe-left": return "三指左滑"
    case "three-finger-swipe-right": return "三指右滑"
    case "two-finger-swipe-left": return "二指左滑"
    case "two-finger-swipe-right": return "二指右滑"
    case "four-finger-tap": return "四指点按"
    case "four-finger-swipe-left": return "四指左滑"
    case "four-finger-swipe-right": return "四指右滑"
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
    case "two_finger_swipe_left": return "二指左滑"
    case "two_finger_swipe_right": return "二指右滑"
    case "four_finger_tap": return "四指点按"
    case "four_finger_swipe_left": return "四指左滑"
    case "four_finger_swipe_right": return "四指右滑"
    default: return rawValue
    }
}

func displayActionName(_ actionId: StandardActionID) -> String {
    switch actionId {
    case .browserLinkOpenAdjacent: return "链接在新标签页打开"
    case .browserTabActivatePrevious: return "切换左侧标签页"
    case .browserTabActivateNext: return "切换右侧标签页"
    case .browserTabCloseCurrent: return "关闭当前标签页"
    case .browserHistoryBack: return "后退"
    case .browserHistoryForward: return "前进"
    case .browserPageReload: return "刷新页面"
    case .browserTabOpenNew: return "打开新标签页"
    case .browserTabPin: return "固定当前标签页"
    case .browserTabUnpin: return "取消固定当前标签页"
    case .browserTabToggleMute: return "静音/取消静音当前标签页"
    case .browserTabCloseOthers: return "关闭其他标签页"
    case .browserTabRestore: return "恢复刚关闭的标签页"
    case .browserLinkCopy: return "复制链接"
    case .browserPageCopyURL: return "复制页面 URL"
    case .browserPageScrollTopBottom: return "滚动到页面顶部/底部"
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
