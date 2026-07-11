import Foundation
import GestureKitCore
import Network

final class LocalEventServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    /// 每条 transport 连接有稳定 ID，认证完成后 registry 用该 ID 定向发送。
    private var connections: [UUID: NWConnection] = [:]
    private let logger: GestureKitLogger
    private let onMessage: @Sendable (LocalIPCEnvelope) -> Void
    /// v2 迁移入口：在旧 envelope 解码失败时保留原始 JSON 供认证层处理。
    var onRawMessage: (@Sendable (UUID, Data) -> Void)?
    var onConnectionCountChanged: ((Int) -> Void)?

    init(
        port: NWEndpoint.Port = 17653,
        logger: GestureKitLogger,
        onMessage: @escaping @Sendable (LocalIPCEnvelope) -> Void = { _ in }
    ) throws {
        listener = try NWListener(using: .tcp, on: port)
        self.logger = logger
        self.onMessage = onMessage
    }

    func start() {
        listener.stateUpdateHandler = { [logger] state in
            switch state {
            case .ready:
                logger.info("ipc_listener_ready port=17653")
            case .failed(let error):
                logger.error("ipc_listener_failed error=\"\(error)\"")
            case .cancelled:
                logger.info("ipc_listener_cancelled")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.add(connection, id: UUID())
            connection.start(queue: .global(qos: .userInitiated))
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        let activeConnections = snapshotConnections().map(\.value)
        activeConnections.forEach { $0.cancel() }
        listener.cancel()
    }

    func publish(_ envelope: LocalIPCEnvelope) -> Int {
        guard let line = try? LocalIPCProtocol.encodeLine(envelope) else { return 0 }
        let data = Data((line + "\n").utf8)

        let activeConnections = snapshotConnections().map(\.value)
        activeConnections.forEach { connection in
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
        return activeConnections.count
    }

    /// 向已认证 Provider 对应的单条连接发送 v2 envelope，禁止广播动作。
    func send(_ envelope: ProviderEnvelope, to connectionID: UUID) throws {
        let data = try JSONEncoder().encode(envelope) + Data([10])
        lock.lock(); let connection = connections[connectionID]; lock.unlock()
        guard let connection else { throw ProviderSessionError.unknownSession }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func add(_ connection: NWConnection, id: UUID) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.logger.info("ipc_client_connected connections=\(self.connectionCount())")
                self.notifyConnectionCountChanged()
            case .failed(let error):
                self.logger.warn("ipc_client_failed error=\"\(error)\"", rateLimitKey: "ipc_client_failed")
                self.remove(connection, id: id)
            case .cancelled:
                self.remove(connection, id: id)
            default:
                break
            }
        }
        lock.lock()
        connections[id] = connection
        lock.unlock()
        receiveNext(from: connection, id: id, buffer: Data())
    }

    private func receiveNext(from connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            var nextBuffer = buffer
            if let data, !data.isEmpty {
                nextBuffer.append(data)
                nextBuffer = self.consumeIncomingBuffer(nextBuffer, connectionID: id)
            }
            if let error {
                self.logger.warn("ipc_client_receive_failed error=\"\(error)\"", rateLimitKey: "ipc_client_receive_failed")
                self.remove(connection, id: id)
                return
            }
            if isComplete {
                self.remove(connection, id: id)
                return
            }
            self.receiveNext(from: connection, id: id, buffer: nextBuffer)
        }
    }

    private func consumeIncomingBuffer(_ buffer: Data, connectionID: UUID) -> Data {
        var remaining = buffer
        while let newlineIndex = remaining.firstIndex(of: 10) {
            let lineData = remaining[..<newlineIndex]
            if !lineData.isEmpty, let line = String(data: lineData, encoding: .utf8) {
                do {
                    onMessage(try LocalIPCProtocol.decodeLine(line))
                } catch {
                    onRawMessage?(connectionID, Data(lineData))
                }
            }
            remaining.removeSubrange(...newlineIndex)
        }
        return remaining
    }

    private func snapshotConnections() -> [UUID: NWConnection] {
        lock.lock()
        defer { lock.unlock() }
        return connections
    }

    private func remove(_ connection: NWConnection, id: UUID) {
        lock.lock()
        connections.removeValue(forKey: id)
        let count = connections.count
        lock.unlock()
        onConnectionCountChanged?(count)
    }

    private func notifyConnectionCountChanged() {
        let count = connectionCount()
        onConnectionCountChanged?(count)
    }

    func connectionCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return connections.count
    }
}
