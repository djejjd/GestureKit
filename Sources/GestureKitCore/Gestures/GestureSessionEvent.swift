import Foundation

/// 三指候选刚成立时的无语义输入事实。
public struct GestureCandidate: Equatable, Sendable {
    public let startedAt: TimeInterval
    public let centroidX: Float
    public let centroidY: Float
    /// 候选的输入事实；用于按配置推导能力，不编码为具体手势名称。
    public let fingerCount: Int

    public init(startedAt: TimeInterval, centroidX: Float, centroidY: Float, fingerCount: Int = 3) {
        self.startedAt = startedAt
        self.centroidX = centroidX
        self.centroidY = centroidY
        self.fingerCount = fingerCount
    }
}

/// 原语识别阶段产生的事件。候选事件不等待分类结果。
public enum GestureSessionEvent: Equatable, Sendable {
    case candidateStarted(GestureCandidate)
    case primitiveClassified(RecognizedGesture)
    case primitiveRejected(RecognizedGesture)

    public var recognizedGesture: RecognizedGesture? {
        switch self {
        case .primitiveClassified(let value), .primitiveRejected(let value): return value
        case .candidateStarted: return nil
        }
    }
}
