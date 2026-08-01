import Foundation
import Network

enum E2ELinkScenario: String, Codable, Equatable, Sendable {
    case success
    case leaseExpiry
    case providerUnavailable
    case resultUnknown
}

struct E2ELinkOperationCommand: Codable, Equatable, Sendable {
    let token: String
    let gestureSessionId: String
    let operationId: String
    let scenario: E2ELinkScenario
}

enum E2EControlResult: Codable, Equatable, Sendable {
    case accepted(gestureSessionId: String, operationId: String)
    case rejected(reason: String)
}

actor E2EControlServer {
    private let token: String
    private var consumedOperationIDs = Set<String>()
    private let dispatch: @Sendable (E2ELinkOperationCommand) async -> E2EControlResult
    private var listener: NWListener?
    private var _port: UInt16?

    /// 监听器就绪后可用；仅用于测试获取系统分配的端口。
    var port: UInt16? { _port }

    init(
        token: String,
        dispatch: @escaping @Sendable (E2ELinkOperationCommand) async -> E2EControlResult
    ) {
        self.token = token
        self.dispatch = dispatch
    }

    /// 校验层：token 匹配 + operationId 幂等，再委托 dispatch 进入 runtime。
    func handle(_ command: E2ELinkOperationCommand) async -> E2EControlResult {
        guard command.token == token else {
            return .rejected(reason: "e2e_control_unauthorized")
        }
        guard consumedOperationIDs.insert(command.operationId).inserted else {
            return .rejected(reason: "e2e_operation_reused")
        }
        return await dispatch(command)
    }

    // MARK: - Network layer

    /// 在 127.0.0.1 上绑定系统分配端口，ready 后输出 `gesturekit_e2e_control_port=<decimal>`。
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 0)

        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let port = listener.port {
                    Task { await self.setPort(port.rawValue) }
                    print("gesturekit_e2e_control_port=\(port.rawValue)")
                }
            case .failed:
                break
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleIncomingConnection(connection) }
        }

        listener.start(queue: .global())
    }

    func stop() {
        listener?.cancel()
        listener = nil
        _port = nil
    }

    // MARK: - Connection handling

    private func handleIncomingConnection(_ connection: NWConnection) {
        guard isLoopback(connection) else {
            send(.rejected(reason: "e2e_control_non_loopback"), on: connection)
            return
        }

        connection.start(queue: .global())

        // 允许读入最多 64KB 以便在回调内判定 16KB 上限。
        let maxReceive = 65536
        connection.receive(minimumIncompleteLength: 1, maximumLength: maxReceive) { [weak self] data, _, _, error in
            guard let self else { connection.cancel(); return }

            if error != nil {
                connection.cancel()
                return
            }

            guard let data else {
                connection.cancel()
                return
            }

            if data.count > 16384 {
                Task { await self.send(.rejected(reason: "e2e_control_input_too_large"), on: connection) }
                return
            }

            guard let command = try? JSONDecoder().decode(E2ELinkOperationCommand.self, from: data) else {
                Task { await self.send(.rejected(reason: "e2e_control_decode_failed"), on: connection) }
                return
            }

            Task {
                let result = await self.handle(command)
                await self.send(result, on: connection)
            }
        }
    }

    private func isLoopback(_ connection: NWConnection) -> Bool {
        if case .hostPort(let host, _) = connection.endpoint {
            return host == "127.0.0.1" || host == "::1" || host == "localhost"
        }
        return false
    }

    private func send(_ result: E2EControlResult, on connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(result) else {
            connection.cancel()
            return
        }
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func setPort(_ value: UInt16) {
        _port = value
    }
}
