import XCTest
@testable import GestureKitApp
import Network

/// 覆盖 GESTUREKIT_IPC_PORT 环境覆盖：E2E 验收时测试 App 与真实 App 共享默认端口
/// 17653，必须能通过环境变量隔离到独立端口，Host 才能连到正确的测试 App。
final class LocalEventServerTests: XCTestCase {
    func testIPCProxyPortDefaultsTo17653WhenUnset() {
        let port = LocalEventServer.ipcPortFromEnvironment([:])
        XCTAssertEqual(port.rawValue, 17653)
    }

    func testIPCProxyPortReadsValidOverride() {
        let port = LocalEventServer.ipcPortFromEnvironment(["GESTUREKIT_IPC_PORT": "19099"])
        XCTAssertEqual(port.rawValue, 19099)
    }

    func testIPCProxyPortFallsBackOnInvalidOverride() {
        XCTAssertEqual(LocalEventServer.ipcPortFromEnvironment(["GESTUREKIT_IPC_PORT": "abc"]).rawValue, 17653)
        XCTAssertEqual(LocalEventServer.ipcPortFromEnvironment(["GESTUREKIT_IPC_PORT": "0"]).rawValue, 17653)
        XCTAssertEqual(LocalEventServer.ipcPortFromEnvironment(["GESTUREKIT_IPC_PORT": "70000"]).rawValue, 17653)
    }
}
