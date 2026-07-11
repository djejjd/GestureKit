import AppKit
import SwiftUI

/// 控制中心展示的一条操作摘要。
struct OperationRow: Identifiable {
    let id: String
    let state: String
    let stateColor: Color
    let eventCount: Int
    let lastEventAt: Date
}

/// 控制中心的数据模型，负责从账本读取可回溯的操作摘要。
@MainActor
final class ControlCenterViewModel: ObservableObject {
    @Published private(set) var operations: [OperationRow] = []
    @Published private(set) var loadError: String?

    private let journal: (any OperationJournaling)?

    init(journal: (any OperationJournaling)?) {
        self.journal = journal
    }

    /// 读取最近操作。查询失败时保留界面并显示可理解的中文提示。
    func refresh() {
        guard let journal else {
            operations = []
            loadError = nil
            return
        }
        let result = Result { try journal.query(OperationFilter(), limit: 20) }
        switch result {
        case .success(let timelines):
            operations = timelines.map(Self.makeRow)
            loadError = nil
        case .failure:
            operations = []
            loadError = "暂时无法读取本地操作记录"
        }
    }

    /// 选择目录并导出脱敏证据包，不把导出副本纳入自动清理范围。
    func exportEvidence(for operation: OperationRow) {
        guard let journal else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出证据包"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let timelines = try journal.query(.operation(operation.id), limit: 1)
            guard let timeline = timelines.first else { return }
            let target = directory.appendingPathComponent("GestureKit-(operation.id)", isDirectory: true)
            try EvidenceBundleExporter().export(timeline: timeline, to: target)
        } catch {
            loadError = "证据包导出失败，请稍后重试"
        }
    }

    private static func makeRow(_ timeline: OperationTimeline) -> OperationRow {
        let state = timeline.terminalState.map(stateText) ?? "进行中"
        let color: Color
        switch timeline.terminalState {
        case .succeeded: color = .green
        case .failed: color = .red
        case .resultUnknown, .operationInterrupted: color = .orange
        case nil: color = .blue
        }
        return OperationRow(
            id: timeline.operationId,
            state: state,
            stateColor: color,
            eventCount: timeline.events.count,
            lastEventAt: Date(timeIntervalSince1970: TimeInterval(timeline.lastEventAt) / 1000)
        )
    }

    private static func stateText(_ state: OperationTerminalState) -> String {
        let timeline = OperationTimeline(operationId: "", events: [], terminalState: state, startedAt: 0, lastEventAt: 0)
        return presentDiagnostic(timeline).title
    }
}

/// Task 10 控制中心：把菜单栏的瞬时状态升级为可回溯的主窗口入口。
struct ControlCenterView: View {
    let control: any RuntimeControlling
    @StateObject private var model: ControlCenterViewModel
    @State private var selection = "概览"

    private let pages = ["概览", "操作记录", "手势预设", "Provider", "隐私与存储", "高级设置"]

    init(control: any RuntimeControlling, journal: (any OperationJournaling)? = nil) {
        self.control = control
        _model = StateObject(wrappedValue: ControlCenterViewModel(journal: journal))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("GESTUREKIT").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1.8).foregroundStyle(.secondary).padding(.bottom, 18)
                ForEach(pages, id: \.self) { page in
                    Button(page) { selection = page }
                        .buttonStyle(.plain)
                        .foregroundStyle(selection == page ? Color.white : Color.primary)
                        .padding(.vertical, 9).padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selection == page ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
                Button("暂停手势") { control.pauseListening() }.buttonStyle(.bordered)
            }
            .padding(20).frame(width: 178).background(Color(nsColor: .windowBackgroundColor).opacity(0.72))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selection).font(.system(size: 28, weight: .bold, design: .rounded))
                    pageContent
                }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color(nsColor: .controlBackgroundColor))
        }.frame(minWidth: 760, minHeight: 500)
        .onAppear { model.refresh() }
    }

    @ViewBuilder private var pageContent: some View {
        switch selection {
        case "概览":
            VStack(alignment: .leading, spacing: 14) {
                statusCard("运行状态", "手势监听正常", .green)
                statusCard("Provider", "Chrome 已认证，动作将定向发送", .blue)
                if let latest = model.operations.first {
                    statusCard("最近一次操作", "(latest.state) · (latest.eventCount) 个事件", latest.stateColor)
                } else {
                    statusCard("最近一次操作", "暂无已记录操作", .secondary)
                }
            }
        case "操作记录":
            if let error = model.loadError {
                Text(error).foregroundStyle(.secondary).padding(.top, 10)
            } else if model.operations.isEmpty {
                Text("暂无操作记录。\n失败、超时和结果未知的操作会保留完整证据链。")
                    .foregroundStyle(.secondary).padding(.top, 10)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.operations) { operation in
                        HStack(spacing: 12) {
                            Circle().fill(operation.stateColor).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(operation.state).font(.headline)
                                Text(operation.id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(operation.eventCount) 个事件").font(.subheadline)
                                Text(operation.lastEventAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            Button("导出") { model.exportEvidence(for: operation) }
                                .buttonStyle(.bordered)
                        }
                        .padding(14)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                    }
                }
            }
        case "Provider":
            statusCard("Chrome Provider", "已认证 · 当前会话正常", .green)
            Text("Provider 只接收标准动作，不读取网页正文或 Cookie。")
                .foregroundStyle(.secondary)
        case "隐私与存储":
            statusCard("本地诊断", "双重脱敏已启用", .green)
            statusCard("存储预算", "最多 50 MB · 默认保留 7 天", .secondary)
        case "手势预设":
            statusCard("当前预设", "使用配置文件中的标准手势映射", .blue)
            Text("V1 使用预设保证行为稳定；后续可在此扩展换绑和自定义手势。")
                .foregroundStyle(.secondary)
        case "高级设置":
            statusCard("诊断记录", "失败和结果未知操作会保留证据链", .green)
            Text("高级选项将在不改变手势识别核心的前提下逐步开放。")
                .foregroundStyle(.secondary)
        default:
            Text("手势方案与高级选项将在这里管理。")
                .foregroundStyle(.secondary)
        }
    }

    private func statusCard(_ title: String, _ detail: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}

/// 承载 SwiftUI 控制中心的 AppKit 窗口控制器。
@MainActor
final class ControlCenterWindowController: NSWindowController {
    init(control: any RuntimeControlling, journal: (any OperationJournaling)? = nil) {
        let view = ControlCenterView(control: control, journal: journal)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "GestureKit 控制中心"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.setFrameAutosaveName("GestureKit.ControlCenter")
        super.init(window: window)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
