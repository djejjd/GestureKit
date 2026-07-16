import Foundation
@testable import GestureKitApp
import XCTest

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testNormalStateShowsDefaultText() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 正常运行")
    }

    func testGestureRecognizedChangesState() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerGestureRecognizedForTesting(gesture: "three_finger_swipe_left")

        XCTAssertEqual(controller.currentStateForTesting(), .gestureRecognized(gesture: "three_finger_swipe_left"))
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 正常运行")
    }

    func testGestureWarningChangesState() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerGestureWarningForTesting(reason: "dx_too_short")

        XCTAssertEqual(controller.currentStateForTesting(), .gestureWarning(reason: "dx_too_short"))
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 正常运行")
    }

    func testAppErrorChangesState() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerAppErrorForTesting(reason: "listener_stopped")

        XCTAssertEqual(controller.currentStateForTesting(), .appError(reason: "listener_stopped"))
        XCTAssertEqual(controller.statusTextForTesting(), "手势监听服务已停止")
    }

    func testPauseAndResume() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerPausedForTesting()
        XCTAssertEqual(controller.currentStateForTesting(), .paused)
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 已暂停")

        controller.triggerResumedForTesting()
        XCTAssertEqual(controller.currentStateForTesting(), .normal)
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 正常运行")
    }

    func testErrorStateNotOverriddenByGesture() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerAppErrorForTesting(reason: "listener_stopped")
        controller.triggerGestureRecognizedForTesting(gesture: "three_finger_tap")

        // Should stay in error state, not switch to recognized
        XCTAssertEqual(controller.currentStateForTesting(), .appError(reason: "listener_stopped"))
    }

    func testPausedStateNotOverriddenByGesture() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerPausedForTesting()
        controller.triggerGestureWarningForTesting(reason: "dx_too_short")

        // Should stay paused
        XCTAssertEqual(controller.currentStateForTesting(), .paused)
    }

    func testRecoveringFromErrorGoesToNormal() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerAppErrorForTesting(reason: "listener_stopped")
        controller.apply(event: AppMenuBarEvent(type: .appRecovered))

        XCTAssertEqual(controller.currentStateForTesting(), .normal)
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 正常运行")
    }

    func testPauseStartsTimer() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerPausedForTesting()

        XCTAssertTrue(controller.isPauseTimerActiveForTesting())
    }

    func testResumeStopsTimer() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerPausedForTesting()
        controller.triggerResumedForTesting()

        XCTAssertFalse(controller.isPauseTimerActiveForTesting())
    }

    func testAutoResumeAfterPauseTimeout() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerPausedForTesting()
        XCTAssertEqual(controller.currentStateForTesting(), .paused)
        XCTAssertEqual(control.resumeCount, 0)

        controller.triggerPauseAutoResumeForTesting()

        XCTAssertEqual(controller.currentStateForTesting(), .normal)
        XCTAssertEqual(control.resumeCount, 1)
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 正常运行")
        XCTAssertFalse(controller.isPauseTimerActiveForTesting())
    }

    func testChromeExecutionSuccessShowsGreenAndActionText() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.apply(event: AppMenuBarEvent(type: .chromeExecuted(
            action: "activate_left_tab", success: true, detail: nil
        )))

        XCTAssertEqual(controller.currentStateForTesting(), .normal)
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 正常运行")
    }

    /// 单次成功只写入操作记录，不能在菜单栏留下短暂动作摘要。
    func testSingleSuccessfulGestureDoesNotAddTransientMenuSummary() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.apply(event: AppMenuBarEvent(type: .chromeExecuted(
            action: "activate_left_tab", success: true, detail: nil
        )))

        XCTAssertNil(controller.gestureSummaryForTesting())
    }

    /// 日志目录已由控制中心替代，菜单栏只保留生命周期操作。
    func testMenuDoesNotContainLogDirectoryEntry() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        XCTAssertFalse(controller.menuTitlesForTesting().contains("打开日志目录"))
    }

    func testChromeExecutionFailureShowsWarningAndReason() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.apply(event: AppMenuBarEvent(type: .chromeExecuted(
            action: "activate_left_tab", success: false, detail: "没有可切换的标签页"
        )))

        XCTAssertEqual(controller.currentStateForTesting(), .gestureWarning(reason: "没有可切换的标签页"))
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 正常运行")
    }

    func testGestureRecognizedDoesNotFlashGreen() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.triggerGestureRecognizedForTesting(gesture: "three_finger_swipe_left")

        XCTAssertEqual(controller.currentStateForTesting(), .gestureRecognized(gesture: "three_finger_swipe_left"))
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 正常运行")
    }
}

@MainActor
final class SpyRuntimeControl: RuntimeControlling {
    var pauseCount = 0
    var resumeCount = 0
    var openLogCount = 0

    func pauseListening() { pauseCount += 1 }
    func resumeListening() { resumeCount += 1 }
    func quitApplication() {}
    func openLogDirectory() { openLogCount += 1 }
    func refreshConfigurationSnapshot() {}
    func updateBinding(id: String, enabled: Bool) throws {}
}
