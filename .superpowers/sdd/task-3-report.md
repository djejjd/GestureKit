# Task 3 Report: 实现真实 Chrome runner 与四类断言

**状态**: DONE_WITH_CONCERNS
**Commit**: `e5ca4d0`
**Branch**: `feat/v2.4-link-reliability` (worktree)

## 测试摘要

`node --test scripts/e2e/test-link-reliability.mjs` — 6/6 pass (assertAdjacentActivatedTab 4 tests, redactSummary 2 tests)
`zsh scripts/dev/test-link-reliability.sh --dry-run` — exit 0，输出完整环境预检命令，未启动 GUI 或写入用户 profile

## 每步结果

### Step 1: 写 runner 失败测试
- 创建 `scripts/e2e/test-link-reliability.mjs`，含 `assertAdjacentActivatedTab` 4 个测试和 `redactSummary` 2 个测试
- `assertAdjacentActivatedTab`: 接受相邻 active tab / 拒绝非相邻 / 拒绝无 active / 拒绝 source 为唯一 active
- `redactSummary`: 脱敏 query/token/secret / 保留非敏感字段

### Step 2: 确认测试先失败
- `node --test scripts/e2e/test-link-reliability.mjs` → FAIL
- 错误: `ERR_MODULE_NOT_FOUND: Cannot find module .../run-link-reliability.mjs`
- 符合预期：runner export 不存在

### Step 3: 实现临时环境与 CDP 驱动
创建 4 个文件：

1. **`scripts/e2e/run-link-reliability.mjs`** (557 行)
   - 导出: `assertAdjacentActivatedTab(tabs, sourceTabId)` — 验证相邻 active tab
   - 导出: `redactSummary(summary)` — 脱敏 4 类 pattern（token=, secret=, key=, credential=）
   - 导出: `runLinkReliabilityScenarios(config)` — 主 async 函数，编排完整测试环境
   - 内置: `FixtureHttpServer` (固定端口 4567)、`CDPClient` (Node 内置 WebSocket)、`ScenarioRunner` (四场景执行)
   - CLI: `node run-link-reliability.mjs --dry-run` 打印环境配置
   - Cleanup: 所有路径（成功/失败/异常）均终止子进程、关闭 server、删除临时目录

2. **`scripts/e2e/fixtures/link-reliability.html`** + **`link-reliability-target.html`**
   - fixture 页面含 `#e2e-link` 链接（target="_blank"）
   - 暴露 `window.__gesturekitE2E.sendCommand()` 供 CDP Runtime.evaluate 调用
   - 监听 `window.postMessage` 的 `gesturekit.e2eLinkResult` 显示结果

3. **`scripts/dev/test-link-reliability.sh`**
   - `--dry-run` 模式: 运行 Node 测试 + 打印环境命令（不启动 GUI/Chrome/App）
   - 真实模式: 预检 Chrome/Xcode/Node 可用性后委托给 runner
   - 退出码对齐 runner: 0=四场景全过, 1=场景失败, 2=环境预检失败

四场景实现：
- **success**: 发 E2E 命令 → guard arm → CDP 点击链接 → 断言 target tab 相邻 active + source URL 不变
- **leaseExpiry**: 发 leaseExpiry 命令 → 等待 → 导航 source tab → 验证下次 success 为新 session 不复用旧 guard
- **providerUnavailable**: 发 providerUnavailable 命令 → kill App → CDP 点击链接 → 验证 click 不被持久阻止
- **resultUnknown**: 发 resultUnknown 命令 → 不回复 context → 等待 deadline 过期 → 验证下次 success 可执行

### Step 4: 验证 Node 测试和真实入口预检
- `node --test scripts/e2e/test-link-reliability.mjs` → **6/6 pass, exit 0**
- `zsh scripts/dev/test-link-reliability.sh --dry-run` → **exit 0**
- dry-run 输出包含: 环境变量、临时目录、token（占位符）、extension 构建命令、GestireKitHost 构建、native messaging manifest、fixture server 配置、GestureKitApp 启动命令、Chrome 启动命令、四场景执行顺序、cleanup 步骤

### Step 5: 真实 Chrome 真实验收
未执行（属于人工验收关口）。

### Step 6: 提交
```
git add scripts/e2e scripts/dev/test-link-reliability.sh
git commit -m "test(e2e): verify real Chrome link reliability"
```
Commit: `e5ca4d0`

## 自审问题

### Concern 1: 真实 Chrome 模式下 Provider 认证链路未端到端验证
受限于 Step 5 不执行，runner 的 `runLinkReliabilityScenarios` 在真实模式下的行为未经过实际 Chrome + App + Extension 三联体验证。具体风险：
- `ProviderCredentialStore` 使用 `~/Library/Application Support/GestureKit/providers/` 固定路径；runner 不隔离此目录
- `GestureKitHost` 连接 `127.0.0.1:17653`（硬编码）；如 App IPC 端口冲突可能导致连接失败
- Extension background 的 `e2eControl.dispatch` 当前返回 `{ status: "e2e_dispatched" }`（stub），不实际触发 link 操作管线；runner 依赖 App E2E 控制端口（TCP）而非 extension bridge 来触发手势，这可能与预期流程有偏差

### Concern 2: runner 中 `providerUnavailable` 场景的 App 进程管理
`#runProviderUnavailable()` 会 kill App 进程，但后续 `#runResultUnknown()` 需要 App 在运行。当前代码未实现 App 重启逻辑——`providerUnavailable` 后 `runAll()` 直接调用 `#runResultUnknown()`。真实模式下 Step 5 验收时需注意此顺序问题。

### Concern 3: `assertAdjacentActivatedTab` 的 tab 模型
函数使用 `tab.id`（对应 CDP `targetId`）而非 Chrome Tab ID。CDP 的 `Target.getTargets` 返回的 `targetId` 与 `chrome.tabs` 的 `tab.id` 是不同的命名空间。真实模式下可能需要通过 `Target.attachToTarget` + `Browser.getWindowForTarget` 建立 window/tab 的映射关系来正确判断相邻性。

### Concern 4: 日志/错误输出的 token 安全
Runner 在异常路径中 `console.error(\`[runner] 环境预检失败: ${err.message}\`)` 可能打印包含 token 的错误信息。虽然 token 是临时生成的（进程结束后无效），但严格遵循"日志不得打印 token"约束时应确保 `err.message` 不含 token。当前 token 仅通过子进程 env 和 TCP payload 传递，未出现在异常路径的 error message 中，风险较低。

---

## Review 修复 (2026-08-01): 3 个确定性缺陷

**Commit**: `(见下方)`
**Branch**: `feat/v2.4-link-reliability`

### C1 — `#getTabs()` active 判定修复

**根因**: `active: t.targetId === this.#pageTargetId`，`#pageTargetId` 在 `runAll()` 初始化时设置一次不再更新。点击 `target="_blank"` 新开 tab 后，source 页被错误标成 active、新 tab 被错误标成非 active。

**修复**:
- 扩展 `CDPClient.send(method, params, sessionId)` 接受可选的 `sessionId` 参数，支持将命令路由到特定 target session
- 重写 `#getTabs()`: 对每个 page target 调用 `Target.attachToTarget` + `Runtime.enable` + `Runtime.evaluate("document.hasFocus()")`，获取 Chrome 真实 active 状态

### C2 — `providerUnavailable` 后 `resultUnknown` App 进程缺失

**根因**: `#runProviderUnavailable()` 执行 `#appProcess.kill("SIGTERM")`，之后 `runAll()` 调 `#runResultUnknown()` 通过 TCP 向已死 App 发命令，5s 超时，exit 2。

**修复**:
- `ScenarioRunner` 构造器新增 `processes`（数组引用）、`appPath`、`buildEnv` 三个参数
- 新增 `#restartApp()` 方法: spawn 新 GestureKitApp（同 token），读取 `gesturekit_e2e_control_port`，更新 `#controlPort` 和 `#appProcess`，将新进程 push 到 `processes` 数组以进入 cleanup
- `runAll()` 在 `#runProviderUnavailable()` 之后、`#runResultUnknown()` 之前调用 `await this.#restartApp()`

### I3 — `assertAdjacentActivatedTab` 数组下标不可靠

**根因**: `Target.getTargets` 返回数组顺序不等于标签栏顺序，且 success 场景只有 source + target 两个 page tab，用数组下标判断"相邻"不可靠。

**修复**:
- `assertAdjacentActivatedTab` 改为: 断言恰好 2 个 page tab，source 非 active，另一个 tab active
- 错误消息改为中文（"期望恰好两个 page tab"、"source tab 不应为 active"、"另一个 page tab 应为 active"）

### 测试覆盖

```
node --test scripts/e2e/test-link-reliability.mjs  →  7/7 pass (新增 "rejects when source tab not found")
zsh scripts/dev/test-link-reliability.sh --dry-run  →  exit 0
```

新增测试用例:
- `rejects when more than two page tabs exist` — 匹配新错误消息 `/恰好.*两个/`
- `rejects when source tab is active (新 tab 应获得焦点)` — 匹配 `/source.*active|active.*source|不应.*active/`
- `rejects when source tab not found` — 新增，覆盖 sourceId 不存在的分支

---

## Re-review Fix: CDP sessionId 路由缺失

**时间**: 2026-08-01 | **审查轮次**: Task 3 re-review | **严重度**: Important

### 问题描述

`runAll()` 里 `Target.attachToTarget` 返回了 `sessionId`，但只保存了 `this.#pageTargetId`，未保存 sessionId。后续 6 处页面级 CDP 命令（`Runtime.enable`、`Page.navigate`、`Runtime.evaluate`）均未带 sessionId，导致命令路由到 browser target（不支持 Page domain、无 DOM），真实 Chrome 下场景执行失败。

### 受影响位置（6 处）

| # | 方法 | CDP 命令 | 作用 |
|---|------|----------|------|
| 1 | `runAll()` | `Runtime.enable` | 启用 page Runtime domain |
| 2 | `runAll()` | `Page.navigate` | 场景 1 后重置 fixture 页 |
| 3 | `runAll()` | `Page.navigate` | 场景 2 后重置 fixture 页 |
| 4 | `#runSuccess()` | `Runtime.evaluate` | 模拟点击 `#e2e-link` |
| 5 | `#runLeaseExpiry()` | `Page.navigate` | 导航离开触发 guard release |
| 6 | `#runProviderUnavailable()` | `Runtime.evaluate` | Provider 不可用后点击链接 |

### 修复内容

1. **新增导出纯函数** `pageEvaluate(cdp, expression, sessionId)` 和 `pageNavigate(cdp, url, sessionId)` — 封装 CDP 页面级命令，通过 sessionId 路由到 page target，可独立单测
2. **新增实例字段** `#pageSessionId` — 保存 `Target.attachToTarget` 返回的 sessionId
3. **6 处调用点全部使用新 helper + sessionId**：
   - `Runtime.enable` → `this.#cdp.send("Runtime.enable", {}, this.#pageSessionId)`
   - `Page.navigate` → `pageNavigate(this.#cdp, url, this.#pageSessionId)`（3 处）
   - `Runtime.evaluate` → `pageEvaluate(this.#cdp, expr, this.#pageSessionId)`（2 处）
4. **更新实例方法** `#pageEvaluate` 和 `#sendPageCommand` 接受可选 sessionId 参数（向前兼容）
5. **`#getTabs()` 保持不动** — 它每次调用独立 attach 各 tab，语义独立且正确

### 测试覆盖

```
node --test scripts/e2e/test-link-reliability.mjs  →  11/11 pass
zsh scripts/dev/test-link-reliability.sh --dry-run  →  exit 0
```

新增 4 个单测 — mock cdp 对象验证 sessionId 透传：
- `pageEvaluate` calls cdp.send with Runtime.evaluate, expression, returnByValue, and sessionId
- `pageEvaluate` passes null sessionId when not provided
- `pageNavigate` calls cdp.send with Page.navigate, url, and sessionId
- `pageNavigate` passes null sessionId when not provided

### 改动文件

- `scripts/e2e/run-link-reliability.mjs` — 新增 2 个导出函数 + `#pageSessionId` + 6 处调用点修复
- `scripts/e2e/test-link-reliability.mjs` — 新增 4 个 mock cdp 单测
