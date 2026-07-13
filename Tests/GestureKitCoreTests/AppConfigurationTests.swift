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
}
