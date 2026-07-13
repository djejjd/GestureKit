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
            schemaVersion: 2,
            configurationVersion: max(1, (existing?.configurationVersion ?? 0) + 1),
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
            return configuration
        }
        let configuration = AppConfiguration.initial()
        try store.saveAppConfiguration(configuration)
        return configuration
    }
}
