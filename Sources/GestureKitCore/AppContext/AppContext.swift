public struct AppContext: Equatable, Sendable {
    public let bundleId: String
    public let browserKind: BrowserKind

    public init(bundleId: String, browserKind: BrowserKind) {
        self.bundleId = bundleId
        self.browserKind = browserKind
    }
}
