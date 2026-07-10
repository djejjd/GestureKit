import Foundation
import Security

/// 管理每个 Provider 安装实例的本地认证密钥；目录和文件权限分别固定为 0700/0600。
final class ProviderCredentialStore: @unchecked Sendable {
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GestureKit/providers", isDirectory: true)
    }

    func secret(for installID: String) throws -> Data {
        guard !installID.isEmpty, !installID.contains("/") else { throw ProviderSessionError.invalidInstallID }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let file = directory.appendingPathComponent("\(installID).secret")
        if let data = try? Data(contentsOf: file), data.count == 32 { return data }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ProviderSessionError.credentialUnavailable }
        let secret = Data(bytes)
        try secret.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return secret
    }
}
