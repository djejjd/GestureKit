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
    var body: some View { pageCards(state.cards) }
}

struct PrivacyPage: View {
    let state: PrivacyPageState
    var body: some View { pageCards(state.cards) }
}

struct PresetPage: View {
    let state: PresetPageState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageCards(state.cards)
            ForEach(state.bindings) { binding in
                HStack {
                    VStack(alignment: .leading) {
                        Text(binding.gesture).font(.headline)
                        Text(binding.action).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(binding.enabled ? "已启用" : "已关闭")
                        .foregroundStyle(binding.enabled ? .green : .secondary)
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("轻扫灵敏度：\(sensitivityName(state.sensitivity))")
                .foregroundStyle(.secondary)
        }
    }
}

private func sensitivityName(_ value: SwipeSensitivity) -> String {
    switch value { case .robust: "稳健"; case .standard: "标准"; case .sensitive: "灵敏" }
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
