import ApplicationServices
import Foundation

/// 验证短时 CGEventTap 是否能抑制鼠标默认行为的手工 Spike。
@main
struct InteractionShieldProbe {
    /// 解析参数、安装 event tap，并在指定时长后自动退出。
    static func main() {
        let configuration = Configuration(arguments: CommandLine.arguments)
        guard let probe = ShieldProbe(configuration: configuration) else {
            Foundation.exit(2)
        }
        probe.run()
    }
}

/// Probe 的运行时参数；默认仅监听，避免意外阻断正常输入。
private struct Configuration {
    let durationMs: Int
    let shieldMs: Int
    let shieldDelayMs: Int

    init(arguments: [String]) {
        durationMs = Self.value(named: "--duration-ms", in: arguments) ?? 5_000
        shieldMs = Self.value(named: "--shield-ms", in: arguments) ?? 0
        shieldDelayMs = Self.value(named: "--shield-delay-ms", in: arguments) ?? 0
    }

    /// 读取整数参数；非法值回退到默认值，以确保 Probe 不会无限运行。
    private static func value(named name: String, in arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return Int(arguments[index + 1])
    }
}

/// 持有 C 回调需要的对象生命周期，并负责在 lease 结束后自动退出。
private final class ShieldProbe {
    private let configuration: Configuration
    private var shieldStartsAt: Date?
    private var shieldEndsAt: Date?
    private var eventTap: CFMachPort?

    init?(configuration: Configuration) {
        self.configuration = configuration
        guard CGPreflightListenEventAccess() else {
            print("interaction_shield_probe_unavailable reason=input_monitoring_not_granted")
            return nil
        }
    }

    /// 安装 head-insert event tap，并在主运行循环中保持到 Probe 自动结束。
    func run() {
        let eventMask = CGEventMask(1) << CGEventType.leftMouseDown.rawValue |
            CGEventMask(1) << CGEventType.leftMouseDragged.rawValue |
            CGEventMask(1) << CGEventType.leftMouseUp.rawValue

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("interaction_shield_probe_unavailable reason=event_tap_create_failed")
            return
        }
        self.eventTap = eventTap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        if configuration.shieldMs > 0 {
            let start = Date().addingTimeInterval(Double(configuration.shieldDelayMs) / 1_000)
            shieldStartsAt = start
            shieldEndsAt = start.addingTimeInterval(Double(configuration.shieldMs) / 1_000)
        }
        print("interaction_shield_probe_started shield_delay_ms=\(configuration.shieldDelayMs) shield_ms=\(configuration.shieldMs) duration_ms=\(configuration.durationMs)")
        RunLoop.main.run(until: Date().addingTimeInterval(Double(configuration.durationMs) / 1_000))
        print("interaction_shield_probe_stopped")
    }

    /// 在 lease 内丢弃左键下压、拖动和释放；其他事件始终透传。
    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let probe = Unmanaged<ShieldProbe>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 系统禁用 event tap 后立即恢复监听，避免因暂时超时永久失效。
            if let eventTap = probe.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let shieldStartsAt = probe.shieldStartsAt,
              let shieldEndsAt = probe.shieldEndsAt,
              Date() >= shieldStartsAt,
              Date() < shieldEndsAt else {
            return Unmanaged.passUnretained(event)
        }
        print("interaction_shield_event_suppressed type=\(type.rawValue)")
        return nil
    }
}
