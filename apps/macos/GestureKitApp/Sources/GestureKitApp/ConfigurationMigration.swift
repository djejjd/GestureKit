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
}
