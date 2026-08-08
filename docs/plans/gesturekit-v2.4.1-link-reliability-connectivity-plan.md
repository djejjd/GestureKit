# GestureKit V2.4.1 真实 Chrome 门 I3 连通性整改计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**版本语义：** 本次整改是 **v2.4 的补丁（v2.4.1）**，不新开功能版本。在 v2.4 合并结果（main `aec2588`）之上修复，只收敛缺陷与必要的测试基础设施简化，不引入新功能、新手势、新 Provider 动作或公开协议字段。

**目标：** 修复真实 Chrome 门（`zsh scripts/dev/test-link-reliability.sh`）的缺口 I3——扩展→Host→App 的 provider 链路无法建立，导致 `success`/`leaseExpiry` 两个场景失败。修复后四个场景全部通过，真实 Chrome 门成为可用的链接可靠性回归门。

**范围：** 严格限制在 E2E 测试基础设施（`scripts/e2e/`、`scripts/dev/test-link-reliability.sh`、E2E extension build 与 bridge、E2EControlServer 相关改动），不触碰生产手势识别、动作执行与 Provider v2 协议。顺带按根因分析收敛 E2E 层冗余（见下），但不做大规模生产架构重构。

## 根因（v2.4 真实 Chrome 首次试跑 + 架构审核逐条核验确认）

1. **（主根因，Task 1 探针修正）扩展未加载——真因是品牌 Chrome 忽略 `--load-extension`**：Google Chrome（品牌版）142 起完全移除 `--load-extension`（本机 151 实测 stderr：`--load-extension is not allowed in Google Chrome, ignoring.`；`--disable-features=DisableLoadExtensionCommandLineSwitch` 已失效）。runner 依赖 `--load-extension` 加载 E2E 扩展 → 扩展从未加载，provider 链路在起点即断。附带问题确实存在但属次要：runner 只用 esbuild 构建 JS、从不拷贝 manifest/静态文件到临时扩展目录，且 manifest 内 `dist/...` 与 `--outdir ${extensionOut}` 布局不一致。**正确加载路径**：CDP `Extensions.loadUnpacked`（品牌 Chrome 151 实测可用，Task 1 已验证完整副本可加载 + content script 注入），或改用 Chrome for Testing（Chromium 构建，保留 `--load-extension`）。
2. **（Task 1 探针修正）扩展 ID 不匹配——原结论是误读**：含 `key` 的未打包扩展 ID 取 **key 推导**（`Extensions.loadUnpacked` 实测 `pdegbjhgibenmgaaplhnpbnhaaipndoh`，与 `extension-id.mjs` 完全一致），**并非路径推导**；runner 按 manifest key 写 `allowed_origins` 是**正确**的。计划原记录的 `fignfifoniblkonapihmkfakmlgkbkcf` 实为 Chrome 内置组件 **Google Network Speech** 的 ID（其 `manifest.name`="Google Network Speech"），v2.4 调试误读了该 SW target。仅当扩展**移除 key** 时 ID 才由路径推导（`sha256(realpath(目录))` 前 16 字节 nibble 映射 `a..p`，Task 1 已验证可复现）——E2E 无需路径算法。方案 B（注入 key 使 ID 确定）自始无关：key 本就生效。
3. **（Task 1 探针修正）manifest 位置——原结论相反**：Chrome 的 `DIR_USER_NATIVE_MESSAGING` 由 `DIR_USER_DATA` 推导。用临时 `--user-data-dir` 时读 **`<user-data-dir>/NativeMessagingHosts/`**（marker 探针实测被读取、host 被拉起），**不读** `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`；只有用默认 profile 才读用户级目录。runner 现在写 `<profile>/NativeMessagingHosts` 的位置**正确**。注意：manifest 查找有进程内缓存，应"先写 manifest 再启动 Chrome"。优先方案仍建议独立 host 名（如 `com.gesturekit.host.e2e`）完全避开用户级真实 manifest。
4. **active 检测不可靠**：`document.hasFocus()` 在无 GUI 焦点（后台 Chrome 窗口）时对全部 tab 返回 false，无法区分真实激活。修复机制：runner 经 CDP 附着扩展 service worker target，执行 `chrome.tabs.query({active:true})` 取真实 active tab——不依赖 GUI 焦点，也不依赖将被删除的 page bridge（与 Task 5 兼容）。
5. **（前提更正）leaseExpiry 语义**：架构审核核验发现——`linkClickProtectionEnabled` 在生产恒为 false（`content/pointerTracker.ts` 仅定义 `setLinkClickProtectionEnabled`，全仓库无生产调用点，初始值 false），guard lease 过期后 `interactionGuard.active()` 返回 null，普通点击本就不被拦截。**"连接到 App 时开启拦截"的前提不成立**，docs 对 leaseExpiry 失败的记载与代码推演不符。Task 4 改为：先探针复核真实失败模式，再按实际语义修正断言与文档，**不改 content script 逻辑**。

**次因（测试 mock 了错误形状）**：runner 的 node 单测 mock CDP 返回 `{targetInfos:...}`（真实是 `{result:{targetInfos:...}}`），App 单测直接读 `server.port`（不测 stdout 接口），把错误假设固化。整改时：**先探针/真实运行验证接口形状，再写 mock**；对无法端到端跑的部分，在文档如实标注"未验证"。

## 全局约束（沿用 v2.4）

- 范围与验收依据：`docs/product/gesturekit-v2.4-reliability-contract.md`；不新增手势、Provider、动作或公开 Provider Protocol 字段。
- E2E control token 仅存在于临时 profile/扩展副本/子进程环境；日志、证据与失败输出不得打印 token、完整 URL query/hash、Cookie、页面正文或原始 `targetRef`。
- 测试控制入口默认不可用；无 token/非 loopback/不匹配时拒绝且不创建 guard/session。
- 每项实现遵循 TDD：先运行失败测试，再最小实现，再运行任务级与相关全量测试。
- 项目文档中文优先；代码、命令、协议字段和路径保持原文。

---

## 任务

### Task 1：探针确认——扩展可加载性、ID 算法、manifest 读取位置、leaseExpiry 真实失败模式

- [x] **Step 1**：写一次性探针脚本（临时 profile + **完整可加载扩展副本**：含 `manifest.json` + `popup.html` + `smoke.html` + `dist/` 构建输出），确认 (a) 完整副本能否被 Chrome 加载（content script 注入），(b) 扩展 ID 算法（含 key / 无 key 两种）能否复现，(c) Chrome 是否读取 `<user-data-dir>/NativeMessagingHosts`。**注意**：品牌 Chrome 151 忽略 `--load-extension`，探针改用 CDP `Extensions.loadUnpacked` 加载（见下方结论）。
- [x] **Step 2**：记录结论到本计划（见下方"探针结论"）。**废弃方案 B**（注入 manifest `key` 使 ID 确定）——方案 B 的前提（`--load-extension` 忽略 key）被探针证伪：含 key 扩展 ID 即 key 推导，runner 现状正确；无需固定目录路径。
- [x] **Step 3**：顺带复核 leaseExpiry 真实失败模式（broken chain 下无 guard → 普通点击正常导航、无新 tab，docs 记载与实测一致；探针确认 `linkClickProtectionEnabled` 生产恒 false）。
- [ ] **Step 4**：提交探针与结论。（本任务执行代理按约束不 commit；提交留待 Task 6/PR 阶段。）

#### 探针结论（Task 1 执行记录，2026-08-07 本机 Chrome 151.0.7922.76 / node v23）

探针脚本：`scripts/dev/probe-link-reliability.mjs`（可重复运行；临时 profile/临时目录/独立 host 名，运行结束清理进程与临时目录）。四个问题结论：

**(a) 扩展可加载性 —— 成立，但加载方式必须改为 CDP `Extensions.loadUnpacked`**
- 品牌 Chrome 151 实测忽略 `--load-extension`（stderr：`--load-extension is not allowed in Google Chrome, ignoring.`）；`--disable-features=DisableLoadExtensionCommandLineSwitch` 已失效（142 起移除）。v2.4 真实 Chrome 门扩展从未加载，真因在此。
- 完整副本（`manifest.json`+`popup.html`+`smoke.html`+`dist/`；`build.mjs --outdir <ext>/dist` 使布局与 manifest 内 `dist/...` 引用一致；`popup.css` 非 esbuild 产物需从 `src/popup/popup.css` 拷贝）经 CDP `Extensions.loadUnpacked` 加载：**成功**——service worker target = `chrome-extension://pdegbjhgibenmgaaplhnpbnhaaipndoh/dist/background/background.js`；**content script 注入成功**（isolated world 中 `window.__gestureKitPointerTrackerState.linkClickProtectionEnabled === false`）。

**(b) 扩展 ID 算法 —— 可复现，两种规则（key 优先），runner 现状正确**
- **含 `key`**（本仓库 manifest 带 key）：ID = key 推导 = `pdegbjhgibenmgaaplhnpbnhaaipndoh`（`loadUnpacked` 实测与 `extension-id.mjs` 一致）。
- **无 `key`**：ID = `sha256(realpath(目录))` 前 16 字节、每字节高低 nibble 映射 `a..p`（实测与算法预测一致；必须用 realpath，字面路径不匹配）。
- 计划原记录的 `fignfifoniblkonapihmkfakmlgkbkcf` 实为 Chrome 内置组件 **Google Network Speech** 的 ID（其 `manifest.name`="Google Network Speech"），v2.4 调试误读了该 SW target；不是 E2E 扩展的 ID。E2E 不需要路径算法。

**(c) manifest 读取位置 —— 与计划根因 3 相反，runner 现状正确**
- marker 探针（manifest `path` 指向写标记文件的脚本）实测：Chrome 151 读 **`<user-data-dir>/NativeMessagingHosts/`**（marker 被写、host 被拉起），**不读** `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`（connectNative → `Specified native messaging host not found`）。
- 原因：`DIR_USER_NATIVE_MESSAGING` 由 `DIR_USER_DATA` 推导；用临时 `--user-data-dir` 即临时 profile 下的 `NativeMessagingHosts`，默认 profile 才读 `~/Library/...`。runner 现写 `<profile>/NativeMessagingHosts` 位置正确。注意 manifest 查找有进程内缓存——E2E 应"先写 manifest 再启动 Chrome"。

**(d) leaseExpiry —— 代码推演正确，docs 记载基本一致**
- `linkClickProtectionEnabled` 生产恒 `false`：`setLinkClickProtectionEnabled` 仅定义、无生产调用点；`gestureSettings.ts` 的 settings 字段未下发到 content script。
- 探针实测（扩展加载 + content script 注入，broken chain 无 guard）：点击前 isolated world 状态 `{linkClickProtectionEnabled:false, protectedLinkClick:null, pendingConsumedClick:null}`；对 `#e2e-link` 普通点击**不被拦截**，正常导航到 `https://example.test/e2e-target`（error page），不打开新 tab。

**对 Task 2/3/4 的影响**
- Task 2：加载方式改为 CDP `Extensions.loadUnpacked`（或 Chrome for Testing）；`allowed_origins` 继续用 `extension-id.mjs`（key 推导）；manifest 写 `<profile>/NativeMessagingHosts` 不变；建议保留独立 host 名方案。
- Task 3：active 检测按计划经 CDP 附着 SW 执行 `chrome.tabs.query({active:true})`；CDP 响应形状按真实 `{result:...}` 核验。
- Task 4：leaseExpiry 断言按探针结论保留/修正，补充 guard trace；不改 content script 逻辑。注意：点击 `example.test` 后 `TargetInfo.url` 更新有延迟（实测最慢 ~4s），runner 当前点击后等 1500ms 偏紧，建议加长。

### Task 2：修复扩展加载与 manifest 写入、allowed_origins

- [x] **Step 1（前置，修复主根因 1）**：runner 改用 **CDP `Extensions.loadUnpacked`**（品牌 Chrome 151 实测可用）加载完整扩展副本，替代已失效的 `--load-extension`；或改用 Chrome for Testing（Chromium 构建，保留 `--load-extension`）。构建后拷贝 `manifest.json`/`popup.html`/`smoke.html` 到临时扩展目录，按 manifest 内相对路径（`dist/...`）对齐布局（`build.mjs --outdir <ext>/dist`；`popup.css` 从 `src/popup/popup.css` 拷贝）。以"Chrome 能加载该扩展、content script 注入"为验证标准。
- [x] **Step 2**：`allowed_origins` **继续用 `extension-id.mjs`（manifest key 推导）**——Task 1 探针确认含 key 扩展 ID 即 key 推导（`pdegbjhgibenmgaaplhnpbnhaaipndoh`），runner 现状正确；无需路径算法。
- [x] **Step 3**：manifest 写入位置 **`<profile>/NativeMessagingHosts` 保持不变**（Task 1 探针确认该位置被读取）；**优先方案**：E2E build 覆盖 `HOST_NAME` 为独立 host 名（如 `com.gesturekit.host.e2e`），完全不触碰用户级真实 manifest。注意先写 manifest 再启动 Chrome（进程内缓存）。
- [x] **Step 4**：TDD：先写断言失败的 node 测试，实现后通过；dry-run 展示真实命令。

#### 结论（Task 2 执行记录，2026-08-08 本机 Chrome 151 / node v23）

改动集中在 E2E 测试基础设施，生产手势/Provider 协议未动：

- **`scripts/e2e/run-link-reliability.mjs`（runner 主修复）**
  - 扩展构建改为「完整可加载副本」：`build.mjs --outdir <副本>/dist`（对齐 manifest 内 `dist/...` 引用）→ `copyExtensionStaticFiles()` 拷贝 `manifest.json`/`popup.html`/`smoke.html` 到副本根 + `src/popup/popup.css` → `dist/popup/popup.css` → `validateExtensionLayout()` 校验 manifest 引用的文件真实存在。
  - Chrome 启动参数移除失效的 `--load-extension`；CDP 连接后经 `Extensions.loadUnpacked` 加载完整副本，校验返回 ID == key 推导 ID（`pdegbjhgibenmgaaplhnpbnhaaipndoh`），并 `waitForExtensionServiceWorker()` 等待扩展 SW target 出现（证明已加载）。
  - `runAll()` 在扩展加载后重新加载 fixture 页面（页面在扩展之前打开，content script 不会注入已加载页面），`verifyContentScriptInjected()` 在 isolated world 校验 `window.__gestureKitPointerTrackerState` 暴露。
  - 独立 host 名：native messaging manifest 写 `<profile>/NativeMessagingHosts/com.gesturekit.host.e2e.json`，`name`/`allowed_origins` 用 `hostManifest()` 构造；先写 manifest 再启动 Chrome（进程内缓存）。
- **`extensions/chrome/scripts/build.mjs`**：新增 `GESTUREKIT_HOST_NAME` 环境变量 → esbuild `define __GESTUREKIT_HOST_NAME__` 注入（仅 background build）。生产构建不设环境变量时不注入，行为不变。
- **`extensions/chrome/src/background/background.ts`**：`HOST_NAME` 改为可注入 seam——`typeof __GESTUREKIT_HOST_NAME__ !== "undefined" ? __GESTUREKIT_HOST_NAME__ : "com.gesturekit.host"`（`declare const` + typeof 守卫，未注入时回退默认名，生产行为不变）。E2E build 注入 `com.gesturekit.host.e2e`，使扩展 `connectNative` 用独立 host 名，彻底避开用户级真实 manifest。
- **`scripts/e2e/test-link-reliability.mjs`**：新增 11 条 node 单测（28 总），覆盖：独立 host 名常量、静态文件拷贝布局、dist 布局校验（缺文件抛错）、`Extensions.loadUnpacked` 调用、`waitForExtensionServiceWorker` 轮询、host manifest 内容、content script 注入验证。

**TDD 红→绿**：先写断言失败的 node 单测（模块因缺导出 `E2E_HOST_NAME` 等加载失败 = 红），再实现 runner helper + build.mjs/background.ts 注入，最终 node e2e 28/28 绿、`npm test` 176/176 绿。

**验证结果**
- `npm test`（extensions/chrome vitest）：**176 绿**（Task 5 基线不变，background.ts 改动不影响）。
- `node --test scripts/e2e/test-link-reliability.mjs`：**28 绿**（17 基线 + 11 新增）。
- `zsh scripts/dev/test-link-reliability.sh --dry-run`：展示真实命令——`GESTUREKIT_HOST_NAME="com.gesturekit.host.e2e" node scripts/build.mjs --outdir "<ext>/dist"`、静态文件拷贝、`com.gesturekit.host.e2e.json` 独立 host 名 manifest、Chrome 无 `--load-extension`、CDP `Extensions.loadUnpacked` 加载流程。
- **真实 Chrome（单次 headless 运行）**：完整副本布局校验通过 → loadUnpacked ID == key 推导 ID == `pdegbjhgibenmgaaplhnpbnhaaipndoh` → 扩展 SW 出现（`chrome-extension://.../dist/background/background.js`）→ content script 注入成功（isolated world `{hasLastPointer:false, linkClickProtectionEnabled:false}`）。与探针结论一致。

**对 Task 3 的影响**：runner 现在可靠地加载扩展 + 注入 content script，success 场景的 guard/action 链路起点已打通；`#getTabs` 的 `document.hasFocus()` active 检测仍不可靠（后台无 GUI 焦点恒 false），按 Task 3 计划改为经 CDP 附着扩展 SW 执行 `chrome.tabs.query({active:true})`。此外 `TargetInfo.url` 更新有延迟（探针实测最慢 ~4s），runner 点击后等 1500ms 偏紧，Task 3/4 建议加长。残留清理已确认：无 e2e 匹配的 Chrome 进程、无遗留临时目录、用户级 manifest 未触碰。

### Task 3：修复 success 场景 active 检测

- [x] **Step 1**：runner 经 CDP `Target.attachToTarget` 附着扩展 service worker target，`Runtime.evaluate("chrome.tabs.query({active:true})")` 取真实 active tab 作为 active 判定来源。**不采用**扩展→runner 上报通道（与 Task 5 删 page bridge 冲突）与 AppleScript/前置激活窗口（依赖 GUI 会话，CI 下必失败）。
- [x] **Step 2**：替换 `#getTabs` 的 active 判定来源；TDD 覆盖（CDP 响应形状按真实 `{result:...}` 结构 mock，先探针确认）。
- [x] **Step 3**：本地真实 Chrome 跑 success 场景，断言相邻激活 tab URL == 固定目标且 source 未变。

#### 结论（Task 3 执行记录，2026-08-08 本机 Chrome 151 / node v23）

改动集中在 E2E 测试基础设施（`scripts/e2e/`），生产手势/Provider 协议未动：

**active 检测来源替换（Step 1/2）**
- `#getTabs` 不再逐 page target 附着跑 `document.hasFocus()`（后台/无 GUI 焦点恒 false），改为：`Target.getTargets` 枚举 page target（提供 CDP targetId）+ 经 `Target.attachToTarget`（flatten 会话）附着扩展 SW，在 SW 上下文执行 `chrome.tabs.query({active:true})`（`returnByValue` + `awaitPromise`）取真实 active tab，按 URL 匹配标记 active。
- CDP `TargetInfo.targetId` 与 chrome tab `id` 是两套 ID 空间，E2E fixture 中 source/target URL 互不相同，按 URL 匹配即可区分真实激活。
- **真实运行发现关键形状**：新 tab 打开后 TargetInfo.url 立即更新到固定目标，但 chrome.tabs 的 `url` 要等导航 commit（`status:"loading"` 期间 `url` 为空、目标在 `pendingUrl`）——`markActiveByUrl` 必须同时匹配 `url` 与 `pendingUrl`，否则加载中的活动 tab 被判非 active（初版实跑即暴露此 bug）。
- 新导出 helper（均可单测）：`queryActiveTabs`、`markActiveByUrl`、`hasAdjacentTargetTab`、`waitForTabs`。

**等待策略改动（Step 3）**
- success 场景点击后由固定 `sleep(1500)` 改为 `waitForTabs` 轮询（默认 250ms 间隔 / 10s 超时），等待"非 source 且 URL == `https://example.test/e2e-target`"的相邻 tab 出现；超时区分 `guard_not_armed:source_navigated`（source 被原地导航 = guard 未拦截）与 `target_url_not_updated`。
- 探针实测 `TargetInfo.url` 更新最慢 ~4s，轮询消除了该延迟导致的 flake。
- **provider 启动竞态（残留，Task 6 关注）**：首次 headless 实跑 success 偶发 `source_navigated`——扩展 SW 已存活但 App 侧 provider 会话尚未建立，guard arm 静默失败。尝试经 CDP 从 SW 自身上下文 `chrome.runtime.sendMessage` 触发 `gesturekit.runConnectionProbe` 作为"已连接"信号，实测**不成立**（`Could not establish connection. Receiving end does not exist.`——sendMessage 不会递到 SW 自身监听器）。改用场景 1 前 1500ms settle 缩小竞态窗口（探针确认链路正常时数百毫秒内建立），并如实记录该残留。
- 顺带新增 runner `--headless` 选项（新无头模式支持扩展；CI 无 GUI 会话时建议使用），默认不开启。

**TDD 红→绿**
1. 先写 10 条失败 node 单测（新函数未导出 → import 失败 = 红），再实现 → 38 绿（28 基线 + 10 新增）。
2. 真实运行暴露 `pendingUrl` 形状 → 补 1 条失败测试（红）→ `markActiveByUrl` 匹配 pendingUrl → 绿。

**验证结果（真实 Chrome 151，headless + 非 headless 各一次）**
- success：`terminalStatus:"succeeded"`、`failureStage:null`、durationMs ~765ms——相邻激活 tab URL == `https://example.test/e2e-target`，source tab URL 未变，且 target 被判 active、source 判非 active（`chrome.tabs.query({active:true})` + pendingUrl 匹配生效）。
- providerUnavailable / resultUnknown：`terminalStatus` 符合契约，绿。
- leaseExpiry：仍失败（`guard_still_armed:click_blocked`，见"对 Task 4 的影响"）。
- `npm test`（extensions/chrome vitest）：**176 绿**（Task 5 基线不变）。
- `node --test scripts/e2e/test-link-reliability.mjs`：**38 绿**（28 基线 + 10 新增）。
- 残留清理：无 e2e 匹配的 Chrome 进程、无遗留临时目录、用户级 manifest 未触碰。

**对 Task 4 的影响**
- `#getTabs` 改动只影响 active 字段，不影响 leaseExpiry 的 tab 数 / source URL 检查（URL 仍来自 TargetInfo）。
- leaseExpiry 仍失败根因：点击 `https://example.test/e2e-target` 后 source 被原地导航，但 `TargetInfo.url` 更新有延迟（探针实测最慢 ~4s），runner 点击后固定 `sleep(1500)` 偏紧 → 误报 `guard_still_armed:click_blocked`。Task 4 需把 leaseExpiry 的固定等待改为轮询（或按探针结论修正断言），并补 guard trace 断言。

### Task 4：修正 leaseExpiry 语义与断言（不改 content script 逻辑）

- [x] **Step 1**：按 Task 1 Step 3 探针结论确认 guard lease 过期后 content script 真实行为：`interactionGuard.active()` 返回 null、`linkClickProtectionEnabled` 生产恒 false，普通点击本就不被拦截。
- [x] **Step 2**：按实际语义修正 runner 断言与 docs 记载（`docs/operations/troubleshooting.md` 等）；**不改 content script/guard 逻辑**，除非探针发现真实拦截缺陷。
- [x] **Step 3**：本地真实 Chrome 跑 leaseExpiry，断言源页正常导航、无新 tab；补充 guard trace 断言（缺口 I2）证明"无 guard 放行"而非"链路断裂恰好放行"。

#### 结论（Task 4 执行记录，2026-08-08 本机 Chrome 151 / node v23）

改动集中在 `scripts/e2e/` 测试基础设施；**content script/guard 逻辑与生产 background 未改**。

**Step 1/2（leaseExpiry 轮询 + 断言修正）**
- `#runLeaseExpiry` 点击后固定 `sleep(1500)` 改为 `waitForTabs` 轮询 source tab URL 更新到
  `https://example.test/e2e-target`（15s 超时；`TargetInfo.url` 同 tab 导航到不可解析的
  example.test 时更新慢至 ~10s DNS 超时，轮询消除误报根因）。超时诊断区分
  `guard_still_armed:new_tab_opened` 与 `source_url_not_updated`。
- 断言按探针语义：guard 曾被 arm、release/lease 过期后普通点击不被拦截 → source 原地导航、
  无新 tab。`linkClickProtectionEnabled` 生产恒 false 已在 troubleshooting.md 记录。
- **顺带修复了一个真实路由缺陷**：success 后 active tab 是目标 tab，而 background
  `routeInteractionGuard` 把 guard arm 路由到 active tab；若不先 `#activateTabByUrl` 激活
  source（fixture）tab，leaseExpiry 的 arm 会发到无 content script 的目标 tab
  （实测 `forward_failed:content_script_unavailable`），点击放行实为"链路断裂恰好放行"。
  runner 在 leaseExpiry 前激活 fixture tab（新增 `findTabIdByUrl` helper，纯函数可单测）。

**Step 3（guard trace 断言，缺口 I2）**
- 观测方式落地：runner 以 Foundation 参数域启动 App（`-gesturekitDiagnosticLoggingEnabled YES`，
  NSArgumentDomain 优先级最高、仅影响本进程不持久化），使扩展 `diagnosticLoggingEnabled=true`，
  `recordGuardTrace` 非终态阶段落到 `chrome.storage.local` 的 `gesturekitDiagnostics`；runner
  经 CDP 附着扩展 SW，在 SW 上下文 `chrome.storage.local.get` 读取并按时间窗口过滤。
- **实测发现**：content script 回发的 `armed` 阶段会与 background 自身并发持久化竞态丢失
  （`void appendDiagnostic` 对同一 session 多次并发 get→set 的 lost-update，`armed` 中间阶段
  丢失而 `forwarding`/`forwarded` 稳定）。因此断言改用等价的 `forwarded:guard_armed`——
  content script 仅在 `interactionGuard.arm()` 之后才回 `guard_armed`，故 `forwarding` +
  `forwarded:guard_armed` 是"guard 确实被 arm"的直接证据；再断言无 `click_blocked`/
  `lease_expired`（点击未被拦截再恢复）。**未改生产 background 暴露接口**（无需 seam）。
- 真实 Chrome（headless）leaseExpiry：`terminalStatus:"lease_released"`、`failureStage:null`，
  guard trace 断言通过（`forwarding` + `forwarded:guard_armed` 在窗口内、无 `click_blocked`/
  `lease_expired`），source 原地导航到固定目标、无新 tab。
- 新增 node 单测 22 条（`leaseExpirySourceNavigated`/`findTabIdByUrl`/`matchGuardStageMessage`/
  `guardTraceSessionsInWindow`/`parseGuardTraceStages`/`hasForwardedGuardArmed`/
  `hasGuardBlockedClick` 等），node e2e 38 → **60 绿**；`npm test` **176 绿**（未触碰 extension src）。

**对 Task 6 的影响**
- 真实 Chrome 门四场景全过；leaseExpiry 源导航受 example.test DNS 超时影响偏慢（~10s），
  15s 超时已留余量；若 CI 网络 DNS 更慢需留意。
- 残留：`providerUnavailable`/`resultUnknown` 走 dispatch/终态路径绕过真实手势链路（I1，
  Task 6 决定是否收敛）；成功场景的 provider 启动竞态（Task 3 记录）未在本 Task 处理。
- 提交仍留待 Task 6/PR；本 Task 未 commit、未 push。

### Task 5：E2E 层冗余收敛（顺带，不放大改动）

- [x] **Step 1**：删除完整冗余清单：`controlledPageBridge.ts`、`e2eControl.ts` 整个模块、`e2eControl.test.ts`（现有 6 条断言）、`background.ts` 中 `createE2EControl` 调用（import + 调用点）与 `gesturekit.e2eLinkOperation` onMessage 分支、`build.mjs` 中 bridge 的 E2E build 段。统一为单一控制通道（App TCP）。**先删测试再删实现，或一次性删除**——避免中间态 `npm test` 不绿。
- [x] **Step 2**：确认删除后 `npm test`（182）与 node e2e 单测仍绿；文档同步。
- [ ] **Step 3**：提交，说明删除项不影响功能。（本任务执行代理按约束不 commit；提交留待 Task 6/PR 阶段。）

#### 结论（Task 5 执行记录）

删除项均不影响功能，理由如下：

- **runner 不依赖被删通道**：`scripts/e2e/run-link-reliability.mjs` 全程经 App TCP E2E 控制端口（`#sendE2ECommand` → `tcpRoundtrip("127.0.0.1", controlPort, ...)`）驱动四场景，**从未引用** `controlledPageBridge` / `e2eControl` / `gesturekit.e2eLinkOperation`；fixture `link-reliability.html` 里的 `window.__gesturekitE2E` 页面桥接入口是旧通道遗留，runner 不调用。`manifest.json` 的 `content_scripts` 仅注册 `dist/content/pointerTracker.js`，从未注册 `controlledPageBridge.js`——该桥从未实际注入页面。
- **background.ts**：移除 `createE2EControl` import 与调用块（含 `__GESTUREKIT_E2E_TOKEN__` 声明与 `e2eToken`/`e2eAllowedOrigin` 推导）及 `gesturekit.e2eLinkOperation` onMessage 分支。生产路径（native messaging、guard、v2 dispatch、control center）不受影响；`dispatch` 原为 stub（恒返回 `e2e_dispatched`），无真实链路。
- **build.mjs**：移除 `--e2e-token` 参数、`__GESTUREKIT_E2E_TOKEN__` define 注入与 controlledPageBridge E2E build 段。默认 `npm run build`（无 outdir/token）产出不变；E2E build 不再注入 token，但扩展端已无任何消费方。
- **验证结果**：删除前基线 `npm test` 182 绿 / node e2e 单测 17 绿；删除后 `npm test` **176 绿**（182 − 6 条被删断言）/ node e2e 单测 17 绿，`npm run build` 正常产出 `dist/background/background.js`、`dist/content/pointerTracker.js`、`dist/popup/popup.js`、`dist/smoke/smoke.js`。

### Task 6：全量验证与真实 Chrome 门

- [x] **Step 1**：`swift test`（本机含 MenuBarControllerTests）、`npm test`、`npm run build`、`node --test scripts/e2e/test-link-reliability.mjs`、`zsh scripts/dev/test-link-reliability.sh --dry-run` 全绿。（2026-08-08 实测：swift 182 绿、npm test 176 绿、node e2e 60 绿、build 产物正常、dry-run exit 0。）
- [x] **Step 2**：开发者本机跑真实 Chrome 门，四场景全部 `terminalStatus` 符合契约，无残留 App/Chrome/临时目录。（2026-08-08 headless 单次运行全过，四场景 `failureStage:null`；残留检查通过。遗留竞态如实记录：success 场景 provider 启动竞态、leaseExpiry example.test DNS 超时偏慢 ~10s。）
- [ ] **Step 3**：CI（`workflow_dispatch` 或合并后 main push）质量门绿；更新 `docs/operations/e2e-checklist.md` / `troubleshooting.md` 撤下或收敛 I3 缺口描述。（2026-08-08：文档收敛已完成——I3 关闭描述已写入两处 docs；**CI hosted runner 行为未在本机验证**，需主线程触发 `workflow_dispatch` 或合并后 main push 确认。）
- [ ] **Step 4**：提交并开 PR 到 main（v2.4.1）。（由主线程在用户授权后处理，Task 6 执行代理不提交。）

---

## 验收标准

- 真实 Chrome 门四场景全过：扩展被 Chrome 正常加载（content script 注入）；success 相邻激活 tab URL==固定目标且 source 未变；leaseExpiry 普通点击正常导航无新 tab **且 guard trace 证明无 guard**；providerUnavailable/resultUnknown 终态符合契约。
- 通用 CI（swift/extension/scripts）在 GitHub hosted runner 全绿。
- 无 token/凭据泄漏；无残留进程或临时目录；用户级 native messaging manifest 不被改动（独立 host 名方案）或被正确备份恢复。
- E2E 层删除了未使用的 bridge/stub，单一控制通道，不改变生产行为。

---

## 修订记录

- **2026-08-08（Task 6 全量验证完成）**：验证矩阵全绿——swift test 182 绿（本机含
  MenuBarControllerTests，GUI 会话无跳过）、npm test 176 绿、npm run build 产出
  background/pointerTracker/popup/smoke（无 controlledPageBridge，popup.css 为 esbuild
  从 popup.ts CSS import 生成的正常产物）、node e2e 单测 60 绿、dry-run exit 0。
  真实 Chrome 门（headless，Chrome 151.0.7922.76 / node v23.11.0）单次运行四场景全过：
  success→`succeeded`、leaseExpiry→`lease_released`（durationMs 11825，example.test DNS
  超时偏慢如实记录）、providerUnavailable→`provider_unavailable_guard_released`、
  resultUnknown→`result_unknown`，全部 `failureStage:null`。残留检查：无 e2e 匹配的
  Chrome 进程、无 `$TMPDIR/gesturekit-e2e-*` 残留、用户真实 GestureKitApp/GestureKitHost
  进程（40080/40191）未触碰。文档收敛：`e2e-checklist.md`/`troubleshooting.md` 的 I3
  缺口描述由"失败中"收敛为"2026-08-08 已关闭（真因 --load-extension 移除，修复为 CDP
  loadUnpacked + 独立 host 名）"，并如实标注 CI hosted runner 行为未在本机验证。
  遗留竞态/未验证项：success 场景 provider 启动竞态（Task 3 记录，1500ms settle 缓解）、
  I1（providerUnavailable/resultUnknown 绕过真实手势链路）、CI hosted runner 行为未验证。
  Step 3/4（CI 质量门、提交与 PR）留待主线程。
- **2026-08-08（Task 4 完成）**：leaseExpiry 点击后固定等待改为 `waitForTabs` 轮询 source URL 更新（15s 超时，消除 `TargetInfo.url` 延迟误报）；顺带修复"success 后 guard arm 路由到目标 tab 而非 source"的路由缺陷（runner 先激活 fixture tab）；补 guard trace 断言（I2）——经 Foundation 参数域开启扩展诊断日志，CDP 附着 SW 读 `chrome.storage.local` 的 `gesturekitDiagnostics`，用 `forwarding`+`forwarded:guard_armed` 证明 guard 曾被 arm、无 `click_blocked`/`lease_expired` 证明点击未被拦截。实测发现 content script 回发的 `armed` 阶段与 background 并发持久化竞态丢失（`appendDiagnostic` lost-update），断言改用等价的 `forwarded:guard_armed`；**未改生产 background/content script**。node e2e 38→60 绿、`npm test` 176 绿、真实 Chrome headless 四场景全过（leaseExpiry `lease_released`、source 原地导航、无新 tab、guard trace 通过）。修订 `troubleshooting.md`/`e2e-checklist.md` 的 leaseExpiry 语义与 I2 缺口描述。
- **2026-08-08（Task 3 完成）**：success 场景 active 检测改为经 CDP 附着扩展 SW 执行 `chrome.tabs.query({active:true})`（替换 `document.hasFocus()`），按 URL + `pendingUrl` 匹配（真实运行发现 chrome.tabs `url` 在导航 commit 前为空、目标在 `pendingUrl`）；点击后改为轮询等待目标 tab URL 更新（替换固定 1500ms）。Task 3 Step 1-3 完成并记录结论。记录残留项：provider 启动竞态（SW→Host→App 会话建立晚于场景 1 启动，偶发 success 误报 source_navigated，已用 1500ms settle 缓解）；leaseExpiry 仍失败（example.test 导航 URL 更新延迟 vs 1500ms 等待偏紧，Task 4 处理）。探针确认经 CDP 从 SW 自身上下文 sendMessage 不会递到 SW 自身监听器，`waitForProviderConnected` 方案废弃。
- **2026-08-07（Task 1 探针执行后修正）**：根因 1-3 由探针实测修正——主根因实为品牌 Chrome 142+ 移除 `--load-extension`（`Extensions.loadUnpacked` 为可用替代，Task 1 已验证完整副本可加载 + content script 注入）；根因 2"ID 路径推导/忽略 key"是误读（含 key 扩展 ID 即 key 推导，`fignfifoniblkonapihmkfakmlgkbkcf` 为 Google Network Speech 组件 ID）；根因 3"profile 级 manifest 不被读取"相反（`DIR_USER_NATIVE_MESSAGING` 随 user-data-dir 推导，profile 级被读取）。Task 1 Step 1-3 完成并记录探针结论；Task 2 Step 1/2/3 相应更新（loadUnpacked 加载、key 推导 allowed_origins、manifest 位置不变）；Task 4 补充 `example.test` 导航 `TargetInfo.url` 更新延迟提醒。Task 5 由并行代理完成（删除 bridge/stub，`npm test` 176 绿）。
- **2026-08-07（架构审核后修正）**：根因列表补主根因"扩展未加载（manifest 未拷入临时目录 + dist 布局不匹配）"，更正根因 5"leaseExpiry 语义"的前提错误（`linkClickProtectionEnabled` 生产恒 false）；废弃方案 B（`--load-extension` 忽略 key）；Task 2 新增扩展加载修复前置、独立 host 名优先；Task 3 明确 CDP 附着 service worker 取真实 active；Task 5 补全删除清单；验收标准加扩展可加载性与 guard trace 断言。审核范围：仅本次补充/修正部分做最终审查。
