# GestureKit V2.4-A 链接动作可靠性闭环实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 为三指点按链接建立真实 Chrome 质量门，验证 guard、相邻新标签、lease 释放、不可用与结果未知路径，同时将不依赖图形会话的检查接入 CI。

**架构：** 只在 E2E 临时 extension 副本和显式 `--e2e-control-token` 的 App 进程中启用测试控制平面。Node runner 创建 loopback fixture、临时 Chrome profile 和临时 extension 副本，以 Chrome DevTools Protocol 观察 tab 状态；手势测试命令仍进入 App 的 `GestureSessionCoordinator` 和既有 Provider v2 链路，不能直接调用 `chrome.tabs`。

**技术栈：** Swift 6.2、AppKit、Chrome MV3、TypeScript、Vitest、Node 23 内置 `WebSocket`、Chrome DevTools Protocol、GitHub Actions macOS runner。

## 全局约束

- 本计划以 `docs/product/gesturekit-v2.4-reliability-contract.md` 为范围与验收依据；不新增手势、Provider、动作或公开 Provider Protocol 字段。
- E2E control token 由 runner 生成，至少 256-bit，仅存在临时 profile、临时 extension 副本和子进程环境；日志、证据与失败输出不得打印 token、完整 URL query/hash、Cookie、页面正文或原始 `targetRef`。
- 测试控制入口默认不可用；App 没有 `--e2e-control-token`、extension 没有编译期 `GESTUREKIT_E2E_TOKEN`、来源不是 loopback fixture 或 token 不匹配时必须拒绝，且不创建 guard/session。
- 所有 E2E 操作使用唯一 `gestureSessionId` 和 `operationId`，并从既有 `OperationJournal`、Provider ledger 与 telemetry 读取终态；禁止直接伪造成功结果。
- 测试触发不得依赖真实触控板帧，真实硬件、权限和系统手势冲突继续按人工清单验收。
- 每项实现遵循 TDD：先运行失败测试，再最小实现，再运行任务级和相关全量测试。
- 项目文档中文优先；代码、命令、协议字段和路径保持原文。

---

## 文件结构

- `apps/macos/GestureKitApp/Sources/GestureKitApp/E2EControlServer.swift`：只在显式 token 下监听 loopback 控制请求，验证 token/一次性 ID，转发测试命令。
- `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`：创建 E2E server，并用既有 `GestureSessionCoordinator` 发起测试候选；进程退出时关闭 server 与待处理资源。
- `apps/macos/GestureKitApp/Sources/GestureKitApp/main.swift`：解析 `--e2e-control-token`，不带参数时保持当前启动行为。
- `Tests/GestureKitAppTests/E2EControlServerTests.swift`：验证授权、一次性 ID、关闭和 fail-closed 语义。
- `extensions/chrome/scripts/build.mjs`：支持输出到临时目录和编译期 E2E token，不改变默认构建输出。
- `extensions/chrome/src/e2e/controlledPageBridge.ts`：仅在 loopback fixture 与匹配 token 下将测试页命令转发给 background，并回传脱敏状态。
- `extensions/chrome/src/background/e2eControl.ts`：调用既有 Native Messaging/Provider 链路，收集 guard trace 与操作终态；非 E2E build 导出拒绝实现。
- `extensions/chrome/src/background/background.ts`：按编译期开关注册 E2E bridge，不改变普通 message 分发。
- `extensions/chrome/tests/e2eControl.test.ts`：验证 token、origin、ID 和故障场景的拒绝/转发行为。
- `scripts/e2e/run-link-reliability.mjs`：创建临时 fixture/profile/extension，启动 App 与 Chrome，通过 CDP 执行四类验证，输出脱敏 JSON 摘要。
- `scripts/e2e/fixtures/link-reliability.html`：本地固定页面；只包含固定 `https://example.test/e2e-target` 链接和结构化测试事件。
- `scripts/e2e/test-link-reliability.mjs`：对 runner 的纯 Node 单元测试，覆盖 CDP tab 断言、摘要脱敏与失败阶段。
- `.github/workflows/quality-gate.yml`：运行非图形质量门；真实 Chrome 验收只由 macOS 开发机/专用 runner job 执行。
- `scripts/dev/test-link-reliability.sh`：封装 runner 的预检、参数、退出码与稳定输出。
- `docs/operations/e2e-checklist.md`、`docs/operations/troubleshooting.md`：增加 V2.4-A 执行与故障定位步骤。

## Task 1：定义测试控制边界与 App 一次性命令

**Files:**

- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/E2EControlServer.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/main.swift`
- Create: `Tests/GestureKitAppTests/E2EControlServerTests.swift`

**Interfaces:**

```swift
struct E2ELinkOperationCommand: Codable, Equatable {
    let token: String
    let gestureSessionId: String
    let operationId: String
    let scenario: E2ELinkScenario
}

enum E2ELinkScenario: String, Codable { case success, leaseExpiry, providerUnavailable, resultUnknown }

enum E2EControlResult: Codable, Equatable {
    case accepted(gestureSessionId: String, operationId: String)
    case rejected(reason: String)
}
```

- [ ] **Step 1: 写 App 控制服务失败测试**

```swift
func testRejectsCommandWhenTokenDoesNotMatch() async throws {
    let server = E2EControlServer(token: "valid-token") { _ in .accepted(gestureSessionId: "g", operationId: "o") }
    let result = await server.handle(.init(token: "wrong", gestureSessionId: "g-1", operationId: "o-1", scenario: .success))
    XCTAssertEqual(result, .rejected(reason: "e2e_control_unauthorized"))
}

func testRejectsReusedOperationIDWithoutCallingRuntime() async throws {
    var calls = 0
    let server = E2EControlServer(token: "valid-token") { command in calls += 1; return .accepted(gestureSessionId: command.gestureSessionId, operationId: command.operationId) }
    _ = await server.handle(.init(token: "valid-token", gestureSessionId: "g-1", operationId: "o-1", scenario: .success))
    let repeated = await server.handle(.init(token: "valid-token", gestureSessionId: "g-2", operationId: "o-1", scenario: .success))
    XCTAssertEqual(repeated, .rejected(reason: "e2e_operation_reused"))
    XCTAssertEqual(calls, 1)
}
```

- [ ] **Step 2: 确认测试先失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter E2EControlServerTests`

Expected: FAIL，提示 `E2EControlServer` 或 `E2ELinkOperationCommand` 未定义。

- [ ] **Step 3: 实现 fail-closed 控制服务**

```swift
actor E2EControlServer {
    private let token: String
    private var consumedOperationIDs = Set<String>()
    private let dispatch: @Sendable (E2ELinkOperationCommand) async -> E2EControlResult

    func handle(_ command: E2ELinkOperationCommand) async -> E2EControlResult {
        guard command.token == token else { return .rejected(reason: "e2e_control_unauthorized") }
        guard !consumedOperationIDs.contains(command.operationId) else { return .rejected(reason: "e2e_operation_reused") }
        consumedOperationIDs.insert(command.operationId)
        return await dispatch(command)
    }
}
```

`GestureKitRuntime` 仅在启动参数包含非空 token 时创建该服务；将 `.success` 转为现有 candidate/classification/context/action 路径，`.leaseExpiry` 不发 action，`.providerUnavailable` 在 provider 路由前生成现有不可用终态，`.resultUnknown` 在 `action_accepted` 后丢弃最终回执并由既有 deadline recovery 收敛。所有退出路径调用既有 guard release 与 Journal 终态写入。

- [ ] **Step 4: 验证 App 定向测试**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter E2EControlServerTests --filter GestureSessionCoordinatorTests --filter RuntimeLifecycleTests`

Expected: 所有选中测试通过；每个拒绝、lease 与 result unknown 测试断言无遗留 guard/session。

- [ ] **Step 5: 提交**

```bash
git add apps/macos/GestureKitApp/Sources/GestureKitApp/E2EControlServer.swift apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift apps/macos/GestureKitApp/Sources/GestureKitApp/main.swift Tests/GestureKitAppTests/E2EControlServerTests.swift
git commit -m "test(runtime): add gated e2e link control"
```

## Task 2：构建临时 extension 与受控页面桥接

**Files:**

- Modify: `extensions/chrome/scripts/build.mjs`
- Create: `extensions/chrome/src/e2e/controlledPageBridge.ts`
- Create: `extensions/chrome/src/background/e2eControl.ts`
- Modify: `extensions/chrome/src/background/background.ts`
- Create: `extensions/chrome/tests/e2eControl.test.ts`

**Interfaces:**

```ts
export type E2EPageCommand = {
  token: string;
  gestureSessionId: string;
  operationId: string;
  scenario: "success" | "leaseExpiry" | "providerUnavailable" | "resultUnknown";
};

export function createE2EControl(input: {
  token: string | null;
  allowedOrigin: string | null;
  dispatch: (command: E2EPageCommand) => Promise<{ status: string }>;
}): { handle(origin: string, command: E2EPageCommand): Promise<{ status: string }> };
```

- [ ] **Step 1: 写 extension 失败测试**

```ts
it("rejects a production build and does not dispatch", async () => {
  const dispatch = vi.fn();
  const control = createE2EControl({ token: null, allowedOrigin: null, dispatch });
  await expect(control.handle("http://127.0.0.1:4567", fixtureCommand())).resolves.toEqual({ status: "e2e_unavailable" });
  expect(dispatch).not.toHaveBeenCalled();
});

it("rejects an origin mismatch before forwarding the command", async () => {
  const dispatch = vi.fn();
  const control = createE2EControl({ token: "token", allowedOrigin: "http://127.0.0.1:4567", dispatch });
  await expect(control.handle("https://example.test", fixtureCommand())).resolves.toEqual({ status: "e2e_origin_rejected" });
  expect(dispatch).not.toHaveBeenCalled();
});
```

- [ ] **Step 2: 确认测试先失败**

Run: `cd extensions/chrome && npm test -- --run tests/e2eControl.test.ts`

Expected: FAIL，提示 `createE2EControl` 未定义。

- [ ] **Step 3: 实现临时构建和页面桥接**

`build.mjs` 新增 `--outdir <directory>` 与 `--e2e-token <token>`：默认不变；仅在同时提供 token 和 outdir 时为 background/content bundle 注入 `__GESTUREKIT_E2E_TOKEN__`。runner 把 `manifest.json`、`popup.html`、`smoke.html` 与构建输出复制到临时目录，Chrome 从该目录加载，仓库 `dist/` 不接受 E2E token。

`controlledPageBridge.ts` 仅接受 `window.postMessage` 的 `gesturekit.e2eLinkOperation`，使用 `location.origin`、编译期 token 和完整 command 字段校验；通过 `chrome.runtime.sendMessage` 转发，回传的只有 `status`、session/operation ID 与阶段枚举。普通 build 的 `token === null` 时不注册 listener。

- [ ] **Step 4: 验证 extension 定向与完整测试**

Run: `cd extensions/chrome && npm test -- --run tests/e2eControl.test.ts tests/interactionGuard.test.ts tests/v2Dispatcher.test.ts && npm test && npm run build`

Expected: 定向测试和全部 Vitest 通过；默认 `npm run build` 产物不包含 E2E token 或 `gesturekit.e2eLinkOperation` listener。

- [ ] **Step 5: 提交**

```bash
git add extensions/chrome/scripts/build.mjs extensions/chrome/src/e2e/controlledPageBridge.ts extensions/chrome/src/background/e2eControl.ts extensions/chrome/src/background/background.ts extensions/chrome/tests/e2eControl.test.ts
git commit -m "test(extension): add gated link reliability bridge"
```

## Task 3：实现真实 Chrome runner 与四类断言

**Files:**

- Create: `scripts/e2e/run-link-reliability.mjs`
- Create: `scripts/e2e/test-link-reliability.mjs`
- Create: `scripts/e2e/fixtures/link-reliability.html`
- Create: `scripts/dev/test-link-reliability.sh`

**Interfaces:**

```ts
export type LinkReliabilitySummary = {
  scenario: "success" | "leaseExpiry" | "providerUnavailable" | "resultUnknown";
  gestureSessionId: string;
  operationId: string;
  terminalStatus: string;
  failureStage: string | null;
  durationMs: number;
};

export function redactSummary(summary: LinkReliabilitySummary): LinkReliabilitySummary;
export function assertAdjacentActivatedTab(tabs: Array<{ id: string; url: string; active: boolean }>, sourceTabId: string): void;
```

- [ ] **Step 1: 写 runner 失败测试**

```ts
it("accepts only an adjacent active fixed-target tab", () => {
  expect(() => assertAdjacentActivatedTab([
    { id: "source", url: "http://127.0.0.1:4567/link-reliability.html", active: false },
    { id: "target", url: "https://example.test/e2e-target", active: true }
  ], "source")).not.toThrow();
});

it("redacts query and token-like values from failure summaries", () => {
  expect(JSON.stringify(redactSummary({ scenario: "success", gestureSessionId: "g", operationId: "o", terminalStatus: "failed?token=raw", failureStage: "guard", durationMs: 1 }))).not.toContain("token=raw");
});
```

- [ ] **Step 2: 确认测试先失败**

Run: `node --test scripts/e2e/test-link-reliability.mjs`

Expected: FAIL，提示 runner export 不存在。

- [ ] **Step 3: 实现临时环境与 CDP 驱动**

runner 使用 `mkdtemp` 创建 profile、extension 副本和 fixture server；以 `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --user-data-dir=<temporary> --load-extension=<temporary-extension> --remote-debugging-port=0` 启动，读取 profile 的 `DevToolsActivePort` 并用 Node 内置 `WebSocket` 连接 CDP。它必须：

1. 启动带 token 的 `GestureKitApp`，并在完成或失败时终止子进程、关闭 socket/http server、删除临时目录。
2. 打开 `http://127.0.0.1:<port>/link-reliability.html`，先移动指针到固定链接，再由页面 bridge 发出测试 command。
3. 对 success 断言 guard trace 的 `armed` 在 `click_observed` 前、来源 tab URL 不变、右侧目标 tab 激活。
4. 对 leaseExpiry 断言 500ms lease 后来源 tab 导航、下一次 command 的 guard/session 不复用。
5. 对 providerUnavailable 先关闭 App，再断言无新 tab、页面 click 未被持久阻止、摘要为结构化不可用原因。
6. 对 resultUnknown 在 action accepted 后丢弃最终回执，轮询 Journal recovery，断言 `result_unknown`、无自动重放且下一次 success 可执行。

runner 仅打印 `LinkReliabilitySummary` 的 JSON 行；退出码 `0` 表示四个场景均断言通过，`1` 表示场景失败，`2` 表示 Chrome/App/extension 环境预检失败并输出下一步。

- [ ] **Step 4: 验证 Node 测试和真实入口预检**

Run: `node --test scripts/e2e/test-link-reliability.mjs && zsh scripts/dev/test-link-reliability.sh --dry-run`

Expected: Node 测试通过；dry-run 输出 Chrome、App、临时 profile、extension、副本和 fixture 的命令，不启动 GUI 或写入用户 profile。

- [ ] **Step 5: 执行专用 macOS 真实验收**

Run: `zsh scripts/dev/test-link-reliability.sh`

Expected: 输出四条脱敏 JSON 摘要，全部 `terminalStatus` 符合契约；Chrome 仅使用临时 profile，命令结束后无残留 App/Chrome 子进程或临时目录。

- [ ] **Step 6: 提交**

```bash
git add scripts/e2e scripts/dev/test-link-reliability.sh
git commit -m "test(e2e): verify real Chrome link reliability"
```

## Task 4：接入 CI、文档与发布质量门

**Files:**

- Create: `.github/workflows/quality-gate.yml`
- Modify: `docs/operations/e2e-checklist.md`
- Modify: `docs/operations/troubleshooting.md`
- Modify: `README.md`

**Interfaces:**

CI workflow 的 job 名称固定为 `swift`, `extension`, `scripts`；每个 job 使用 `macos-15`，失败日志只打印命令、阶段、退出码和脱敏摘要。真实 Chrome runner 不在通用 CI 自动执行，而作为 `workflow_dispatch` 输入 `run_real_chrome=true` 的专用 job，默认 `false`。

- [ ] **Step 1: 写 workflow 结构测试**

```bash
rg -q 'name: swift' .github/workflows/quality-gate.yml
rg -q 'name: extension' .github/workflows/quality-gate.yml
rg -q 'name: scripts' .github/workflows/quality-gate.yml
rg -q 'run_real_chrome' .github/workflows/quality-gate.yml
```

- [ ] **Step 2: 确认测试先失败**

Run: `zsh -c 'rg -q "name: swift" .github/workflows/quality-gate.yml'`

Expected: FAIL，因为 workflow 尚未创建。

- [ ] **Step 3: 实现质量门与运维说明**

`swift` job 运行 `swift test` 与 `swift build`；`extension` job 在 `extensions/chrome` 运行 `npm ci`、`npm test`、`npm run build`；`scripts` job 运行 manifest、native host、install-local dry-run、smoke dry-run 与 provider protocol 测试。`workflow_dispatch` 的真实 Chrome job 只在显式输入为 true 时调用 `zsh scripts/dev/test-link-reliability.sh`，并将脱敏 JSON 摘要作为 artifact；不得上传 profile、日志原文、token 或凭据。

文档必须明确通用 CI 不等于真实触控板验证，记录本地前置条件、四种终态、预检失败下一步和临时 profile 清理语义。

- [ ] **Step 4: 验证全部质量门**

Run:

```bash
git diff --check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
cd extensions/chrome && npm test && npm run build
cd ../..
zsh scripts/dev/test-render-native-host-manifest.sh
zsh scripts/dev/test-install-native-host.sh
zsh scripts/dev/test-install-local.sh
zsh scripts/dev/test-smoke-check.sh
zsh scripts/dev/test-provider-protocol.sh
node --test scripts/e2e/test-link-reliability.mjs
zsh scripts/dev/test-link-reliability.sh --dry-run
```

Expected: 所有自动化命令退出码为 `0`；真实 Chrome 命令保留为独立 macOS 验收记录，不以 dry-run 代替。

- [ ] **Step 5: 提交**

```bash
git add .github/workflows/quality-gate.yml docs/operations/e2e-checklist.md docs/operations/troubleshooting.md README.md
git commit -m "ci: add v2.4 link reliability quality gate"
```

## 计划自检

- 契约中的临时 profile、临时 extension、token、唯一 session/operation、四种验收路径、脱敏摘要和 CI 边界分别由 Task 1–4 覆盖。
- 生产入口保持默认关闭由 Task 1 与 Task 2 的拒绝测试覆盖；无 token、错误 token、错误 origin、ID 重复都不会派发操作。
- 所有跨组件路径均复用现有 `GestureSessionCoordinator`、Provider v2、OperationJournal、ledger/outbox；没有新增公开协议消息。
- 本计划未包含 `TODO`、`TBD` 或未指定的实现/验证命令。
