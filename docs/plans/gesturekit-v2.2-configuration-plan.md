# GestureKit V2.2 手势配置实施计划

> **执行要求：** 按任务顺序采用测试先行；每个任务完成后完成其指定测试和一次独立审核。

**目标：** 让三项已验证 Chrome 手势可独立启用或关闭，并让三档轻扫灵敏度从 App 权威配置稳定驱动启动、运行时和 Chrome Provider 同步。

**架构：** `AppConfiguration` 保持唯一配置快照。新增配置运行时适配层，在 App 启动和用户修改时以同一份快照构造 `GestureRecognizer`、配置化 `RuleEngine` 与 `RecognitionPlan`；控制中心只调用该适配层，不直接写 `UserDefaults`。Chrome 仅接收快照和确认版本，不能写回绑定。

**技术栈：** Swift 6、SwiftUI/AppKit、XCTest、Chrome MV3、TypeScript、Vitest。

## 全局约束

- 实现必须符合 `docs/product/gesturekit-v2.2-configuration-contract.md`。
- 只开放三指点按链接、三指左滑、三指右滑和三档灵敏度；不展示未端到端验证的边缘点按或双击关闭标签。
- `AppConfiguration` 为唯一用户配置来源；旧 `settings_update` 只能用于一次性迁移，不能覆盖 App 配置。
- 关闭链接打开绑定必须移除 `link_click` guard；普通网页点击不得受影响。
- 项目文档与用户文案中文优先；协议字段、动作 ID 和代码标识保持原文。
- 不改变 Provider Protocol v2 的消息类型；配置变更通过既有 `configuration_snapshot/configuration_ack` 完成。

## 当前基线

- 隔离分支：`feature/v2.2-gesture-configuration`。
- Swift 测试在本机 Command Line Tools 环境中无法编译测试模块，错误为 `no such module 'XCTest'`；`xcode-select -p` 指向 `/Library/Developer/CommandLineTools`，没有完整 Xcode。此问题必须在实施前通过完整 Xcode 工具链复测，不得当作产品回归。
- Chrome 扩展 worktree 未安装依赖，`npm test` 报 `vitest: command not found`。先执行 `npm install` 后再建立扩展侧基线。

---

### Task 1：配置化动作解析与兼容迁移

**文件：**
- 修改：`Sources/GestureKitCore/Rules/RuleEngine.swift`
- 修改：`Sources/GestureKitCore/Rules/RuleModels.swift`
- 修改：`Sources/GestureKitCore/Settings/AppConfiguration.swift`
- 修改：`apps/macos/GestureKitApp/Sources/GestureKitApp/ConfigurationMigration.swift`
- 修改：`Tests/GestureKitCoreTests/RuleEngineTests.swift`
- 修改：`Tests/GestureKitCoreTests/AppConfigurationTests.swift`
- 修改：`Tests/GestureKitAppTests/ConfigurationMigrationTests.swift`

**接口：**
- 新增 `RuleEngine.init(configuration: AppConfiguration)`。
- 新增 `ComposedGesture.gestureDefinitionID: String`，对现有六个组合手势返回稳定定义 ID。
- `RuleEngine.resolve(gesture:context:)` 仅从启用的 `BindingRule` 匹配动作、上下文约束与优先级；无匹配时返回 `nil`。
- `AppConfiguration` 增加仅表达 V2.2 UI 可配置项目的稳定访问器，避免 SwiftUI 依赖规则 ID 字符串。

**步骤：**
- [ ] 为已启用链接绑定、已关闭链接绑定、左右滑绑定和 `targetKind` 不匹配写失败测试；验证禁用后 `resolve` 返回 `nil`。
- [ ] 为旧 schema 配置缺少 V2.2 UI 摘要字段写迁移测试；验证补齐默认三项启用与标准灵敏度，并递增配置版本。
- [ ] 实现由 `BindingRule` 驱动的解析，保留旧 `RuleEngine(rules:)` 与 `match` 仅供旧测试和迁移边界使用；正式运行时不再调用它。
- [ ] 实现配置访问器和 schema 兼容解码；拒绝未知未来 schema，不静默回退为默认配置。
- [ ] 运行 `swift test --filter RuleEngineTests`、`swift test --filter AppConfigurationTests`、`swift test --filter ConfigurationMigrationTests`。
- [ ] 提交：`feat: resolve actions from app configuration`。

### Task 2：App 运行时配置事务

**文件：**
- 新建：`apps/macos/GestureKitApp/Sources/GestureKitApp/GestureConfigurationController.swift`
- 修改：`apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- 修改：`apps/macos/GestureKitApp/Sources/GestureKitApp/RuntimeControl.swift`
- 修改：`apps/macos/GestureKitApp/Sources/GestureKitApp/AppDelegate.swift`
- 修改：`Tests/GestureKitAppTests/RuntimeSettingsTests.swift`
- 新建：`Tests/GestureKitAppTests/GestureConfigurationControllerTests.swift`

**接口：**
- `GestureConfigurationController` 负责 `loadOrCreate()`、`updateBinding(id:enabled:)`、`updateSensitivity(_:)`、`restoreDefaults()` 和只读 `snapshot()`。
- 每次写入生成更高的 `configurationVersion`，原子保存 `AppConfiguration`，并通过回调向运行时提供完整新快照。
- `GestureKitRuntime.apply(configuration:)` 替换识别阈值、`RuleEngine` 和 guard 派生计划；成功后调用既有 `refreshConfigurationSnapshot()`。
- `RuntimeControlling` 暴露用户级配置读写方法及应用状态，不暴露 `UserDefaults`、规则 ID 或 Provider session ID。

**步骤：**
- [ ] 写失败测试：启动读取已保存的“灵敏”配置后，边界轻扫按灵敏阈值识别；重启新 Runtime 后结果一致。
- [ ] 写失败测试：关闭三指点按链接后，运行时不产生链接动作，且候选 guard 特征为空；重新启用后恢复。
- [ ] 写失败测试：保存失败、无活动 Provider、Provider 未确认和确认旧版本时，分别形成正确的用户级应用状态。
- [ ] 实现控制器的校验、版本递增、保存和回调；失败时保持旧运行时快照并返回可展示错误。
- [ ] 在 Runtime 初始化阶段加载 `authoritativeConfiguration()`，用其 `recognition` 创建 `GestureRecognizer`，并以其绑定构建 `RuleEngine`；删除正式路径对 `loadRules()` 的依赖。
- [ ] 实现 `apply(configuration:)` 的顺序：先校验并构造新运行时对象，再保存，再原子替换运行时状态，最后发 Provider 快照；Provider 未确认不回滚已保存且已应用的 App 配置。
- [ ] 运行 `swift test --filter RuntimeSettingsTests`、`swift test --filter GestureConfigurationControllerTests`、`swift test --filter RuntimeLifecycleTests`。
- [ ] 提交：`feat: apply app-owned gesture configuration at runtime`。

### Task 3：控制中心手势与操作页面

**文件：**
- 修改：`apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPresentation.swift`
- 修改：`apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterDataSource.swift`
- 修改：`apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPages.swift`
- 修改：`apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterView.swift`
- 修改：`Tests/GestureKitAppTests/ControlCenterPresentationTests.swift`
- 新建：`Tests/GestureKitAppTests/GestureConfigurationPresentationTests.swift`

**接口：**
- 将 `PresetPageState` 替换为 `GestureConfigurationPageState`，包含三项 `GestureBindingItem`、当前 `SwipeSensitivity`、应用状态和恢复默认入口状态。
- `ControlCenterDataSource` 新增读取配置页面和提交单项开关、灵敏度、恢复默认的用户级方法。
- 控制中心导航文案从“手势预设”改为“手势与操作”。

**步骤：**
- [ ] 写表现模型测试：默认三项均启用、关闭项显示“已关闭”、Provider 未连接显示“已保存，等待 Chrome 确认”、确认当前版本显示“Chrome 已确认”。
- [ ] 写 SwiftUI 数据源测试：只呈现三项契约内手势，不呈现边缘点按或双击关闭标签；恢复默认只重置开关和灵敏度。
- [ ] 实现新的表现模型和 `RuntimeControlCenterDataSource` 适配；所有 UI 写入通过 `RuntimeControlling` 到 Task 2 控制器。
- [ ] 实现每项开关、三档分段选择器、状态说明和恢复默认确认；禁用或同步中时给出中文说明，不泄露规则 ID、动作枚举或 Provider 错误码。
- [ ] 更新操作详情标题，附加“配置版本 N”与不含敏感数据的配置摘要。
- [ ] 运行 `swift test --filter ControlCenterPresentationTests`、`swift test --filter GestureConfigurationPresentationTests`。
- [ ] 提交：`feat: add gesture configuration controls to control center`。

### Task 4：Chrome 配置确认与 V1 设置迁移边界

**文件：**
- 修改：`extensions/chrome/src/background/settingsSync.ts`
- 修改：`extensions/chrome/src/settings/gestureSettings.ts`
- 修改：`extensions/chrome/src/background/index.ts`
- 修改：`extensions/chrome/tests/settingsSync.test.ts`
- 修改：`extensions/chrome/tests/gestureSettings.test.ts`
- 修改：`Tests/GestureKitAppTests/RuntimeSettingsTests.swift`

**接口：**
- Provider 对 `configuration_snapshot` 只缓存其 `storeEpoch/schemaVersion/configurationVersion` 与只读配置 JSON，并以收到的版本回传 `configuration_ack`。
- 旧 `settings_update` 仅在 App 迁移标记不存在时允许触发一次导入；之后返回明确拒绝，不得更新运行时或覆盖 App 配置。
- Chrome UI 侧的旧灵敏度持久设置保留为迁移来源和兼容展示，不再作为正式写入入口。

**步骤：**
- [ ] 写 Vitest：新配置快照确认同一版本；收到旧版本后不得把已确认状态回退；未连接时不得伪造已应用。
- [ ] 写 Vitest：迁移标记完成后旧 `settings_update` 不覆盖 V2.2 配置。
- [ ] 写 Swift 测试：App 收到旧设置更新时只允许首次导入，第二次返回 `legacy_settings_write_rejected`，并保持现有配置版本。
- [ ] 实现配置版本比较和确认状态更新；删除 extension 侧把轻扫设置当作 App 正式运行时来源的行为。
- [ ] 运行 `npm test -- settingsSync gestureSettings` 和 `swift test --filter RuntimeSettingsTests`。
- [ ] 提交：`fix: make chrome configuration sync app authoritative`。

### Task 5：端到端回归、文档和发布准备

**文件：**
- 修改：`docs/architecture/config-derived-interaction-guards.md`
- 修改：`docs/operations/gesturekit-v1-e2e-checklist.md`
- 修改：`docs/operations/gesturekit-v1-local-install.md`
- 修改：`docs/product/gesturekit-v2.2-configuration-contract.md`
- 视实际结果修改：`README.md`

**步骤：**
- [ ] 在完整 Xcode 环境运行 `swift test`；记录测试数量、结果与现有非阻塞编译警告。若仍无法运行，先解决工具链选择问题，不得以部分测试替代全量验证。
- [ ] 在扩展目录运行 `npm install`、`npm test` 和 `npm run build`。
- [ ] 执行手动验收：三项默认手势、逐项关闭/重新开启、三档灵敏度边界、App 重启保持、Chrome 断连后保存、重连确认、恢复默认、关闭链接绑定后的普通单指链接点击。
- [ ] 对启用链接绑定执行三指打开链接回归：新标签正常打开，原标签不刷新；记录 guard 诊断链路。
- [ ] 更新架构和操作文档，移除“当前预设”的用户文案，补充配置状态、迁移边界和手动验证步骤。
- [ ] 审核变更仅覆盖本契约；将二指及未验证 V1 模型手势记录为后续事项。
- [ ] 提交：`docs: document v2.2 gesture configuration verification`。

## 覆盖检查

- 三项独立开关：Task 1、Task 2、Task 3。
- 三档灵敏度、启动恢复与运行时应用：Task 2、Task 3。
- App 权威配置和旧 V1 路径收口：Task 1、Task 2、Task 4。
- Chrome 确认和断连语义：Task 2、Task 3、Task 4。
- 链接 guard 不回归：Task 2、Task 5。
- 用户文案、诊断版本和手动验收：Task 3、Task 5。
