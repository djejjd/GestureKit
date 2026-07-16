import XCTest
@testable import GestureKitCore

final class AppConfigurationTests: XCTestCase {
    func testConfigurationRoundTripsItsAuthorityMetadataAndContents() throws {
        let configuration = AppConfiguration(
            storeEpoch: "epoch-1",
            schemaVersion: 2,
            configurationVersion: 7,
            rules: DefaultRules.v1Bindings,
            recognition: .sensitive
        )

        let decoded = try JSONDecoder().decode(
            AppConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        XCTAssertEqual(decoded, configuration)
    }

    func testUpdatingBindingIncrementsVersionAndPreservesOtherBindings() throws {
        let original = AppConfiguration.initial(storeEpoch: "test")

        let updated = try original.updatingBinding(id: "link-open-adjacent", enabled: false)

        XCTAssertEqual(updated.configurationVersion, original.configurationVersion + 1)
        XCTAssertFalse(updated.rules.first { $0.id == "link-open-adjacent" }?.enabled ?? true)
        XCTAssertEqual(
            updated.rules.first { $0.id == "swipe-left-next-tab" }?.enabled,
            original.rules.first { $0.id == "swipe-left-next-tab" }?.enabled
        )
    }
}
