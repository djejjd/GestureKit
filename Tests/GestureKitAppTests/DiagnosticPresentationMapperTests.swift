import XCTest
@testable import GestureKitApp
import GestureKitCore

final class DiagnosticPresentationMapperTests: XCTestCase {
    func testResultUnknownUsesUserFacingChineseText() {
        let timeline = OperationTimeline(operationId: "op", events: [], terminalState: .resultUnknown, startedAt: 1, lastEventAt: 2)
        let model = presentDiagnostic(timeline)
        XCTAssertEqual(model.title, "操作结果暂时无法确认")
        XCTAssertFalse(model.title.contains("result_unknown"))
    }

    func testAllTerminalStatesAvoidProtocolEnumText() {
        let states: [OperationTerminalState?] = [.succeeded, .failed, .resultUnknown, .operationInterrupted, nil]
        for state in states {
            let timeline = OperationTimeline(operationId: "op", events: [], terminalState: state, startedAt: 1, lastEventAt: 2)
            let model = presentDiagnostic(timeline)
            XCTAssertFalse(model.title.contains("primitive_"))
            XCTAssertFalse(model.suggestion.contains("error_"))
        }
    }
}
