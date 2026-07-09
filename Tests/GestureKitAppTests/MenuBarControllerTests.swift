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
        XCTAssertEqual(controller.statusTextForTesting(), "GestureKit 异常")
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
}
