import AppKit
import ApplicationServices
import GestureKitCore

@MainActor
protocol DragInputShield: AnyObject {
    func start()
    func arm(sessionID: String)
    func finish(sessionID: String)
    func cancel(reason: String)
    func stop()
}

/// 回调持有稳定的间接引用；护盾析构后，等待主队列清理期间事件只透传。
@MainActor
private final class ShieldCallbackContext {
    weak var owner: NativeDragInputShield?
}

/// 资源操作均在主队列；对象析构只调度这个 Sendable 生命周期对象，
/// 不调用 macOS 15 的 isolated-deinit 回部署 thunk，也不留下悬空 userInfo。
@MainActor
private final class ShieldTapResources {
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var timer: Timer?
    let context = ShieldCallbackContext()

    func invalidate() {
        timer?.invalidate()
        timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
    }

    nonisolated func scheduleInvalidation() {
        // 强持有 resources/context，直到主队列停止 tap；回调的 weak owner 此时可已为 nil。
        DispatchQueue.main.async { self.invalidate() }
    }
}

/// 只注册左键事件，不请求权限、不修改系统偏好。lease 到期后输入始终透传。
/// event tap 与触控候选都在主 run loop；系统超时会自动禁用 tap，回调不做磁盘 I/O。
@MainActor
final class NativeDragInputShield: DragInputShield {
    private var state = DragInputShieldState()
    private let resources = ShieldTapResources()
    private var running = false
    private var unavailableReason = "event_tap_create_failed"
    private let logger: GestureKitLogger
    private var audit: (id: String, started: Int64, down: Int, drag: Int, up: Int)?
    private let isChromeFrontmost: () -> Bool

    init(logger: GestureKitLogger, isChromeFrontmost: @escaping () -> Bool = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome"
    }) {
        self.logger = logger
        self.isChromeFrontmost = isChromeFrontmost
        resources.context.owner = self
    }

    deinit { resources.scheduleInvalidation() }

    func start() {
        running = true
        _ = installIfNeeded()
    }

    func arm(sessionID: String) {
        guard running, isChromeFrontmost() else { return }
        guard installIfNeeded() else {
            logger.warn("input_shield_summary sessionId=\(sessionID) stage=arm outcome=unavailable reason=\(unavailableReason) elapsed_ms=0")
            return
        }
        let now = Self.now()
        expire(now: now)
        if audit?.id != sessionID { summarize(reason: "superseded", now: now) }
        guard state.arm(sessionID: sessionID, now: now) else { return }
        audit = (sessionID, now, 0, 0, 0)
        logger.debug("input_shield_stage sessionId=\(sessionID) stage=armed lease_ms=800")
    }

    func finish(sessionID: String) {
        state.finish(sessionID: sessionID, now: Self.now())
        logger.debug("input_shield_stage sessionId=\(sessionID) stage=settling")
    }

    func cancel(reason: String) {
        state.cancel()
        summarize(reason: reason, now: Self.now())
    }

    func stop() {
        running = false
        cancel(reason: "stopped")
        resources.invalidate()
    }

    private func installIfNeeded() -> Bool {
        // macOS 仅在用户已经授予相关权限时安装主动过滤，不自动弹权限提示。
        guard CGPreflightListenEventAccess() else { unavailableReason = "input_monitoring_not_granted"; return false }
        guard AXIsProcessTrusted() else { unavailableReason = "accessibility_not_granted"; return false }
        unavailableReason = "event_tap_create_failed"
        if let tap = resources.tap {
            let enabled = CGEvent.tapIsEnabled(tap: tap)
            if !enabled { unavailableReason = "event_tap_disabled" }
            return enabled
        }
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let created = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: Self.callback,
            userInfo: Unmanaged.passUnretained(resources.context).toOpaque()
        ) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            CFMachPortInvalidate(created)
            return false
        }
        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            _ = state.suppress(.down, now: Self.now())
        }
        resources.tap = created
        resources.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.state.sessionID != nil && !self.isChromeFrontmost() { self.cancel(reason: "frontmost_changed") }
                self.expire(now: Self.now())
            }
        }
        resources.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<ShieldCallbackContext>.fromOpaque(userInfo).takeUnretainedValue()
        let suppressed = MainActor.assumeIsolated { context.owner?.handleEvent(type) ?? false }
        return suppressed ? nil : Unmanaged.passUnretained(event)
    }

    private func handleEvent(_ type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancel(reason: type == .tapDisabledByTimeout ? "tap_timeout" : "tap_disabled")
            if type == .tapDisabledByTimeout, CGPreflightListenEventAccess(), AXIsProcessTrusted(), let tap = resources.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }
        if state.sessionID != nil && !isChromeFrontmost() { cancel(reason: "frontmost_changed") }
        let now = Self.now()
        expire(now: now)
        let kind: ShieldMouseEvent
        switch type {
        case .leftMouseDown: kind = .down
        case .leftMouseDragged: kind = .dragged
        case .leftMouseUp: kind = .up
        default: return false
        }
        let suppressed = state.suppress(kind, now: now)
        if suppressed {
            switch kind {
            case .down: audit?.down += 1
            case .dragged: audit?.drag += 1
            case .up: audit?.up += 1
            }
        }
        if state.sessionID == nil { summarize(reason: "released", now: now) }
        return suppressed
    }

    private func expire(now: Int64) {
        state.expire(now: now)
        if state.sessionID == nil { summarize(reason: "lease_expired", now: now) }
    }

    private func summarize(reason: String, now: Int64) {
        guard let audit else { return }
        self.audit = nil
        let logger = logger
        // event tap 的实时回调只更新计数；摘要在后续主队列任务写入受管理日志。
        DispatchQueue.main.async {
            logger.info("input_shield_summary sessionId=\(audit.id) gesture=swipe_candidate context=chrome guard=armed outcome=\(reason) stage=terminal down=\(audit.down) drag=\(audit.drag) up=\(audit.up) elapsed_ms=\(now - audit.started)")
        }
    }

    private static func now() -> Int64 { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) }
}
