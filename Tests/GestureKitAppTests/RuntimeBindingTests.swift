import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

/// Task 4 绑定热更新：用户绑定保存 → RuleEngine 立即重建并生效。
@MainActor
final class RuntimeBindingTests: XCTestCase {
    private func makeStore(_ suite: String) -> UserDefaultsSettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsSettingsStore(defaults: defaults)
    }

    private func makeRuntime(store: any SettingsStore) -> GestureKitRuntime {
        GestureKitRuntime(
            menuBarHandler: { _ in },
            touchBackend: BindingStubTouchBackend(),
            settingsStore: store,
            logger: GestureKitLogger(terminalWriter: { _ in })
        )
    }

    private var genericContext: ProviderContextSnapshot {
        ProviderContextSnapshot(contextId: "binding-test", targetKind: .noTarget, targetRef: nil, deadline: 1_000)
    }

    func testUpdateGestureBindingPersistsOverrideForNewGesture() throws {
        let store = makeStore("GestureKitTests.runtimeBindingNewGesture")
        let runtime = makeRuntime(store: store)

        try runtime.updateGestureBinding(
            gestureDefinitionID: "two-finger-swipe-left",
            actionID: .browserTabActivateNext,
            enabled: true
        )

        let overrides = try store.loadBindingOverrides()
        XCTAssertEqual(overrides.count, 1)
        XCTAssertEqual(overrides.first?.gestureDefinitionId, "two-finger-swipe-left")
        XCTAssertEqual(overrides.first?.actionId, .browserTabActivateNext)
        XCTAssertEqual(overrides.first?.enabled, true)
    }

    func testUpdateGestureBindingTakesEffectImmediatelyForNewGesture() throws {
        let store = makeStore("GestureKitTests.runtimeBindingImmediateNew")
        let runtime = makeRuntime(store: store)

        try runtime.updateGestureBinding(
            gestureDefinitionID: "two-finger-swipe-left",
            actionID: .browserTabActivateNext,
            enabled: true
        )

        XCTAssertEqual(
            runtime.resolveForTesting(gesture: .twoFingerSwipeLeft, context: genericContext)?.actionId,
            .browserTabActivateNext
        )
    }

    func testUpdateGestureBindingOverridesDefaultGestureAction() throws {
        let store = makeStore("GestureKitTests.runtimeBindingDefaultAction")
        let runtime = makeRuntime(store: store)

        try runtime.updateGestureBinding(
            gestureDefinitionID: "three-finger-swipe-left",
            actionID: .browserPageReload,
            enabled: true
        )

        XCTAssertEqual(
            runtime.resolveForTesting(gesture: .threeFingerSwipeLeft, context: genericContext)?.actionId,
            .browserPageReload
        )
        XCTAssertEqual(try store.loadBindingOverrides().first?.id, "swipe-left-next-tab")
        XCTAssertNil(try store.loadBindingOverrides().first?.gestureDefinitionId)
    }

    func testUpdateGestureBindingDisablesDefaultGesture() throws {
        let store = makeStore("GestureKitTests.runtimeBindingDisableDefault")
        let runtime = makeRuntime(store: store)

        try runtime.updateGestureBinding(
            gestureDefinitionID: "three-finger-swipe-left",
            actionID: nil,
            enabled: false
        )

        XCTAssertNil(runtime.resolveForTesting(gesture: .threeFingerSwipeLeft, context: genericContext))
        XCTAssertEqual(try store.loadBindingOverrides().first?.enabled, false)
    }

    func testUpdateGestureBindingDisablesNewGesture() throws {
        let store = makeStore("GestureKitTests.runtimeBindingDisableNew")
        let runtime = makeRuntime(store: store)
        try runtime.updateGestureBinding(
            gestureDefinitionID: "two-finger-swipe-left",
            actionID: .browserTabActivateNext,
            enabled: true
        )

        try runtime.updateGestureBinding(
            gestureDefinitionID: "two-finger-swipe-left",
            actionID: .browserTabActivateNext,
            enabled: false
        )

        XCTAssertNil(runtime.resolveForTesting(gesture: .twoFingerSwipeLeft, context: genericContext))
        XCTAssertEqual(try store.loadBindingOverrides().first?.enabled, false)
    }

    func testUpdateGestureBindingRestoringDefaultActionClearsOverride() throws {
        let store = makeStore("GestureKitTests.runtimeBindingRestoreDefault")
        let runtime = makeRuntime(store: store)
        try runtime.updateGestureBinding(
            gestureDefinitionID: "three-finger-swipe-left",
            actionID: .browserPageReload,
            enabled: true
        )
        XCTAssertEqual(
            runtime.resolveForTesting(gesture: .threeFingerSwipeLeft, context: genericContext)?.actionId,
            .browserPageReload
        )

        // 用户把动作切回默认动作（激活下一个标签）且启用态不变 → 清除覆盖，回退默认。
        try runtime.updateGestureBinding(
            gestureDefinitionID: "three-finger-swipe-left",
            actionID: .browserTabActivateNext,
            enabled: true
        )

        XCTAssertTrue(try store.loadBindingOverrides().isEmpty)
        XCTAssertEqual(
            runtime.resolveForTesting(gesture: .threeFingerSwipeLeft, context: genericContext)?.actionId,
            .browserTabActivateNext
        )
    }

    func testRestoreDefaultConfigurationClearsUserOverrides() throws {
        let store = makeStore("GestureKitTests.runtimeBindingRestoreDefaults")
        let runtime = makeRuntime(store: store)
        try runtime.updateGestureBinding(
            gestureDefinitionID: "two-finger-swipe-left",
            actionID: .browserTabActivateNext,
            enabled: true
        )

        try runtime.restoreDefaultConfiguration()

        XCTAssertTrue(try store.loadBindingOverrides().isEmpty)
        XCTAssertNil(runtime.resolveForTesting(gesture: .twoFingerSwipeLeft, context: genericContext))
        XCTAssertEqual(
            runtime.resolveForTesting(gesture: .threeFingerSwipeLeft, context: genericContext)?.actionId,
            .browserTabActivateNext
        )
    }
}

private final class BindingStubTouchBackend: TouchBackend {
    let frames = AsyncStream<TouchFrame> { continuation in
        continuation.finish()
    }

    func start() -> Bool { true }
    func stop() -> Bool { true }
}
