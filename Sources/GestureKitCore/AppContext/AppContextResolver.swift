import AppKit

public struct AppContextResolver {
    private let bundleIdProvider: () -> String

    public init(bundleIdProvider: @escaping () -> String = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    }) {
        self.bundleIdProvider = bundleIdProvider
    }

    public func currentContext(elementType: ElementType) -> RuleContext {
        let bundleId = bundleIdProvider()
        return RuleContext(
            appBundleId: bundleId,
            browserKind: bundleId == "com.google.Chrome" ? .chrome : .other,
            elementType: elementType
        )
    }
}
