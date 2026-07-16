import XCTest
@testable import GestureKitApp
@testable import GestureKitCore

@MainActor
final class GestureSessionCoordinatorTests: XCTestCase {
    func testCandidateImmediatelyJournalsAndRoutesGuard() {
        var journaled: [String] = []
        var routed: [String] = []
        let coordinator = GestureSessionCoordinator(
            guardJournal: { journaled.append($0) },
            guardRouter: { id, _ in routed.append(id) }
        )

        let sessionId = coordinator.handle(.candidateStarted(GestureCandidate(startedAt: 0, centroidX: 0.5, centroidY: 0.5)))

        XCTAssertNotNil(sessionId)
        XCTAssertEqual(journaled, [sessionId!])
        XCTAssertEqual(routed, [sessionId!])
    }

    func testOverlappingCandidatesClassifyInArrivalOrderAndRejectedSessionIsRemoved() {
        var requested: [String] = []
        var ids = ["first", "second"]
        let coordinator = GestureSessionCoordinator(
            contextRouter: { id, _ in requested.append(id) },
            sessionID: { ids.removeFirst() }
        )
        let first = coordinator.handle(.candidateStarted(candidate))
        let second = coordinator.handle(.candidateStarted(candidate))

        XCTAssertEqual(coordinator.handle(.primitiveClassified(swipeLeft)), first)
        XCTAssertEqual(coordinator.handle(.primitiveRejected(rejected)), second)
        XCTAssertEqual(requested, ["first"])
        XCTAssertNil(coordinator.handle(.primitiveClassified(swipeLeft)))
    }

    func testInterruptedCandidateReleasesItsGuardBeforeNextCandidateClassifies() {
        var ids = ["interrupted", "next"]
        var released: [String] = []
        var requested: [String] = []
        let coordinator = GestureSessionCoordinator(
            guardReleaseRouter: { released.append($0) },
            contextRouter: { id, _ in requested.append(id) },
            sessionID: { ids.removeFirst() }
        )

        XCTAssertEqual(coordinator.handle(.candidateStarted(candidate)), "interrupted")
        XCTAssertEqual(coordinator.handle(.primitiveRejected(rejected)), "interrupted")
        XCTAssertEqual(coordinator.handle(.candidateStarted(candidate)), "next")
        XCTAssertEqual(coordinator.handle(.primitiveClassified(swipeLeft)), "next")

        XCTAssertEqual(released, ["interrupted"])
        XCTAssertEqual(requested, ["next"])
    }

    func testContextAfterClassificationUsesSessionCompositionWithoutCallerSupplyingGesture() {
        var actions: [(String, StandardActionID)] = []
        let coordinator = GestureSessionCoordinator(
            actionRouter: { id, action in actions.append((id, action.actionId)) },
            monotonicClockMs: { 10 },
            sessionID: { "session" }
        )
        let id = coordinator.handle(.candidateStarted(candidate))!
        _ = coordinator.handle(.primitiveClassified(swipeLeft))

        coordinator.receiveContext(ProviderContextSnapshot(contextId: "ctx", targetKind: .noTarget, targetRef: nil, deadline: 1), for: id)

        XCTAssertEqual(actions.map(\.0), ["session"])
        XCTAssertEqual(actions.map(\.1), [.browserTabActivateNext])
    }

    func testSynchronousContextResponseDuringClassificationUsesPersistedSessionComposition() {
        var actions: [StandardActionID] = []
        var coordinator: GestureSessionCoordinator!
        coordinator = GestureSessionCoordinator(
            contextRouter: { id, _ in
                coordinator.receiveContext(
                    ProviderContextSnapshot(contextId: "ctx", targetKind: .noTarget, targetRef: nil, deadline: 1),
                    for: id
                )
            },
            actionRouter: { _, action in actions.append(action.actionId) },
            monotonicClockMs: { 10 },
            sessionID: { "session" }
        )

        _ = coordinator.handle(.candidateStarted(candidate))
        _ = coordinator.handle(.primitiveClassified(swipeLeft))

        XCTAssertEqual(actions, [.browserTabActivateNext])
    }

    func testContextAfterActionBudgetDoesNotDispatchEvenWhenDescriptorDeadlineIsFuture() {
        var now: Int64 = 0
        var actionCount = 0
        let coordinator = GestureSessionCoordinator(
            actionRouter: { _, _ in actionCount += 1 },
            monotonicClockMs: { now },
            sessionID: { "session" }
        )
        let id = coordinator.handle(.candidateStarted(candidate))!
        _ = coordinator.handle(.primitiveClassified(swipeLeft))
        now = 151

        coordinator.receiveContext(ProviderContextSnapshot(contextId: "ctx", targetKind: .noTarget, targetRef: nil, deadline: .max), for: id)

        XCTAssertEqual(actionCount, 0)
    }

    func testRuleResolutionCrossingActionBudgetDoesNotDispatch() {
        let clock = TestClock(now: 0)
        var actionCount = 0
        let coordinator = GestureSessionCoordinator(
            ruleEngine: AdvancingRuleResolver(clock: clock, resolvedAtMs: 151),
            actionRouter: { _, _ in actionCount += 1 },
            monotonicClockMs: { clock.now },
            sessionID: { "session" }
        )
        let id = coordinator.handle(.candidateStarted(candidate))!
        _ = coordinator.handle(.primitiveClassified(swipeLeft))

        coordinator.receiveContext(ProviderContextSnapshot(contextId: "ctx", targetKind: .noTarget, targetRef: nil, deadline: .max), for: id)

        XCTAssertEqual(actionCount, 0)
    }
}

private final class TestClock: @unchecked Sendable {
    var now: Int64

    init(now: Int64) {
        self.now = now
    }
}

private final class AdvancingRuleResolver: RuleResolving, @unchecked Sendable {
    private let clock: TestClock
    private let resolvedAtMs: Int64

    init(clock: TestClock, resolvedAtMs: Int64) {
        self.clock = clock
        self.resolvedAtMs = resolvedAtMs
    }

    func resolve(gesture: ComposedGesture, context: ProviderContextSnapshot) -> ActionDescriptor? {
        clock.now = resolvedAtMs
        return ActionDescriptor(
            actionId: .browserTabActivateNext,
            contextId: context.contextId,
            targetRef: nil,
            parameters: [:],
            deadline: context.deadline
        )
    }
}

private let candidate = GestureCandidate(startedAt: 0, centroidX: 0.5, centroidY: 0.5)
private let swipeLeft = RecognizedGesture(
    gesture: .threeFingerSwipeLeft, status: .success, reason: .success,
    durationMs: 120, dx: -0.2, dy: 0, thresholds: .standard, centroidX: 0.5, centroidY: 0.5
)
private let rejected = RecognizedGesture(
    gesture: nil, status: .gestureUnstable, reason: .distanceTooShort,
    durationMs: 120, dx: 0, dy: 0, thresholds: .standard, centroidX: 0.5, centroidY: 0.5
)
