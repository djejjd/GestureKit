import Foundation
import GestureKitCore
import Network

final class LocalEventServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    init(port: NWEndpoint.Port = 17653) throws {
        listener = try NWListener(using: .tcp, on: port)
    }

    func start() {
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

    func publish(_ envelope: LocalIPCEnvelope) {
        guard let line = try? LocalIPCProtocol.encodeLine(envelope) else { return }
        let data = Data((line + "\n").utf8)

        snapshotConnections().forEach { connection in
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func add(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
    }

    private func snapshotConnections() -> [NWConnection] {
        lock.lock()
        defer { lock.unlock() }
        return connections
    }
}
