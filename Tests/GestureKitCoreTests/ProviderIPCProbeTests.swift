import XCTest
@testable import GestureKitCore

final class ProviderIPCProbeTests: XCTestCase {
    func testProviderIPCProbeAuthenticatesValidClientAndRejectsInvalidCredential() throws {
        let result = try runProviderIPCProbe()

        XCTAssertEqual(result.transport, "unix_domain_socket")
        XCTAssertEqual(result.socketPermissions, "0600")
        XCTAssertTrue(result.challengeAccepted)
        XCTAssertTrue(result.invalidCredentialRejected)
    }
}
