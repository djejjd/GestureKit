import XCTest
@testable import GestureKitCore

final class SettingsStoreTests: XCTestCase {
    func testEmptyStoreReturnsDefaultRules() throws {
        let defaults = UserDefaults(suiteName: "GestureKitTests.empty")!
        defaults.removePersistentDomain(forName: "GestureKitTests.empty")
        let store = UserDefaultsSettingsStore(defaults: defaults)

        XCTAssertEqual(try store.loadRules(), DefaultRules.v1)
    }

    func testSaveAndLoadRulesRoundTrip() throws {
        let defaults = UserDefaults(suiteName: "GestureKitTests.roundtrip")!
        defaults.removePersistentDomain(forName: "GestureKitTests.roundtrip")
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var rules = DefaultRules.v1
        rules[0].enabled = false

        try store.saveRules(rules)

        XCTAssertEqual(try store.loadRules(), rules)
    }

    func testEmptyStoreReturnsNoBindingOverrides() throws {
        let defaults = UserDefaults(suiteName: "GestureKitTests.bindingOverridesEmpty")!
        defaults.removePersistentDomain(forName: "GestureKitTests.bindingOverridesEmpty")
        let store = UserDefaultsSettingsStore(defaults: defaults)

        XCTAssertEqual(try store.loadBindingOverrides(), [])
    }

    func testSaveAndLoadBindingOverridesRoundTrip() throws {
        let defaults = UserDefaults(suiteName: "GestureKitTests.bindingOverridesRoundTrip")!
        defaults.removePersistentDomain(forName: "GestureKitTests.bindingOverridesRoundTrip")
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let overrides = [
            BindingOverride(id: "swipe-left-next-tab", enabled: false, actionId: nil),
            BindingOverride(id: "link-open-adjacent", enabled: nil, actionId: .browserPageReload)
        ]

        try store.saveBindingOverrides(overrides)

        XCTAssertEqual(try store.loadBindingOverrides(), overrides)
    }
}
