# GestureKit V1 当前进度归档

日期：2026-07-08

更新日期：2026-07-09

相关文档：

- `docs/product/gesturekit-v1-contract.md`
- `docs/product/gesturekit-v1-requirements.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
- `docs/plans/gesturekit-v1-optimization-roadmap.md`
- `docs/plans/gesturekit-p3-installation-connectivity-plan.md`
- `docs/operations/gesturekit-v1-local-install.md`
- `docs/operations/gesturekit-v1-e2e-checklist.md`
- `docs/operations/gesturekit-v1-troubleshooting.md`

## 1. 当前状态

当前分支：

```text
plan/v1-spikes
```

当前已提交 HEAD：

```text
345e0ac docs: clarify smoke check phases
```

当前阶段：

```text
P4 推荐应用闭环已完成；准备进入 P5 菜单栏状态与生命周期加固
```

当前工作结论：

- `P4` 已把推荐结果推进到"可显式应用、可确认是否真正生效"的闭环。
- `P5` 尚未开始实现；当前只有路线图和方向约束。

## 2. 已完成并提交的工作

截至本次归档，已经完成：

- V1 契约、需求、技术设计、ADR 和正式产品实现计划基线。
- GestureKit App / GestureKitHost / GestureKitCore / Chrome extension 的正式代码骨架。
- 轻扫灵敏度、扩展 popup、诊断面板、推荐档位与推荐最小距离能力。
- `P3` 安装与验收闭环：
  - native host manifest 渲染脚本；
  - native host 安装脚本；
  - `probe_request` / `probe_response` 连通探针；
  - `smoke.html` dev smoke 页面；
  - `smoke-check.sh` 开发入口；
  - 中文本地安装说明、E2E 清单和排障文档。

## 3. P3 归档

### 3.1 P3 目标

`P3` 的目标是把 GestureKit 的本地安装、连接配置和基础验收流程收敛成低摩擦、可重复、可诊断的闭环，不新增任何用户手势能力。

### 3.2 P3 已完成内容

已完成 4 个任务：

1. `Task 1`：native host manifest 渲染脚本
2. `Task 2`：native host 安装脚本
3. `Task 3`：extension -> native host -> App IPC 连通探针
4. `Task 4`：`smoke-check` 命令与运维文档收口

当前关键产物：

- `scripts/dev/render-native-host-manifest.sh`
- `scripts/dev/install-native-host.sh`
- `scripts/dev/smoke-check.sh`
- `extensions/chrome/smoke.html`
- `extensions/chrome/src/background/connectionProbe.ts`
- `docs/operations/gesturekit-v1-local-install.md`
- `docs/operations/gesturekit-v1-e2e-checklist.md`
- `docs/operations/gesturekit-v1-troubleshooting.md`

### 3.3 P3 关键提交记录

```text
345e0ac docs: clarify smoke check phases
552bb48 docs: align smoke check swift entrypoint
458b03e docs: update task 4 report
9c2ff24 docs: close p3 installation workflow
d30b388 feat: add connectivity probe
7dfaf73 fix: make native host install atomic
499ef9a feat: add native host installer command
617f93e fix: escape native host manifest json
acf8992 feat: add native host manifest renderer
```

### 3.4 P3 已通过验证

脚本与安装链路：

```bash
zsh scripts/dev/test-render-native-host-manifest.sh
zsh scripts/dev/test-install-native-host.sh
zsh scripts/dev/test-smoke-check.sh
```

结果：通过。

Swift 与 native host：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test
```

结果：通过。

Chrome extension：

```bash
cd extensions/chrome
npm test
npm run build
```

结果：通过。

连通探针：

- 已增加 `probe_request` / `probe_response` 协议类型；
- 已增加 App 侧 `probe_request` 回复路径；
- 已增加 `chrome-extension://<id>/smoke.html` 作为 dev smoke 页面；
- 已把安装文档拆成“阶段一：预检查”和“阶段二：连通性探针”。

### 3.5 P3 当前结论

`P3` 已完成当前目标，当前仓库已经具备：

- 可生成且可安装的 native host manifest；
- 可通过固定命令验证 host、extension 和 App IPC 链路；
- 可区分“预检查成功但 App 尚未启动”与“真正连接失败”；
- 可通过中文文档完成安装、预检查和排障。

`P3` 当前已知限制：

- 当前环境默认 `swift` 可能指向 Command Line Tools；仓库当前验证以
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  为正式 Swift 入口。
- `smoke-check.sh` 负责预检查和打开 smoke 页面，不负责自动启动 `GestureKitApp`。
- smoke 页面是否真正显示 `connected`，仍依赖 App 已单独启动。

## 4. P4 归档

### 4.1 P4 目标

`P4` 的目标是把当前”只读展示推荐档位/推荐最小距离”推进到”用户可以显式应用推荐设置，并且知道应用结果是否真实生效”的闭环。

### 4.2 P4 已完成内容

已完成 5 个 Task：

1. `Task 1`：协议契约与 App 会话标识 — `ProbeResponsePayload` 和 `SettingsAckPayload` 新增 `appSessionId`；Runtime 生成稳定 UUID 会话号
2. `Task 2`：扩展侧推荐设置模型与有效阈值解析 — `SwipeRecognitionOverride` 类型、`resolveEffectiveSwipeRecognition`、`buildRecommendedSettings`、`describeRecognitionDelta`
3. `Task 3`：后台同步状态机与 stale/failed 语义 — 五态模型 `saved_only | pending | applied | failed | stale`，完整状态迁移链路
4. `Task 4`：popup 推荐应用、确认与诊断 delta 展示 — 推荐卡片渲染、显式确认流程、状态分离展示、诊断 delta 输出
5. `Task 5`：文档、全量验证与收口 — 验收清单、排障文档更新

当前关键产物修改/新增：

- `Sources/GestureKitCore/Protocol/GestureKitMessage.swift`
- `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- `extensions/chrome/src/settings/swipeRecognition.ts` (新增)
- `extensions/chrome/src/settings/gestureSettings.ts`
- `extensions/chrome/src/background/settingsSync.ts`
- `extensions/chrome/src/background/background.ts`
- `extensions/chrome/src/background/connectionProbe.ts`
- `extensions/chrome/src/protocol/messages.ts`
- `extensions/chrome/src/popup/popup.ts`
- `extensions/chrome/src/popup/popup.css`
- `extensions/chrome/src/diagnostics/diagnostics.ts`
- `extensions/chrome/popup.html`
- `docs/operations/gesturekit-v1-e2e-checklist.md`
- `docs/operations/gesturekit-v1-troubleshooting.md`

### 4.3 P4 关键提交记录

```text
afee405 feat: add recommendation apply flow in popup
883a7a9 feat: track recommendation apply sync state
84707f4 feat: add recommendation-aware swipe settings
278a120 feat: add app session to settings ack
```

### 4.4 P4 已通过验证

Swift 与 native host：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # 41 passed
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build  # Build complete
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test  # self-test passed
```

Chrome extension：

```bash
cd extensions/chrome
npm test       # 97 passed
npm run build  # Build complete
```

### 4.5 P4 当前结论

`P4` 已完成当前目标：

- 用户能在 popup 中看见推荐并主动应用；
- 推荐应用结果在 UI 和诊断摘要中可见；
- 推荐失败不允许静默处理，必须返回明确原因；
- “已保存”与”已应用”状态语义明确，不会把最后一次 ack 误显示成持久生效；
- 推荐应用不突破规则 source of truth 边界；
- `appSessionId` 作为跨端状态锚点已落地。

## 5. P5 修改方向

`P5` 聚焦菜单栏状态增强、排障入口和生命周期加固，不重写手势识别主流程。

## 6. 恢复开发时的建议步骤

如果从本次归档恢复，建议按以下顺序继续：

1. 运行：

   ```bash
   git status --short
   git log --oneline --decorate -6
   ```

2. 先确认 `P3` 入口仍可工作：

   ```bash
   zsh scripts/dev/test-render-native-host-manifest.sh
   zsh scripts/dev/test-install-native-host.sh
   zsh scripts/dev/test-smoke-check.sh
   ```

3. 阅读 `P5` 方向文档：

   ```bash
   sed -n '110,135p' docs/plans/gesturekit-v1-optimization-roadmap.md
   ```

4. 再开始写 `P5` 的独立实施计划或直接进入 `P5` 执行。

## 7. 已知后续事项

- `P5` 仍需独立实施计划或执行分解。
- 当前 `smoke-check.sh` 的职责是”预检查入口 + 打开 smoke 页面”，不是完整自动化 E2E。
- `pyenv: cannot rehash ... isn't writable` 仍可能在 `npm` 命令中出现警告，但当前不阻塞通过。

## 8. 暂停时的原则

- 不纳入 `.obsidian/`。
- 项目文档继续保持中文优先。
- `P4` 前不回退已完成的 `P3` 安装链路。
- 审核仍以 `docs/product/gesturekit-v1-contract.md` 为最高项目契约。
