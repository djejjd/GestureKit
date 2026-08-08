# CLAUDE.md（中文参考版）

> AI 使用英文版 `CLAUDE.md`，本文件仅供人类阅读参考。

## 构建、测试与运行

```bash
# Swift（macOS 15, Swift 6.2）
swift build
swift test
swift test --filter TestSuiteName    # 单个测试套件
swift test --filter testMethodName   # 单个测试方法
swift run GestureKitApp              # 启动菜单栏 App
swift run GestureKitHost --self-test # Native Host 自检

# Chrome 扩展
cd extensions/chrome
npm install
npm test                  # vitest（jsdom 环境）
npm test -- --run tests/file.test.ts  # 单个测试文件
npm run build             # esbuild 打包
```

如果 Xcode 命令行工具不是默认项，Swift 命令前加 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

调试手势识别：`GESTUREKIT_DEBUG=1 swift run GestureKitApp`。

日志路径：`~/Library/Logs/GestureKit/GestureKitApp.log`（单文件 1MB，最多保留 3 个轮转文件）。

## 架构：三层手势→浏览器管线

GestureKit 是面向 Chrome 的 macOS 触控板手势工具，由三个进程通过协议链连接：

```
触控板硬件
  → MultitouchSupportBackend（私有框架，通过 OpenMultitouchSupport 封装）
  → GestureRecognizer（识别原语：点按/轻扫、三指、区域、时长）
  → RuleEngine / BindingResolver（手势 + 上下文 → ActionDescriptor）
  → ProviderRouter → 认证 IPC → Native Host Shim → Chrome Native Messaging
  → Chrome 扩展（ActionProvider：执行 browser.tabs / browser.link 动作）
```

**核心设计原则**：`GestureKitCore` 共享库不得引用 `chrome.tabs`、Chrome 专用动作枚举或 `connectNative()`。手势识别与手势含义解耦——"三指左滑"是原语，映射为"切换到下一个标签页"发生在 `BindingResolver` 中，以标准 `ActionDescriptor` 表达（如 `browser.tab.activate_next`）。

## 包/目标映射

| 目标 | 路径 | 职责 |
|---|---|---|
| `GestureKitCore`（库） | `Sources/GestureKitCore/` | 共享层：手势识别、规则引擎、IPC 协议、设置存储、Provider Protocol v2 模型 |
| `GestureKitApp`（可执行） | `apps/macos/GestureKitApp/Sources/GestureKitApp/` | macOS 菜单栏 App、控制中心 UI、运行时循环、操作日志、Provider 会话 |
| `GestureKitHost`（可执行） | `native-host/gesturekit-host/Sources/GestureKitHost/` | Chrome Native Messaging stdio ↔ App IPC 透明桥接 |
| `GestureKitCoreTests` | `Tests/GestureKitCoreTests/` | Core 层单元测试 |
| `GestureKitAppTests` | `Tests/GestureKitAppTests/` | App 层单元测试 |
| Chrome 扩展 | `extensions/chrome/` | MV3 扩展：后台 Service Worker、内容脚本、popup |
| 探针程序（4 个） | `spikes/` | 独立研究用可执行程序：触控板输入、IPC、TCC 权限、交互屏蔽 |

## Provider Protocol v2（关键抽象）

定义于 `Sources/GestureKitCore/Provider/ProviderProtocolV2.swift`。App 与任意 ActionProvider 之间的双向类型化协议：

- **17 种消息类型**，严格的 type↔payload 映射（fail-closed 解码——未知组合直接拒绝）
- **7 个标准动作 ID**：`browser.link.open_adjacent`、`browser.tab.activate_previous/next`、`browser.tab.close_current`、`browser.history.back/forward`、`browser.page.reload`
- **3 种终态结果**：`succeeded`、`failed`、`result_unknown`
- JSON Schema 位于 `packages/protocol/schemas/`，TypeScript 类型位于 `extensions/chrome/src/provider/protocol.ts`

Chrome adapter 在内部将旧版 `GestureKitMessage`（version:1）转换为 v2；v2 是前进方向。

## 操作日志与证据链

每次三指候选产生一个 `gestureSessionId` 和完整证据链，持久化在 SQLite WAL 中（`apps/.../OperationJournal.swift`）：
- 追加式阶段事件，包含唯一 `eventId`、单调递增的 `producerSequence`
- 受管理存储预算 50MB（App 45MB，Chrome Provider 5MB），7 天保留
- 证据包导出：包含 manifest、脱敏页面指纹、阶段时间线
- 双重脱敏：Provider 采集源脱敏 → App 入库再次校验脱敏，均须去除 query/hash、Cookie、DOM 文本

Chrome 扩展侧以 IndexedDB operation ledger + telemetry outbox 对应，支持离线恢复。

## V1 → V2 迁移（当前状态）

项目处于 V1 到 V2 的重构中期。关键权力转移：

- **配置主权**：App `SettingsStore` 为唯一写入方；扩展 popup 变为只读上下文展示
- **诊断存储**：从扩展环形缓冲区迁移到 App `OperationJournal`
- **IPC**：从广播模式升级为认证 Provider 会话 + 按安装凭据定向路由
- **UI**：App 新增 6 页控制中心窗口；菜单栏只保留生命周期 + 持续故障；popup 仅显示页面上下文 + 连接状态

实施顺序：`Task 1/2/2A（Spike）→ Task 3（协议定义）→ Task 4（操作日志）→ Task 5（认证 IPC）→ Task 10A（UI 框架搭建）→ Task 6/7（账本/会话）→ Task 8（Chrome 守护/动作）→ Task 9（配置迁移）→ Task 10B（UI 数据接入）→ Task 11（端到端验收/清理）`。

完整计划：`docs/plans/v2/可靠性平台-实施计划.md`
UI 契约：`docs/architecture/v2-UI信息架构.md`
架构决策：`docs/adr/0001-使用原生宿主中间层.md` 至 `0003`

## 关键约定

- 面向用户的文案和代码注释使用中文；协议字段、路径、API 名称保持英文
- 每个任务遵循 TDD：先写失败测试 → 确认失败 → 最小实现 → 全量套件通过 → 提交
- `RuleEngine` 是唯一动作决策入口；`BindingResolver` 为内部实现——Provider 不得修改 `actionId`
- 每个 `operationId` 的副作用最多执行一次；结果不确定时触发对账，绝不自动重放
- `guard_armed` 是 `browser.link.open_adjacent` 的硬性前置条件——链接点按动作必须在其就绪后才能派发

## 工作流程规范

**第一步：问题分析。** 当被问到 bug、功能或架构问题时——先追踪相关代码路径，呈现根因。此阶段不做实现、不提修改方案、不改代码。

**第二步：方案设计。** 在用户确认根因后，提出具体方案：改哪些文件、每个文件改什么、为什么。涉及 3 个以上文件或触及协议边界的改动，先起 agent 审核方案可行性和边界情况。

**第三步：用户确认。** 得到明确同意前不得写代码。"看起来合理""可以""做吧"等肯定答复即可——但绝不默认。

**第四步：实施。** 确认后按 TDD 执行：写失败测试 → 确认失败 → 实现 → 全量通过。

## 行为记录

| 日期 | 错误行为模式 | 整改措施 |
|---|---|---|
| 2026-07-14 | 跳过根因呈现和方案确认，直接开始改代码。 | 新增上方工作流程规范（第1-4步）。代码已回退。 |

## 日志规范

`GestureKitLogger` 有 4 个级别：`debug`、`info`、`warn`、`error`。

- **debug** — 仅在诊断日志开启时输出（设置开关或 `GESTUREKIT_DEBUG=1`）。适用于：逐帧触控数据、时序明细、内部状态迁移、协议消息原文、context 请求/响应字段。任何在正常运行中属于噪音的内容均应归入此类。
- **info** — 仅写入日志文件（终端不显示）。适用于：手势识别结果（成功和被拒绝的都要记）、动作分发/结果、Provider 连接状态变更、设置已应用。
- **warn** — 写入文件 + 终端。适用于：瞬态故障（Provider 不可用、context 发送失败、超时）、意外的协议消息、可自恢复的降级运行。
- **error** — 写入文件 + 终端。适用于：启动失败、后端崩溃、日志写入失败、永久能力丧失。

选择依据：如果不用调试模式也需要这条日志来回答"刚才发生了什么"——用 `info`/`warn`/`error`。如果只在主动排查具体问题时有用——用 `debug`。正常运行中可能每秒触发多次的日志必须加 `rateLimitKey`，防止日志淹没。
