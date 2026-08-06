# GestureKit V2.4.1 真实 Chrome 门 I3 连通性整改计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**版本语义：** 本次整改是 **v2.4 的补丁（v2.4.1）**，不新开功能版本。在 v2.4 合并结果（main `aec2588`）之上修复，只收敛缺陷与必要的测试基础设施简化，不引入新功能、新手势、新 Provider 动作或公开协议字段。

**目标：** 修复真实 Chrome 门（`zsh scripts/dev/test-link-reliability.sh`）的缺口 I3——扩展→Host→App 的 provider 链路无法建立，导致 `success`/`leaseExpiry` 两个场景失败。修复后四个场景全部通过，真实 Chrome 门成为可用的链接可靠性回归门。

**范围：** 严格限制在 E2E 测试基础设施（`scripts/e2e/`、`scripts/dev/test-link-reliability.sh`、E2E extension build 与 bridge、E2EControlServer 相关改动），不触碰生产手势识别、动作执行与 Provider v2 协议。顺带按根因分析收敛 E2E 层冗余（见下），但不做大规模生产架构重构。

## 根因（v2.4 真实 Chrome 首次试跑确认）

1. **扩展 ID 不匹配**：Chrome 用 `--load-extension` 加载未打包扩展时，扩展 ID 由**扩展目录路径**推导（实测 `fignfifoniblkonapihmkfakmlgkbkcf`），**忽略 manifest `key`**；而 runner 按 manifest key 推导 ID（`extension-id.mjs` → `pdegbjhgibenmgaaplhnpbnhaaipndoh`）写入 native messaging manifest 的 `allowed_origins`。`connectNative("com.gesturekit.host")` 被 Chrome 以 allowed_origins 不匹配拒绝，Host 进程不拉起。
2. **manifest 位置不确定**：实测临时 profile 的 `<user-data-dir>/NativeMessagingHosts` 中的 manifest 未被读取（marker 探针从未触发），Chrome 对 macOS 可能只读用户级注册 `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`。需确认并选择写入位置（临时替换用户级注册 + 备份/恢复，或验证 profile 路径可用）。
3. **active 检测不可靠**：`document.hasFocus()` 在无 GUI 焦点（后台 Chrome 窗口）时对全部 tab 返回 false，无法区分真实激活。需改用扩展上报 `chrome.tabs` 真实 active 状态，或 runner 前置激活 Chrome 窗口。
4. **leaseExpiry 语义未理清**：guard lease 过期后，content script 的 `linkClickProtectionEnabled`（连接到 App 时开启）仍会拦截普通点击，需明确两机制边界，让 lease 过期后普通点击真正不被拦截。

**次因（测试 mock 了错误形状）**：runner 的 node 单测 mock CDP 返回 `{targetInfos:...}`（真实是 `{result:{targetInfos:...}}`），App 单测直接读 `server.port`（不测 stdout 接口），把错误假设固化。整改时：**先探针/真实运行验证接口形状，再写 mock**；对无法端到端跑的部分，在文档如实标注"未验证"。

## 全局约束（沿用 v2.4）

- 范围与验收依据：`docs/product/gesturekit-v2.4-reliability-contract.md`；不新增手势、Provider、动作或公开 Provider Protocol 字段。
- E2E control token 仅存在于临时 profile/扩展副本/子进程环境；日志、证据与失败输出不得打印 token、完整 URL query/hash、Cookie、页面正文或原始 `targetRef`。
- 测试控制入口默认不可用；无 token/非 loopback/不匹配时拒绝且不创建 guard/session。
- 每项实现遵循 TDD：先运行失败测试，再最小实现，再运行任务级与相关全量测试。
- 项目文档中文优先；代码、命令、协议字段和路径保持原文。

---

## 任务

### Task 1：确认扩展 ID 推导算法与 manifest 读取位置（探针）

- [ ] **Step 1**：写一次性探针脚本（临时 profile + `--load-extension` + marker manifest），确认 (a) Chrome 对给定扩展目录路径分配的 ID 算法能否复现（用于 runner 计算），(b) Chrome 是否读取 `<user-data-dir>/NativeMessagingHosts`。
- [ ] **Step 2**：记录结论到本计划。若路径 ID 算法不可靠，改为方案 B：在临时 extension 的 manifest 注入 `key` 使 ID 确定（验证 `--load-extension` 是否尊重 key，不改变生产构建）。
- [ ] **Step 3**：提交探针与结论。

### Task 2：修复 manifest 写入与 allowed_origins

- [ ] **Step 1**：runner 按实际加载的扩展 ID 计算 `allowed_origins`（Task 1 结论），不再用 manifest key 推导。
- [ ] **Step 2**：manifest 写到 Chrome 实际读取的位置；若需临时替换用户级注册，做备份/恢复，运行结束不残留，且不得影响运行中的真实 GestureKitApp（隔离端口已有）。
- [ ] **Step 3**：TDD：先写断言失败的 node 测试，实现后通过；dry-run 展示真实命令。

### Task 3：修复 success 场景 active 检测

- [ ] **Step 1**：扩展 E2E 通道上报 `chrome.tabs` 真实 active tab（或 runner 用 CDP/AppleScript 前置激活 Chrome 窗口后保留 `document.hasFocus()`）。
- [ ] **Step 2**：替换 `#getTabs` 的 active 判定来源；TDD 覆盖。
- [ ] **Step 3**：本地真实 Chrome 跑 success 场景，断言相邻激活 tab URL == 固定目标且 source 未变。

### Task 4：理清 leaseExpiry 语义

- [ ] **Step 1**：确认 guard lease 过期后 content script 行为：`interactionGuard.active()` 与 `linkClickProtectionEnabled` 的关系。
- [ ] **Step 2**：让 lease 过期后的普通点击不被拦截（若语义要求如此）；或按实际语义修正断言与文档。
- [ ] **Step 3**：本地真实 Chrome 跑 leaseExpiry，断言源页正常导航、无新 tab。

### Task 5：E2E 层冗余收敛（顺带，不放大改动）

- [ ] **Step 1**：移除/标注未使用的扩展页面 bridge（`controlledPageBridge`）与 `e2eControl.dispatch` stub，统一为单一控制通道（App TCP）。
- [ ] **Step 2**：确认删除后 `npm test`（182）与 node e2e 单测仍绿；文档同步。
- [ ] **Step 3**：提交，说明删除项不影响功能。

### Task 6：全量验证与真实 Chrome 门

- [ ] **Step 1**：`swift test`（本机含 MenuBarControllerTests）、`npm test`、`npm run build`、`node --test scripts/e2e/test-link-reliability.mjs`、`zsh scripts/dev/test-link-reliability.sh --dry-run` 全绿。
- [ ] **Step 2**：开发者本机跑真实 Chrome 门，四场景全部 `terminalStatus` 符合契约，无残留 App/Chrome/临时目录。
- [ ] **Step 3**：CI（`workflow_dispatch` 或合并后 main push）质量门绿；更新 `docs/operations/e2e-checklist.md` / `troubleshooting.md` 撤下或收敛 I3 缺口描述。
- [ ] **Step 4**：提交并开 PR 到 main（v2.4.1）。

---

## 验收标准

- 真实 Chrome 门四场景全过（success 相邻激活 tab URL==固定目标且 source 未变；leaseExpiry 普通点击正常导航无新 tab；providerUnavailable/resultUnknown 终态符合契约）。
- 通用 CI（swift/extension/scripts）在 GitHub hosted runner 全绿。
- 无 token/凭据泄漏；无残留进程或临时目录。
- E2E 层删除了未使用的 bridge/stub，单一控制通道，不改变生产行为。
