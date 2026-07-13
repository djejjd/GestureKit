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
            lastEventAt: Date(timeIntervalSince1970: 0),
            evidenceTimeline: []
        )
        let page = OperationPageState(items: [item], selectedOperationID: item.id, message: nil, canLoadMore: false)
        XCTAssertEqual(page.selectedItem, item)
    }

    func testRuntimeDataSourcePaginatesJournalAndUsesChineseTerminalPresentation() {
        let request = ProviderEvent(
            eventId: "request-1",
            producerSessionId: "provider-1",
            producerSequence: 1,
            causedByEventId: nil,
            monotonicClockMs: 1,
            wallClockMs: 1,
            gestureSessionId: "gesture-1",
            operationId: "op-1",
            type: .actionRequest,
            payload: .actionRequest(ActionDescriptor(
                actionId: .browserTabActivateNext,
                contextId: "ctx-1",
                targetRef: nil,
                parameters: ["gesture": "three_finger_swipe_left"],
                deadline: 2
            ))
        )
        let result = ProviderEvent(
            eventId: "result-1",
            producerSessionId: "provider-1",
            producerSequence: 2,
            causedByEventId: "request-1",
            monotonicClockMs: 2,
            wallClockMs: 2,
            gestureSessionId: "gesture-1",
            operationId: "op-1",
            type: .actionResult,
            payload: .actionResult(ProviderActionResultPayload(
                operationId: "op-1",
                outcome: .succeeded,
                reason: nil,
                completedAt: 2
            ))
        )
        let journal = StubJournal(timelines: [
            OperationTimeline(operationId: "newest", events: [request, result], terminalState: .resultUnknown, startedAt: 1, lastEventAt: 3),
            OperationTimeline(operationId: "older", events: [], terminalState: .succeeded, startedAt: 1, lastEventAt: 2)
        ])
        let source = RuntimeControlCenterDataSource(
            journal: journal,
            configurationStore: StubConfigurationStore(configuration: .initial()),
            health: { .disconnected }
        )

        let page = source.operationPage(limit: 1)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.title, "三指左滑 · 切换右侧标签页")
        XCTAssertEqual(page.items.first?.presentation.title, "操作结果暂时无法确认")
        XCTAssertFalse(page.items.first?.presentation.title.contains("result_unknown") ?? true)
        XCTAssertEqual(page.items.first?.evidenceTimeline.first, "1. 已识别三指左滑，准备切换右侧标签页")
        XCTAssertEqual(page.items.first?.evidenceTimeline.last, "2. 浏览器返回结果：成功")
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

    func testRuntimeDataSourceForwardsEvidenceExportToJournal() throws {
        let journal = ExportRecordingJournal()
        let source = RuntimeControlCenterDataSource(
            journal: journal,
            configurationStore: StubConfigurationStore(configuration: .initial()),
            health: { .preparing }
        )
        let destination = URL(fileURLWithPath: "/tmp/gesturekit-evidence")

        try source.exportEvidence(operationID: "operation-42", to: destination)

        XCTAssertEqual(journal.exportedOperationID, "operation-42")
        XCTAssertEqual(journal.exportedURL, destination)
    }

    func testEvidenceExportFailureHasChineseUserFacingStatus() {
        XCTAssertEqual(evidenceExportStatusMessage(for: ExportFailure.sample), "证据包导出失败，请检查所选位置后重试")
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

private enum ExportFailure: Error { case sample }

private final class ExportRecordingJournal: OperationJournaling, @unchecked Sendable {
    var exportedOperationID: String?
    var exportedURL: URL?
    func append(_ event: ProviderEvent) throws {}
    func recoverExpired(now: Int64) throws -> [RecoveredOperation] { [] }
    func query(_ filter: OperationFilter, limit: Int) throws -> [OperationTimeline] { [] }
    func exportEvidence(operationId: String, to url: URL) throws {
        exportedOperationID = operationId
        exportedURL = url
    }
}
