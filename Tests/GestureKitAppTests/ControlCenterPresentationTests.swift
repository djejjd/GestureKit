import XCTest
@testable import GestureKitApp

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
}
