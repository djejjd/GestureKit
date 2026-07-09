import Foundation
import GestureKitCore
import Network

final class LocalEventServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private let logger: GestureKitLogger
    private let onMessage: @Sendable (LocalIPCEnvelope) -> Void

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
            self?.add(connection)
            connection.start(queue: .global(qos: .userInitiated))
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        let activeConnections = snapshotConnections()
        activeConnections.forEach { $0.cancel() }
        listener.cancel()
    }

    func publish(_ envelope: LocalIPCEnvelope) -> Int {
        guard let line = try? LocalIPCProtocol.encodeLine(envelope) else { return 0 }
        let data = Data((line + "\n").utf8)

        let activeConnections = snapshotConnections()
        activeConnections.forEach { connection in
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
        return activeConnections.count
    }

    private func add(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.logger.info("ipc_client_connected connections=\(self.connectionCount())")
            case .failed(let error):
                self.logger.warn("ipc_client_failed error=\"\(error)\"", rateLimitKey: "ipc_client_failed")
                self.remove(connection)
            case .cancelled:
                self.remove(connection)
            default:
                break
            }
        }
        lock.lock()
        connections.append(connection)
        lock.unlock()
        receiveNext(from: connection, buffer: Data())
    }

    private func receiveNext(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            var nextBuffer = buffer
            if let data, !data.isEmpty {
                nextBuffer.append(data)
                nextBuffer = self.consumeIncomingBuffer(nextBuffer)
            }
            if let error {
                self.logger.warn("ipc_client_receive_failed error=\"\(error)\"", rateLimitKey: "ipc_client_receive_failed")
                self.remove(connection)
                return
            }
            if isComplete {
                self.remove(connection)
                return
            }
            self.receiveNext(from: connection, buffer: nextBuffer)
        }
    }

    private func consumeIncomingBuffer(_ buffer: Data) -> Data {
        var remaining = buffer
        while let newlineIndex = remaining.firstIndex(of: 10) {
            let lineData = remaining[..<newlineIndex]
            if !lineData.isEmpty, let line = String(data: lineData, encoding: .utf8) {
                do {
                    onMessage(try LocalIPCProtocol.decodeLine(line))
                } catch {
                    logger.warn("ipc_message_decode_failed error=\"\(error)\"", rateLimitKey: "ipc_message_decode_failed")
                }
            }
            remaining.removeSubrange(...newlineIndex)
        }
        return remaining
    }

    private func snapshotConnections() -> [NWConnection] {
        lock.lock()
        defer { lock.unlock() }
        return connections
    }

    private func remove(_ connection: NWConnection) {
        lock.lock()
        connections.removeAll { $0 === connection }
        lock.unlock()
    }

    func connectionCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return connections.count
    }
}
