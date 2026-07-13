import XCTest
@testable import GestureKitApp
import GestureKitCore

@MainActor
final class ControlCenterPresentationTests: XCTestCase {
    /// 控制中心导航顺序是已确认的信息架构，不得由页面实现任意调整。
    func testControlCenterPageOrderMatchesUIContract() {
        XCTAssertEqual(ControlCenterPage.allCases.map(\.rawValue), [
            "概览", "操作记录", "手势预设", "Provider", "隐私与存储", "高级设置"
        ])
    }

    /// 对页面保护失败使用中文解释，不能向用户暴露 Provider 内部状态。
    func testGuardUnavailableNeverLeaksProtocolEnum() {
        let presentation = ControlCenterNotice.guardUnavailable.presentation()
        XCTAssertEqual(presentation.title, "为避免误触，本次操作未执行")
        XCTAssertFalse(presentation.title.contains("guard_unavailable"))
        XCTAssertFalse(presentation.detail.contains("guard_unavailable"))
    }

    /// UI 框架阶段没有真实 Provider 时，预览数据不能显示已经连接。
    func testPreviewDataNeverClaimsProviderIsConnected() {
        let overview = PreviewControlCenterDataSource().overview()
        XCTAssertEqual(overview.provider.detail, "Chrome 尚未连接")
    }

    /// 操作页面的详情只能来自当前选择项，避免 UI 重新读取或暴露原始事件字段。
    func testOperationPageFindsSelectedItem() {
        let item = OperationListItem(
            id: "operation-1",
            title: "三指点按",
            presentation: .resultUnknown,
            eventCount: 4,
            lastEventAt: Date(timeIntervalSince1970: 0)
        )
        let page = OperationPageState(items: [item], selectedOperationID: item.id, message: nil, canLoadMore: false)
        XCTAssertEqual(page.selectedItem, item)
    }

    func testRuntimeDataSourcePaginatesJournalAndUsesChineseTerminalPresentation() {
        let journal = StubJournal(timelines: [
            OperationTimeline(operationId: "newest", events: [], terminalState: .resultUnknown, startedAt: 1, lastEventAt: 3),
            OperationTimeline(operationId: "older", events: [], terminalState: .succeeded, startedAt: 1, lastEventAt: 2)
        ])
        let source = RuntimeControlCenterDataSource(
            journal: journal,
            configurationStore: StubConfigurationStore(configuration: .initial()),
            health: { .disconnected }
        )

        let page = source.operationPage(limit: 1)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.presentation.title, "操作结果暂时无法确认")
        XCTAssertFalse(page.items.first?.presentation.title.contains("result_unknown") ?? true)
        XCTAssertTrue(page.canLoadMore)
        source.loadMoreOperations()
        XCTAssertEqual(source.operationPage(limit: 1).items.count, 2)
    }

    func testRuntimeDataSourceShowsAuthoritativePresetAndProviderHealth() {
        let configuration = AppConfiguration.initial(storeEpoch: "epoch")
        let source = RuntimeControlCenterDataSource(
            journal: StubJournal(timelines: []),
            configurationStore: StubConfigurationStore(configuration: configuration),
            health: { .connected(capabilityCount: 3, configurationApplied: false) }
        )

        XCTAssertEqual(source.presetPage().cards.first?.detail, "标准浏览预设")
        XCTAssertTrue(source.providerPage().cards.contains { $0.detail == "当前预设正在同步" })
    }
}

private final class StubJournal: OperationJournaling, @unchecked Sendable {
    let timelines: [OperationTimeline]
    init(timelines: [OperationTimeline]) { self.timelines = timelines }
    func append(_ event: ProviderEvent) throws {}
    func recoverExpired(now: Int64) throws -> [RecoveredOperation] { [] }
    func query(_ filter: OperationFilter, limit: Int) throws -> [OperationTimeline] { Array(timelines.prefix(limit)) }
    func exportEvidence(operationId: String, to url: URL) throws {}
}

private struct StubConfigurationStore: AppConfigurationStore {
    let configuration: AppConfiguration?
    func loadAppConfiguration() throws -> AppConfiguration? { configuration }
    func saveAppConfiguration(_ configuration: AppConfiguration) throws {}
    func importLegacyAppConfiguration(_ configuration: AppConfiguration) throws {}
    func hasLegacyMigrationMarker() throws -> Bool { false }
}
