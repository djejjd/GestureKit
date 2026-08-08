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

    func testOperationPageFindsExplicitlySelectedOlderItem() {
        let newest = OperationListItem(
            id: "newest",
            title: "最新操作",
            presentation: .resultUnknown,
            eventCount: 1,
            lastEventAt: Date(timeIntervalSince1970: 2),
            evidenceTimeline: ["最新证据"]
        )
        let older = OperationListItem(
            id: "older",
            title: "较早操作",
            presentation: .resultUnknown,
            eventCount: 1,
            lastEventAt: Date(timeIntervalSince1970: 1),
            evidenceTimeline: ["较早证据"]
        )
        let page = OperationPageState(items: [newest, older], selectedOperationID: newest.id, message: nil, canLoadMore: false)

        XCTAssertEqual(page.item(id: older.id), older)
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
        XCTAssertFalse(page.canLoadMore)
    }

    func testRuntimeDataSourceShowsAuthoritativePresetAndProviderHealth() {
        let configuration = AppConfiguration.initial(storeEpoch: "epoch")
        let source = RuntimeControlCenterDataSource(
            journal: StubJournal(timelines: []),
            configurationStore: StubConfigurationStore(configuration: configuration),
            health: { .connected(capabilities: [.browserPageReload], configurationApplied: false) },
            loadUserBindings: { [] },
            systemGestureResolver: { _ in false }
        )

        XCTAssertEqual(source.presetPage().cards.first?.detail, "版本 1")
        // Task 4：绑定页展示全量预设手势（6 个三指 + 2 个二指 + 3 个四指）。
        XCTAssertEqual(source.presetPage().bindings.count, 11)
        XCTAssertTrue(source.providerPage().cards.contains { $0.detail == "当前预设正在同步" })
    }

    func testRuntimeDataSourcePresetPageListsAllGesturesWithChineseNames() {
        let configuration = AppConfiguration.initial(storeEpoch: "epoch")
        let source = RuntimeControlCenterDataSource(
            journal: StubJournal(timelines: []),
            configurationStore: StubConfigurationStore(configuration: configuration),
            health: { .disconnected },
            loadUserBindings: { [] },
            systemGestureResolver: { _ in false }
        )

        let page = source.presetPage()
        let twoFinger = try? XCTUnwrap(page.bindings.first { $0.gestureDefinitionID == "two-finger-swipe-left" })
        XCTAssertEqual(twoFinger?.gesture, "二指左滑")
        XCTAssertNil(twoFinger?.actionID)
        // 未绑定新手势默认"启用"：用户选动作即视为启用意图（否则保存 enabled=false 会不生效）。
        XCTAssertEqual(twoFinger?.enabled, true)
        XCTAssertEqual(twoFinger?.statusText, "未绑定")
        let fourTap = try? XCTUnwrap(page.bindings.first { $0.gestureDefinitionID == "four-finger-tap" })
        XCTAssertEqual(fourTap?.gesture, "四指点按")
    }

    func testRuntimeDataSourcePresetPageShowsDefaultAndOverrideState() {
        let configuration = AppConfiguration.initial(storeEpoch: "epoch")
        let source = RuntimeControlCenterDataSource(
            journal: StubJournal(timelines: []),
            configurationStore: StubConfigurationStore(configuration: configuration),
            health: { .disconnected },
            loadUserBindings: {
                [BindingOverride(id: "swipe-left-next-tab", gestureDefinitionId: nil, enabled: true, actionId: .browserPageReload)]
            },
            systemGestureResolver: { _ in false }
        )

        let page = source.presetPage()
        let defaultRow = try? XCTUnwrap(page.bindings.first { $0.gestureDefinitionID == "three-finger-tap" })
        XCTAssertEqual(defaultRow?.statusText, "默认绑定")
        let overridden = try? XCTUnwrap(page.bindings.first { $0.gestureDefinitionID == "three-finger-swipe-left" })
        XCTAssertEqual(overridden?.actionID, .browserPageReload)
        XCTAssertEqual(overridden?.hasUserOverride, true)
        XCTAssertEqual(overridden?.statusText, "用户覆盖")
    }

    func testRuntimeDataSourcePresetPageReportsTwoFingerSystemGestureConflict() {
        let configuration = AppConfiguration.initial(storeEpoch: "epoch")
        let source = RuntimeControlCenterDataSource(
            journal: StubJournal(timelines: []),
            configurationStore: StubConfigurationStore(configuration: configuration),
            health: { .disconnected },
            loadUserBindings: {
                [BindingOverride(
                    id: "user-two-finger-swipe-left",
                    gestureDefinitionId: "two-finger-swipe-left",
                    enabled: true,
                    actionId: .browserTabActivateNext
                )]
            },
            systemGestureResolver: { $0 == .twoFingerPageSwipe }
        )

        let page = source.presetPage()
        XCTAssertEqual(page.conflicts.count, 1)
        XCTAssertEqual(page.conflicts.first?.id, "two-finger-page-swipe")
        XCTAssertEqual(page.conflicts.first?.gesture, "二指左/右滑")
    }

    func testRuntimeDataSourcePresetPageIgnoresConflictWhenBindingDisabledOrSystemOff() {
        let configuration = AppConfiguration.initial(storeEpoch: "epoch")
        // 绑定存在但 enabled=false：即使系统开启也不提示。
        let disabledSource = RuntimeControlCenterDataSource(
            journal: StubJournal(timelines: []),
            configurationStore: StubConfigurationStore(configuration: configuration),
            health: { .disconnected },
            loadUserBindings: {
                [BindingOverride(
                    id: "user-two-finger-swipe-left",
                    gestureDefinitionId: "two-finger-swipe-left",
                    enabled: false,
                    actionId: .browserTabActivateNext
                )]
            },
            systemGestureResolver: { _ in true }
        )
        XCTAssertTrue(disabledSource.presetPage().conflicts.isEmpty)

        // 绑定启用但系统关闭：也不提示。
        let systemOffSource = RuntimeControlCenterDataSource(
            journal: StubJournal(timelines: []),
            configurationStore: StubConfigurationStore(configuration: configuration),
            health: { .disconnected },
            loadUserBindings: {
                [BindingOverride(
                    id: "user-two-finger-swipe-left",
                    gestureDefinitionId: "two-finger-swipe-left",
                    enabled: true,
                    actionId: .browserTabActivateNext
                )]
            },
            systemGestureResolver: { _ in false }
        )
        XCTAssertTrue(systemOffSource.presetPage().conflicts.isEmpty)
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
    func clearOperationListDisplay() throws {}
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
    func clearOperationListDisplay() throws {}
    func exportEvidence(operationId: String, to url: URL) throws {
        exportedOperationID = operationId
        exportedURL = url
    }
}
