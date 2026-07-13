import Foundation

/// 由 macOS App 持有并下发给 Provider 的权威配置快照。
public struct AppConfiguration: Codable, Equatable, Sendable {
    public let storeEpoch: String
    public let schemaVersion: Int
    public let configurationVersion: Int64
    public let rules: [BindingRule]
    public let recognition: GestureRecognitionSettings

    public init(
        storeEpoch: String,
        schemaVersion: Int,
        configurationVersion: Int64,
        rules: [BindingRule],
        recognition: GestureRecognitionSettings
    ) {
        self.storeEpoch = storeEpoch
        self.schemaVersion = schemaVersion
        self.configurationVersion = configurationVersion
        self.rules = rules
        self.recognition = recognition
    }

    public static func initial(storeEpoch: String = UUID().uuidString) -> AppConfiguration {
        AppConfiguration(
            storeEpoch: storeEpoch,
            schemaVersion: 2,
            configurationVersion: 1,
            rules: DefaultRules.v1Bindings,
            recognition: .standard
        )
    }
}
