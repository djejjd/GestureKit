# Task 6 原子接受边界修复交接

## 范围与结果

修复 Chrome Provider v2 的 `action_request` 分发路径：在任何 `ChromeActionAdapter.execute()`（进而 `chrome.tabs`）副作用之前，先用现有 IndexedDB ledger 的单个 `accept()` 事务持久化 `accepted` ledger 状态和 `action_accepted` outbox 事件。

- `accept()` 成功且返回 `accepted` 后才允许 adapter 执行。
- `accept()` 的任何异常（包括 `ProviderStorageFullError`）都会阻止 adapter/Chrome API，并向 App 发送 `action_result { outcome: "failed", reason: "storage_full" }`。
- 重复 `operationId` 使用 ledger 的既有状态生成结果，不再次执行副作用。
- adapter 完成后，分发器生成 `action_result` 事件，通过 ledger `finalize()` 持久化，再发送结果信封。
- V1 `NativePortManager` 路径未改动。

## 变更文件

- `extensions/chrome/src/provider/v2Dispatcher.ts`
  - 注入 `OperationLedgerStore` 和 provider session ID。
  - 构造带单调 producer sequence 的 accepted/final ProviderEvent。
  - 在执行前执行 fail-closed `accept()`，并处理重复操作。
- `extensions/chrome/src/background/background.ts`
  - 复用 `providerLedger` 初始化完成后的 store 创建 v2 dispatcher，保证生产路径获得 ledger。
- `extensions/chrome/tests/v2Dispatcher.test.ts`
  - 新增 storage-full fail-closed 回归测试。
  - 新增 accepted 已落库后才执行、重复 request 不重复执行的回归测试。

## TDD 证据

### RED

命令：`npm test -- --run tests/v2Dispatcher.test.ts`

实现前结果：3 个测试中 2 个失败。

- `does not execute Chrome actions when accepted evidence cannot be persisted`：期望执行次数 `0`，实际为 `1`。
- `does not execute a duplicate action request after it was accepted`：期望执行次数 `1`，实际为 `2`。

### GREEN

聚焦测试：`npm test -- --run tests/v2Dispatcher.test.ts`

结果：`1 passed`, `3 passed`。

## 验证

- `npm test -- --run`：通过，`21` 个 test files、`133` 个 tests。
- `npm run build`：通过。
- `git diff --check`：通过。

## 已知限制

- 额外执行的 `npx tsc --noEmit` 失败，报告了 background、smoke 和多组既有测试 mock 的严格类型错误；这些错误不在本次变更文件内，且 `npm run build` 与完整 Vitest 均通过。本任务未扩大范围修复它们。
- 本修复只覆盖 Task 6 的 accepted-before-side-effect 断言；不改变 Task 7/8 的迁移或重连策略。

## 审查后补充修复（第二轮）

审查发现第一轮仍有三个异常出口可能让 background listener 的 Promise 拒绝：accepted 事件的 sequence 分配在 `try` 外、Chrome adapter 的异常未转换、以及 `finalize()` 的异常未转换。

`V2Dispatcher` 现将 accepted 事件构造与 sequence 分配一并放入 acceptance fail-closed 边界；任何异常均在未执行 Chrome 副作用时返回协议合法的 `failed/storage_full`。adapter 抛错时会尝试原子持久化并发送 `failed/chrome_api_error`。终态事件构造或 `finalize()` 失败时，保留 durable `accepted` 状态，并发送 `result_unknown/recovery_timeout`，不会虚报已持久化的终态。

### 第二轮 RED

命令：`npm test -- --run tests/v2Dispatcher.test.ts`

实现前结果：6 个测试中 3 个失败，均为预期的未处理拒绝：

- `sequence unavailable`
- `Chrome tabs failed`
- `finalize unavailable`

### 第二轮 GREEN

- `npm test -- --run tests/v2Dispatcher.test.ts`：`1 passed`, `6 passed`。
- 完整回归及构建见本次提交前的验证输出。

## 第二次审查后修复（第三轮）

### 根因与边界

原 `accept()` 的返回值只有 `LedgerState`。重复请求恰好读到 in-flight 的既有 `accepted` 记录时，无法区分“本次刚创建”与“另一请求已创建”，因此两个 dispatcher 都可能执行。并且终态重复请求仅由 ledger state 推断原因，丢失了持久化的原始 `action_result.reason`。

新增 additive `acceptWithDisposition()`，返回 `{ state, created }`；原 `accept()` 保持原签名并委托该方法，兼容既有调用。该方法仍在同一 IndexedDB readwrite transaction 中执行 ledger/outbox 写入。V2 dispatcher 仅在 `created: true` 时进入 adapter；所有既有操作均直接返回。终态 duplicate 从 ledger 保存的 `action_result` 事件读取原始 outcome/reason；若证据不存在则保守返回 `result_unknown/recovery_timeout`。

### 第三轮 RED

命令：`npm test -- --run tests/operationLedger.test.ts tests/v2Dispatcher.test.ts`

实现前结果：16 个测试中 3 个失败。

- `acceptWithDisposition is not a function`。
- in-flight duplicate：期望 1 次执行，实际 2 次。
- failed terminal duplicate：期望 `chrome_api_error`，实际伪造为 `provider_disconnected`。

### 第三轮 GREEN

- 聚焦：`tests/operationLedger.test.ts` 与 `tests/v2Dispatcher.test.ts`，`16/16` 通过。
- 新回归覆盖：acceptance 创建归属、in-flight duplicate 竞争、failed terminal duplicate 的原始 reason 返回。

## Task 6 补充测试覆盖（tombstone、离线队列和 ACK 回收）

在既有 ledger/outbox 实现上补齐 Task 6 明示的边界测试：

- 10,000 条终态记录在 10 分钟后压缩为 tombstone，并从压缩完成起保留完整 7 天后删除。
- 离线 24 小时的 queued telemetry 仍保留，并按 `producerSequence` 而非写入顺序发送。
- outbox 容量饱和时第二条事件明确返回 `provider_storage_full`；仅在 ACK 删除第一条后才回收容量并允许写入。
- 已有 accepted/final 跨 service-worker restart 测试改为明确的 restart-boundary 命名，继续验证两次提交边界后的可恢复状态和 pending 事件。

### RED / GREEN

新增 tombstone 测试初次运行失败：实现从 `terminalAt` 而不是 `compactedAt` 起计算 7 天生命周期，导致 tombstone 提前约 10 分钟删除。将删除条件改为 `now - compactedAt >= 7 天` 后通过。

### 验证

- `npm test -- --run tests/operationLedger.test.ts tests/telemetryOutbox.test.ts tests/reconciliation.test.ts`：3 files、14 tests 通过。
- `npm test -- --run`：21 files、141 tests 通过。
- `npm run build`：通过。
- `git diff --check`：通过。
