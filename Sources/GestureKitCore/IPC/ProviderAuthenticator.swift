import CryptoKit
import Foundation

/// 使用安装凭据对 Provider challenge-response 进行 HMAC-SHA256 校验。
public struct ProviderAuthenticator: Sendable {
    private let secret: SymmetricKey

    /// 以每个 Provider 安装实例独有的凭据创建认证器。
    public init(secret: Data) {
        self.secret = SymmetricKey(data: secret)
    }

    /// 计算绑定 Provider 安装 ID 与 nonce 的认证响应。
    public func response(for providerInstallID: String, nonce: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: challengeData(providerInstallID: providerInstallID, nonce: nonce), using: secret))
    }

    /// 验证认证响应是否对应同一个 Provider 安装实例和当前 nonce。
    public func verify(_ response: Data, providerInstallID: String, nonce: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            response,
            authenticating: challengeData(providerInstallID: providerInstallID, nonce: nonce),
            using: secret
        )
    }

    /// 使用分隔符消除安装 ID 与 nonce 直接拼接时的边界歧义。
    private func challengeData(providerInstallID: String, nonce: Data) -> Data {
        var data = Data(providerInstallID.utf8)
        data.append(0)
        data.append(nonce)
        return data
    }
}
