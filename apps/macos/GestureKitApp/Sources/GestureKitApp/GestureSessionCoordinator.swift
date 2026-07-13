import Foundation
import GestureKitCore

/// App 边界的候选会话协调器。它只处理 session、时序和定向路由，
/// 不知道任何 Chrome API，也不启动 InteractionShield。
@MainActor
final class GestureSessionCoordinator {
    static let contextBudgetMs: Int64 = 120
    static let actionBudgetMs: Int64 = 150
    static let centerDoubleTapWindowMs: Int64 = 300

    private struct PendingTap {
        let sessionID: String
        let recognized: RecognizedGesture
        let classifiedAtMs: Int64
    }

    private let ruleEngine: any RuleResolving
    private let guardJournal: (String) -> Void
    private let guardRouter: (String) -> Void
    private let contextRouter: (String, Int64) -> Void
    private let actionRouter: (String, ActionDescriptor) -> Void
    private let monotonicClockMs: () -> Int64
    private let sessionID: () -> String
    private var activeSessions: [String: Int64] = [:]
    private var pendingCenterTap: PendingTap?

    init(
        ruleEngine: any RuleResolving = RuleEngine(),
        guardJournal: @escaping (String) -> Void = { _ in },
        guardRouter: @escaping (String) -> Void = { _ in },
        contextRouter: @escaping (String, Int64) -> Void = { _, _ in },
        actionRouter: @escaping (String, ActionDescriptor) -> Void = { _, _ in },
        monotonicClockMs: @escaping () -> Int64 = { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) },
        sessionID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.ruleEngine = ruleEngine
        self.guardJournal = guardJournal
        self.guardRouter = guardRouter
        self.contextRouter = contextRouter
        self.actionRouter = actionRouter
        self.monotonicClockMs = monotonicClockMs
        self.sessionID = sessionID
    }

    /// 候选一出现即先持久化/路由 guard；绝不等待分类或上下文。
    @discardableResult
    func handle(_ event: GestureSessionEvent) -> String? {
        switch event {
        case .candidateStarted:
            let id = sessionID()
            activeSessions[id] = monotonicClockMs()
            guardJournal(id)
            guardRouter(id)
            return id
        case .primitiveClassified(let recognized):
            guard let id = activeSessions.keys.sorted().last else { return nil }
            primitiveClassified(recognized, sessionID: id)
            return id
        case .primitiveRejected:
            return activeSessions.keys.sorted().last
        }
    }

    /// context response 与组合仲裁并行：分类时已发出 context 请求；事实返回后立即决策。
    func receiveContext(_ context: ProviderContextSnapshot, for sessionID: String, gesture: ComposedGesture) {
        guard let classifiedAt = activeSessions[sessionID], monotonicClockMs() - classifiedAt <= Self.contextBudgetMs else { return }
        guard let action = ruleEngine.resolve(gesture: gesture, context: context) else { return }
        actionRouter(sessionID, action)
    }

    private func primitiveClassified(_ recognized: RecognizedGesture, sessionID: String) {
        let now = monotonicClockMs()
        activeSessions[sessionID] = now
        contextRouter(sessionID, now + Self.contextBudgetMs)
        guard let gesture = compose(recognized, now: now, sessionID: sessionID) else { return }
        // 边缘点按与滑动的组合在这里立即完成，不等待中间双击窗口。
        // action 实际等 context 事实返回后由 receiveContext 发出。
        _ = gesture
    }

    private func compose(_ recognized: RecognizedGesture, now: Int64, sessionID: String) -> ComposedGesture? {
        guard let primitive = recognized.gesture else { return nil }
        switch primitive {
        case .threeFingerSwipeLeft: return .threeFingerSwipeLeft
        case .threeFingerSwipeRight: return .threeFingerSwipeRight
        case .threeFingerTap:
            guard let centroidX = recognized.centroidX else { return nil }
            if centroidX <= 0.20 { return .threeFingerTapLeftEdge }
            if centroidX >= 0.80 { return .threeFingerTapRightEdge }
            if let pendingCenterTap, now - pendingCenterTap.classifiedAtMs <= Self.centerDoubleTapWindowMs {
                self.pendingCenterTap = nil
                return .threeFingerDoubleTapCenter
            }
            pendingCenterTap = PendingTap(sessionID: sessionID, recognized: recognized, classifiedAtMs: now)
            return .threeFingerTap
        }
    }
}
