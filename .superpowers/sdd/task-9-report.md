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

## 生产接线补充

- Runtime 现在只把 `settings_update` 作为 marker 尚不存在时的 legacy import 输入；首次导入写入 marker 后，所有后续 legacy settings update 都返回 `applied: false`，不会修改 recognizer 或 App 配置。
- 已认证的 v2 Provider 会话会接收由 App 持久化权威配置生成的 `configuration_snapshot`。Runtime 接收 `configuration_ack` 时仅记录日志，不会以 Provider ACK 覆盖 App 配置。
- 新增 RED-GREEN Runtime 用例：验证 marker 后 legacy 写入被拒绝，以及 Provider 快照与已持久化的 App 配置一致。
- 补充验证：`swift test --filter RuntimeSettingsTests` 6 passed；全量 `swift test` 136 passed；Chrome 全量 23 files、151 tests passed；`npm run build` exit 0；`git diff --check` 无输出。
