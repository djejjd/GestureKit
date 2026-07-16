import AppKit
import SwiftUI
import GestureKitCore

/// Task 10A 控制中心：只负责固定导航和页面组合，数据由只读数据源提供。
struct ControlCenterView: View {
    let control: any RuntimeControlling
    let dataSource: any ControlCenterDataSource
    @State private var selection: ControlCenterPage = .overview
    @State private var refreshToken = 0
    @State private var selectedOperationID: String?
    @State private var evidenceExportStatus: String?
    @State private var showingClearConfirmation = false
    @State private var showingRestoreDefaultsConfirmation = false

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
                        .contentShape(Rectangle())
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
                    if let evidenceExportStatus {
                        Text(evidenceExportStatus)
                            .foregroundStyle(.red)
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 500)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                refreshToken += 1
            }
        }
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
                selectedOperationID: $selectedOperationID,
                onLoadMore: {
                    refreshToken += 1
                },
                onExport: exportEvidence,
                onClearListDisplay: { showingClearConfirmation = true }
            )
            .confirmationDialog("清空列表显示？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button("清空列表显示", role: .destructive, action: clearOperationListDisplay)
            } message: {
                Text("这只会隐藏当前操作记录列表，不会删除本地诊断日志或已导出的证据包。")
            }
        case .presets:
            PresetPage(state: dataSource.presetPage(), onBindingChanged: updateBinding, onSensitivityChanged: updateSensitivity, onRestoreDefaults: { showingRestoreDefaultsConfirmation = true })
            .confirmationDialog("恢复默认配置？", isPresented: $showingRestoreDefaultsConfirmation, titleVisibility: .visible) {
                Button("恢复默认配置", role: .destructive, action: restoreDefaults)
            } message: {
                Text("将恢复三项手势开关和轻扫灵敏度，不会删除操作记录或诊断日志。")
            }
        case .providers:
            ProviderPage(state: dataSource.providerPage())
        case .privacy:
            PrivacyPage(state: dataSource.privacyPage())
        case .advanced:
            AdvancedPage(onDiagnosticLoggingChanged: {
                control.refreshConfigurationSnapshot()
            })
        }
    }

    private func updateBinding(id: String, enabled: Bool) {
        do {
            try dataSource.updateBinding(id: id, enabled: enabled)
            evidenceExportStatus = nil
        } catch {
            evidenceExportStatus = "手势设置更新失败，请稍后重试"
        }
        refreshToken += 1
    }

    private func updateSensitivity(_ sensitivity: SwipeSensitivity) {
        do {
            try dataSource.updateSensitivity(sensitivity)
            evidenceExportStatus = nil
        } catch {
            evidenceExportStatus = "轻扫灵敏度更新失败，请稍后重试"
        }
        refreshToken += 1
    }

    private func restoreDefaults() {
        do { try dataSource.restoreDefaultConfiguration(); evidenceExportStatus = nil }
        catch { evidenceExportStatus = "恢复默认配置失败，请稍后重试" }
        refreshToken += 1
    }

    private func exportEvidence(operationID: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "请选择保存脱敏证据包的位置"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try dataSource.exportEvidence(operationID: operationID, to: url.appendingPathComponent("GestureKit-证据包-\(operationID)"))
            evidenceExportStatus = "证据包已导出"
        } catch {
            evidenceExportStatus = evidenceExportStatusMessage(for: error)
        }
        refreshToken += 1
    }

    private func clearOperationListDisplay() {
        do {
            try dataSource.clearOperationListDisplay()
            evidenceExportStatus = nil
        } catch {
            evidenceExportStatus = "操作记录列表清空失败，请稍后重试"
        }
        refreshToken += 1
    }
}

func evidenceExportStatusMessage(for error: Error) -> String {
    "证据包导出失败，请检查所选位置后重试"
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
