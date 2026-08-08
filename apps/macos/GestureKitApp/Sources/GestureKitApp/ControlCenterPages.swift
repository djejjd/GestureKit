import SwiftUI
import GestureKitCore

/// 控制中心除操作记录外的页面组件，均只依赖表现模型。
struct OverviewPage: View {
    let state: ControlCenterOverview

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            StatusCardView(card: state.runtime)
            StatusCardView(card: state.provider)
            StatusCardView(card: state.latestOperation)
            if let attention = state.attention {
                StatusCardView(card: attention)
            }
        }
    }
}

struct ProviderPage: View {
    let state: ProviderPageState

    @State private var showingCapabilities = false

    var body: some View {
        let provider = state.cards.first
        let capabilities = state.cards.filter { $0.title == "可用能力" }
        let status = state.cards.filter { $0.title != "Chrome Provider" && $0.title != "可用能力" }
        VStack(alignment: .leading, spacing: 14) {
            if let provider { StatusCardView(card: provider) }
            if !capabilities.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingCapabilities.toggle()
                        }
                    } label: {
                        HStack {
                            Text("查看能力（\(capabilities.count) 项）")
                            Spacer()
                            Image(systemName: showingCapabilities ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("浏览器可用能力")
                    .accessibilityValue(showingCapabilities ? "已展开" : "已折叠")
                    .padding(16)

                    if showingCapabilities {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(capabilities.enumerated()), id: \.offset) { _, capability in
                                Label(capability.detail, systemImage: capabilityIcon(capability.detail))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding([.horizontal, .bottom], 16)
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
            }
            pageCards(status)
        }
    }
}

struct PrivacyPage: View {
    let state: PrivacyPageState
    var body: some View { pageCards(state.cards) }
}

struct PresetPage: View {
    let state: PresetPageState
    let onBindingChanged: (GestureBindingPresentation) -> Void
    let onSensitivityChanged: (SwipeSensitivity) -> Void
    let onRestoreDefaults: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageCards(state.cards)
            if !state.conflicts.isEmpty {
                ForEach(state.conflicts) { conflict in
                    conflictCard(conflict)
                }
            }
            if !state.bindings.isEmpty {
                HStack {
                    Text("手势").frame(maxWidth: .infinity, alignment: .leading)
                    Text("关联操作").frame(maxWidth: .infinity, alignment: .leading)
                    Text("状态").frame(width: 64, alignment: .center)
                    Text("启用").frame(width: 48, alignment: .center)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                ForEach(state.bindings) { binding in
                    bindingRow(binding)
                }
            }
            Picker("轻扫灵敏度", selection: Binding(get: { state.sensitivity }, set: onSensitivityChanged)) {
                Text("稳健").tag(SwipeSensitivity.robust)
                Text("标准").tag(SwipeSensitivity.standard)
                Text("灵敏").tag(SwipeSensitivity.sensitive)
            }
            .pickerStyle(.segmented)
            Button("恢复默认配置", action: onRestoreDefaults)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func bindingRow(_ binding: GestureBindingPresentation) -> some View {
        HStack(spacing: 12) {
            Label(binding.gesture, systemImage: gestureIcon(binding.gestureDefinitionID))
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: Binding<StandardActionID?>(
                get: { binding.actionID },
                set: { onBindingChanged(binding.withAction($0)) }
            )) {
                Text("未绑定").tag(StandardActionID?.none)
                ForEach(StandardActionID.allCases, id: \.self) { action in
                    Text(displayActionName(action)).tag(StandardActionID?.some(action))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(binding.statusText)
                .font(.caption)
                .foregroundStyle(binding.hasUserOverride ? Color.orange : Color.secondary)
                .frame(width: 64, alignment: .center)
            Toggle("", isOn: Binding(
                get: { binding.enabled },
                set: { onBindingChanged(binding.withEnabled($0)) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .frame(width: 48, alignment: .center)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private func conflictCard(_ conflict: SystemGestureConflict) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(conflict.gesture)与系统「\(conflict.setting)」冲突")
                    .font(.headline)
                Text(conflict.howToDisable)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.4)))
    }
}

private func gestureIcon(_ gestureDefinitionID: String) -> String {
    switch gestureDefinitionID {
    case "three-finger-tap", "three-finger-tap-left-edge", "three-finger-tap-right-edge", "three-finger-double-tap-center", "four-finger-tap":
        return "hand.tap"
    case "two-finger-swipe-left", "three-finger-swipe-left", "four-finger-swipe-left":
        return "arrow.left"
    case "two-finger-swipe-right", "three-finger-swipe-right", "four-finger-swipe-right":
        return "arrow.right"
    default:
        return "hand.draw"
    }
}

private extension GestureBindingPresentation {
    func withAction(_ actionID: StandardActionID?) -> GestureBindingPresentation {
        var copy = self
        copy.actionID = actionID
        copy.action = actionID.map { displayActionName($0) } ?? "未绑定"
        return copy
    }

    func withEnabled(_ enabled: Bool) -> GestureBindingPresentation {
        var copy = self
        copy.enabled = enabled
        return copy
    }
}

private func capabilityIcon(_ title: String) -> String {
    if title.contains("打开链接") { return "arrow.up.right.square" }
    if title.contains("切换") { return "rectangle.on.rectangle" }
    if title.contains("关闭") { return "xmark.square" }
    if title.contains("后退") { return "arrow.backward" }
    if title.contains("前进") { return "arrow.forward" }
    if title.contains("刷新") { return "arrow.clockwise" }
    return "puzzlepiece"
}


struct AdvancedPage: View {
    let onDiagnosticLoggingChanged: () -> Void
    @AppStorage(GestureKitLogger.diagnosticLoggingDefaultsKey) private var diagnosticLoggingEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("启用诊断日志", isOn: $diagnosticLoggingEnabled)
                .toggleStyle(.switch)
                .onChange(of: diagnosticLoggingEnabled) { _, _ in
                    onDiagnosticLoggingChanged()
                }
            Text("开启后会记录更细的链路日志，用于复现频繁问题；默认只保留关键日志。")
                .foregroundStyle(.secondary)
            StatusCardView(card: .init(title: "系统权限", detail: "将在实际检测后显示说明", severity: .informational))
            StatusCardView(card: .init(title: "Provider 凭据", detail: "连接后可管理已注册 Provider", severity: .informational))
        }
    }
}

struct StatusCardView: View {
    let card: ControlCenterStatusCard

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title).font(.headline)
                Text(card.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }

    private var color: Color {
        switch card.severity {
        case .informational: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

@ViewBuilder
private func pageCards(_ cards: [ControlCenterStatusCard]) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
            StatusCardView(card: card)
        }
    }
}
