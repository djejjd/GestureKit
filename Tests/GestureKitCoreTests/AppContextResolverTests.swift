import XCTest
@testable import GestureKitCore

final class AppContextResolverTests: XCTestCase {
    func testChromeBundleMapsToChromeContext() {
        let resolver = AppContextResolver(bundleIdProvider: { "com.google.Chrome" })

        let context = resolver.currentContext(elementType: .link)

        XCTAssertEqual(context, RuleContext(appBundleId: "com.google.Chrome", browserKind: .chrome, elementType: .link))
    }

    func testNonChromeBundleMapsToOther() {
        let resolver = AppContextResolver(bundleIdProvider: { "com.apple.finder" })

        let context = resolver.currentContext(elementType: .any)

        XCTAssertEqual(context.browserKind, .other)
        XCTAssertEqual(context.appBundleId, "com.apple.finder")
    }
}
