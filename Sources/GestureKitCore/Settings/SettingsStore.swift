import Foundation

public protocol SettingsStore {
    func loadRules() throws -> [Rule]
    func saveRules(_ rules: [Rule]) throws
}

/// App 配置的持久化边界。Provider 只能消费快照，不能通过此接口写入配置。
public protocol AppConfigurationStore {
    func loadAppConfiguration() throws -> AppConfiguration?
    func saveAppConfiguration(_ configuration: AppConfiguration) throws
    func importLegacyAppConfiguration(_ configuration: AppConfiguration) throws
}

public enum AppConfigurationStoreError: Error, Equatable {
    case legacyMigrationAlreadyCompleted
}

public struct UserDefaultsSettingsStore: SettingsStore, AppConfigurationStore {
    private let defaults: UserDefaults
    private let rulesKey = "gesturekit.rules.v1"
    private let appConfigurationTransactionKey = "gesturekit.appConfiguration.v2.transaction"

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

    public func loadAppConfiguration() throws -> AppConfiguration? {
        guard let data = defaults.data(forKey: appConfigurationTransactionKey) else { return nil }
        return try JSONDecoder.gestureKit.decode(AppConfigurationTransaction.self, from: data).configuration
    }

    public func saveAppConfiguration(_ configuration: AppConfiguration) throws {
        let migrated = (try? loadTransaction()?.legacyMigrationComplete) ?? false
        try commit(configuration, marksLegacyMigrationComplete: migrated)
    }

    public func importLegacyAppConfiguration(_ configuration: AppConfiguration) throws {
        guard !(try loadTransaction()?.legacyMigrationComplete ?? false) else {
            throw AppConfigurationStoreError.legacyMigrationAlreadyCompleted
        }
        try commit(configuration, marksLegacyMigrationComplete: true)
    }

    /// 一个持久化记录包含快照、迁移标记、epoch 与版本，因此不存在部分提交状态。
    private func commit(_ configuration: AppConfiguration, marksLegacyMigrationComplete: Bool) throws {
        let transaction = AppConfigurationTransaction(
            configuration: configuration,
            legacyMigrationComplete: marksLegacyMigrationComplete,
            storeEpoch: configuration.storeEpoch,
            configurationVersion: configuration.configurationVersion
        )
        defaults.set(try JSONEncoder.gestureKit.encode(transaction), forKey: appConfigurationTransactionKey)
    }

    private func loadTransaction() throws -> AppConfigurationTransaction? {
        guard let data = defaults.data(forKey: appConfigurationTransactionKey) else { return nil }
        return try JSONDecoder.gestureKit.decode(AppConfigurationTransaction.self, from: data)
    }
}

private struct AppConfigurationTransaction: Codable {
    let configuration: AppConfiguration
    let legacyMigrationComplete: Bool
    let storeEpoch: String
    let configurationVersion: Int64
}
