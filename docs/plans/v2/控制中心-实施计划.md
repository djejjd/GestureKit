# 控制中心状态与操作记录实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 控制中心持续显示真实的 App/Chrome Provider 状态和实际能力，并将操作记录限制为最近 50 条且可仅清空列表显示。

**Architecture:** `GestureKitRuntime` 维护监听、认证和配置确认的健康快照；`ControlCenterView` 每秒重读该快照。Chrome extension 在接收配置快照后上报其标准能力，App 将能力快照写入会话。`OperationJournal` 新增仅用于 UI 的隐藏操作元数据表；清空列表只写入该表，绝不删除事件、日志或导出副本。

**Tech Stack:** Swift 6.2、SwiftUI、SQLite、Chrome MV3 TypeScript、Vitest、XCTest。

## 全局约束

- 所有用户可见文案使用中文，禁止显示协议枚举、Provider 凭据、session ID、nonce、HMAC、原始 `targetRef`、URL query/hash、Cookie 或网页正文。
- Chrome Provider 的已连接状态必须以已认证会话和 `configuration_ack(applied: true)` 为准。
- Provider 能力必须来自认证后收到的 `capability_snapshot`，不得由 App 默认假定完整能力集合。
- 操作列表最多展示 50 条未隐藏记录；不能提供“加载更多”。
- “清空列表显示”只隐藏既有操作，不删除 `OperationJournal` 事件、结构化诊断日志、Provider outbox 或已导出的证据包；7 天/50 MB 自动保留规则不变。
- 所有改动在分支 `fix/control-center-status` 中进行，保持范围限于已确认设计。

---

### Task 1: 建立真实 Provider 会话与能力快照

**Files:**
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/ProviderSessionRegistry.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- Modify: `extensions/chrome/src/background/background.ts`
- Create: `extensions/chrome/src/provider/chromeCapabilities.ts`
- Create: `extensions/chrome/tests/chromeCapabilities.test.ts`
- Modify: `Tests/GestureKitAppTests/RuntimeLifecycleTests.swift`
- Modify: `Tests/GestureKitAppTests/ProviderSessionRegistryTests.swift`

**Interfaces:**
- Produces `ChromeProviderCapabilities.standard: readonly StandardActionID[]`，作为 Chrome extension 唯一能力声明来源。
- Produces `ProviderSessionRegistry.updateCapabilities(_:for:connectionID:)`，只允许认证会话更新自身能力。
- Consumes `CapabilitySnapshotPayload(capabilities:capabilityVersion:)`，并拒绝未认证、会话不匹配或跨连接的快照。

- [ ] **Step 1: 写出 Swift 会话能力失败测试**

在 `RuntimeLifecycleTests` 中完成一次 hello/challenge/authenticate 后，发送包含 `browser.page.reload` 的 `capability_snapshot`，断言 `controlCenterHealth` 只保留 1 项能力；再从不同 `connectionID` 发送包含全部能力的快照，断言能力集合不变。测试构造的 envelope：

```swift
ProviderEnvelope(
    protocolVersion: 2, messageId: "capabilities-1", providerSessionId: sessionID,
    gestureSessionId: nil, operationId: nil, type: .capabilitySnapshot,
    timestamp: 102,
    payload: .capabilitySnapshot(.init(capabilities: [.browserPageReload], capabilityVersion: 1)),
    error: nil
)
```

- [ ] **Step 2: 运行失败测试**

运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimeLifecycleTests`

预期：失败，因为 runtime 将 `capability_snapshot` 落入未经授权的默认分支，且会话能力不可变。

- [ ] **Step 3: 实现会话能力更新**

将 `AuthenticatedProviderSession.capabilities` 改为可在 registry 锁内替换的会话字段；认证时初始化为空集合，不再使用 `Set(StandardActionID.allCases)`。新增：

```swift
func updateCapabilities(
    _ snapshot: CapabilitySnapshotPayload,
    for providerSessionID: String,
    connectionID: UUID
) -> Bool
```

该方法仅在 `providerSessionID` 存在、连接匹配时替换为 `Set(snapshot.capabilities)` 并返回 `true`。在 `Runtime.handleProviderEnvelope` 增加 `.capabilitySnapshot` 分支，验证当前会话和连接后调用该方法；不写入操作账本。

- [ ] **Step 4: 写出 extension 能力声明测试**

创建 `chromeCapabilities.test.ts`，断言 `ChromeProviderCapabilities.standard` 等于协议定义的 7 个标准动作，且无重复值：

```ts
expect(ChromeProviderCapabilities.standard).toEqual([
  "browser.link.open_adjacent", "browser.tab.activate_previous",
  "browser.tab.activate_next", "browser.tab.close_current",
  "browser.history.back", "browser.history.forward", "browser.page.reload"
]);
```

- [ ] **Step 5: 实现 Chrome 快照发送**

创建 `chromeCapabilities.ts` 并导出上述不可变数组。`handleConfigurationSnapshot` 在成功或失败的 `configuration_ack` 前，通过同一 `port` 发送：

```ts
{
  ...envelope,
  messageId: crypto.randomUUID(),
  type: "capability_snapshot",
  timestamp: Date.now(),
  payload: { capabilities: [...ChromeProviderCapabilities.standard], capabilityVersion: 1 },
  error: null
} satisfies ProviderEnvelope
```

保留配置 ACK 的既有语义，能力快照不包含页面、诊断或凭据数据。

- [ ] **Step 6: 运行针对性测试并提交**

运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimeLifecycleTests
(cd extensions/chrome && npm test -- tests/chromeCapabilities.test.ts)
```

预期：两组测试通过。提交：`git add apps/macos/GestureKitApp/Sources/GestureKitApp/ProviderSessionRegistry.swift apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift extensions/chrome/src/background/background.ts extensions/chrome/src/provider/chromeCapabilities.ts extensions/chrome/tests/chromeCapabilities.test.ts Tests/GestureKitAppTests/RuntimeLifecycleTests.swift Tests/GestureKitAppTests/ProviderSessionRegistryTests.swift && git commit -m "fix: report authenticated chrome provider capabilities"`。

### Task 2: 使控制中心状态持续且准确地刷新

**Files:**
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPresentation.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterDataSource.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterView.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPages.swift`
- Modify: `Tests/GestureKitAppTests/ControlCenterPresentationTests.swift`

**Interfaces:**
- Produces稳定的 `ControlCenterHealth` 表现模型，区分监听启动、运行、停止和失败，以及 Provider 未连接、认证/配置同步和已连接。
- Consumes `controlCenterHealth` 和 capability 集合，不读取 Provider 凭据或会话标识。

- [ ] **Step 1: 写出健康状态与能力文案失败测试**

在 `ControlCenterPresentationTests` 添加断言：监听停止不得显示“正在准备 GestureKit”；已认证但 `configurationApplied == false` 时 Provider 卡片必须显示“当前预设正在同步”；连接后 Provider 页必须包含“打开链接”“切换到前一个标签”等中文能力项，且不包含 `browser.`。

- [ ] **Step 2: 运行失败测试**

运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlCenterPresentationTests`

预期：失败，因为现有模型把 `stopped` 归为 preparing，并且只显示能力数量。

- [ ] **Step 3: 实现状态和能力表现模型**

扩展 `ControlCenterHealth` 及其卡片映射，使 `.stopped` 显示“手势监听已停止”，监听失败显示“无法开始手势监听”，无认证会话显示“Chrome 尚未连接”，已认证但未确认配置显示“当前预设正在同步”，只有 `configurationApplied == true` 时显示“Chrome Provider 已连接”。

将 connected case 携带 `Set<StandardActionID>`，在 `RuntimeControlCenterDataSource.providerPage()` 使用单独中文映射逐项构造状态卡，而非 `capabilityCount`。无能力快照的认证会话显示“正在确认浏览器能力”，不能显示全部能力。

- [ ] **Step 4: 实现自动刷新**

在 `ControlCenterView` 用每秒触发的 SwiftUI 时间线或等价 `Task` 更新 `refreshToken`，并让所有页面状态在更新时重新调用 data source。保留导出成功/失败后的即时刷新。不得为刷新创建第二个 runtime、轮询 Provider 或在视图层保存敏感会话信息。

- [ ] **Step 5: 运行针对性测试并提交**

运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlCenterPresentationTests`

预期：通过。提交：`git add apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPresentation.swift apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterDataSource.swift apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterView.swift apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPages.swift Tests/GestureKitAppTests/ControlCenterPresentationTests.swift && git commit -m "fix: refresh control center provider status"`。

### Task 3: 添加不删除日志的操作列表隐藏存储

**Files:**
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/OperationJournal.swift`
- Modify: `Tests/GestureKitAppTests/OperationJournalTests.swift`

**Interfaces:**
- Produces `OperationJournaling.clearOperationListDisplay() throws`，只修改 UI 展示元数据。
- `OperationJournaling.query(_:limit:)` 自动排除已隐藏操作，供控制中心列表使用；`exportEvidence(operationId:to:)` 必须仍能导出隐藏操作。

- [ ] **Step 1: 写出隐藏而非删除的失败测试**

在 `OperationJournalTests` 追加三个操作，调用 `clearOperationListDisplay()` 后断言通用 `query(OperationFilter(), limit: 50)` 为空；对其中一个操作调用内部诊断查询或 `exportEvidence`，断言其事件仍存在且导出的 evidence 包存在。随后追加第四个操作，断言查询只返回第四个操作。

- [ ] **Step 2: 运行失败测试**

运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OperationJournalTests`

预期：失败，因为协议没有清空展示方法，查询不排除任何操作。

- [ ] **Step 3: 实现隐藏元数据迁移和查询过滤**

将 schema version 升级，并在事务内创建：

```sql
CREATE TABLE operation_display_hidden (
    operation_id TEXT PRIMARY KEY REFERENCES operations(operation_id) ON DELETE CASCADE
);
```

实现 `clearOperationListDisplay()`，在串行队列与单个 SQLite 事务中执行：

```sql
INSERT OR IGNORE INTO operation_display_hidden(operation_id)
SELECT operation_id FROM operations;
```

在通用操作列表 SQL 加入 `NOT EXISTS` 子查询排除上述表。`exportEvidenceInternal` 必须用一个不包含 UI 隐藏条件的按 ID 查询，保证隐藏记录仍可导出。不得删除 `operations`、`events`、WAL、日志文件或导出目录。

- [ ] **Step 4: 运行针对性测试并提交**

运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OperationJournalTests`

预期：通过。提交：`git add apps/macos/GestureKitApp/Sources/GestureKitApp/OperationJournal.swift Tests/GestureKitAppTests/OperationJournalTests.swift && git commit -m "feat: clear operation list display without deleting evidence"`。

### Task 4: 限制控制中心记录为 50 条并接入清空确认

**Files:**
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterDataSource.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/OperationHistoryView.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterView.swift`
- Modify: `Tests/GestureKitAppTests/ControlCenterPresentationTests.swift`

**Interfaces:**
- `ControlCenterDataSource.operationPage()` 固定返回最多 50 条未隐藏操作。
- `ControlCenterDataSource.clearOperationListDisplay() throws` 转发到 journal 元数据接口。
- `OperationHistoryView` 通过 `onClearListDisplay` 请求清空，不直接访问账本。

- [ ] **Step 1: 写出展示窗口和转发失败测试**

在 `ControlCenterPresentationTests` 用 51 条 timeline 构造 stub journal，断言 `operationPage()` 返回 50 条且 `canLoadMore == false`。让 recording journal 记录 `clearOperationListDisplay()` 调用，断言 data source 的转发只调用该接口，不调用 append、删除或导出。

- [ ] **Step 2: 运行失败测试**

运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlCenterPresentationTests`

预期：失败，因为当前窗口为 20 条且支持加载更多，数据源没有清空接口。

- [ ] **Step 3: 实现 50 条窗口和确认 UI**

删除 `loadMoreOperations()`、`additionalLoadedCount` 和“加载更多”按钮；将 `ControlCenterView` 的查询改为固定 50。操作记录页在非空状态显示“清空列表显示”按钮，使用 SwiftUI confirmation dialog，标题为“清空列表显示？”，说明为“这只会隐藏当前操作记录列表，不会删除本地诊断日志或已导出的证据包。”，确认动作调用 data source 并刷新。错误时显示现有通用错误区域，新增中文的清空失败文案。

- [ ] **Step 4: 运行针对性测试并提交**

运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlCenterPresentationTests`

预期：通过。提交：`git add apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterDataSource.swift apps/macos/GestureKitApp/Sources/GestureKitApp/OperationHistoryView.swift apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterView.swift Tests/GestureKitAppTests/ControlCenterPresentationTests.swift && git commit -m "feat: limit and clear operation list display"`。

### Task 5: 回归验证与文档同步

**Files:**
- Modify: `docs/architecture/gesturekit-v2-ui-information-architecture.md`
- Modify: `docs/product/gesturekit-v1-contract.md`
- Modify: `docs/architecture/control-center-status-and-history-design.md`

- [ ] **Step 1: 更新长期契约文档**

在 UI 架构的“操作记录”段落写明最近 50 条和“清空列表显示”不删除诊断证据；在 Provider 段落写明能力必须来自认证后的 snapshot；在 V1 契约的 UI/诊断边界写明展示隐藏不影响 7 天/50 MB 自动保留。将本设计状态改为“已实施”。

- [ ] **Step 2: 运行完整验证**

运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
(cd extensions/chrome && npm test)
(cd extensions/chrome && npm run build)
./scripts/dev/test-provider-protocol.sh
git diff --check
```

预期：Swift 测试、Chrome Vitest、扩展构建和 Provider 协议 smoke 全部通过；`git diff --check` 无输出。

- [ ] **Step 3: 人工验收**

启动 App 和 Chrome extension：打开控制中心后等待不超过 1 秒，确认运行状态和 Chrome Provider 状态随启动、连接、断连和恢复变化；Provider 页逐项展示实际能力；生成 51 条操作后列表只显示 50 条；点击“清空列表显示”并确认后列表为空，再触发新操作后仅新操作出现；导出一条已隐藏操作并确认导出成功；检查日志仍可用于诊断。

- [ ] **Step 4: 提交文档**

运行：`git add docs/architecture/gesturekit-v2-ui-information-architecture.md docs/product/gesturekit-v1-contract.md docs/architecture/control-center-status-and-history-design.md && git commit -m "docs: record control center history behavior"`。

## 计划自检

- 覆盖性：Task 1 解决真实能力上报，Task 2 解决可见状态卡死，Task 3 保护原始日志并实现隐藏语义，Task 4 固定 50 条和用户动作，Task 5 做跨端回归与长期文档同步。
- 无占位项：所有接口、SQL、测试命令、文案和提交范围均已明确。
- 一致性：所有 UI 清空调用均经过 `OperationJournaling.clearOperationListDisplay()`；任何导出仍按操作 ID 绕过展示隐藏过滤。
