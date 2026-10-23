import XCTest
@testable import GestureKitApp

/// 必须保持同步 XCTest：Swift 6.2/macOS 15 的 isolated-deinit 回部署缺陷
/// 在无当前 Swift task 的同步释放路径触发，改成 async 会掩盖回归。
@MainActor
final class NativeDragInputShieldLifecycleTests: XCTestCase {
    func testUnstartedNativeShieldCanBeReleasedSynchronously() {
        weak var released: NativeDragInputShield?
        autoreleasepool {
            let shield = NativeDragInputShield(logger: GestureKitLogger(terminalWriter: { _ in }), isChromeFrontmost: { false })
            released = shield
        }
        XCTAssertNil(released)
    }

    func testRepeatedStopAndSynchronousReleaseDoNotRetainShield() {
        weak var released: NativeDragInputShield?
        autoreleasepool {
            let shield = NativeDragInputShield(logger: GestureKitLogger(terminalWriter: { _ in }), isChromeFrontmost: { false })
            released = shield
            shield.stop()
            shield.stop()
        }
        XCTAssertNil(released)
    }
}
