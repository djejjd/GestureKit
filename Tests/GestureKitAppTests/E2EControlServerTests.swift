import XCTest
@testable import GestureKitApp

final class E2EControlServerTests: XCTestCase {
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
}

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
