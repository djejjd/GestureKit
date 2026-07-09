import Foundation
@testable import GestureKitApp
import XCTest

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testMenuBarControllerRendersListeningAndConnectionStatus() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.apply(status: AppRuntimeStatus(
            listeningState: .listening,
            connectionState: .connected(clientCount: 1),
            lastGesture: nil,
            lastError: nil,
            logFilePathHint: "/tmp/gesturekit.log"
        ))

        XCTAssertEqual(controller.statusTitlesForTesting(), [
            "监听：运行中",
            "连接：已连接(1)"
        ])
    }

    func testMenuBarControllerRendersStoppedAndDisconnected() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.apply(status: AppRuntimeStatus(
            listeningState: .stopped,
            connectionState: .disconnected,
            lastGesture: "three_finger_swipe_right",
            lastError: nil,
            logFilePathHint: "/tmp/gesturekit.log"
        ))

        let titles = controller.statusTitlesForTesting()
        XCTAssertTrue(titles.contains("监听：已停止"))
        XCTAssertTrue(titles.contains("连接：未连接"))
    }

    func testMenuBarControllerHidesLastGestureWhenNil() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.apply(status: AppRuntimeStatus(
            listeningState: .listening,
            connectionState: .connected(clientCount: 1),
            lastGesture: "three_finger_tap",
            lastError: nil,
            logFilePathHint: "/tmp/gesturekit.log"
        ))
        controller.apply(status: AppRuntimeStatus(
            listeningState: .listening,
            connectionState: .connected(clientCount: 1),
            lastGesture: nil,
            lastError: nil,
            logFilePathHint: "/tmp/gesturekit.log"
        ))

        let titles = controller.statusTitlesForTesting()
        XCTAssertFalse(titles.contains { $0.hasPrefix("最近手势：") })
    }

    func testMenuBarControllerShowsLastErrorWhenPresent() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.apply(status: AppRuntimeStatus(
            listeningState: .listening,
            connectionState: .connected(clientCount: 1),
            lastGesture: nil,
            lastError: "unsupported_app",
            logFilePathHint: "/tmp/gesturekit.log"
        ))

        let titles = controller.statusTitlesForTesting()
        XCTAssertTrue(titles.contains("最近错误：unsupported_app"))
    }

    func testMenuBarControllerHidesLastErrorWhenCleared() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.apply(status: AppRuntimeStatus(
            listeningState: .listening,
            connectionState: .connected(clientCount: 1),
            lastGesture: nil,
            lastError: "unsupported_app",
            logFilePathHint: "/tmp/gesturekit.log"
        ))
        controller.apply(status: AppRuntimeStatus(
            listeningState: .listening,
            connectionState: .connected(clientCount: 1),
            lastGesture: nil,
            lastError: nil,
            logFilePathHint: "/tmp/gesturekit.log"
        ))

        let titles = controller.statusTitlesForTesting()
        XCTAssertFalse(titles.contains { $0.hasPrefix("最近错误：") })
    }

    func testMenuBarControllerShowsLastGestureWhenPresent() {
        let control = SpyRuntimeControl()
        let controller = MenuBarController(control: control)

        controller.apply(status: AppRuntimeStatus(
            listeningState: .listening,
            connectionState: .connected(clientCount: 1),
            lastGesture: "three_finger_tap",
            lastError: nil,
            logFilePathHint: "/tmp/gesturekit.log"
        ))

        let titles = controller.statusTitlesForTesting()
        XCTAssertTrue(titles.contains("最近手势：点按"))
    }
}

@MainActor
final class SpyRuntimeControl: RuntimeControlling {
    var refreshCount = 0
    var startCount = 0
    var stopCount = 0

    func startListening() { startCount += 1 }
    func stopListening() { stopCount += 1 }
    func refreshStatus() { refreshCount += 1 }
    func quitApplication() {}
    func openLogDirectory() {}
    func openInstallGuide() {}
    func openTroubleshootingGuide() {}
}
