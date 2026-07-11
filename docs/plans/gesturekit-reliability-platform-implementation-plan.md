# GestureKit 可靠性与可扩展动作平台实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 在不丢失现有 Chrome V1 行为的前提下，建立可认证 Provider、统一证据链、持久化操作账本和 App 主窗口，并为后续浏览器与可配置手势保留稳定边界。

**架构：** 先通过 Unix socket、page guard 时序和 clean-TCC Spike 固化风险结论；然后实现 Provider Protocol v2、App `OperationJournal`、Chrome IndexedDB outbox/ledger 和认证会话；最后把现有手势、网页上下文、配置和 UI 迁移到新边界。Chrome 是第一个 Provider，Native Messaging 仍由扩展用 `connectNative()` 发起。

**技术栈：** Swift 6.2、macOS 15、AppKit + SwiftUI host window、Foundation/CryptoKit/Network、SQLite3、Chrome MV3、TypeScript、IndexedDB、Vitest。

## 全局约束

- 项目文档中文优先；代码、协议字段、命令和路径保持原文。
- 所有用户配置只由 App `SettingsStore` 保存；扩展只保存只读缓存、operation ledger 和 outbox。
- Core 不得引用 `chrome.tabs`、Chrome 专用动作枚举或 `connectNative()`。
- Provider Protocol 使用 `protocolVersion: 2`；legacy `GestureKitMessage version: 1` 只存在于 Chrome adapter 迁移边界。
- 所有动作必须经唯一 `RuleEngine` 门面；`BindingResolver` 是内部组件，Provider 不得更改 `actionId`。
- `operationId` 的副作用最多执行一次；结果不确定时对账，不自动重放。
- Provider 的 `ledger.accepted + action_accepted` 与 `ledger.final + action_result` 必须分别在同一个 IndexedDB 事务提交。
- 受管理诊断总预算为 50 MB：App 45 MB，V1 Chrome Provider 5 MB；导出副本不计入预算。
- Provider 采集源和 App 入库端都必须进行结构化白名单脱敏；不得持久化 query/hash、DOM 文本、id/class、Cookie、表单值或自由文本 details。
- 链接动作必须以 `guard_armed` 为前置条件；page guard 时序 Spike 未通过时，三指点按链接不能通过 V1 验收。
- `CGEventTapShield` 是“普通操作不受持续延迟影响”的首要保护路径；无权限或 Spike 未通过时，保留 V1 有界链接点击保护并记录降级原因。它不阻塞 Provider 协议开发，但未通过时不得将候选期 page guard 标记为通过。
- 每个任务遵循 TDD：先写失败测试，确认失败，再写最小实现，运行任务级测试和完整相关套件，最后提交。

## 执行角色与交接闸门

- **实现型 AI**：负责按任务实现代码、单元/集成测试、测试夹具和实现说明；不得修改本计划的验收标准，不得把 Spike 或 UI 人工验收标记为 `passed`。
- **主审核代理（本计划的编排者）**：负责审查跨模块边界、敏感权限、协议兼容、证据链完整性，并亲自执行 Task 1、Task 2 的 Spike 结论和 Task 10 的 UI/交互验收；必要时退回实现任务，不以“可复现”替代已有证据。
- **实现型 AI 的交接包**必须包含：变更文件清单、失败测试到通过测试的命令与输出、已知限制、未决风险、可导出的最小证据包。没有交接包不得进入下一阶段。
- **Spike 闸门**：Task 1/2 只能产生 `passed`、`passed_with_notes` 或 `failed`；只有主审核代理依据原始命令输出、打包产物和人工记录确认后，后续任务才能消费结论。`passed_with_notes` 不得被下游当作 `passed`。
- **UI 闸门**：Task 10 的实现型 AI 只负责窗口/popup 代码和自动化测试；主审核代理在真实 App/扩展构建产物上检查文案（不得出现 `primitive_rejected` 等内部枚举）、信息层级、关键路径和窄屏布局，并单独记录通过/退回理由。
- **禁止越权**：实现型 AI 不得顺手启用 `CGEventTapShield`、修改权限说明、删除 legacy 主流程或扩大 V1 手势范围；这些变更必须由主审核代理在对应闸门确认后批准。

### 已确认的负责人分配

| 任务 | 主负责人 | 实现型 AI 可承担的范围 | 主审核代理的保留职责 |
| --- | --- | --- | --- |
| Task 1：SQLite / 认证 IPC / clean-TCC Spike | 主审核代理 | 不派发主逻辑 | Spike 实现、正式环境执行和结论 |
| Task 2：page guard 时序 Spike | 主审核代理 | 不派发主逻辑 | Spike 实现、真实 Chrome 时序和结论 |
| Task 2A：InteractionShield Spike | 主审核代理 | 不派发主逻辑 | 权限、事件 tap、副作用矩阵和结论 |
| Task 3：Provider Protocol v2 | 实现型 AI | 模型、schema、fixture、单测 | 协议和兼容性审查 |
| Task 4：Journal / 脱敏 / 证据包 | 实现型 AI | 存储、迁移、导出、单测 | 数据保留、脱敏和导出隐私审查 |
| Task 5：认证会话 / 定向 IPC | 主审核代理 | 不拆分主逻辑 | 凭据、nonce、重放、session 绑定和断连 |
| Task 6：IndexedDB ledger / outbox | 实现型 AI | 全部实现和自动测试 | 幂等、容量、断连恢复审查 |
| Task 7：手势 session / 通用规则 | 实现型 AI | Core 实现和回归测试 | API 兼容、时延预算、规则语义审查 |
| Task 8：Chrome context / guard / action | 主审核代理 | 仅可协助独立 API 夹具 | 候选绑定、真实 guard、跨组件时序 |
| Task 9：配置主权迁移 | 实现型 AI | 全部实现和自动测试 | 一次性迁移与回滚审查 |
| Task 10：App 窗口 / 菜单 / popup | 实现型 AI | view model、页面、popup 实现 | 信息架构、诊断文案、真实 UI/交互验收 |
| Task 11：E2E / legacy 清理 / 发布关口 | 主审核代理 | 脚本和文档草稿 | 实际验收、证据归档、legacy 删除批准 |

实现型 AI 任务启动前，主审核代理必须向用户提供可复制的任务 prompt。prompt 必须引用本计划、列明允许修改的路径、禁止改动的边界、测试命令、交接包路径和不得自行宣布通过的闸门。

---

## 阶段顺序

```text
P0 风险 Spike
  ├─ Task 1: 本地 IPC / SQLite / clean-TCC
  ├─ Task 2: page guard 时序
  └─ Task 2A: InteractionShield 可行性（独立闸门）

P1 可观测性与协议底座
  └─ Task 3: Provider Protocol v2 与 JSON schema
      ├─ Task 4: OperationJournal、脱敏与证据包
      └─ Task 5: 认证 Provider 会话与定向 IPC

P2 Chrome Provider 迁移
  ├─ Task 10A: App/popup UI 框架与状态文案（依赖 Task 4，不接入 Provider/配置业务）
  ├─ Task 6: IndexedDB ledger/outbox 与重连对账
  ├─ Task 7: 手势 session、通用规则与上下文快照
  └─ Task 8: Chrome context、guard 和标准动作 adapter（依赖 Task 4-7）

P3 配置与界面迁移
  ├─ Task 9: App 配置迁移和 Provider 配置快照
  ├─ Task 10B: App 主窗口、菜单栏和精简 popup 的真实数据接入（依赖 Task 4、Task 9）
  └─ Task 11: 端到端验收、legacy 清理和发布关口（依赖全部实现任务及 Spike 闸门）
```

实际执行顺序固定为：`Task 1/2/2A 并行 → Task 3 契约闭环门 → Task 4 → Task 4 审核闭环门 → Task 5 → Task 10A → Task 6/7 并行 → Task 8 → Task 9 → Task 10B → Task 11`。Task 10A 只固化 UI 框架、状态文案和 popup 信息边界，不能显示未验证的成功状态，也不能消费 Task 6–9 的运行时模型。Task 1 或 Task 2 未经主审核代理确认时，只能继续做不依赖其结论的测试夹具，不能进入生产迁移；Task 2A 为可选能力，未通过不阻塞基础方案，但必须保留 `NoopShield`。Task 3 未通过跨语言载荷判别门时，Task 4/5 均不得开始；Task 4 未通过导出脱敏、迁移和幂等审核门时，Task 5 不得消费其模型或存储。

## 文件结构

- `Sources/GestureKitCore/Provider/ProviderProtocolV2.swift`：v2 envelope、ID、上下文、动作和 telemetry Codable 模型。
- `Sources/GestureKitCore/Rules/BindingModels.swift`：`GestureDefinition`、标准 `ActionDescriptor` 和版本化配置模型。
- `Sources/CSQLite/module.modulemap`：SQLite3 system-library module。
- `apps/macos/GestureKitApp/Sources/GestureKitApp/OperationJournal.swift`：SQLite WAL、迁移、事件去重、清理和证据包导出。
- `apps/macos/GestureKitApp/Sources/GestureKitApp/ProviderSessionRegistry.swift`：Provider 注册、认证、会话和定向路由。
- `apps/macos/GestureKitApp/Sources/GestureKitApp/ProviderCredentialStore.swift`：安装凭据生成、轮换和撤销。
- `apps/macos/GestureKitApp/Sources/GestureKitApp/GestureSessionCoordinator.swift`：候选 session、组合和 guard 生命周期。
- `apps/macos/GestureKitApp/Sources/GestureKitApp/GestureKitWindowController.swift`：App 主窗口和 SwiftUI hosting。
- `native-host/gesturekit-host/Sources/GestureKitHost/ProviderBridge.swift`：stdio 与认证 App IPC 的透明桥接。
- `extensions/chrome/src/provider/protocol.ts`：v2 TypeScript 类型和运行时校验。
- `extensions/chrome/src/provider/operationLedger.ts`：IndexedDB `operationId` 去重账本。
- `extensions/chrome/src/provider/telemetryOutbox.ts`：事务性事件 outbox、ACK、压缩和容量保护。
- `extensions/chrome/src/provider/chromeProvider.ts`：上下文查询、标准动作执行、对账和能力声明。
- `extensions/chrome/src/content/interactionGuard.ts`：候选会话 guard 状态机。
- `extensions/chrome/src/settings/appConfigurationCache.ts`：只读配置快照、epoch/version 和 legacy 一次性导入。
- `extensions/chrome/src/popup/popup.ts`：只保留当前页状态和打开 App 入口。

## Task 1: 先完成 SQLite、认证本地 IPC 和 clean-TCC Spike

**文件：**

- Create: `Sources/CSQLite/module.modulemap`
- Modify: `Package.swift`
- Create: `spikes/provider-ipc/Sources/ProviderIPCProbe/main.swift`
- Create: `spikes/provider-ipc/README.md`
- Create: `docs/research/provider-ipc-and-clean-tcc-spike.md`
- Test: `Tests/GestureKitCoreTests/SQLiteAvailabilityTests.swift`

**接口：**

```swift
import CSQLite

func sqliteVersion() throws -> String
func runProviderIPCProbe() throws -> ProviderIPCProbeResult
```

`ProviderIPCProbeResult` 必须包含 `transport`、`socketPermissions`、`challengeAccepted`、`invalidCredentialRejected` 和 `sameUIDThreatModel`。

当前仓库的 `LocalEventServer`/`AppIPCClient` 仍使用 loopback TCP。Spike 不得只验证一条与生产无关的临时 Unix socket：若选择 Unix socket，必须在本任务中同时抽象并迁移 App、host 的 transport、启动/发现和旧连接关闭路径；若最终保留 TCP，必须记录 loopback 绑定、端口发现/抢占、防陈旧 host 和凭据绑定证据，并将 `transport` 结论写成 `tcp_loopback`。两种方案都必须让后续 Task 5 复用同一 `IPCTransport` 接口，不能让 Spike 结果与生产链路分叉。

- [ ] **Step 1: 写 SQLite 可用性失败测试**

```swift
func testSQLiteVersionIsAvailable() throws {
    let version = try sqliteVersion()
    XCTAssertFalse(version.isEmpty)
}
```

- [ ] **Step 2: 运行测试，确认当前工程没有 SQLite module**

Run: `swift test --filter SQLiteAvailabilityTests`

Expected: FAIL，错误包含 `no such module 'CSQLite'` 或 `cannot find 'sqliteVersion'`。

- [ ] **Step 3: 增加 system library target 和最小包装**

```swift
// Package.swift
.systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
.target(name: "GestureKitCore", dependencies: ["CSQLite"], path: "Sources/GestureKitCore"),

// 在现有 GestureKitApp target 的 dependencies 中加入 "CSQLite"：
.executableTarget(
  name: "GestureKitApp",
  dependencies: ["GestureKitCore", "CSQLite", .product(name: "OpenMultitouchSupport", package: "OpenMultiTouchSupport")],
  path: "apps/macos/GestureKitApp/Sources/GestureKitApp"
)

// Sources/CSQLite/module.modulemap
module CSQLite [system] {
  header "sqlite3.h"
  link "sqlite3"
  export *
}
```

```swift
import CSQLite

func sqliteVersion() throws -> String {
    guard let value = sqlite3_libversion() else { throw SQLiteAvailabilityError.versionUnavailable }
    return String(cString: value)
}
```

- [ ] **Step 4: 实现 Provider IPC Probe**

Probe 必须创建位于 `0700` 临时目录的 `0600` Unix socket，生成 32-byte secret，并验证以下序列：

```text
provider_hello(providerInstallId)
→ provider_challenge(nonce)
→ provider_authenticate(HMAC-SHA256(secret, nonce))
→ authenticated session
```

Probe 同时向错误 HMAC 客户端返回 `provider_auth_failed`，并在 README 中明确 V1 不抵御已攻陷的同 UID 进程。

`ProviderIPCProbe` 必须作为 SwiftPM executable product/target 注册在 `Package.swift`，并在 clean checkout 中可执行 `swift run ProviderIPCProbe`；`sqliteVersion()` 放在可被测试和 probe 共同依赖的明确 target（不得依赖测试文件或未声明的 module）。Probe 的结果 JSON、原始命令输出、签名/打包路径和 clean-TCC 记录由实现型 AI 提交，最终 `passed` 只能由主审核代理确认。

- [ ] **Step 5: 执行 Probe 与 clean-TCC 手工矩阵**

Run: `swift run ProviderIPCProbe`

Expected: 输出 JSON，`transport` 必须与最终选型一致（`unix_domain_socket` 或 `tcp_loopback`），并且 `socketPermissions=0600`（Unix）或等价的 loopback/凭据绑定证据（TCP）、`challengeAccepted=true`、`invalidCredentialRejected=true`。

手工矩阵必须在正式签名/打包形态下记录：重置 TCC、Input Monitoring 和 Accessibility 均关闭时的首次启动、重启、权限撤销，以及 `TouchBackend.start()` 的实际结果。至少覆盖旧 socket/端口残留、错误凭据、重复 nonce、过期 session、providerInstallId 不匹配和同 UID 客户端；任何不确定结果都必须 fail-closed，并保留原始证据，不能由实现型 AI 自行降级为“可用”。

- [ ] **Step 6: 运行 Swift 完整测试并提交**

Run: `swift test`

Expected: PASS。

```bash
git add Package.swift Sources/CSQLite Sources/GestureKitCore Tests/GestureKitCoreTests spikes/provider-ipc docs/research/provider-ipc-and-clean-tcc-spike.md
git commit -m "spike: verify sqlite and authenticated provider ipc"
```

## Task 2: 验证 page guard 能在 DOM 副作用前 armed

**文件：**

- Create: `spikes/page-guard-timing/guard-timing.html`
- Create: `spikes/page-guard-timing/README.md`
- Modify: `extensions/chrome/src/content/pointerTracker.ts`
- Test: `extensions/chrome/tests/pageGuardTiming.test.ts`
- Modify: `docs/research/trackpad-gesture-stability-matrix.md`

**接口：**

自动化时序测试和页面夹具可由实现型 AI 编写；真实 Chrome 扩展、App、host、DOM 的端到端时序和最终 `passed` 判定由主审核代理执行。任何 candidate 到达 DOM 副作用之后才收到 `guard_armed`，都必须判定为失败并阻断链接动作。

当前结论见 `docs/research/page-guard-timing-spike.md`：现有 V1 链路没有候选开始消息，无法在 DOM 前可靠 armed。V2 改用本地 `InteractionShield` 作为首要保护，page guard 仅保留为辅助证据与降级路径。

```ts
export type GuardCommand = {
  type: "gesturekit.guardArm";
  gestureSessionId: string;
  issuedAtMonotonicMs: number;
  leaseMs: number;
};

export type GuardObservation = {
  gestureSessionId: string;
  domEventMonotonicMs: number;
  armedAtMonotonicMs: number | null;
  status: "armed_before_dom" | "late" | "unavailable";
};
```

- [ ] **Step 1: 写失败测试，拒绝未 armed 的链接消费**

```ts
it("does not consume a link click without a matching armed session", () => {
  const result = consumeGuardedClick({ gestureSessionId: "g-1", now: 10 });
  expect(result).toEqual({ status: "guard_unavailable" });
});

it("records armed_before_dom when the arm command arrives first", () => {
  armGuard({ gestureSessionId: "g-1", issuedAtMonotonicMs: 1, leaseMs: 800 });
  const result = observeTargetDOMEvent({ gestureSessionId: "g-1", now: 2 });
  expect(result.status).toBe("armed_before_dom");
});
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `npm test -- --run tests/pageGuardTiming.test.ts`

Expected: FAIL，提示 `consumeGuardedClick` 或 `armGuard` 未定义。

- [ ] **Step 3: 实现候选期 guard 状态机**

`pointerTracker.ts` 不得继续对所有普通链接常驻延迟。guard 必须仅匹配当前 tab、一次性 `gestureSessionId` 和未过期 lease，并监听 `click`、`selectstart`、`dragstart`。

```ts
function isActiveGuard(guard: GuardState | null, sessionId: string, now: number): boolean {
  return guard?.gestureSessionId === sessionId && now <= guard.expiresAtMonotonicMs && !guard.consumed;
}
```

- [ ] **Step 4: 执行自动和人工时序 Spike**

Run: `npm test -- --run tests/pageGuardTiming.test.ts tests/pointerTracker.test.ts`

Expected: PASS。

人工测试必须在 `guard-timing.html` 记录候选、host/extension、content script 和目标 DOM 事件的单调时钟。标准链接场景 30 次全部为 `armed_before_dom` 才可判定 `passed`；任何 `late` 或 `unavailable` 使三指点按链接保持阻塞。

- [ ] **Step 5: 提交 Spike 结果**

```bash
git add spikes/page-guard-timing extensions/chrome/src/content/pointerTracker.ts extensions/chrome/tests/pageGuardTiming.test.ts extensions/chrome/tests/pointerTracker.test.ts docs/research/trackpad-gesture-stability-matrix.md
git commit -m "spike: measure page guard timing"
```

## Task 2A: 独立验证 InteractionShield 可行性（主审核闸门）

该任务不是实现型 AI 的默认开发任务。实现型 AI 可以准备最小调用适配器和测试夹具，但真实权限申请、签名 App、事件 tap 生命周期和副作用矩阵由主审核代理执行。目标是判断三指滑动期间能否抑制文本选中、图片拖动等系统/网页默认行为，而不是承诺一定启用权限。

当前 Spike 结论见 `docs/research/interaction-shield-spike.md`，状态为 `passed_with_notes`：短 lease 可抑制真实拖动并在结束后恢复输入，但尚未完成全部权限与跨窗口矩阵，因此不得接入默认生产路径。

- 记录 `NoopShield` 基线，以及 `CGEventTapShield` 在 Input Monitoring/Accessibility 各权限组合下的启动、失效、恢复和退出行为。
- 覆盖普通点击、文本选择、图片拖动、输入框、跨窗口切换和权限撤销；任何权限不可用、事件 tap 超时或行为不确定时必须回退 `NoopShield`，不得阻断普通输入。
- 产物必须包括正式签名/打包 App、原始命令输出、权限提示截图/说明、事件计时和失败样本；结论只能是 `passed`、`passed_with_notes` 或 `failed`。
- 只有主审核代理确认 `passed` 后，Task 8/Task 11 才能将 shield 接入默认路径；否则保留 `NoopShield`，并在 UI 中以用户可理解文案说明未启用原因，不暴露内部枚举。

## Task 3: 固化 Provider Protocol v2 和标准领域模型

**文件：**

- Create: `packages/protocol/schemas/provider-v2.schema.json`
- Create: `Sources/GestureKitCore/Provider/ProviderProtocolV2.swift`
- Create: `Sources/GestureKitCore/Rules/BindingModels.swift`
- Create: `extensions/chrome/src/provider/protocol.ts`
- Create: `packages/protocol/fixtures/provider-v2-action-request.json`
- Test: `Tests/GestureKitCoreTests/ProviderProtocolV2Tests.swift`
- Test: `extensions/chrome/tests/providerProtocol.test.ts`

**接口：**

```swift
public struct ProviderEnvelope: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let messageId: String
    public let providerSessionId: String
    public let gestureSessionId: String?
    public let operationId: String?
    public let type: ProviderMessageType
    public let timestamp: Int64
    public let payload: ProviderPayload
}

public struct ActionDescriptor: Codable, Sendable, Equatable {
    public let actionId: StandardActionID
    public let contextId: String
    public let targetRef: String?
    public let parameters: [String: String]
    public let deadline: Int64
}
```

- [ ] **Step 1: 写 Swift 与 TypeScript 的 v2 fixture 失败测试**

```swift
func testActionRequestFixtureDecodesAsProtocolV2() throws {
    let message = try decodeFixture("provider-v2-action-request.json")
    XCTAssertEqual(message.protocolVersion, 2)
    XCTAssertEqual(message.type, .actionRequest)
}
```

```ts
it("rejects a legacy v1 envelope at the Provider boundary", () => {
  expect(() => decodeProviderEnvelope({ version: 1, type: "gesture_event" })).toThrow("protocolVersion");
});
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter ProviderProtocolV2Tests`

Expected: FAIL，缺少 `ProviderEnvelope`。

Run: `npm test -- --run tests/providerProtocol.test.ts`

Expected: FAIL，缺少 `decodeProviderEnvelope`。

- [ ] **Step 3: 实现协议、动作和 telemetry event 模型**

`ProviderEvent` 必须包含 `eventId`、`producerSessionId`、`producerSequence`、`causedByEventId`、单调时钟、wall-clock、`gestureSessionId` 和 `operationId`。标准动作至少定义：

```text
browser.link.open_adjacent
browser.tab.activate_previous
browser.tab.activate_next
browser.tab.close_current
browser.history.back
browser.history.forward
browser.page.reload
```

`context_snapshot` 必须只带 `contextId`、页面身份、过期时间、标准 target facts 和不透明 `targetRef`。

实现必须遵守架构文档 3.4.1 的完整 type-payload 判别表。`ProviderPayload` 不得通过“尝试依次解码已知结构”的方式猜测类型；必须由 `type` 驱动解码并拒绝不匹配载荷。`action_result` 必须有显式 `succeeded`/`failed`/`result_unknown` outcome，不能只用消息类型表示成功。

- [ ] **Step 3A: 补齐协议负向与跨语言一致性测试**

Swift 与 TypeScript 都必须覆盖：缺少 `error` 键、空 ID、负数/小数/NaN timestamp、未知 type、type-payload 不匹配、`action_request` 缺少 operationId、`action_result` 缺少或非法 outcome。每个样例必须在两端一致拒绝；同时增加所有 17 个消息类型的合法 fixture/round-trip 覆盖，不能以未实现的 payload 占位。

- [ ] **Step 4: 运行跨语言 fixture 测试**

Run: `swift test --filter ProviderProtocolV2Tests`

Expected: PASS。

Run: `npm test -- --run tests/providerProtocol.test.ts`

Expected: PASS。

- [ ] **Step 5: 提交协议基线**

```bash
git add packages/protocol Sources/GestureKitCore/Provider Sources/GestureKitCore/Rules/BindingModels.swift Tests/GestureKitCoreTests extensions/chrome/src/provider/protocol.ts extensions/chrome/tests/providerProtocol.test.ts
git commit -m "feat: add provider protocol v2 models"
```

## Task 4: 实现 OperationJournal、双重脱敏和证据包

**文件：**

- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/OperationJournal.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/DiagnosticRedactor.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/EvidenceBundleExporter.swift`
- Test: `Tests/GestureKitAppTests/OperationJournalTests.swift`
- Test: `Tests/GestureKitAppTests/DiagnosticRedactorTests.swift`
- Test: `Tests/GestureKitAppTests/EvidenceBundleExporterTests.swift`

**接口：**

```swift
protocol OperationJournaling: Sendable {
    func append(_ event: ProviderEvent) throws
    func recoverExpired(now: Int64) throws -> [RecoveredOperation]
    func query(_ filter: OperationFilter, limit: Int) throws -> [OperationTimeline]
    func exportEvidence(operationId: String, to url: URL) throws
}

struct RedactedPageContext: Codable, Equatable {
    let host: String
    let redactedPath: String
    let targetKind: String
    let targetRole: String?
}
```

- [ ] **Step 1: 写 Journal 失败测试**

```swift
func testAppendIsIdempotentByEventID() throws {
    try journal.append(event)
    try journal.append(event)
    XCTAssertEqual(try journal.query(.operation(event.operationId!), limit: 10).count, 1)
}

func testRecoveryMarksExpiredAcceptedOperationUnknown() throws {
    try journal.append(acceptedEvent(deadline: 1))
    XCTAssertEqual(try journal.recoverExpired(now: 2).first?.terminalState, .resultUnknown)
}
```

还必须先写以下失败测试：`action_result` 的三种 outcome 分别归并为成功、失败、结果未知；同一 `eventId` 携带不同 operationId 时不得创建第二个 operation；恢复超时操作后必须存在带原因的终态事件；当前版本打开、旧版本升级、未来版本拒绝；producer sequence 缺口按 producer session 独立计算。

- [ ] **Step 2: 写脱敏失败测试**

```swift
func testRedactorRemovesQueryHashAndTokenLikeSegments() {
    let value = redactor.redactURL("https://example.com/user/a@example.com/reset/123456789012?token=x#frag")
    XCTAssertFalse(value.contains("token="))
    XCTAssertFalse(value.contains("a@example.com"))
    XCTAssertFalse(value.contains("123456789012"))
}
```

- [ ] **Step 3: 实现 SQLite schema 和容量规则**

创建 `sessions`、`operations`、`events`、`provider_sessions`、`configuration_snapshots` 表。`events.event_id` 和 `(producer_session_id, producer_sequence)` 必须唯一。数据库打开时启用 WAL，清理时按已完成 operation 删除、checkpoint，并把超过 lease 的未完成 operation 收敛为 `operation_interrupted` 或 `result_unknown`。

App 的 Journal 主库、WAL、SHM 和结构化日志总额超过 45 MB 时，先压缩低优先级成功事件；若关键事件不能写入，返回 `journal_storage_full` 并让运行时暂停动作派发。

- [ ] **Step 4: 实现双重脱敏和证据包**

Provider 输入只接受 host、路径 segment、tag/role 和枚举 failure reason。`DiagnosticRedactor` 必须再次拒绝 `message`、`details`、query、hash、DOM id/class/text。无法解析、无 host 或不允许 scheme 的 URL 必须输出枚举化不可用原因，禁止回退保存原始输入。导出 manifest 必须包含 schema/redaction 版本、ID 因果关系、配置 hash、能力版本、时间基准、终态和缺失范围；导出器必须在实际写入 events、manifest、README 前应用脱敏，并仅在真实应用后标记 `redactionApplied`。导出目录每次均强制 `0700`，导出文件为 `0600`。

`EvidenceBundleExporterTests` 必须使用含 query、hash、邮箱、token 和 `targetRef` 的 fixture，断言这些原文不出现在 `events.json`、`manifest.json` 或 `README.txt`；同时断言目录/文件权限、已存在目录权限修正和 `redactionApplied` 与实际输出一致。

- [ ] **Step 5: 运行任务测试和 Swift 全量测试**

Run: `swift test --filter OperationJournalTests`

Expected: PASS。

Run: `swift test --filter DiagnosticRedactorTests`

Expected: PASS。

Run: `swift test`

Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add apps/macos/GestureKitApp/Sources/GestureKitApp/OperationJournal.swift apps/macos/GestureKitApp/Sources/GestureKitApp/DiagnosticRedactor.swift apps/macos/GestureKitApp/Sources/GestureKitApp/EvidenceBundleExporter.swift Tests/GestureKitAppTests
git commit -m "feat: add persistent operation journal"
```

## Task 5: 将 App IPC 改为认证 Provider 会话和定向路由

**文件：**

- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/ProviderCredentialStore.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/ProviderSessionRegistry.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/LocalEventServer.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- Modify: `native-host/gesturekit-host/Sources/GestureKitHost/AppIPCClient.swift`
- Create: `native-host/gesturekit-host/Sources/GestureKitHost/ProviderBridge.swift`
- Test: `Tests/GestureKitAppTests/ProviderSessionRegistryTests.swift`

**接口：**

```swift
struct AuthenticatedProviderSession: Equatable, Sendable {
    let providerInstallID: String
    let providerID: String
    let providerSessionID: String
    let capabilities: Set<StandardActionID>
}

protocol ProviderSessionRouting: Sendable {
    func register(_ hello: ProviderHello, credential: Data) throws -> AuthenticatedProviderSession
    func send(_ envelope: ProviderEnvelope, to providerSessionID: String) throws
    func session(for context: AppContext) -> AuthenticatedProviderSession?
}
```

- [ ] **Step 1: 写会话认证和定向发送失败测试**

```swift
func testInvalidHMACCannotRegisterProvider() throws {
    XCTAssertThrowsError(try registry.register(hello, credential: Data("bad".utf8)))
}

func testSendTargetsOnlySelectedProviderSession() throws {
    let first = try registerChromeSession("one")
    _ = try registerChromeSession("two")
    try registry.send(envelope, to: first.providerSessionID)
    XCTAssertEqual(first.sent.count, 1)
    XCTAssertEqual(second.sent.count, 0)
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter ProviderSessionRegistryTests`

Expected: FAIL，缺少 `ProviderSessionRegistry`。

- [ ] **Step 3: 实现凭据生命周期和会话 registry**

首次 Provider 注册生成 32-byte secret 并写入 `~/Library/Application Support/GestureKit/providers/<install-id>.secret`，父目录 `0700`、文件 `0600`。`ProviderSessionRegistry` 必须执行 `provider_hello → challenge → HMAC authenticate`，记录 session replacement 事件，并拒绝未认证 payload。

`LocalEventServer.publish` 必须删除广播实现，改为 `send(_:to:)`；`Runtime` 只能经 `ProviderRouter` 选择 Chrome session 后定向发送。

- [ ] **Step 4: 把 host 变为透明 v2 bridge**

`ProviderBridge` 只处理 Native Messaging length framing 与 Unix socket 字节转发。它不解析动作、配置或 telemetry，不写日志正文。连接失败时仅发送 v2 `app_unavailable` 结构化错误。

- [ ] **Step 5: 运行测试和 host 自检**

Run: `swift test --filter ProviderSessionRegistryTests`

Expected: PASS。

Run: `swift run GestureKitHost --self-test`

Expected: `GestureKitHost self-test passed`。

- [ ] **Step 6: 提交**

```bash
git add apps/macos/GestureKitApp/Sources/GestureKitApp native-host/gesturekit-host/Sources/GestureKitHost Tests/GestureKitAppTests
git commit -m "feat: add authenticated provider sessions"
```

## Task 6: 实现 Chrome Provider 的 IndexedDB ledger、outbox 和对账

**文件：**

- Create: `extensions/chrome/src/provider/indexedDb.ts`
- Create: `extensions/chrome/src/provider/operationLedger.ts`
- Create: `extensions/chrome/src/provider/telemetryOutbox.ts`
- Create: `extensions/chrome/src/provider/reconciliation.ts`
- Modify: `extensions/chrome/package.json`
- Modify: `extensions/chrome/vitest.config.ts`
- Create: `extensions/chrome/tests/setup.ts`
- Test: `extensions/chrome/tests/operationLedger.test.ts`
- Test: `extensions/chrome/tests/telemetryOutbox.test.ts`
- Test: `extensions/chrome/tests/reconciliation.test.ts`

**接口：**

```ts
export type LedgerState = "accepted" | "success" | "failed" | "result_unknown";

export interface OperationLedger {
  accept(operationId: string, event: ProviderEvent): Promise<LedgerState>;
  finalize(operationId: string, state: LedgerState, event: ProviderEvent): Promise<void>;
  status(operationId: string): Promise<LedgerRecord | null>;
}

export interface TelemetryOutbox {
  append(event: ProviderEvent): Promise<void>;
  acknowledge(eventIds: string[]): Promise<void>;
  pending(limit: number): Promise<ProviderEvent[]>;
}
```

Vitest 必须使用真实 IndexedDB 语义的测试环境：

```json
// extensions/chrome/package.json
"devDependencies": {
  "fake-indexeddb": "^6.0.0"
}
```

```ts
// extensions/chrome/tests/setup.ts
import "fake-indexeddb/auto";
```

```ts
// extensions/chrome/vitest.config.ts
test: { environment: "jsdom", setupFiles: ["./tests/setup.ts"] }
```

- [ ] **Step 1: 写 accepted/final 原子事务失败测试**

```ts
it("persists accepted ledger state and action_accepted event atomically", async () => {
  await expect(store.accept("op-1", acceptedEvent("op-1"))).resolves.toBe("accepted");
  expect(await store.ledger.status("op-1")).toMatchObject({ state: "accepted" });
  expect(await store.outbox.pending(10)).toContainEqual(acceptedEvent("op-1"));
});

it("returns the existing state without executing a duplicate operation", async () => {
  await store.accept("op-1", acceptedEvent("op-1"));
  await expect(store.accept("op-1", acceptedEvent("op-1"))).resolves.toBe("accepted");
});
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `npm test -- --run tests/operationLedger.test.ts tests/telemetryOutbox.test.ts`

Expected: FAIL，缺少 IndexedDB store。

- [ ] **Step 3: 实现单数据库原子事务**

使用一个 IndexedDB database，包含 `ledger`、`outbox`、`metadata` object stores。`accept` 在同一 readwrite transaction 写入 ledger 和 `action_accepted` event；`finalize` 在同一 transaction 写入 terminal ledger 和 `action_result` event。ACK 只删除 outbox event，不得修改 ledger。

完整 ledger 在 App 确认 final event 后保留 10 分钟，再压缩为 7 天 tombstone。5 MB 容量内预留 1 MB 给未确认关键事件；无法写关键记录时返回 `provider_storage_full`，调用方不得执行 Chrome 副作用。

- [ ] **Step 4: 实现 ACK、压缩和对账**

`telemetry_ack` 使用 event ID 列表。重连顺序固定为认证、`operation_status_request`、ledger 对账、按 `producerSequence` 发送 batch、等待 ACK。测试 10,000 tombstone、24 小时离线队列、满载 ACK 回收，以及 worker 在 accepted/final transaction 提交前后中断。

- [ ] **Step 5: 运行 Chrome 完整测试**

Run: `npm test -- --run tests/operationLedger.test.ts tests/telemetryOutbox.test.ts tests/reconciliation.test.ts`

Expected: PASS。

Run: `npm test -- --run`

Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add extensions/chrome/package.json extensions/chrome/package-lock.json extensions/chrome/vitest.config.ts extensions/chrome/src/provider extensions/chrome/tests/setup.ts extensions/chrome/tests/operationLedger.test.ts extensions/chrome/tests/telemetryOutbox.test.ts extensions/chrome/tests/reconciliation.test.ts
git commit -m "feat: add chrome provider ledger and outbox"
```

## Task 7: 把候选手势、组合和规则迁移到 App Core

**文件：**

- Modify: `Sources/GestureKitCore/Gestures/GestureRecognizer.swift`
- Create: `Sources/GestureKitCore/Gestures/GestureSessionEvent.swift`
- Modify: `Sources/GestureKitCore/Rules/RuleModels.swift`
- Modify: `Sources/GestureKitCore/Rules/RuleEngine.swift`
- Modify: `Sources/GestureKitCore/Rules/DefaultRules.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/GestureSessionCoordinator.swift`
- Test: `Tests/GestureKitCoreTests/GestureSessionEventTests.swift`
- Test: `Tests/GestureKitCoreTests/RuleEngineTests.swift`
- Test: `Tests/GestureKitAppTests/GestureSessionCoordinatorTests.swift`

**接口：**

```swift
public enum GestureSessionEvent: Equatable, Sendable {
    case candidateStarted(GestureCandidate)
    case primitiveClassified(RecognizedGesture)
    case primitiveRejected(RecognizedGesture)
}

public protocol RuleResolving: Sendable {
    func resolve(gesture: ComposedGesture, context: ProviderContextSnapshot) -> ActionDescriptor?
}
```

- [ ] **Step 1: 写候选开始和规则事实失败测试**

```swift
func testThreeTouchesEmitCandidateBeforeCompletion() {
    let events = recognizer.observe(frameWithThreeTouches)
    XCTAssertEqual(events.first, .candidateStarted(expectedCandidate))
}

func testLinkContextResolvesOpenAdjacentAction() {
    XCTAssertEqual(ruleEngine.resolve(gesture: .threeFingerTap, context: standardLinkContext).actionId, .browserLinkOpenAdjacent)
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter GestureSessionEventTests`

Expected: FAIL，`GestureSessionEvent` 未定义。

- [ ] **Step 3: 实现 session 事件和唯一 RuleEngine**

`GestureRecognizer.observe` 改为返回 `[GestureSessionEvent]`：首次恰好三指触摸发出 `candidateStarted`，结束时发出 classified/rejected。`GestureSessionCoordinator` 为候选生成 `gestureSessionId`，立即把 `guard_requested` 写入 Journal 并向已选 Provider 定向发送。

`RuleEngine` 内部实现 `BindingResolver`，根据标准 context facts 解析六项 V1 绑定：链接打开、左右边缘切 tab、中间双击关闭、左右轻扫切 tab。Chrome 专用 `ActionType` 不得出现在新规则输入或输出中。

- [ ] **Step 4: 实现并行 context/composition 与延迟预算**

原语分类后并行发起 context request 和组合仲裁。标准链接事实返回时立即剪枝 no-link 双击；边缘点按不等待双击窗口。要求：context response <=120ms；链接/边缘从原语分类到 action request <=150ms；中间双击窗口 <=300ms，第二击分类到请求 <=150ms。所有数值使用单调时钟记录。

- [ ] **Step 5: 运行任务级与完整 Swift 测试**

Run: `swift test --filter GestureSessionEventTests`

Expected: PASS。

Run: `swift test --filter RuleEngineTests`

Expected: PASS。

Run: `swift test`

Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/GestureKitCore/Gestures Sources/GestureKitCore/Rules apps/macos/GestureKitApp/Sources/GestureKitApp/GestureSessionCoordinator.swift Tests/GestureKitCoreTests Tests/GestureKitAppTests
git commit -m "feat: add provider-neutral gesture sessions and rules"
```

## Task 8: 实现 Chrome context、候选期 guard 和标准动作 adapter

**文件：**

- Create: `extensions/chrome/src/provider/chromeProvider.ts`
- Create: `extensions/chrome/src/content/interactionGuard.ts`
- Modify: `extensions/chrome/src/background/background.ts`
- Modify: `extensions/chrome/src/background/actionExecutor.ts`
- Modify: `extensions/chrome/src/background/chromeApi.ts`
- Modify: `extensions/chrome/src/content/linkResolver.ts`
- Modify: `extensions/chrome/src/content/pointerTracker.ts`
- Test: `extensions/chrome/tests/chromeProvider.test.ts`
- Test: `extensions/chrome/tests/interactionGuard.test.ts`
- Test: `extensions/chrome/tests/actionExecutor.test.ts`

**接口：**

```ts
export interface ChromeProvider {
  context(request: ContextRequest): Promise<ContextSnapshot>;
  execute(request: ActionRequest): Promise<ActionResult>;
  reconcile(operationId: string): Promise<OperationStatusResponse>;
}

export type ContextSnapshot = {
  contextId: string;
  expiresAt: number;
  targetKind: "standard_link" | "no_target" | "page_unavailable";
  targetRef?: string;
  pageIdentity: string;
};
```

- [ ] **Step 1: 写标准动作和 guard 前置失败测试**

```ts
it("rejects link action when guard is not armed", async () => {
  await expect(provider.execute(linkRequest({ guardState: "guard_unavailable" }))).resolves.toMatchObject({
    status: "guard_unavailable"
  });
});

it("executes browser.tab.activate_next without a link targetRef", async () => {
  await expect(provider.execute(nextTabRequest())).resolves.toMatchObject({ status: "success" });
});
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `npm test -- --run tests/chromeProvider.test.ts tests/interactionGuard.test.ts`

Expected: FAIL，缺少 `ChromeProvider`。

- [ ] **Step 3: 实现 context snapshot**

Provider 查询活动 tab，把 pointer hit-test 结果映射为 `standard_link`、`no_target` 或 `page_unavailable`。`targetRef` 只在 Provider 内保存为 session-bound opaque key；App 不接收 URL 或 DOM 标识。context 过期、tab 变化或 frame 不匹配必须返回 `context_expired`。

- [ ] **Step 4: 实现 guard 与标准动作映射**

`interactionGuard.ts` 处理 `gesturekit.guardArm`、`gesturekit.guardRelease`，只在 matching session/lease 中消费 DOM 事件。`actionExecutor.ts` 改为消费标准 action ID：

```ts
browser.link.open_adjacent -> chrome.tabs.create
browser.tab.activate_previous -> chrome.tabs.update
browser.tab.activate_next -> chrome.tabs.update
browser.tab.close_current -> chrome.tabs.remove
browser.history.back -> chrome.tabs.goBack
browser.history.forward -> chrome.tabs.goForward
browser.page.reload -> chrome.tabs.reload
```

`ChromeApi` 必须同步扩展以下可测试接口，避免 adapter 直接读取全局 `chrome`：

```ts
tabs: {
  goBack(tabId: number): Promise<void>;
  goForward(tabId: number): Promise<void>;
  reload(tabId?: number, reloadProperties?: chrome.tabs.ReloadProperties): Promise<void>;
}
```

链接动作先检查 `guard_armed` 和有效 `targetRef`，再调用 ledger accept；任何失败都不得触发 `chrome.tabs.create`。

- [ ] **Step 5: 运行完整 Chrome 测试和构建**

Run: `npm test -- --run`

Expected: PASS。

Run: `npm run build`

Expected: exit 0。

- [ ] **Step 6: 提交**

```bash
git add extensions/chrome/src/background extensions/chrome/src/content extensions/chrome/src/provider extensions/chrome/tests
git commit -m "feat: add chrome provider context and guarded actions"
```

## Task 9: 迁移配置主权并提供 Provider 配置快照

**文件：**

- Modify: `Sources/GestureKitCore/Settings/SettingsStore.swift`
- Create: `Sources/GestureKitCore/Settings/AppConfiguration.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/ConfigurationMigration.swift`
- Create: `extensions/chrome/src/settings/appConfigurationCache.ts`
- Modify: `extensions/chrome/src/background/settingsSync.ts`
- Modify: `extensions/chrome/src/background/background.ts`
- Test: `Tests/GestureKitCoreTests/AppConfigurationTests.swift`
- Test: `Tests/GestureKitAppTests/ConfigurationMigrationTests.swift`
- Test: `extensions/chrome/tests/appConfigurationCache.test.ts`

**接口：**

```swift
public struct AppConfiguration: Codable, Equatable, Sendable {
    public let storeEpoch: String
    public let schemaVersion: Int
    public let configurationVersion: Int64
    public let rules: [BindingRule]
    public let recognition: GestureRecognitionSettings
}
```

- [ ] **Step 1: 写一次性导入失败测试**

```swift
func testLegacySettingsImportRunsOnlyOnce() throws {
    try migration.importLegacy(legacyConfiguration)
    XCTAssertThrowsError(try migration.importLegacy(legacyConfiguration))
}
```

```ts
it("drops a cache with a different store epoch", () => {
  expect(applySnapshot(cacheWithEpoch("old"), snapshotWithEpoch("new"))).toEqual(snapshotWithEpoch("new"));
});
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter ConfigurationMigrationTests`

Expected: FAIL，缺少 `ConfigurationMigration`。

Run: `npm test -- --run tests/appConfigurationCache.test.ts`

Expected: FAIL，缺少 `applySnapshot`。

- [ ] **Step 3: 实现 App 配置事务和 legacy cutover**

App 首次 v2 连接时仅在没有 migration marker 的情况下请求 legacy snapshot。校验后在同一持久化事务写入 `AppConfiguration`、marker、epoch 和 version。之后 popup 禁止写用户配置；Provider 收到 epoch 不一致时删除缓存并等待权威 snapshot。

- [ ] **Step 4: 删除扩展反向设置同步**

移除 `chrome.storage.onChanged → settings_update` 主路径。保留 legacy adapter 只用于一次导入，导入成功后拒绝后续 legacy 写入。所有配置 ACK 只表达 Provider 缓存已应用，不能覆盖 App。

- [ ] **Step 5: 运行测试和提交**

Run: `swift test --filter AppConfigurationTests`

Expected: PASS。

Run: `npm test -- --run tests/appConfigurationCache.test.ts tests/settingsSync.test.ts`

Expected: PASS。

```bash
git add Sources/GestureKitCore/Settings apps/macos/GestureKitApp/Sources/GestureKitApp/ConfigurationMigration.swift extensions/chrome/src/settings extensions/chrome/src/background Tests extensions/chrome/tests
git commit -m "feat: make app configuration authoritative"
```

## Task 10: 实现 App 主窗口并收缩菜单栏与 popup

> **执行分期：** `Task 10A` 在 Task 5 后前置完成固定导航、页面骨架、中文状态模型、最小 popup 和菜单栏收缩，不接入未完成的 Provider、ledger、guard 或配置逻辑。`Task 10B` 在 Task 9 后将既有页面接入 `OperationJournal`、`HealthSupervisor`、`SettingsStore`、Provider 会话和配置快照，并完成真实构建产物验收。页面责任以 [`gesturekit-v2-ui-information-architecture.md`](../architecture/gesturekit-v2-ui-information-architecture.md) 为准。

**文件：**

- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/GestureKitWindowController.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/GestureKitDashboardView.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/OperationHistoryView.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/DiagnosticPresentationMapper.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/AppDelegate.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/MenuBarController.swift`
- Modify: `extensions/chrome/popup.html`
- Modify: `extensions/chrome/src/popup/popup.ts`
- Modify: `extensions/chrome/src/popup/popup.css`
- Test: `Tests/GestureKitAppTests/DiagnosticPresentationMapperTests.swift`
- Test: `extensions/chrome/tests/popup.test.ts`

**接口：**

实现型 AI 负责可测试的 view model、窗口路由、popup 数据源和文案映射；主审核代理负责真实构建产物的视觉与交互验收。验收至少覆盖首次启动、无权限、无 Provider、断连、结果不确定、历史分页、证据导出和窄窗口；界面只显示用户可理解的中文状态，不显示协议枚举、错误码或原始脱敏字段。

```swift
@MainActor
protocol GestureKitWindowPresenting {
    func showDashboard()
    func showOperation(operationID: String)
}

func presentDiagnostic(_ timeline: OperationTimeline) -> PresentedDiagnostic
```

- [ ] **Step 1: 写面向用户文案失败测试**

```swift
func testPresentationNeverLeaksProtocolEnum() {
    let model = presentDiagnostic(resultUnknownTimeline)
    XCTAssertFalse(model.title.contains("result_unknown"))
    XCTAssertEqual(model.title, "操作结果暂时无法确认")
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter DiagnosticPresentationMapperTests`

Expected: FAIL，缺少 `presentDiagnostic`。

- [ ] **Step 3: Task 10A 实现 AppKit + SwiftUI 主窗口框架**

`AppDelegate` 保持 accessory activation policy，新增 `NSWindowController` 承载 SwiftUI。侧边栏固定为概览、操作记录、手势预设、Provider、隐私与存储、高级设置。Task 10A 的历史记录、Provider 和配置页面只依赖只读 presentation data source 并展示准备中/不可用状态；Task 10B 才通过 `OperationJournal.query` 分页读取并接入 `EvidenceBundleExporter`。

`DiagnosticPresentationMapper` 把内部终态映射为中文，例如：

```swift
case .resultUnknown:
    return PresentedDiagnostic(title: "操作结果暂时无法确认", suggestion: "系统已保存完整诊断信息")
```

- [ ] **Step 4: Task 10A 收缩菜单栏和 popup**

菜单栏仅保留状态、暂停/恢复、打开 GestureKit、持续故障摘要和退出。popup 仅显示当前页面支持状态、连接、当前预设、当前页面最近结果和打开 App 入口；移除完整设置、推荐和历史诊断列表。

Task 10B 为既有页面补充真实状态、当前页面结果、历史分页和证据导出。Task 11 通过前，旧设置存储只可作为 Task 9 一次性迁移输入，popup 不得重新获得配置写入能力。

- [ ] **Step 5: 运行 UI 相关测试和构建**

Run: `swift test --filter GestureKitAppTests`

Expected: PASS。

Run: `npm test -- --run tests/popup.test.ts`

Expected: PASS。

Run: `swift build`

Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add apps/macos/GestureKitApp/Sources/GestureKitApp extensions/chrome/popup.html extensions/chrome/src/popup Tests/GestureKitAppTests extensions/chrome/tests/popup.test.ts
git commit -m "feat: add app control center and minimal popup"
```

## Task 11: 完成契约测试、端到端验收和 legacy 清理

**文件：**

- Modify: `scripts/dev/smoke-check.sh`
- Create: `scripts/dev/test-provider-protocol.sh`
- Modify: `docs/operations/gesturekit-v1-e2e-checklist.md`
- Modify: `docs/operations/gesturekit-v1-troubleshooting.md`
- Modify: `docs/research/trackpad-gesture-stability-matrix.md`
- Modify: `docs/product/gesturekit-v1-contract.md`
- Modify: `docs/product/gesturekit-v1-requirements.md`
- Test: `scripts/dev/test-provider-protocol.sh`

**验收矩阵：**

```text
1. 标准链接：30 次，guard_armed 先于 DOM，当前页 0 次原地跳转，0 次重复开页。
2. 边缘点按：左/右各 30 次，动作请求 <=150ms。
3. 中间双击：30 次，仲裁 <=300ms，第二击后请求 <=150ms。
4. 轻扫：左右各 30 次，成功或用户可理解拒绝均有完整 timeline。
5. 断连：1/10/60 秒，重连后 journal 能给出最终或 result_unknown，不重复执行。
6. 容量：10,000 tombstone + 24 小时 outbox 峰值，关键事件不丢，ACK 后回收。
7. 权限：clean-TCC 正式打包矩阵；page guard Spike 必须 passed。
8. InteractionShield：只在独立 Spike passed 后接入；失败保留 NoopShield。
```

- [ ] **Step 1: 写 smoke check 失败断言**

```bash
provider_result="$(./scripts/dev/test-provider-protocol.sh)"
test "$provider_result" = "provider_protocol_ok"
```

- [ ] **Step 2: 运行脚本，确认缺少 v2 检查**

Run: `scripts/dev/test-provider-protocol.sh`

Expected: FAIL，脚本或 Provider v2 握手尚未存在。

- [ ] **Step 3: 实现协议 smoke check 和 legacy 删除**

脚本必须启动 App、host 和 Chrome Provider probe，验证认证、capability snapshot、context request、action accepted/result、telemetry ACK 和重连对账。只在所有 v2 契约测试通过后删除 legacy `settings_update/settings_ack` 主流程、旧 popup 配置入口和旧诊断环形数组主存储职责。

- [ ] **Step 4: 执行完整验证**

Run: `swift test`

Expected: PASS。

Run: `npm test -- --run`

Expected: PASS。

Run: `npm run build`

Expected: exit 0。

Run: `scripts/dev/smoke-check.sh`

Expected: exit 0，包含 `provider_protocol_ok`。

- [ ] **Step 5: 归档人工证据并提交**

将 clean-TCC、page guard、手势稳定性和端到端矩阵结果写入研究/运维文档。未达到 page guard `passed` 时不得把三指点按链接标记为完成。

```bash
git add scripts/dev/smoke-check.sh scripts/dev/test-provider-protocol.sh docs/operations/gesturekit-v1-e2e-checklist.md docs/operations/gesturekit-v1-troubleshooting.md docs/research/trackpad-gesture-stability-matrix.md docs/product/gesturekit-v1-contract.md docs/product/gesturekit-v1-requirements.md extensions/chrome apps/macos Sources Tests native-host
git commit -m "feat: complete reliable gesture provider platform"
```

## 计划自审

- 覆盖性：Task 1-2A 覆盖实施前 IPC、page guard 和 InteractionShield 闸门；Task 3-6 覆盖 v2 协议、认证、Journal、outbox、幂等与对账；Task 7-9 覆盖手势、上下文、配置主权和 Chrome Provider；Task 10 覆盖 App/菜单栏/popup；Task 11 覆盖契约验收、清理和人工证据。
- 范围：第二个真实 Provider、三击运行时、DIY 编辑器和 `CGEventTapShield` 正式接入均未进入任务，仍是后续非阻塞增强。
- 一致性：所有任务使用 `gestureSessionId`、`operationId`、`eventId`、`ProviderEnvelope`、`ActionDescriptor`、`OperationJournal` 和 `Provider Protocol v2` 的同一命名。
- 验证：每个实现任务包含失败测试、通过测试和独立提交；Spike 原始证据和 UI 最终验收由主审核代理确认；最终任务运行 Swift、Chrome、构建、smoke 和人工验收。
