/// 原生鼠标过滤的纯状态机。所有时刻来自本机单调时钟，绝不重放事件。
enum ShieldMouseEvent { case down, dragged, up }

struct DragInputShieldState {
    static let leaseMs: Int64 = 800
    static let settlingMs: Int64 = 120
    private(set) var sessionID: String?
    private(set) var deadline: Int64 = 0
    private var settlingDeadline: Int64?
    private var ownsDown = false
    /// 先前已透传的 down 不属于本候选；必须继续透传 drag/up。
    private var forwardedDown = false

    mutating func arm(sessionID: String, now: Int64) -> Bool {
        guard self.sessionID != sessionID else { return false }
        self.sessionID = sessionID
        deadline = now + Self.leaseMs
        settlingDeadline = nil
        // 分帧落地升级候选不能丢失已拦截的按下序列。
        return true
    }

    mutating func finish(sessionID: String, now: Int64) {
        guard self.sessionID == sessionID, settlingDeadline == nil else { return }
        settlingDeadline = min(deadline, now + Self.settlingMs)
    }

    mutating func cancel() {
        sessionID = nil
        deadline = 0
        settlingDeadline = nil
        ownsDown = false
        // 已透传的 down 直到实际 up 才结束；cancel 不能伪造抬起。
    }

    mutating func expire(now: Int64) {
        if sessionID != nil && (now >= deadline || (!ownsDown && now >= (settlingDeadline ?? deadline))) {
            cancel()
        }
    }

    mutating func suppress(_ event: ShieldMouseEvent, now: Int64) -> Bool {
        expire(now: now)
        switch event {
        case .down:
            if sessionID != nil && !forwardedDown {
                ownsDown = true
                return true
            }
            forwardedDown = true
            return false
        case .dragged:
            return ownsDown
        case .up:
            forwardedDown = false
            guard ownsDown else { return false }
            ownsDown = false
            expire(now: now)
            return true
        }
    }
}
