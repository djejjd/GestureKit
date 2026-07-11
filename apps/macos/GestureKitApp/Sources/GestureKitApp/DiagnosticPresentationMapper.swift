import Foundation

/// 面向用户展示的诊断摘要，禁止泄露协议枚举和内部错误码。
struct PresentedDiagnostic: Equatable {
    let title: String
    let suggestion: String
}

/// 将内部终态映射为稳定、可理解的中文文案。
func presentDiagnostic(_ timeline: OperationTimeline) -> PresentedDiagnostic {
    switch timeline.terminalState {
    case .succeeded:
        return PresentedDiagnostic(title: "操作已完成", suggestion: "本次操作已收到明确结果")
    case .failed:
        return PresentedDiagnostic(title: "操作未完成", suggestion: "可以查看证据包了解失败阶段")
    case .resultUnknown:
        return PresentedDiagnostic(title: "操作结果暂时无法确认", suggestion: "系统已保存完整诊断信息")
    case .operationInterrupted:
        return PresentedDiagnostic(title: "操作被中断", suggestion: "Provider 连接发生变化，系统已保存诊断信息")
    case nil:
        return PresentedDiagnostic(title: "操作进行中", suggestion: "系统正在等待 Provider 返回结果")
    }
}
