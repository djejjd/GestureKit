import SwiftUI

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
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusCardView(card: .init(title: "当前预设", detail: "正在准备配置数据", severity: .informational))
            Text("V1 使用预设保证行为稳定；完整动作换绑和自定义手势属于后续增强。")
                .foregroundStyle(.secondary)
        }
    }
}

struct AdvancedPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
