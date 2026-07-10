import Foundation
import XCTest
@testable import GestureKitCore

final class ProviderAuthenticationTests: XCTestCase {
    func testAuthenticatorAcceptsResponseForMatchingInstallAndNonce() {
        let authenticator = ProviderAuthenticator(secret: Data(repeating: 0xA5, count: 32))
        let nonce = Data(repeating: 0x5A, count: 32)

        let response = authenticator.response(for: "chrome-install-1", nonce: nonce)

        XCTAssertTrue(authenticator.verify(response, providerInstallID: "chrome-install-1", nonce: nonce))
    }

    func testAuthenticatorRejectsResponseForDifferentInstallOrNonce() {
        let authenticator = ProviderAuthenticator(secret: Data(repeating: 0xA5, count: 32))
        let nonce = Data(repeating: 0x5A, count: 32)
        let response = authenticator.response(for: "chrome-install-1", nonce: nonce)

        XCTAssertFalse(authenticator.verify(response, providerInstallID: "other-install", nonce: nonce))
        XCTAssertFalse(authenticator.verify(response, providerInstallID: "chrome-install-1", nonce: Data(repeating: 0x5B, count: 32)))
    }
}
