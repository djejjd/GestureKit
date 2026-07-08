# GestureKit V1 当前进度归档

日期：2026-07-08

更新日期：2026-07-08

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
P3 安装与验收闭环已完成；准备进入 P4 推荐应用闭环
```

当前工作结论：

- `P3` 已把 native host manifest 生成、安装、extension 到 App 的连通探针、以及安装/排障文档收口成可重复流程。
- `P4` 尚未开始实现；当前只有路线图和方向约束，没有新的代码或文档提交。

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

## 4. P4 修改方向

### 4.1 P4 目标

`P4` 的目标不是继续扩诊断展示，而是把“推荐结果”推进到“可显式应用、可确认是否真正生效”的闭环。

### 4.2 P4 主要修改方向

`P4` 主要收在 4 条线上：

1. 推荐应用入口
   - 在 popup 中增加“应用推荐设置”入口。
   - 入口只针对轻扫灵敏度和相关阈值，不扩展到动作绑定。

2. 应用前确认
   - 应用前要有显式确认，不做静默自动修改。
   - 保持当前规则 source of truth 不变。

3. 应用后状态语义
   - 明确区分“已保存到 extension 设置”和“App 运行时已应用”。
   - 明确 `settings_ack` 的语义，不把最后一次 ack 误显示成持久生效。

4. 失败与恢复路径
   - host 断开、App 未运行、ack 缺失、App 重启后状态不一致，都要有明确反馈。
   - 复制诊断时补充“当前设置 vs 推荐设置”的差异摘要。

### 4.3 P4 主要改动位置

预计主要改动这些位置：

- `extensions/chrome/src/popup/popup.ts`
- `extensions/chrome/popup.html`
- `extensions/chrome/src/background/settingsSync.ts`
- `extensions/chrome/src/settings/gestureSettings.ts`
- `extensions/chrome/src/diagnostics/diagnostics.ts`
- `extensions/chrome/tests/popup.test.ts`
- `extensions/chrome/tests/settingsSync.test.ts`
- `extensions/chrome/tests/gestureSettings.test.ts`
- `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- `Tests/GestureKitAppTests/RuntimeSettingsTests.swift`

### 4.4 P4 不做的内容

`P4` 不做：

- 不新增新的用户手势动作；
- 不做规则编辑器；
- 不把 extension 设置扩成任意动作绑定；
- 不做自动应用推荐；
- 不扩到多浏览器支持；
- 不在本阶段做菜单栏 UI 加固或开源整理。

## 5. 恢复开发时的建议步骤

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

3. 阅读 `P4` 方向文档：

   ```bash
   sed -n '1,220p' docs/plans/gesturekit-v1-optimization-roadmap.md
   ```

4. 再开始写 `P4` 的独立实施计划或直接进入 `P4` 执行。

## 6. 已知后续事项

- `P4` 仍需独立实施计划或执行分解，不建议直接从口头方向进入多文件实现。
- 当前 `smoke-check.sh` 的职责是“预检查入口 + 打开 smoke 页面”，不是完整自动化 E2E。
- `pyenv: cannot rehash ... isn't writable` 仍可能在 `npm` 命令中出现警告，但当前不阻塞通过。

## 7. 暂停时的原则

- 不纳入 `.obsidian/`。
- 项目文档继续保持中文优先。
- `P4` 前不回退已完成的 `P3` 安装链路。
- 审核仍以 `docs/product/gesturekit-v1-contract.md` 为最高项目契约。
