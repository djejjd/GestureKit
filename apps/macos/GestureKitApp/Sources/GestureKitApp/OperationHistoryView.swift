import SwiftUI

/// 操作记录的双栏页面；Task 10B 只替换数据源和导出动作，不改变布局边界。
struct OperationHistoryView: View {
    let state: OperationPageState
    let onLoadMore: () -> Void
    let onExport: (String) -> Void
    let onClearListDisplay: () -> Void

    var body: some View {
        if state.items.isEmpty {
            ContentUnavailableView(
                "暂无操作记录",
                systemImage: "clock.arrow.circlepath",
                description: Text(state.message ?? "失败、超时和结果未知的操作会保留完整证据链。")
            )
        } else {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(state.items) { item in
                        operationRow(item)
                    }
                    Button("清空列表显示", action: onClearListDisplay).buttonStyle(.bordered)
                }
                .frame(minWidth: 260, maxWidth: 320, alignment: .leading)

                if let selected = state.selectedItem {
                    operationDetail(selected)
                } else {
                    ContentUnavailableView("选择一条操作记录", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }

    private func operationRow(_ item: OperationListItem) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color(for: item.presentation)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text(item.presentation.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.lastEventAt, style: .relative).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func operationDetail(_ item: OperationListItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.title).font(.title2.bold())
            Text(item.presentation.title).font(.headline).foregroundStyle(color(for: item.presentation))
            Text(item.presentation.detail).foregroundStyle(.secondary)
            GroupBox("系统建议") {
                Text(item.presentation.suggestion).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("证据时间线") {
                if item.evidenceTimeline.isEmpty {
                    Text("暂无可显示的阶段记录。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(item.evidenceTimeline.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            Text("导出的证据包不受 7 天/50 MB 自动清理控制。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("导出脱敏证据包") { onExport(item.id) }
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }

    private func color(for presentation: OperationPresentation) -> Color {
        presentation.title == OperationPresentation.resultUnknown.title ? .orange : .blue
    }
}
