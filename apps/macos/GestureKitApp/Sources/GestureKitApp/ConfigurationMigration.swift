import Foundation
import GestureKitCore

/// 将扩展存量配置切换到 App 权威存储。迁移标记一旦落库即不可回退。
struct ConfigurationMigration {
    private let store: any AppConfigurationStore

    init(store: any AppConfigurationStore) {
        self.store = store
    }

    func importLegacy(_ configuration: AppConfiguration) throws {
        try store.importLegacyAppConfiguration(configuration)
    }

    func importLegacy(recognition: GestureRecognitionSettings) throws -> AppConfiguration {
        let existing = try store.loadAppConfiguration()
        let configuration = AppConfiguration(
            storeEpoch: existing?.storeEpoch ?? UUID().uuidString,
            schemaVersion: 3,
            configurationVersion: max(1, (existing?.configurationVersion ?? 0) + 1),
            gestureDefinitions: existing?.gestureDefinitions ?? DefaultRules.v1GestureDefinitions,
            rules: existing?.rules ?? DefaultRules.v1Bindings,
            recognition: recognition
        )
        try importLegacy(configuration)
        return configuration
    }

    func isLegacyImportPending() throws -> Bool {
        try !store.hasLegacyMigrationMarker()
    }

    func authoritativeConfiguration() throws -> AppConfiguration {
        if let configuration = try store.loadAppConfiguration() {
            guard configuration.schemaVersion < 3 else { return configuration }
            let upgraded = AppConfiguration(storeEpoch: configuration.storeEpoch, schemaVersion: 3, configurationVersion: configuration.configurationVersion, gestureDefinitions: configuration.gestureDefinitions, rules: configuration.rules, recognition: configuration.recognition)
            try store.saveAppConfiguration(upgraded)
            return upgraded
        }
        let configuration = AppConfiguration.initial()
        try store.saveAppConfiguration(configuration)
        return configuration
    }
}
