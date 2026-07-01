# GestureKit V1 当前进度归档

日期：2026-06-24

更新日期：2026-07-01

## 1. 当前状态

当前分支：

```text
plan/v1-spikes
```

当前已提交 HEAD：

```text
6f6dcb4 feat: add trackpad input spike
```

当前阶段：

```text
正式开发前 spike 验证
```

本次归档后暂停继续开发。后续恢复时，应先从本文件和 `git status --short` 开始。

## 2. 已完成并提交的工作

已完成：

- V1 设计文档基线。
- 项目设计开发契约。
- 正式开发前路线图。
- 三份 ADR：
  - 使用独立 native host shim。
  - 使用 extension 记录最近 pointer 位置。
  - V1 即引入窄规则引擎。
- V1 正式开发前 spike 执行计划。
- 项目基础骨架。
- 共享 Native Messaging 协议 schema。
- Native Messaging host spike。
- Chrome link hit-test spike。
- Chrome extension build 修复，使 manifest 指向可加载的 build 输出。
- 文档中文优先规则已写入契约，并已把当前用户可见 README 转为中文优先。
- Trackpad input spike 已提交，OpenMultitouchSupport backend 可以启动监听并输出三指候选事件。

## 3. 关键提交记录

```text
6f6dcb4 feat: add trackpad input spike
797665d docs: archive v1 spike progress
454f2a7 fix: bundle chrome content script for manifest loading
470499b docs: enforce Chinese-first project documentation
9b6c084 fix: make chrome link hit-test spike loadable
ab801c5 fix: make native message decode alignment-safe
a5ce32b feat: add chrome link hit-test spike
e539f17 feat: add native messaging host spike
ae790c6 feat: define v1 native message protocol
71f506e fix: avoid empty Swift test target in foundation
bde24d4 chore: add project foundation
13318ca docs: add v1 spike implementation plan
d7d3930 docs: add GestureKit v1 design baseline
```

## 4. 已通过的验证

Native host：

```bash
swift run GestureKitHost --self-test
```

结果：通过。当前 self-test 覆盖：

- encode/decode happy path。
- too-short input。
- length mismatch。
- host response frame round trip。

Chrome extension：

```bash
cd extensions/chrome
npm test
npm run build
npx tsc --noEmit
```

结果：通过。

当前 `dist/content/pointerTracker.js` 由 esbuild 以 IIFE 输出，没有顶层 `import` / `export`，可作为 manifest content script 加载。`dist/background/nativePort.js` 保持 ESM，manifest 使用 `"type": "module"`。

## 5. 审核状态

Task 1：项目基础骨架

- spec 审核通过。
- code quality 审核发现空 Swift test target 问题。
- 已修复：Task 1 不再声明空 test target。

Task 2：共享协议 schema

- spec 审核通过。
- code quality 审核通过。
- 非阻塞建议：后续 codec 应按 `type` 分发到具体 schema，而不是只校验 envelope。

Task 3：Chrome link hit-test spike

- 初始审核发现扩展不可加载问题。
- 已修复：
  - 增加 background simulated gesture bridge。
  - manifest 改为指向 build 输出。
  - 使用 esbuild 将 content script 打包为 IIFE。
- 复审通过。

Task 4：Native Messaging host spike

- 初始审核发现 `Data` 上 `rawBuffer.load(as:)` 存在未对齐内存风险。
- 已修复：按字节组装 little-endian `UInt32`。
- 复审通过。

## 6. 当前未提交工作

当前没有项目代码或项目文档 WIP。

当前未跟踪文件：

```text
?? .obsidian/
```

说明：`.obsidian/` 是本地编辑器配置，未纳入项目提交。

## 7. Task 5 当前发现

Task 5 已经提交。它调研到 OpenMultiTouchSupport 当前上游信息，并写入中文研究笔记。

关键发现：

- 上游仓库：`https://github.com/Kyome22/OpenMultiTouchSupport.git`
- 当前 HEAD：`15c6bb0c6a2d2858559493a28ab23f7ac58648a3`
- package product name：`OpenMultitouchSupport`
- import module name：`OpenMultitouchSupport`
- 监听入口：`OMSManager.shared`
- 启动监听：`OMSManager.startListening() -> Bool`
- 停止监听：`OMSManager.stopListening() -> Bool`
- 事件入口：`OMSManager.touchDataStream`
- app-facing event callback type：`any AsyncShareStream<[OMSTouchData]>`
- 上游要求：
  - `swift-tools-version: 6.2`
  - macOS 15+
  - Xcode 26.2+
  - App Sandbox 关闭

当前 `Package.swift` 已被改为 Swift 6.2 / macOS 15，并添加 OpenMultiTouchSupport 依赖。这是一个重要设计影响点，进入正式开发前必须确认是否接受。

已完成验证：

- `swift build` 通过。
- `swift run TrackpadInputProbe` 能启动默认 multitouch listener。
- probe 能输出 `[candidate:three_finger_tap]`。
- 使用 `Ctrl-C` 后能打印 `device_status=listener_stopped stopped=true`。

仍需补齐：

- `docs/research/trackpad-gesture-stability-matrix.md` 中的人工稳定性矩阵。

## 8. 恢复开发时的建议步骤

恢复时按以下顺序继续：

1. 运行：

   ```bash
   git status --short
   ```

2. 确认当前 HEAD 包含 Task 5：

   ```bash
   git log --oneline --decorate -5
   ```

3. 阅读手势稳定性矩阵：

   ```bash
   sed -n '1,260p' docs/research/trackpad-gesture-stability-matrix.md
   ```

4. 判断是否接受 OpenMultiTouchSupport 当前上游带来的最低要求：

   ```text
   Swift 6.2
   macOS 15+
   Xcode 26.2+
   App Sandbox 关闭
   ```

5. 若接受，继续人工稳定性验证：

   ```bash
   swift build
   swift run TrackpadInputProbe
   ```

6. 若不接受，先调整触控板输入方案，不进入正式开发。

7. 手势稳定性矩阵完成后，回到契约和技术设计做正式开发前修订。

## 9. 已知后续事项

- `docs/plans/gesturekit-v1-implementation-plan.md` 的 Task 4 代码片段曾滞后于实际 self-test 修复，后续 Task 6 应整体校验计划与实现一致性。
- npm install 曾报告 dev dependency audit 风险。当前作为 spike 非阻塞，未执行 `npm audit fix --force`，避免引入破坏性升级。
- 后续审核必须检查文档是否中文优先；代码、API、命令、协议字段保持英文原样。
- 手势稳定性矩阵完成前，不进入正式产品实现。

## 10. 暂停时的原则

- 不纳入 `.obsidian/`。
- 后续恢复时先完成手势稳定性矩阵，再继续正式设计开发。
- 审核仍以 `docs/product/gesturekit-v1-contract.md` 为最高项目契约。
