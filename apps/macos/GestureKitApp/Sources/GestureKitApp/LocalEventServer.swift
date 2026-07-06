import Foundation
import GestureKitCore
import Network

final class LocalEventServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private let logger: GestureKitLogger

    init(port: NWEndpoint.Port = 17653, logger: GestureKitLogger) throws {
        listener = try NWListener(using: .tcp, on: port)
        self.logger = logger
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

    private func connectionCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return connections.count
    }
}
