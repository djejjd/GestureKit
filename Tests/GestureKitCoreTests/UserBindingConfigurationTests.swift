import XCTest
@testable import GestureKitCore

final class UserBindingConfigurationTests: XCTestCase {
    private var defaults: [BindingRule] { DefaultRules.v1Bindings }

    func testNoOverridesYieldsDefaultBindings() {
        let configuration = UserBindingConfiguration()

        XCTAssertEqual(configuration.effectiveBindings(defaults: defaults), defaults)
    }

    func testActionOverrideReplacesDefaultAction() {
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(id: "swipe-left-next-tab", enabled: nil, actionId: .browserPageReload)
        ])

        let effective = configuration.effectiveBindings(defaults: defaults)
        XCTAssertEqual(effective.first { $0.id == "swipe-left-next-tab" }?.actionId, .browserPageReload)
    }

    func testDisabledOverrideRemovesBinding() {
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(id: "swipe-left-next-tab", enabled: false, actionId: nil)
        ])

        let effective = configuration.effectiveBindings(defaults: defaults)
        XCTAssertNil(effective.first { $0.id == "swipe-left-next-tab" })
        XCTAssertEqual(effective.count, defaults.count - 1)
    }

    func testUnknownOverrideIDIgnored() {
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(id: "does-not-exist", enabled: false, actionId: nil)
        ])

        XCTAssertEqual(configuration.effectiveBindings(defaults: defaults), defaults)
    }

    func testRemovingOverrideRestoresDefault() {
        let overridden = UserBindingConfiguration(overrides: [
            BindingOverride(id: "swipe-left-next-tab", enabled: false, actionId: nil)
        ])

        let restored = overridden.removing(id: "swipe-left-next-tab")
        XCTAssertEqual(restored.effectiveBindings(defaults: defaults), defaults)
    }

    func testActionOverrideClearsContextButPreservesOtherFields() {
        let defaultBinding = defaults.first { $0.id == "link-open-adjacent" }
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(id: "link-open-adjacent", enabled: nil, actionId: .browserPageReload)
        ])

        let effective = configuration.effectiveBindings(defaults: defaults)
        let binding = effective.first { $0.id == "link-open-adjacent" }
        XCTAssertEqual(binding?.priority, defaultBinding?.priority)
        // 用户显式改动作时应清空默认绑定的上下文约束（如 standard_link），让动作在任意处触发。
        XCTAssertEqual(binding?.contextConstraints, [:])
        XCTAssertEqual(binding?.gestureDefinitionId, defaultBinding?.gestureDefinitionId)
        XCTAssertEqual(binding?.actionParameters, defaultBinding?.actionParameters)
    }

    func testEnableOnlyOverridePreservesContextConstraints() {
        let defaultBinding = defaults.first { $0.id == "link-open-adjacent" }
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(id: "link-open-adjacent", enabled: true, actionId: nil)
        ])

        let effective = configuration.effectiveBindings(defaults: defaults)
        let binding = effective.first { $0.id == "link-open-adjacent" }
        // 仅改启用态（不改动作）时保留默认上下文约束（链接上）。
        XCTAssertEqual(binding?.contextConstraints, defaultBinding?.contextConstraints)
    }

    func testUpdatingAddsNewOverride() {
        let configuration = UserBindingConfiguration()
        let updated = configuration.updating(
            BindingOverride(id: "swipe-left-next-tab", enabled: false, actionId: nil)
        )

        XCTAssertEqual(updated.overrides.count, 1)
        XCTAssertEqual(updated.overrides.first?.id, "swipe-left-next-tab")
    }

    func testUpdatingReplacesExistingOverride() {
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(id: "swipe-left-next-tab", enabled: false, actionId: nil)
        ])

        let updated = configuration.updating(
            BindingOverride(id: "swipe-left-next-tab", enabled: nil, actionId: .browserPageReload)
        )
        XCTAssertEqual(updated.overrides.count, 1)
        XCTAssertEqual(updated.overrides.first?.enabled, nil)
        XCTAssertEqual(updated.overrides.first?.actionId, .browserPageReload)
    }

    // MARK: - 新手势（无默认绑定）新增绑定

    /// 携带 gestureDefinitionId 的覆盖表示「新增绑定」：为无默认绑定的预设手势（二指/四指）
    /// 创建一条有效绑定规则。
    func testNewGestureOverrideCreatesAdditionBinding() {
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(
                id: "user-two-finger-swipe-left",
                gestureDefinitionId: "two-finger-swipe-left",
                enabled: true,
                actionId: .browserTabActivateNext
            )
        ])

        let effective = configuration.effectiveBindings(defaults: defaults)
        let addition = effective.first { $0.gestureDefinitionId == "two-finger-swipe-left" }
        XCTAssertEqual(addition?.actionId, .browserTabActivateNext)
        XCTAssertEqual(addition?.enabled, true)
        XCTAssertEqual(effective.count, defaults.count + 1)
    }

    /// 禁用的新手势覆盖不产生有效绑定。
    func testDisabledNewGestureOverrideIsInactive() {
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(
                id: "user-two-finger-swipe-left",
                gestureDefinitionId: "two-finger-swipe-left",
                enabled: false,
                actionId: .browserTabActivateNext
            )
        ])

        XCTAssertNil(configuration.effectiveBindings(defaults: defaults)
            .first { $0.gestureDefinitionId == "two-finger-swipe-left" })
    }

    /// 新手势覆盖未指定动作时不产生有效绑定（动作是绑定的必要条件）。
    func testNewGestureOverrideWithoutActionIsInactive() {
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(
                id: "user-two-finger-swipe-left",
                gestureDefinitionId: "two-finger-swipe-left",
                enabled: true,
                actionId: nil
            )
        ])

        XCTAssertNil(configuration.effectiveBindings(defaults: defaults)
            .first { $0.gestureDefinitionId == "two-finger-swipe-left" })
    }

    /// 已被默认绑定覆盖的手势不得重复生成新增绑定；默认绑定优先。
    func testDefaultBoundGestureDoesNotDuplicateAddition() {
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(
                id: "user-three-finger-swipe-left",
                gestureDefinitionId: "three-finger-swipe-left",
                enabled: true,
                actionId: .browserPageReload
            )
        ])

        let effective = configuration.effectiveBindings(defaults: defaults)
        XCTAssertEqual(effective.filter { $0.gestureDefinitionId == "three-finger-swipe-left" }.count, 1)
        XCTAssertEqual(
            effective.first { $0.gestureDefinitionId == "three-finger-swipe-left" }?.actionId,
            .browserTabActivateNext
        )
    }

    /// 新增绑定同样可以被 enabled=false 覆盖（合并时移除），回退后恢复。
    func testNewGestureOverrideCanBeDisabledByLaterOverride() {
        var configuration = UserBindingConfiguration(overrides: [
            BindingOverride(
                id: "user-two-finger-swipe-left",
                gestureDefinitionId: "two-finger-swipe-left",
                enabled: true,
                actionId: .browserTabActivateNext
            )
        ])
        configuration = configuration.updating(BindingOverride(
            id: "user-two-finger-swipe-left",
            gestureDefinitionId: "two-finger-swipe-left",
            enabled: false,
            actionId: .browserTabActivateNext
        ))

        XCTAssertNil(configuration.effectiveBindings(defaults: defaults)
            .first { $0.gestureDefinitionId == "two-finger-swipe-left" })
    }

    /// 移除新手势覆盖后回退为「未绑定」。
    func testRemovingNewGestureOverrideUnbindsGesture() {
        let configuration = UserBindingConfiguration(overrides: [
            BindingOverride(
                id: "user-two-finger-swipe-left",
                gestureDefinitionId: "two-finger-swipe-left",
                enabled: true,
                actionId: .browserTabActivateNext
            )
        ])

        let restored = configuration.removing(id: "user-two-finger-swipe-left")
        XCTAssertNil(restored.effectiveBindings(defaults: defaults)
            .first { $0.gestureDefinitionId == "two-finger-swipe-left" })
    }
}
