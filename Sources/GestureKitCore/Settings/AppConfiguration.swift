import Foundation

/// 由 macOS App 持有并下发给 Provider 的权威配置快照。
public struct AppConfiguration: Codable, Equatable, Sendable {
    public let storeEpoch: String
    public let schemaVersion: Int
    public let configurationVersion: Int64
    public let gestureDefinitions: [GestureDefinition]
    public let rules: [BindingRule]
    public let recognition: GestureRecognitionSettings

    public init(
        storeEpoch: String,
        schemaVersion: Int,
        configurationVersion: Int64,
        gestureDefinitions: [GestureDefinition] = DefaultRules.v1GestureDefinitions,
        rules: [BindingRule],
        recognition: GestureRecognitionSettings
    ) {
        self.storeEpoch = storeEpoch
        self.schemaVersion = schemaVersion
        self.configurationVersion = configurationVersion
        self.gestureDefinitions = gestureDefinitions
        self.rules = rules
        self.recognition = recognition
    }

    public static func initial(storeEpoch: String = UUID().uuidString) -> AppConfiguration {
        AppConfiguration(
            storeEpoch: storeEpoch,
            schemaVersion: 3,
            configurationVersion: 1,
            gestureDefinitions: DefaultRules.v1GestureDefinitions,
            rules: DefaultRules.v1Bindings,
            recognition: .standard
        )
    }

    public func updatingBinding(id: String, enabled: Bool) throws -> AppConfiguration {
        guard rules.contains(where: { $0.id == id }) else {
            throw AppConfigurationEditError.unknownBinding(id)
        }
        let updatedRules = rules.map { rule in
            guard rule.id == id else { return rule }
            return BindingRule(
                id: rule.id,
                gestureDefinitionId: rule.gestureDefinitionId,
                contextConstraints: rule.contextConstraints,
                actionId: rule.actionId,
                actionParameters: rule.actionParameters,
                priority: rule.priority,
                enabled: enabled
            )
        }
        return AppConfiguration(
            storeEpoch: storeEpoch,
            schemaVersion: schemaVersion,
            configurationVersion: configurationVersion + 1,
            gestureDefinitions: gestureDefinitions,
            rules: updatedRules,
            recognition: recognition
        )
    }

    private enum CodingKeys: String, CodingKey { case storeEpoch, schemaVersion, configurationVersion, gestureDefinitions, rules, recognition }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        storeEpoch = try values.decode(String.self, forKey: .storeEpoch)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        configurationVersion = try values.decode(Int64.self, forKey: .configurationVersion)
        gestureDefinitions = try values.decodeIfPresent([GestureDefinition].self, forKey: .gestureDefinitions) ?? DefaultRules.v1GestureDefinitions
        rules = try values.decode([BindingRule].self, forKey: .rules)
        recognition = try values.decode(GestureRecognitionSettings.self, forKey: .recognition)
    }
}

public enum AppConfigurationEditError: Error, Equatable {
    case unknownBinding(String)
}
