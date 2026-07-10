import Darwin
import Foundation

/// Provider IPC Spike 的结构化结果，可直接作为人工验证记录的输入。
public struct ProviderIPCProbeResult: Codable, Sendable {
    public let transport: String
    public let socketPermissions: String
    public let challengeAccepted: Bool
    public let invalidCredentialRejected: Bool
    public let sameUIDThreatModel: String
}

/// Provider IPC Spike 在系统调用或握手帧不符合预期时抛出的错误。
public enum ProviderIPCProbeError: Error {
    case systemCall(String)
    case protocolViolation(String)
}

/// 在受限 Unix socket 上执行一次有效和一次无效的 Provider 认证回环。
public func runProviderIPCProbe() throws -> ProviderIPCProbeResult {
    // AF_UNIX 路径长度受限；使用短路径，同时仍由仅当前用户可访问的目录保护 socket。
    let suffix = String(UUID().uuidString.prefix(12))
    let directory = URL(fileURLWithPath: "/tmp/gk-ipc-\(suffix)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }

    let socketURL = directory.appendingPathComponent("provider.sock")
    let listener = try UnixSocketListener(path: socketURL.path)
    defer { listener.close() }

    let secret = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
    let authenticator = ProviderAuthenticator(secret: secret)
    let server = ProbeServer(listener: listener, authenticator: authenticator)
    server.start()

    let accepted = try ProbeClient(path: socketURL.path, authenticator: authenticator).authenticate(providerInstallID: "chrome-install-1")
    let rejected = try ProbeClient(path: socketURL.path, authenticator: authenticator).authenticate(
        providerInstallID: "chrome-install-1",
        responseOverride: Data(repeating: 0, count: 32)
    ) == false
    try server.finish()

    return ProviderIPCProbeResult(
        transport: "unix_domain_socket",
        socketPermissions: try listener.permissions(),
        challengeAccepted: accepted,
        invalidCredentialRejected: rejected,
        sameUIDThreatModel: "not_resistant_to_compromised_same_uid_process"
    )
}

// MARK: - Probe Server

/// 仅服务两次连接的临时服务器：一次有效凭据、一次无效凭据。
private final class ProbeServer: @unchecked Sendable {
    private let listener: UnixSocketListener
    private let authenticator: ProviderAuthenticator
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var error: Error?

    init(listener: UnixSocketListener, authenticator: ProviderAuthenticator) {
        self.listener = listener
        self.authenticator = authenticator
    }

    /// 在后台串行处理两个客户端，避免测试客户端与 accept 调用互相阻塞。
    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { completion.signal() }
            do {
                // 有效和无效凭据都走同一监听与分帧路径，避免只验证到独立模拟分支。
                try handleClient()
                try handleClient()
            } catch {
                lock.lock()
                self.error = error
                lock.unlock()
            }
        }
    }

    /// 等待服务器处理完成，并将后台线程中的错误回传给调用方。
    func finish() throws {
        completion.wait()
        lock.lock()
        defer { lock.unlock() }
        if let error { throw error }
    }

    /// 执行单个 Provider 的 hello、challenge、authenticate 握手。
    private func handleClient() throws {
        let fd = try listener.accept()
        defer { Darwin.close(fd) }

        let hello = try SocketLine.read(from: fd)
        let fields = hello.split(separator: " ", maxSplits: 1).map(String.init)
        guard fields.count == 2, fields[0] == "provider_hello" else {
            throw ProviderIPCProbeError.protocolViolation("expected provider_hello")
        }

        let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        try SocketLine.write("provider_challenge \(nonce.base64EncodedString())", to: fd)

        let authentication = try SocketLine.read(from: fd)
        let responseFields = authentication.split(separator: " ", maxSplits: 1).map(String.init)
        guard responseFields.count == 2,
              responseFields[0] == "provider_authenticate",
              let response = Data(base64Encoded: responseFields[1]) else {
            throw ProviderIPCProbeError.protocolViolation("expected provider_authenticate")
        }

        let accepted = authenticator.verify(response, providerInstallID: fields[1], nonce: nonce)
        try SocketLine.write(accepted ? "provider_authenticated" : "provider_auth_failed", to: fd)
    }
}

/// 连接临时 Unix socket 并完成一次 Provider 认证交换。
private struct ProbeClient {
    let path: String
    let authenticator: ProviderAuthenticator

    /// 使用指定安装 ID 发起认证；测试可传入伪造响应验证拒绝路径。
    func authenticate(providerInstallID: String, responseOverride: Data? = nil) throws -> Bool {
        let fd = try UnixSocketConnection.connect(path: path)
        defer { Darwin.close(fd) }

        try SocketLine.write("provider_hello \(providerInstallID)", to: fd)
        let challenge = try SocketLine.read(from: fd)
        let fields = challenge.split(separator: " ", maxSplits: 1).map(String.init)
        guard fields.count == 2,
              fields[0] == "provider_challenge",
              let nonce = Data(base64Encoded: fields[1]) else {
            throw ProviderIPCProbeError.protocolViolation("expected provider_challenge")
        }

        let response = responseOverride ?? authenticator.response(for: providerInstallID, nonce: nonce)
        try SocketLine.write("provider_authenticate \(response.base64EncodedString())", to: fd)
        return try SocketLine.read(from: fd) == "provider_authenticated"
    }
}

// MARK: - Unix Socket Transport

/// 封装只服务于 Spike 的 Unix domain socket 监听端。
private final class UnixSocketListener: @unchecked Sendable {
    private let fd: Int32
    private let path: String

    /// 创建 socket、绑定路径、收紧文件权限并开始监听。
    init(path: String) throws {
        self.path = path
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ProviderIPCProbeError.systemCall("socket") }

        do {
            var address = try UnixSocketAddress(path: path).value
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw ProviderIPCProbeError.systemCall("bind") }
            guard chmod(path, 0o600) == 0 else { throw ProviderIPCProbeError.systemCall("chmod") }
            guard listen(fd, 4) == 0 else { throw ProviderIPCProbeError.systemCall("listen") }
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    /// 接受单个连接；调用方负责关闭返回的文件描述符。
    func accept() throws -> Int32 {
        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else { throw ProviderIPCProbeError.systemCall("accept") }
        return client
    }

    /// 读取 socket 文件权限，确保结果由实际文件系统状态而非配置值决定。
    func permissions() throws -> String {
        guard let permissions = try FileManager.default
            .attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber else {
            throw ProviderIPCProbeError.systemCall("attributesOfItem")
        }
        return String(format: "%04o", permissions.uintValue & 0o777)
    }

    /// 关闭监听描述符；路径由外层临时目录清理逻辑移除。
    func close() {
        Darwin.close(fd)
    }
}

/// 建立到指定 Unix domain socket 的客户端连接。
private enum UnixSocketConnection {
    /// 返回已连接的文件描述符；调用方负责关闭。
    static func connect(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ProviderIPCProbeError.systemCall("socket") }
        do {
            var address = try UnixSocketAddress(path: path).value
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw ProviderIPCProbeError.systemCall("connect") }
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }
}

/// 将字符串路径编码为 POSIX `sockaddr_un`。
private struct UnixSocketAddress {
    var value = sockaddr_un()

    /// 校验路径长度并填充 C 结构体，避免静默截断导致连接到错误 socket。
    init(path: String) throws {
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: value.sun_path) else {
            throw ProviderIPCProbeError.protocolViolation("socket path too long")
        }
        value.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &value.sun_path) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
    }
}

/// 使用有上限的换行帧承载 Spike 握手消息。
private enum SocketLine {
    /// 写入一条完整换行帧，短写入一律视为失败。
    static func write(_ line: String, to fd: Int32) throws {
        let data = Data((line + "\n").utf8)
        let count = data.withUnsafeBytes { buffer in
            Darwin.write(fd, buffer.baseAddress, buffer.count)
        }
        guard count == data.count else { throw ProviderIPCProbeError.systemCall("write") }
    }

    /// 读取最多 4 KB 的单行消息，防止异常客户端消耗无界内存。
    static func read(from fd: Int32) throws -> String {
        var data = Data()
        // 换行分帧为等待认证的异常客户端设置明确的内存上限。
        while data.count < 4096 {
            var byte: UInt8 = 0
            let count = Darwin.read(fd, &byte, 1)
            guard count == 1 else { throw ProviderIPCProbeError.systemCall("read") }
            if byte == 10 { return String(decoding: data, as: UTF8.self) }
            data.append(byte)
        }
        throw ProviderIPCProbeError.protocolViolation("line too long")
    }
}
