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
}
