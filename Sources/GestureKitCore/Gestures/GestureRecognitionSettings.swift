import Foundation

public enum SwipeSensitivity: String, Codable, Equatable, Sendable {
    case robust
    case standard
    case sensitive
}

public struct GestureRecognitionSettings: Codable, Equatable, Sendable {
    public let swipeSensitivity: SwipeSensitivity
    public let swipeMinDistance: Float
    public let swipeHorizontalRatio: Float
    public let swipeMinDurationMs: Int
    public let swipeMaxDurationMs: Int

    public init(
        swipeSensitivity: SwipeSensitivity,
        swipeMinDistance: Float,
        swipeHorizontalRatio: Float,
        swipeMinDurationMs: Int,
        swipeMaxDurationMs: Int
    ) {
        self.swipeSensitivity = swipeSensitivity
        self.swipeMinDistance = swipeMinDistance
        self.swipeHorizontalRatio = swipeHorizontalRatio
        self.swipeMinDurationMs = swipeMinDurationMs
        self.swipeMaxDurationMs = swipeMaxDurationMs
    }

    public static let robust = GestureRecognitionSettings(
        swipeSensitivity: .robust,
        swipeMinDistance: 0.11,
        swipeHorizontalRatio: 1.8,
        swipeMinDurationMs: 60,
        swipeMaxDurationMs: 350
    )

    public static let standard = GestureRecognitionSettings(
        swipeSensitivity: .standard,
        swipeMinDistance: 0.09,
        swipeHorizontalRatio: 1.5,
        swipeMinDurationMs: 60,
        swipeMaxDurationMs: 420
    )

    public static let sensitive = GestureRecognitionSettings(
        swipeSensitivity: .sensitive,
        swipeMinDistance: 0.075,
        swipeHorizontalRatio: 1.25,
        swipeMinDurationMs: 50,
        swipeMaxDurationMs: 480
    )

    public static func preset(_ sensitivity: SwipeSensitivity) -> GestureRecognitionSettings {
        switch sensitivity {
        case .robust:
            return .robust
        case .standard:
            return .standard
        case .sensitive:
            return .sensitive
        }
    }
}
