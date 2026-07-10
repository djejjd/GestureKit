import Foundation
import GestureKitCore
import Security

typealias ProviderSessionSink = @Sendable (ProviderEnvelope) -> Void

struct AuthenticatedProviderSession: Equatable, Sendable {
    let providerInstallID: String
    let providerID: String
    let providerSessionID: String
    let capabilities: Set<StandardActionID>
}

enum ProviderSessionError: Error { case invalidInstallID, credentialUnavailable, authenticationFailed, unknownSession }

/// 将安装凭据、一次性 nonce 和定向发送绑定到唯一活动 Provider 会话。
final class ProviderSessionRegistry: @unchecked Sendable {
    private let credentialStore: ProviderCredentialStore
    private let lock = NSLock()
    private var pending: [String: Data] = [:]
    private var sessions: [String: (AuthenticatedProviderSession, ProviderSessionSink)] = [:]

    init(credentialStore: ProviderCredentialStore = ProviderCredentialStore()) { self.credentialStore = credentialStore }

    func beginAuthentication(_ hello: ProviderHelloPayload) throws -> Data {
        let secret = try credentialStore.secret(for: hello.installId)
        guard hello.protocolVersions.contains(PROVIDER_PROTOCOL_VERSION), !secret.isEmpty else { throw ProviderSessionError.authenticationFailed }
        var nonce = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce) == errSecSuccess else { throw ProviderSessionError.credentialUnavailable }
        lock.lock(); pending[hello.installId] = Data(nonce); lock.unlock()
        return Data(nonce)
    }

    func authenticate(installId: String, nonce: Data, response: Data, sink: @escaping ProviderSessionSink = { _ in }) throws -> AuthenticatedProviderSession {
        let secret = try credentialStore.secret(for: installId)
        lock.lock(); defer { lock.unlock() }
        guard pending[installId] == nonce, ProviderAuthenticator(secret: secret).verify(response, providerInstallID: installId, nonce: nonce) else { throw ProviderSessionError.authenticationFailed }
        pending.removeValue(forKey: installId)
        let session = AuthenticatedProviderSession(providerInstallID: installId, providerID: installId, providerSessionID: UUID().uuidString, capabilities: Set(StandardActionID.allCases))
        sessions[session.providerSessionID] = (session, sink)
        return session
    }

    func send(_ envelope: ProviderEnvelope, to providerSessionID: String) throws {
        lock.lock(); let sink = sessions[providerSessionID]?.1; lock.unlock()
        guard let sink else { throw ProviderSessionError.unknownSession }
        sink(envelope)
    }
}
