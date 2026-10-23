import Foundation
import GestureKitCore

/// App 边界的候选会话协调器。它只处理 session、时序和定向路由，
/// 不知道任何 Chrome API，也不启动 InteractionShield。
@MainActor
final class GestureSessionCoordinator {
    static let contextBudgetMs: Int64 = 250
    static let actionBudgetMs: Int64 = 300
    static let centerDoubleTapWindowMs: Int64 = 300

    private struct PendingTap {
        let sessionID: String
        let recognized: RecognizedGesture
        let classifiedAtMs: Int64
    }

    private struct SessionState {
        let startedAtMs: Int64
        var classifiedAtMs: Int64?
        var composedGesture: ComposedGesture?
        var bufferedContext: ProviderContextSnapshot?
        var isAwaitingDoubleTap = false
    }

    private var ruleEngine: any RuleResolving
    private let guardJournal: (String) -> Void
    private let guardRouter: (String, GestureCandidate) -> Void
    private let guardReleaseRouter: (String) -> Void
    private let guardDiscardRouter: (String) -> Void
    private let contextRouter: (String, Int64) -> Void
    private let actionRouter: (String, ActionDescriptor) -> Void
    private let monotonicClockMs: () -> Int64
    private let sessionID: () -> String
    private let pendingTapScheduler: (Int64, @escaping @MainActor () -> Void) -> Void
    private let logger: GestureKitLogger
    private var activeSessions: [String: SessionState] = [:]
    /// `GestureSessionEvent` 尚未携带 ID；因此按候选实际到达顺序关联其终态事件，
    /// 不得从 UUID 字符串排序推断归属。
    private var candidateOrder: [String] = []
    private var pendingCenterTap: PendingTap?

    init(
        ruleEngine: any RuleResolving = RuleEngine(),
        guardJournal: @escaping (String) -> Void = { _ in },
        guardRouter: @escaping (String, GestureCandidate) -> Void = { _, _ in },
        guardReleaseRouter: @escaping (String) -> Void = { _ in },
        guardDiscardRouter: @escaping (String) -> Void = { _ in },
        contextRouter: @escaping (String, Int64) -> Void = { _, _ in },
        actionRouter: @escaping (String, ActionDescriptor) -> Void = { _, _ in },
        monotonicClockMs: @escaping () -> Int64 = { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) },
        sessionID: @escaping () -> String = { UUID().uuidString },
        pendingTapScheduler: @escaping (Int64, @escaping @MainActor () -> Void) -> Void = { delayMs, operation in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled else { return }
                operation()
            }
        },
        logger: GestureKitLogger = GestureKitLogger()
    ) {
        self.ruleEngine = ruleEngine
        self.guardJournal = guardJournal
        self.guardRouter = guardRouter
        self.guardReleaseRouter = guardReleaseRouter
        self.guardDiscardRouter = guardDiscardRouter
        self.contextRouter = contextRouter
        self.actionRouter = actionRouter
        self.monotonicClockMs = monotonicClockMs
        self.sessionID = sessionID
        self.pendingTapScheduler = pendingTapScheduler
        self.logger = logger
    }

    func updateRuleEngine(_ ruleEngine: any RuleResolving) { self.ruleEngine = ruleEngine }

    /// 暂停、配置变化及跨组件失联统一关闭所有候选，旧回调不可复活会话。
    func cancelAll() {
        let ids = Array(activeSessions.keys)
        activeSessions.removeAll()
        candidateOrder.removeAll()
        pendingCenterTap = nil
        for id in ids { guardReleaseRouter(id) }
    }

    /// 候选一出现即先持久化/路由 guard；绝不等待分类或上下文。
    @discardableResult
    func handle(_ event: GestureSessionEvent) -> String? {
        switch event {
        case .candidateStarted(let candidate):
            let id = sessionID()
            activeSessions[id] = SessionState(startedAtMs: monotonicClockMs(), classifiedAtMs: nil, composedGesture: nil, bufferedContext: nil)
            candidateOrder.append(id)
            guardJournal(id)
            guardRouter(id, candidate)
            return id
        case .primitiveClassified(let recognized):
            guard let id = takeNextCandidate() else { return nil }
            primitiveClassified(recognized, sessionID: id)
            return id
        case .primitiveRejected:
            guard let id = takeNextCandidate() else { return nil }
            activeSessions.removeValue(forKey: id)
            if pendingCenterTap?.sessionID == id { pendingCenterTap = nil }
            guardReleaseRouter(id)
            return id
        }
    }

    /// context response 与组合仲裁并行：分类时已发出 context 请求；事实返回后立即决策。
    func receiveContext(_ context: ProviderContextSnapshot, for sessionID: String) {
        guard var session = activeSessions[sessionID],
              let classifiedAt = session.classifiedAtMs,
              let gesture = session.composedGesture else { return }
        let elapsed = monotonicClockMs() - classifiedAt
        guard elapsed <= Self.contextBudgetMs, elapsed <= Self.actionBudgetMs else {
            // 静默丢弃是"小概率没反应"的来源（无动作也无操作记录）；打 warn 便于定位真慢的 context。
            logger.warn("context_dropped elapsed=\(elapsed)ms budget=\(Self.contextBudgetMs)ms sessionId=\(sessionID)")
            return
        }
        if session.isAwaitingDoubleTap {
            session.bufferedContext = context
            activeSessions[sessionID] = session
            return
        }
        resolveAndDispatch(gesture: gesture, context: context, sessionID: sessionID, classifiedAt: classifiedAt)
    }

    private func primitiveClassified(_ recognized: RecognizedGesture, sessionID: String) {
        let now = monotonicClockMs()
        if recognized.gesture == .threeFingerTap,
           let centroidX = recognized.centroidX,
           centroidX > 0.20,
           centroidX < 0.80 {
            handleCenterTap(recognized, now: now, sessionID: sessionID)
            return
        }
        guard let gesture = compose(recognized, now: now, sessionID: sessionID) else {
            contextRouter(sessionID, now + Self.contextBudgetMs)
            return
        }
        guard var session = activeSessions[sessionID] else { return }
        session.classifiedAtMs = now
        session.composedGesture = gesture
        activeSessions[sessionID] = session
        contextRouter(sessionID, now + Self.contextBudgetMs)
        // 边缘点按与滑动的组合在这里立即完成，不等待中间双击窗口。
        // action 实际等 context 事实返回后由 receiveContext 发出。
        _ = gesture
    }

    private func handleCenterTap(_ recognized: RecognizedGesture, now: Int64, sessionID: String) {
        if let pending = pendingCenterTap {
            let elapsed = now - pending.classifiedAtMs
            if elapsed <= Self.centerDoubleTapWindowMs {
                pendingCenterTap = nil
                activeSessions.removeValue(forKey: pending.sessionID)
                guardDiscardRouter(pending.sessionID)
                guardDiscardRouter(sessionID)
                guard var session = activeSessions[sessionID] else { return }
                session.classifiedAtMs = now
                session.composedGesture = .threeFingerDoubleTapCenter
                session.isAwaitingDoubleTap = false
                activeSessions[sessionID] = session
                logger.info("compose double_tap sessionId=\(sessionID)")
                contextRouter(sessionID, now + Self.contextBudgetMs)
                return
            }
            commitPendingCenterTap(sessionID: pending.sessionID)
        }

        guard var session = activeSessions[sessionID] else { return }
        session.classifiedAtMs = now
        session.composedGesture = .threeFingerTap
        session.isAwaitingDoubleTap = true
        activeSessions[sessionID] = session
        pendingCenterTap = PendingTap(sessionID: sessionID, recognized: recognized, classifiedAtMs: now)
        logger.debug("compose pending_stored centroidX=\(recognized.centroidX ?? -1) sessionId=\(sessionID)")
        contextRouter(sessionID, now + Self.contextBudgetMs)
        pendingTapScheduler(Self.centerDoubleTapWindowMs) { [weak self] in
            self?.commitPendingCenterTap(sessionID: sessionID)
        }
    }

    private func commitPendingCenterTap(sessionID: String) {
        guard pendingCenterTap?.sessionID == sessionID,
              var session = activeSessions[sessionID] else { return }
        pendingCenterTap = nil
        session.isAwaitingDoubleTap = false
        let bufferedContext = session.bufferedContext
        session.bufferedContext = nil
        guard session.composedGesture != nil, bufferedContext != nil else {
            activeSessions.removeValue(forKey: sessionID)
            guardReleaseRouter(sessionID)
            return
        }
        // 第一次 context 只用于确认目标并覆盖双击窗口；它的 250ms lease
        // 在 300ms 仲裁结束时已不再可安全执行，因此用同一会话重新取上下文。
        let refreshedAt = monotonicClockMs()
        session.classifiedAtMs = refreshedAt
        activeSessions[sessionID] = session
        contextRouter(sessionID, refreshedAt + Self.contextBudgetMs)
    }

    private func resolveAndDispatch(
        gesture: ComposedGesture,
        context: ProviderContextSnapshot,
        sessionID: String,
        classifiedAt: Int64
    ) {
        guard let action = ruleEngine.resolve(gesture: gesture, context: context) else { return }
        guard monotonicClockMs() - classifiedAt <= Self.actionBudgetMs else { return }
        actionRouter(sessionID, action)
        activeSessions.removeValue(forKey: sessionID)
    }

    private func compose(_ recognized: RecognizedGesture, now: Int64, sessionID: String) -> ComposedGesture? {
        guard let primitive = recognized.gesture else { return nil }
        switch primitive {
        case .threeFingerSwipeLeft: return .threeFingerSwipeLeft
        case .threeFingerSwipeRight: return .threeFingerSwipeRight
        case .twoFingerSwipeLeft: return .twoFingerSwipeLeft
        case .twoFingerSwipeRight: return .twoFingerSwipeRight
        case .fourFingerSwipeLeft: return .fourFingerSwipeLeft
        case .fourFingerSwipeRight: return .fourFingerSwipeRight
        case .fourFingerTap: return .fourFingerTap
        case .threeFingerTap:
            guard let centroidX = recognized.centroidX else {
                logger.debug("compose centroidX=nil sessionId=\(sessionID)")
                return nil
            }
            if centroidX <= 0.20 {
                logger.info("compose edge=left centroidX=\(centroidX) sessionId=\(sessionID)")
                return .threeFingerTapLeftEdge
            }
            if centroidX >= 0.80 {
                logger.info("compose edge=right centroidX=\(centroidX) sessionId=\(sessionID)")
                return .threeFingerTapRightEdge
            }
            return .threeFingerTap
        }
    }

    private func takeNextCandidate() -> String? {
        while !candidateOrder.isEmpty {
            let id = candidateOrder.removeFirst()
            if activeSessions[id] != nil { return id }
        }
        return nil
    }
}
