import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

@MainActor
final class RuntimeProbeTests: XCTestCase {
    func testRuntimeRepliesToProbeRequest() throws {
        let runtime = GestureKitRuntime(
            statusHandler: { _ in },
            touchBackend: RuntimeProbeStubTouchBackend(),
            settingsStore: RuntimeProbeStubSettingsStore(),
            logger: GestureKitLogger(terminalWriter: { _ in }),
            diagnosticSink: { _ in }
        )

        let response = runtime.handleProbeRequestForTesting(id: "probe-1")

        XCTAssertEqual(response.type, MessageType.probeResponse)
        XCTAssertEqual(response.probeResponsePayload?.hostConnected, true)
        XCTAssertEqual(response.probeResponsePayload?.appConnected, true)
    }
}

private final class RuntimeProbeStubTouchBackend: TouchBackend {
    let frames = AsyncStream<TouchFrame> { continuation in
        continuation.finish()
    }

    func start() -> Bool { true }
    func stop() -> Bool { true }
}

private struct RuntimeProbeStubSettingsStore: SettingsStore {
    func loadRules() throws -> [Rule] {
        DefaultRules.v1
    }

    func saveRules(_ rules: [Rule]) throws {}
}
