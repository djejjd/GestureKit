import AppKit
import SwiftUI

/// Task 10 控制中心：把菜单栏的瞬时状态升级为可回溯的主窗口入口。
struct ControlCenterView: View {
    let control: any RuntimeControlling
    @State private var selection = "概览"

    private let pages = ["概览", "操作记录", "Provider", "隐私与存储", "设置"]

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
    }

    @ViewBuilder private var pageContent: some View {
        switch selection {
        case "概览":
            VStack(alignment: .leading, spacing: 14) {
                statusCard("运行状态", "手势监听正常", .green)
                statusCard("Provider", "Chrome 已认证，动作将定向发送", .blue)
                statusCard("最近一次操作", "暂无新的失败记录", .secondary)
            }
        case "操作记录":
            Text("历史操作会从 OperationJournal 分页读取。\n失败、超时和结果未知的操作会保留完整证据链。")
                .foregroundStyle(.secondary).padding(.top, 10)
        case "Provider":
            statusCard("Chrome Provider", "已认证 · 当前会话正常", .green)
            Text("Provider 只接收标准动作，不读取网页正文或 Cookie。")
                .foregroundStyle(.secondary)
        case "隐私与存储":
            statusCard("本地诊断", "双重脱敏已启用", .green)
            statusCard("存储预算", "最多 50 MB · 默认保留 7 天", .secondary)
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
    init(control: any RuntimeControlling) {
        let view = ControlCenterView(control: control)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "GestureKit 控制中心"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.setFrameAutosaveName("GestureKit.ControlCenter")
        super.init(window: window)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
