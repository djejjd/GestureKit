# Task 9 交接报告

## 已交付

- 新增 `AppConfiguration`：包含 `storeEpoch`、schema/version、`BindingRule` 与手势识别阈值，作为 App 权威快照的数据模型。
- `UserDefaultsSettingsStore` 增加 App 配置存储；配置、legacy migration marker、epoch 和 version 编码为同一个持久化 transaction record，避免部分提交。legacy 导入成功后再次导入会抛出 `legacyMigrationAlreadyCompleted`。
- 新增 App 侧 `ConfigurationMigration`，只经 `AppConfigurationStore.importLegacyAppConfiguration` 执行一次性切换。
- Chrome 新增只读 `appConfigurationCache`：epoch 不同立即丢弃旧缓存；同一 epoch 只保留更高版本快照。
- background 已移除 `chrome.storage.onChanged -> settings_update` 和启动时反向同步；收到 `configuration_snapshot` 后仅缓存 App 快照，并以 `configuration_ack` 表达 Provider cache 是否已应用，绝不覆盖 App 配置。
- popup 未改动；其现有实现保持只读，不会写入设置。

## TDD 证据

- RED：`tests/appConfigurationCache.test.ts` 首次运行因缺少 `appConfigurationCache` 模块失败。
- RED：首次 Swift 测试受受限环境的 SwiftPM sandbox/module cache 阻断；改用完整 Xcode 工具链后编译并执行新增迁移测试。
- GREEN：新增 Swift 测试验证快照 Codable round-trip 与 legacy 导入只允许一次；新增 TypeScript 测试验证 epoch 切换与同 epoch 版本单调性。

## 验证

- `swift test --filter ConfigurationMigrationTests`：1 passed。
- `swift test --filter AppConfigurationTests`：1 passed。
- `swift test`：134 passed。
- `npm test -- --run tests/appConfigurationCache.test.ts tests/settingsSync.test.ts`：14 passed。
- `npm test -- --run`：23 files、151 tests passed。
- `npm run build`：exit 0。
- `git diff --check`：无输出。

## 范围

- 未实现 Task 10B UI、Task 11 cleanup、权限或 guard 改动，也未改变 V1 手势动作范围。
