import Foundation
import XCTest
@testable import GestureKitApp
import GestureKitCore

final class ConfigurationMigrationTests: XCTestCase {
    func testLegacySettingsImportRunsOnlyOnce() throws {
        let defaults = UserDefaults(suiteName: "GestureKitTests.configurationMigration")!
        defaults.removePersistentDomain(forName: "GestureKitTests.configurationMigration")
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let migration = ConfigurationMigration(store: store)
        let legacyConfiguration = AppConfiguration(
            storeEpoch: "legacy-epoch",
            schemaVersion: 2,
            configurationVersion: 1,
            rules: DefaultRules.v1Bindings,
            recognition: .standard
        )

        try migration.importLegacy(legacyConfiguration)

        XCTAssertEqual(try store.loadAppConfiguration(), legacyConfiguration)
        XCTAssertThrowsError(try migration.importLegacy(legacyConfiguration))
    }

    func testAuthoritativeConfigurationUpgradesSchema2WithoutReplacingBindings() throws {
        let defaults = UserDefaults(suiteName: "GestureKitTests.configurationSchemaUpgrade")!
        defaults.removePersistentDomain(forName: "GestureKitTests.configurationSchemaUpgrade")
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let schema2 = AppConfiguration(
            storeEpoch: "schema-2",
            schemaVersion: 2,
            configurationVersion: 9,
            rules: DefaultRules.v1Bindings,
            recognition: .sensitive
        )
        try store.saveAppConfiguration(schema2)

        let upgraded = try ConfigurationMigration(store: store).authoritativeConfiguration()

        XCTAssertEqual(upgraded.schemaVersion, 3)
        XCTAssertEqual(upgraded.configurationVersion, schema2.configurationVersion)
        XCTAssertEqual(upgraded.rules, schema2.rules)
        XCTAssertEqual(upgraded.recognition, schema2.recognition)
        XCTAssertFalse(upgraded.gestureDefinitions.isEmpty)
        XCTAssertEqual(try store.loadAppConfiguration(), upgraded)
    }
}
