import Foundation
import GestureKitCore
import Network
import CryptoKit

enum GestureKitHostSelfTest {
    static func run() throws {
        let payload = Data("{\"version\":1}".utf8)
        let encoded = NativeMessageCodec.encode(payload)
        guard encoded.prefix(4) == Data([13, 0, 0, 0]) else {
            throw NSError(domain: "GestureKitHostSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid length prefix"])
        }

        let decoded = try NativeMessageCodec.decode(encoded)
        guard decoded == payload else {
            throw NSError(domain: "GestureKitHostSelfTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Decoded payload mismatch"])
        }

        do {
            _ = try NativeMessageCodec.decode(Data([1, 2, 3]))
            throw NSError(domain: "GestureKitHostSelfTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Too-short input did not fail"])
        } catch NativeMessageCodecError.messageTooShort {
        }

        do {
            _ = try NativeMessageCodec.decode(Data([2, 0, 0, 0, 1]))
            throw NSError(domain: "GestureKitHostSelfTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "Length mismatch did not fail"])
        } catch NativeMessageCodecError.lengthMismatch(expected: 2, actual: 1) {
        }

        let hostResponse = try makeHostUnavailableResponse()
        let decodedEnvelope = try JSONDecoder().decode(ProviderEnvelope.self, from: hostResponse)
        guard decodedEnvelope.protocolVersion == 2,
              decodedEnvelope.error?.code == "app_unavailable" else {
            throw NSError(domain: "GestureKitHostSelfTest", code: 6, userInfo: [NSLocalizedDescriptionKey: "Host unavailable response is not v2"])
        }
        let framedHostResponse = NativeMessageCodec.encode(hostResponse)
        guard try NativeMessageCodec.decode(framedHostResponse) == hostResponse else {
            throw NSError(domain: "GestureKitHostSelfTest", code: 5, userInfo: [NSLocalizedDescriptionKey: "Host response frame did not decode"])
        }

        print("GestureKitHost self-test passed")
    }
}

if CommandLine.arguments.contains("--self-test") {
    do {
        try GestureKitHostSelfTest.run()
        exit(0)
    } catch {
        fputs("GestureKitHost self-test failed: \(error)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--stdio-bridge") {
    runStdioBridge()
    exit(0)
}

runStdioBridge()

func runStdioBridge() {
    // E2E 验收通过 GESTUREKIT_IPC_PORT 让 Host 连到测试 App 的独立 IPC 端口，
    // 避免与真实实例的默认 17653 冲突。无效值回退默认端口。
    let ipcPort: NWEndpoint.Port = {
        if let raw = ProcessInfo.processInfo.environment["GESTUREKIT_IPC_PORT"],
           let value = UInt16(raw),
           value > 0,
           let port = NWEndpoint.Port(rawValue: value) {
            return port
        }
        return 17653
    }()
    let bridge = ProviderBridge(port: ipcPort)
    bridge.start()
    bridge.wait()
}

func makeHostUnavailableResponse() throws -> Data {
    let envelope = ProviderEnvelope(
        protocolVersion: 2,
        messageId: "host-app-unavailable",
        providerSessionId: "host-bridge",
        gestureSessionId: nil,
        operationId: nil,
        type: .healthResponse,
        timestamp: 0,
        payload: .healthResponse(HealthResponsePayload(probeSequence: 0, healthy: false)),
        error: ProviderError(code: "app_unavailable", message: "GestureKit App 不可用")
    )
    return try JSONEncoder().encode(envelope)
}

/// 透明桥接层：只处理 Native Messaging 帧与 App 字节流，不解释动作或 telemetry。
/// 自愈：App 掉线时不退出进程，自己重建 TCP 连接；仅当 stdin 关闭（Chrome 关端口/SW 死）才退出。
private final class ProviderBridge: @unchecked Sendable {
    private let ipcPort: NWEndpoint.Port
    private var connection: NWConnection
    /// 连接代际：每次重建连接递增；旧连接的迟到回调据此识别并丢弃。
    private var connectionGeneration = 0
    /// 是否已调度一次重连（防 .failed 与 receive error 对同一事件双重调度）。
    private var reconnectScheduled = false
    /// App 是否已连通：断连期间 stdin 消息回 app_unavailable，不转发。
    private var connectedToApp = false
    /// 重连间隔（秒）：掉线后快速重试接住 App 重启，之后保持低频。
    private let reconnectIntervalSeconds: Double = 2
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffer = Data()
    private let installID = "chrome-native-host"

    init(port: NWEndpoint.Port) {
        self.ipcPort = port
        self.connection = AppIPCClient(port: port).connect()
    }

    func start() {
        startConnection(connection, generation: connectionGeneration)
        startStdinReader()
    }

    func wait() {
        _ = done.wait(timeout: .distantFuture)
    }

    // MARK: - App 连接管理（自愈）

    private func startConnection(_ conn: NWConnection, generation: Int) {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.lock()
                guard generation == self.connectionGeneration else { self.lock.unlock(); return }
                self.connectedToApp = true
                self.reconnectScheduled = false
                self.lock.unlock()
                self.sendHello(generation: generation)
            // App 尚未启动时，NWConnection 通常先进入 waiting；不能等它自行
            // 转为 failed，否则已打开的 Chrome 端口会一直无法完成认证。
            case .waiting, .failed, .cancelled:
                self.handleAppDisconnected(generation: generation)
            default:
                break
            }
        }
        receiveNext(on: conn, generation: generation)
        conn.start(queue: .global(qos: .userInitiated))
    }

    /// App 掉线：不退出，调度一次重连（代际与调度双 guard）。
    private func handleAppDisconnected(generation: Int) {
        lock.lock()
        guard generation == connectionGeneration else { lock.unlock(); return }
        connectedToApp = false
        if reconnectScheduled { lock.unlock(); return }
        reconnectScheduled = true
        lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + reconnectIntervalSeconds) { [weak self] in
            self?.reconnectToApp(afterDisconnecting: generation)
        }
    }

    private func reconnectToApp(afterDisconnecting disconnectedGeneration: Int) {
        lock.lock()
        // .ready 可能在退避期内到达。此时旧的重连任务必须无副作用，
        // 不能中断已恢复的会话或重复发起认证。
        guard disconnectedGeneration == connectionGeneration, reconnectScheduled else {
            lock.unlock()
            return
        }
        let oldConnection = connection
        connectionGeneration += 1
        reconnectScheduled = false
        let generation = connectionGeneration
        let newConnection = AppIPCClient(port: ipcPort).connect()
        connection = newConnection
        lock.unlock()
        oldConnection.cancel()
        startConnection(newConnection, generation: generation)
    }

    private func receiveNext(on conn: NWConnection, generation: Int) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            // 连接已被重建：丢弃旧连接的迟到回调，避免递归到新连接。
            self.lock.lock()
            let stale = generation != self.connectionGeneration
            self.lock.unlock()
            if stale { return }

            if let data, !data.isEmpty {
                self.consume(data)
            }
            if error != nil || isComplete {
                self.handleAppDisconnected(generation: generation)
                return
            }
            self.receiveNext(on: conn, generation: generation)
        }
    }

    // MARK: - 数据转发

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        let lines = drainLines()
        lock.unlock()

        lines.forEach { line in
            if !handleChallenge(line) {
                writeFrame(line)
            }
        }
    }

    private func drainLines() -> [Data] {
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 10) {
            let line = buffer[..<newlineIndex]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer.removeSubrange(...newlineIndex)
        }
        return lines
    }

    private func writeFrame(_ payload: Data) {
        FileHandle.standardOutput.write(NativeMessageCodec.encode(payload))
    }

    private func writeUnavailableFrame() {
        if let payload = try? makeHostUnavailableResponse() { writeFrame(payload) }
    }

    /// host 是 App 认证的 Provider 身份；只截获 challenge，业务 envelope 保持透明转发。
    private func sendHello(generation: Int) {
        lock.lock()
        let current = generation == connectionGeneration && connectedToApp
        lock.unlock()
        guard current else { return }
        let envelope = ProviderEnvelope(protocolVersion: 2, messageId: UUID().uuidString, providerSessionId: "host-bridge", gestureSessionId: nil, operationId: nil, type: .providerHello, timestamp: currentTimestamp(), payload: .providerHello(ProviderHelloPayload(installId: installID, protocolVersions: [2], environment: "chrome-native-host")), error: nil)
        sendEnvelope(envelope)
    }

    private func handleChallenge(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(ProviderEnvelope.self, from: data),
              case .providerChallenge(let challenge) = envelope.payload,
              let nonce = Data(base64Encoded: challenge.nonce),
              let secret = try? Data(contentsOf: credentialURL()), secret.count == 32 else { return false }
        let response = ProviderAuthenticator(secret: secret).response(for: installID, nonce: nonce)
        let hex = response.map { String(format: "%02x", $0) }.joined()
        let auth = ProviderEnvelope(protocolVersion: 2, messageId: UUID().uuidString, providerSessionId: envelope.providerSessionId, gestureSessionId: nil, operationId: nil, type: .providerAuthenticate, timestamp: currentTimestamp(), payload: .providerAuthenticate(ProviderAuthenticatePayload(installId: installID, hmac: hex)), error: nil)
        sendEnvelope(auth)
        return true
    }

    private func credentialURL() -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GestureKit/providers/\(installID).secret") }
    private func currentTimestamp() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private func sendEnvelope(_ envelope: ProviderEnvelope) { if let data = try? JSONEncoder().encode(envelope) { sendToApp(data) } }

    private func startStdinReader() {
        DispatchQueue.global(qos: .userInitiated).async {
            while true {
                guard let payload = self.readNativeMessagePayload() else {
                    // stdin 关闭 = Chrome 关端口 / SW 死，唯一合法退出点。
                    self.done.signal()
                    return
                }
                self.forwardStdinMessage(payload)
            }
        }
    }

    /// stdin（扩展）消息：App 已连通 → 转发；未连通 → 回 app_unavailable（失败即关闭，不缓冲）。
    private func forwardStdinMessage(_ payload: Data) {
        lock.lock()
        let connected = connectedToApp
        lock.unlock()
        if connected {
            sendToApp(payload)
        } else {
            writeUnavailableFrame()
        }
    }

    private func readNativeMessagePayload() -> Data? {
        let header = FileHandle.standardInput.readData(ofLength: 4)
        guard header.count == 4 else { return nil }
        let bytes = Array(header)
        let length =
            UInt32(bytes[0]) |
            UInt32(bytes[1]) << 8 |
            UInt32(bytes[2]) << 16 |
            UInt32(bytes[3]) << 24
        guard length > 0, length <= 1024 * 1024 else {
            fputs("GestureKitHost invalid native message length=\(length)\n", stderr)
            return nil
        }
        let payload = FileHandle.standardInput.readData(ofLength: Int(length))
        guard payload.count == Int(length) else {
            fputs("GestureKitHost truncated native message expected=\(length) actual=\(payload.count)\n", stderr)
            return nil
        }
        return payload
    }

    private func sendToApp(_ payload: Data) {
        lock.lock()
        let conn = connection
        lock.unlock()
        var line = payload
        line.append(10)
        conn.send(content: line, completion: .contentProcessed { error in
            if let error {
                fputs("GestureKitHost app send failed: \(error)\n", stderr)
            }
        })
    }
}
