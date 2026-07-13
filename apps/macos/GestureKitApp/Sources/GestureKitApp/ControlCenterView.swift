import AppKit
import SwiftUI

/// Task 10A 控制中心：只负责固定导航和页面组合，数据由只读数据源提供。
struct ControlCenterView: View {
    let control: any RuntimeControlling
    let dataSource: any ControlCenterDataSource
    @State private var selection: ControlCenterPage = .overview
    @State private var refreshToken = 0

    init(control: any RuntimeControlling, dataSource: any ControlCenterDataSource) {
        self.control = control
        self.dataSource = dataSource
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("GESTUREKIT")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)
                ForEach(ControlCenterPage.allCases) { page in
                    Button(page.rawValue) { selection = page }
                        .buttonStyle(.plain)
                        .foregroundStyle(selection == page ? Color.white : Color.primary)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selection == page ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
                Button("暂停手势") { control.pauseListening() }
                    .buttonStyle(.bordered)
            }
            .padding(20)
            .frame(width: 178)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selection.rawValue)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    pageContent
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    @ViewBuilder
    private var pageContent: some View {
        let _ = refreshToken
        switch selection {
        case .overview:
            OverviewPage(state: dataSource.overview())
        case .operations:
            OperationHistoryView(
                state: dataSource.operationPage(limit: 20),
                onLoadMore: {
                    dataSource.loadMoreOperations()
                    refreshToken += 1
                },
                onExport: exportEvidence
            )
        case .presets:
            PresetPage(state: dataSource.presetPage())
        case .providers:
            ProviderPage(state: dataSource.providerPage())
        case .privacy:
            PrivacyPage(state: dataSource.privacyPage())
        case .advanced:
            AdvancedPage()
        }
    }

    private func exportEvidence(operationID: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "请选择保存脱敏证据包的位置"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? dataSource.exportEvidence(operationID: operationID, to: url.appendingPathComponent("GestureKit-证据包-\(operationID)"))
        refreshToken += 1
    }
}

/// 承载 SwiftUI 控制中心的 AppKit 窗口控制器。
@MainActor
final class ControlCenterWindowController: NSWindowController {
    init(control: any RuntimeControlling, dataSource: any ControlCenterDataSource) {
        let view = ControlCenterView(control: control, dataSource: dataSource)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "GestureKit 控制中心"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.setFrameAutosaveName("GestureKit.ControlCenter")
        super.init(window: window)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
