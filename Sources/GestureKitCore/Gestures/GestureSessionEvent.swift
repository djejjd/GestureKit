import Foundation

/// 三指候选刚成立时的无语义输入事实。
public struct GestureCandidate: Equatable, Sendable {
    public let startedAt: TimeInterval
    public let centroidX: Float
    public let centroidY: Float

    public init(startedAt: TimeInterval, centroidX: Float, centroidY: Float) {
        self.startedAt = startedAt
        self.centroidX = centroidX
        self.centroidY = centroidY
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
