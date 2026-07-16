import Foundation
import GestureKitCore
import Security

typealias ProviderSessionSink = @Sendable (ProviderEnvelope) -> Void

struct AuthenticatedProviderSession: Equatable, Sendable {
    let providerInstallID: String
    let providerID: String
    let providerSessionID: String
    let capabilities: Set<StandardActionID>
    let connectionID: UUID
}

enum ProviderSessionError: Error { case invalidInstallID, credentialUnavailable, authenticationFailed, unknownSession }

/// 将安装凭据、一次性 nonce 和定向发送绑定到唯一活动 Provider 会话。
final class ProviderSessionRegistry: @unchecked Sendable {
    private let credentialStore: ProviderCredentialStore
    private let lock = NSLock()
    private var pending: [String: Data] = [:]
    private var sessions: [String: (AuthenticatedProviderSession, ProviderSessionSink)] = [:]
    private var activeSessionID: String?

    init(credentialStore: ProviderCredentialStore = ProviderCredentialStore()) { self.credentialStore = credentialStore }

    func beginAuthentication(_ hello: ProviderHelloPayload) throws -> Data {
        let secret = try credentialStore.secret(for: hello.installId)
        guard hello.protocolVersions.contains(PROVIDER_PROTOCOL_VERSION), !secret.isEmpty else { throw ProviderSessionError.authenticationFailed }
        var nonce = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce) == errSecSuccess else { throw ProviderSessionError.credentialUnavailable }
        lock.lock(); pending[hello.installId] = Data(nonce); lock.unlock()
        return Data(nonce)
    }

    func authenticate(installId: String, nonce: Data, response: Data, connectionID: UUID = UUID(), sink: @escaping ProviderSessionSink = { _ in }) throws -> AuthenticatedProviderSession {
        let secret = try credentialStore.secret(for: installId)
        lock.lock(); defer { lock.unlock() }
        guard pending[installId] == nonce, ProviderAuthenticator(secret: secret).verify(response, providerInstallID: installId, nonce: nonce) else { throw ProviderSessionError.authenticationFailed }
        pending.removeValue(forKey: installId)
        let session = AuthenticatedProviderSession(providerInstallID: installId, providerID: installId, providerSessionID: UUID().uuidString, capabilities: [], connectionID: connectionID)
        sessions[session.providerSessionID] = (session, sink)
        activeSessionID = session.providerSessionID
        return session
    }

    /// 生产握手从 registry 保存的一次性 nonce 取值，避免 Provider 在认证响应中回传 nonce。
    func authenticate(installId: String, response: Data, connectionID: UUID = UUID(), sink: @escaping ProviderSessionSink = { _ in }) throws -> AuthenticatedProviderSession {
        lock.lock(); let nonce = pending[installId]; lock.unlock()
        guard let nonce else { throw ProviderSessionError.authenticationFailed }
        return try authenticate(installId: installId, nonce: nonce, response: response, connectionID: connectionID, sink: sink)
    }

    func send(_ envelope: ProviderEnvelope, to providerSessionID: String) throws {
        lock.lock(); let sink = sessions[providerSessionID]?.1; lock.unlock()
        guard let sink else { throw ProviderSessionError.unknownSession }
        sink(envelope)
    }

    /// V1 过渡期只启用一个内置 Chrome Provider，会话替换后始终选择最新认证会话。
    func activeSession() -> AuthenticatedProviderSession? {
        lock.lock(); defer { lock.unlock() }
        guard let activeSessionID else { return nil }
        return sessions[activeSessionID]?.0
    }

    func session(_ providerSessionID: String, belongsTo connectionID: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sessions[providerSessionID]?.0.connectionID == connectionID
    }

    /// 只有已认证连接自身可以声明其实际可执行的标准动作。
    func updateCapabilities(_ snapshot: CapabilitySnapshotPayload, for providerSessionID: String, connectionID: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let (session, sink) = sessions[providerSessionID], session.connectionID == connectionID else { return false }
        sessions[providerSessionID] = (
            AuthenticatedProviderSession(
                providerInstallID: session.providerInstallID,
                providerID: session.providerID,
                providerSessionID: session.providerSessionID,
                capabilities: Set(snapshot.capabilities),
                connectionID: session.connectionID
            ),
            sink
        )
        return true
    }
}
