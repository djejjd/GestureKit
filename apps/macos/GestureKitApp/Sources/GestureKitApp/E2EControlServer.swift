import Foundation

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

    init(
        token: String,
        dispatch: @escaping @Sendable (E2ELinkOperationCommand) async -> E2EControlResult
    ) {
        self.token = token
        self.dispatch = dispatch
    }

    func handle(_ command: E2ELinkOperationCommand) async -> E2EControlResult {
        guard command.token == token else {
            return .rejected(reason: "e2e_control_unauthorized")
        }
        guard consumedOperationIDs.insert(command.operationId).inserted else {
            return .rejected(reason: "e2e_operation_reused")
        }
        return await dispatch(command)
    }
}
