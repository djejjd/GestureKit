import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

/// 验证 Provider 安装凭据、challenge-response 认证和定向会话隔离。
final class ProviderSessionRegistryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProviderSessionRegistryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testInvalidHMACCannotRegisterProvider() throws {
        let store = ProviderCredentialStore(directory: directory)
        let registry = ProviderSessionRegistry(credentialStore: store)
        let hello = ProviderHelloPayload(installId: "chrome-one", protocolVersions: [2], environment: "test")
        let challenge = try registry.beginAuthentication(hello)

        XCTAssertThrowsError(try registry.authenticate(installId: hello.installId, nonce: challenge, response: Data("bad".utf8)))
    }

    func testSendTargetsOnlySelectedProviderSession() throws {
        let store = ProviderCredentialStore(directory: directory)
        let firstMessages = MessageRecorder()
        let secondMessages = MessageRecorder()
        let registry = ProviderSessionRegistry(credentialStore: store)
        let first = try register("one", registry: registry, store: store) { firstMessages.append($0) }
        let second = try register("two", registry: registry, store: store) { secondMessages.append($0) }
        let envelope = ProviderEnvelope(protocolVersion: 2, messageId: "m", providerSessionId: first.providerSessionID, gestureSessionId: nil, operationId: nil, type: .healthProbe, timestamp: 1, payload: .healthProbe(HealthProbePayload(probeSequence: 1, sentAt: 1)), error: nil)

        try registry.send(envelope, to: first.providerSessionID)
        XCTAssertEqual(firstMessages.count, 1)
        XCTAssertEqual(secondMessages.count, 0)
        XCTAssertNotEqual(first.providerSessionID, second.providerSessionID)
    }

    private func register(_ id: String, registry: ProviderSessionRegistry, store: ProviderCredentialStore, sink: @escaping ProviderSessionSink) throws -> AuthenticatedProviderSession {
        let hello = ProviderHelloPayload(installId: id, protocolVersions: [2], environment: "test")
        let nonce = try registry.beginAuthentication(hello)
        let response = ProviderAuthenticator(secret: try store.secret(for: id)).response(for: id, nonce: nonce)
        return try registry.authenticate(installId: id, nonce: nonce, response: response, sink: sink)
    }
}

/// 以锁隔离 Sendable 测试回调的可变状态。
private final class MessageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProviderEnvelope] = []
    var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }
    func append(_ value: ProviderEnvelope) { lock.lock(); values.append(value); lock.unlock() }
}
