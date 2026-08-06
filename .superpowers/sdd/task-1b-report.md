# Task 1b 实施报告

## 状态: DONE

## Commit: 待提交

## 测试摘要

全量 179 测试通过（167 已有 + 12 新增），零失败。

### 新增测试

| 测试套件 | 测试数 | 说明 |
|----------|--------|------|
| E2EControlServerTests (网络层) | 5 | start/port/valid command, wrong token, reused operationId, invalid JSON, oversized input |
| E2ERuntimeScenarioTests | 7 | success, success+action after context, leaseExpiry, providerUnavailable, resultUnknown, token gating (无 token / 有 token) |

### 已有测试（无回归）

- E2EControlServerTests 原有 2 个校验测试：通过
- GestureSessionCoordinatorTests 7 个：通过
- RuntimeLifecycleTests 11 个：通过
- 全部 GestureKitCoreTests + GestureKitAppTests：通过

## 实施内容

### 1. `E2EControlServer.swift` — 补齐网络层
- 添加 `import Network`，`NWListener` 绑定 `127.0.0.1` 系统分配端口
- `start()`: 启动监听，ready 后输出 `gesturekit_e2e_control_port=<decimal>`
- `stop()`: 取消监听
- `port`: 返回系统分配端口（测试用）
- `handleIncomingConnection`: 逐连接验证 loopback 对端、16KB 上限、JSON 解码，全部失败时返回结构化拒绝
- 校验层 (token + operationId 幂等) 复用已有 `handle()` 不变

### 2. `Runtime.swift` — E2E 控制集成
- `init` 新增 `e2eControlToken: String? = nil` 参数
- token 非空时创建 `E2EControlServer` 并异步启动
- 四场景 dispatch：
  - `.success`: 构造 `GestureCandidate` + `RecognizedGesture(.threeFingerTap)` 喂入 `gestureCoordinator`，走完整 guard→context→action 链路
  - `.leaseExpiry`: `candidateStarted` arm guard → `primitiveRejected` release guard，不产生 action
  - `.providerUnavailable`: 分类后 context 请求因无 provider 而失败，写入 Journal 终态 (`resultUnknown`/`guardExpired`)
  - `.resultUnknown`: 走完整链路，action 发出后由既有 deadline recovery 收敛
- 所有退出路径调用 guard release 与 Journal 终态写入
- 测试入口: `e2eControlPort` (async), `dispatchE2EOperationForTesting`

### 3. `main.swift` — 启动参数解析
- 解析 `--e2e-control-token <token>`，无参数时返回 nil（默认不可用）
- 传给 `AppDelegate(e2eControlToken:)`

### 4. `AppDelegate.swift` — Token 传递
- 新增 `init(e2eControlToken:)`，传递给 `GestureKitRuntime` init

### 5. 测试文件
- `E2EControlServerTests.swift`: 新增 5 个网络层测试 + `send`/`waitForPort` 辅助
- `E2ERuntimeScenarioTests.swift` (新建): 7 个场景分发测试，参考 `RuntimeLifecycleTests` 模式

## 执行步骤

### Step 1: 写网络层失败测试
- `E2EControlServerTests.swift` 新增 5 个网络测试，引用尚未存在的 `start()`/`port`/`stop()`

### Step 2: 确认编译失败
```
error: value of type 'E2EControlServer' has no member 'start'
error: value of type 'E2EControlServer' has no member 'stop'
error: value of type 'E2EControlServer' has no member 'port'
```

### Step 3: 实现 E2EControlServer 网络层 + Runtime 集成
- E2EControlServer: NWListener + 连接处理 + 各类拒绝逻辑
- Runtime: e2eControlToken 参数 + 四场景 dispatch + 终态写入
- AppDelegate + main.swift: token 传递

### Step 4: 验证全量测试
```
swift test → 179 tests, 0 failures
swift test --filter "E2EControlServerTests|E2ERuntimeScenarioTests|GestureSessionCoordinatorTests|RuntimeLifecycleTests" → 32 tests, 0 failures
```

### Step 5: 提交
```
git add apps/macos/GestureKitApp/Sources/GestureKitApp/E2EControlServer.swift
apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift
apps/macos/GestureKitApp/Sources/GestureKitApp/main.swift
apps/macos/GestureKitApp/Sources/GestureKitApp/AppDelegate.swift
Tests/GestureKitAppTests/E2EControlServerTests.swift
Tests/GestureKitAppTests/E2ERuntimeScenarioTests.swift
git commit -m "test(runtime): wire gated e2e control into runtime"
```

## 自审问题

1. **OK** — `dispatchE2EOperation` 从 E2EControlServer (独立 actor) 的 dispatch 闭包中通过 `await self.dispatchE2EOperation(command)` 调用，`GestureKitRuntime` 的 `@MainActor` 隔离保证状态访问安全。

2. **OK** — 无 `--e2e-control-token` 时 App 行为完全不变：`e2eServer` 为 nil，不建 server、不开 port、不注册 NWListener。

3. **OK** — token 和端口不泄露到日志。`print("gesturekit_e2e_control_port=\(port)")` 仅输出端口号。token 从不打印，仅用作内部比对。

4. **OK** — 未新增手势、Provider、动作或 Provider Protocol 字段。

5. **注意** — `writeProviderUnavailableTerminalState` 写入终态事件时使用 `ActionResultOutcome.resultUnknown` + `ActionResultReason.guardExpired`。若后续协议定义了更精确的 "provider unavailable" 原因码，应更新此处映射。

## Concerns

无。

---

## Task 1b Review Fix: providerUnavailable guard release 缺口

**日期**: 2026-08-01
**状态**: DONE

### 问题描述

review 发现 `Runtime.swift` 的 `dispatchE2EOperationSync` 中，`.providerUnavailable` 场景调用
`gestureCoordinator.handle(.candidateStarted(...))` + `.primitiveClassified(...)` 后，因无活跃 provider，
`handleCoordinatorContextRequest` early return，coordinator 的 session 留在 `activeSessions` 里成为孤儿——
**guard release 从未触发**。违反计划要求"所有退出路径调用既有 guard release 与 Journal 终态写入"和
AGENTS.md §5（资源创建事件必须在所有退出路径恰好对应一次成功/拒绝终态）。

### 修复内容

#### 1. `Runtime.swift` — `.providerUnavailable` 分支改用 `primitiveRejected`

将原来的 `candidateStarted` + `primitiveClassified` 改为 `candidateStarted` + `primitiveRejected`，
与 `.leaseExpiry` 分支保持一致模式：

- `candidateStarted` → arm guard（coordinator 创建 session，触发 guardRouter → handleCandidateGuardArm）
- `primitiveRejected` → coordinator 自动调用 guardReleaseRouter → `handleCandidateGuardRelease` + 清理 `activeSessions`
- 同时清理 `pendingCoordinatorGestureInfo` 和 `lastCandidateSessionID`
- `writeProviderUnavailableTerminalState` 不变，仍写入 Journal 终态

**效果**: coordinator session 不再泄漏；guard release 在所有退出路径触发。

#### 2. `E2ERuntimeScenarioTests.swift` — 增强测试断言

`testProviderUnavailableScenarioGeneratesTerminalState` 改为使用 `makeAuthenticatedRuntime()`（带 outbound recorder）：

- 新增断言 `interactionGuardArm` 已发送（arm guard）
- 新增断言 `interactionGuardRelease` 已发送（guard release 通过 guardReleaseRouter → handleCandidateGuardRelease 触发）
- 新增断言无 `actionRequest` 和 `contextRequest`（此场景不走 classification）
- 保留 Journal 终态事件断言

`makeAuthenticatedRuntime` helper 返回值增加 `RuntimeRecordingJournal`（第5个元素），所有调用点已更新。

#### 3. Minor 2: `E2EControlServer.swift` — `.failed` case 日志

```swift
case .failed(let error):
    print("gesturekit_e2e_control_listener_failed error=\(error)")
```

#### 4. Minor 3: `Runtime.swift` — `Task { try? await server.start() }` 错误处理

```swift
Task {
    do {
        try await server.start()
    } catch {
        logger.error("e2e_control_server_start_failed error=\"\(error)\"")
    }
}
```

### 测试验证

```
# E2ERuntimeScenarioTests（7 测试，全部通过）
swift test --filter E2ERuntimeScenarioTests
  → 7 tests, 0 failures

# 全量测试
swift test
  → 179 tests, 0 failures
```

### Commit

```
fix(runtime): release guard on provider-unavailable e2e path
```

修改文件：
- `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- `apps/macos/GestureKitApp/Sources/GestureKitApp/E2EControlServer.swift`
- `Tests/GestureKitAppTests/E2ERuntimeScenarioTests.swift`
