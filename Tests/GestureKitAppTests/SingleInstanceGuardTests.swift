import XCTest
@testable import GestureKitApp

final class SingleInstanceGuardTests: XCTestCase {
    func testFileLockExclusivity() {
        // 首次获取锁应成功
        guard let fd1 = SingleInstanceGuard.acquireLock() else {
            XCTFail("首次获取单实例锁失败")
            return
        }
        // 锁已被持有，第二次获取应失败（模拟重复启动）
        XCTAssertNil(SingleInstanceGuard.acquireLock())
        // 释放后可再次获取
        SingleInstanceGuard.releaseLock(fd: fd1)
        guard let fd2 = SingleInstanceGuard.acquireLock() else {
            XCTFail("释放后获取单实例锁失败")
            return
        }
        SingleInstanceGuard.releaseLock(fd: fd2)
    }
}
