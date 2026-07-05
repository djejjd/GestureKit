import Foundation

public protocol SettingsStore {
    func loadRules() throws -> [Rule]
    func saveRules(_ rules: [Rule]) throws
}

public struct UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults
    private let rulesKey = "gesturekit.rules.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadRules() throws -> [Rule] {
        guard let data = defaults.data(forKey: rulesKey) else {
            return DefaultRules.v1
        }
        return try JSONDecoder.gestureKit.decode([Rule].self, from: data)
    }

    public func saveRules(_ rules: [Rule]) throws {
        let data = try JSONEncoder.gestureKit.encode(rules)
        defaults.set(data, forKey: rulesKey)
    }
}
