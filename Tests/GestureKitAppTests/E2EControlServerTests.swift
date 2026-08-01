import Network
import XCTest
@testable import GestureKitApp

final class E2EControlServerTests: XCTestCase {
    // MARK: - Validation tests (existing)

    func testRejectsCommandWhenTokenDoesNotMatch() async {
        let server = E2EControlServer(token: "valid-token") { _ in
            .accepted(gestureSessionId: "g", operationId: "o")
        }

        let result = await server.handle(.init(
            token: "wrong-token",
            gestureSessionId: "g-1",
            operationId: "o-1",
            scenario: .success
        ))

        XCTAssertEqual(result, .rejected(reason: "e2e_control_unauthorized"))
    }

    func testRejectsReusedOperationIDWithoutCallingRuntime() async {
        let calls = LockedBox<Int>(0)
        let server = E2EControlServer(token: "valid-token") { command in
            calls.withValue { $0 += 1 }
            return .accepted(gestureSessionId: command.gestureSessionId, operationId: command.operationId)
        }
        let first = E2ELinkOperationCommand(
            token: "valid-token",
            gestureSessionId: "g-1",
            operationId: "o-1",
            scenario: .success
        )

        _ = await server.handle(first)
        let repeated = await server.handle(.init(
            token: "valid-token",
            gestureSessionId: "g-2",
            operationId: "o-1",
            scenario: .success
        ))

        XCTAssertEqual(repeated, .rejected(reason: "e2e_operation_reused"))
        XCTAssertEqual(calls.value, 1)
    }

    // MARK: - Network layer tests

    func testStartBindsLoopbackAndAcceptsValidCommand() async throws {
        let token = "tk-\(UUID().uuidString)"
        let server = E2EControlServer(token: token) { cmd in
            .accepted(gestureSessionId: cmd.gestureSessionId, operationId: cmd.operationId)
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let port = try await waitForPort(of: server, timeout: 5.0)

        let command = E2ELinkOperationCommand(
            token: token, gestureSessionId: "gs-1", operationId: "op-1", scenario: .success
        )
        let result = try await send(command: command, to: port)

        XCTAssertEqual(result, .accepted(gestureSessionId: "gs-1", operationId: "op-1"))
    }

    func testRejectsCommandWithWrongTokenOverNetwork() async throws {
        let token = "tk-\(UUID().uuidString)"
        let server = E2EControlServer(token: token) { _ in
            XCTFail("dispatch must not be called for wrong token")
            return .rejected(reason: "unreachable")
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let port = try await waitForPort(of: server, timeout: 5.0)

        let command = E2ELinkOperationCommand(
            token: "wrong", gestureSessionId: "gs-1", operationId: "op-1", scenario: .success
        )
        let result = try await send(command: command, to: port)

        XCTAssertEqual(result, .rejected(reason: "e2e_control_unauthorized"))
    }

    func testRejectsReusedOperationIDOverNetwork() async throws {
        let token = "tk-\(UUID().uuidString)"
        let callCount = LockedBox<Int>(0)
        let server = E2EControlServer(token: token) { cmd in
            callCount.withValue { $0 += 1 }
            return .accepted(gestureSessionId: cmd.gestureSessionId, operationId: cmd.operationId)
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let port = try await waitForPort(of: server, timeout: 5.0)

        let command = E2ELinkOperationCommand(
            token: token, gestureSessionId: "gs-1", operationId: "op-1", scenario: .success
        )
        _ = try await send(command: command, to: port)

        let repeated = E2ELinkOperationCommand(
            token: token, gestureSessionId: "gs-2", operationId: "op-1", scenario: .success
        )
        let result = try await send(command: repeated, to: port)

        XCTAssertEqual(result, .rejected(reason: "e2e_operation_reused"))
        XCTAssertEqual(callCount.value, 1)
    }

    func testRejectsInvalidJSON() async throws {
        let server = E2EControlServer(token: "tk") { _ in
            XCTFail("dispatch must not be called for invalid JSON")
            return .rejected(reason: "unreachable")
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let port = try await waitForPort(of: server, timeout: 5.0)

        let invalidData = "not-json".data(using: .utf8)!
        let result = try await send(data: invalidData, to: port)

        XCTAssertEqual(result, .rejected(reason: "e2e_control_decode_failed"))
    }

    func testRejectsOversizedInput() async throws {
        let server = E2EControlServer(token: "tk") { _ in
            XCTFail("dispatch must not be called for oversized input")
            return .rejected(reason: "unreachable")
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let port = try await waitForPort(of: server, timeout: 5.0)

        let oversized = Data(repeating: 0x78, count: 16_385) // 'x' * 16385
        let result = try await send(data: oversized, to: port)

        XCTAssertEqual(result, .rejected(reason: "e2e_control_input_too_large"))
    }
}

// MARK: - Network test helpers

private enum E2ETestError: Error {
    case timeout
    case noData
}

private func waitForPort(of server: E2EControlServer, timeout: TimeInterval) async throws -> UInt16 {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let port = await server.port {
            return port
        }
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
    throw E2ETestError.timeout
}

private func send(command: E2ELinkOperationCommand, to port: UInt16) async throws -> E2EControlResult {
    let data = try JSONEncoder().encode(command)
    return try await send(data: data, to: port)
}

private func send(data: Data, to port: UInt16) async throws -> E2EControlResult {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
        throw E2ETestError.noData
    }
    let connection = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)
    return try await withCheckedThrowingContinuation { continuation in
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                            connection.cancel()
                            return
                        }
                        guard let data else {
                            continuation.resume(throwing: E2ETestError.noData)
                            connection.cancel()
                            return
                        }
                        do {
                            let result = try JSONDecoder().decode(E2EControlResult.self, from: data)
                            continuation.resume(returning: result)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                        connection.cancel()
                    }
                })
            case .failed(let error):
                continuation.resume(throwing: error)
            default:
                break
            }
        }
        connection.start(queue: .global())
    }
}

// MARK: - Thread-safe value container

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func withValue(_ update: (inout Value) -> Void) {
        lock.withLock { update(&storage) }
    }
}
