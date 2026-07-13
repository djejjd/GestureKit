# GestureKit

GestureKit 是一个面向 Google Chrome 的 macOS 触控板手势工具。

它由一个 macOS 原生 App、一个 Chrome MV3 扩展和一个 Native Messaging host 组成，用触控板手势执行常用标签页操作。

当前项目仍处于本地开发和自用实验阶段。它还没有做打包、签名、公证，也不适合作为通用发行版安装。

English version: [English](#english)

## 手势

当前支持的 Chrome 手势：

- 三指点按链接：在当前标签页右侧打开新标签页，并自动切换过去。
- 三指点按空白处左侧边缘：切换到左侧标签页。
- 三指点按空白处右侧边缘：切换到右侧标签页。
- 三指双击空白处中间区域：关闭当前标签页。
- 三指快速左轻扫：切换到右侧标签页。
- 三指快速右轻扫：切换到左侧标签页。

标签页切换只作用于当前 Chrome 窗口。到达最左或最右标签页时会循环切换。

点按类手势会过滤异常短触和动作后的短暂抖动。左/右切 tab 只认触控板边缘区域（左 20%、右 20%），中间单点用于链接检测，中间双点才关闭 tab。关闭 GestureKit 打开的新标签页时会优先回到来源标签页；没有来源标签页时优先切到左侧标签页，最左侧则切到右侧标签页。左右轻扫按 macOS Spaces 的内容移动语义适配：手指向右滑会把左侧内容带过来，因此切到左侧标签页；手指向左滑则切到右侧标签页。左右轻扫只识别短促的 flick，约 `50ms-480ms` 的短促横向动作；可在控制中心调整灵敏度。慢速三指拖动会被判为不稳定手势，以减少 Chrome 页面文本被拖选的情况。

链接点击保护（"防止链接原地跳转"）默认开启。三指放在链接上时，content script 拦截普通点击（约 500ms 保护窗口），等待 App 确认三指点按；确认后阻止当前页原地跳转，并由扩展打开新标签页并切换到它。保护不处理带 Command/Control/Shift/Option 的点击、`target` 非 `_self` 的链接、下载链接和非 `http/https` 链接。保护窗口过期后自动放行导航。

## 架构

### 分层管线

```
触控板硬件
  → MultitouchSupportBackend（私有框架，经 OpenMultitouchSupport 封装）
  → GestureRecognizer（识别原语：点按/轻扫、三指、时长、坐标）
  → GestureSessionCoordinator（区域分类 + 双击仲裁，输出 6 种 ComposedGesture）
  → BindingResolver / RuleEngine（ComposedGesture + 上下文 → ActionDescriptor）
  → ProviderRouter → 认证 IPC → Native Host Shim → Chrome Native Messaging
  → Chrome ActionProvider（执行浏览器动作）
```

三指候选从开始阶段建立统一证据链，每个阶段事件持久化在 SQLite OperationJournal 中。

### 组件

| 组件 | 职责 |
|---|---|
| `GestureKitApp` | macOS 菜单栏 App，6 页控制中心 UI。触控板采集、手势识别、规则引擎、操作日志、Provider 会话管理 |
| `GestureKitHost` | Chrome Native Messaging stdio ↔ App IPC 透明桥接 |
| `GestureKitCore` | Swift 共享库：手势模型、规则引擎、IPC 协议、Provider Protocol v2 类型、设置存储 |
| `extensions/chrome` | Chrome MV3 扩展，V1 首个 ActionProvider。包含 content script（页面交互保护）、background Service Worker（Provider 会话、动作执行、离线账本） |
| `OperationJournal` | App 端 SQLite WAL 持久化存储。追加式阶段事件，50MB / 7 天管理预算，支持脱敏证据包导出 |

### Provider Protocol v2

App 与 Chrome 扩展之间使用双向类型化的 v2 协议（17 种消息类型，7 个标准动作 ID）。认证握手使用安装凭据 HMAC + random challenge。动作只能由已认证 Provider 会话定向路由，不广播。

- JSON Schema：`packages/protocol/schemas/`
- Swift 模型：`Sources/GestureKitCore/Provider/ProviderProtocolV2.swift`
- TypeScript 类型：`extensions/chrome/src/provider/protocol.ts`

### V1 → V2 迁移状态

项目处于 V1 到 V2 的重构中期。关键变化：

- 用户配置统一由 App `SettingsStore` 持有（旧 popup 写入入口已移除）
- Chrome 扩展升级为通用 ActionProvider（Protocol v2）
- 诊断存储从扩展环形缓冲区迁移到 App OperationJournal
- App 从纯菜单栏升级为菜单栏 + 6 页控制中心窗口
- 手势识别升级为原语 → 组合 → 规则绑定分层模型

当前支持的 6 种手势绑定在 `DefaultRules.v1Bindings` 中定义。后续可通过配置替换 `BindingResolver` 实现自定义手势映射。

## 控制中心

macOS App 提供 6 页控制中心窗口，通过菜单栏图标打开：

1. **概览**：运行状态、Provider 连接、最近操作、待处理问题
2. **操作记录**：操作时间线，终态筛选，用户可理解原因，脱敏证据包导出
3. **手势预设**：当前预设与标准手势映射
4. **Provider**：连接状态、能力摘要、配置应用状态、重新连接入口
5. **隐私与存储**：保存内容说明、双重脱敏、存储用量、保留策略
6. **高级设置**：系统权限说明、配置迁移、Provider 凭据管理

## Popup

Chrome 工具栏中的 GestureKit popup 仅显示当前页面上下文，**不再承载设置写入、推荐或诊断展示**：

- 当前页面是否支持手势
- App 和 Chrome Provider 连接状态
- 当前手势预设名称
- 当前页面最近一次操作结果
- 打开 GestureKit 控制中心

## 环境要求

- macOS 15 或更新版本
- 兼容 Swift 6.2 的 Xcode / Swift 工具链
- Google Chrome
- Chrome Developer Mode，用于加载 unpacked extension

GestureKit 当前通过 `OpenMultitouchSupport` 使用私有触控板输入路径。它适合本地实验，不适合 Mac App Store 分发。

## 构建

```bash
swift build

cd extensions/chrome
npm install
npm run build
```

## 本地安装

1. 打开 `chrome://extensions`。
2. 开启 Developer mode。
3. 选择 Load unpacked，并选择 `extensions/chrome`。
4. 复制扩展 ID。
5. 编辑 `spikes/native-messaging/host-manifest/com.gesturekit.host.json`：
   - 把 `path` 改成 `.build/debug/GestureKitHost` 的绝对路径。
   - 把 `allowed_origins` 改成你的 Chrome 扩展 ID。
6. 复制 manifest 到 Chrome Native Messaging host 目录：

```bash
mkdir -p "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
cp spikes/native-messaging/host-manifest/com.gesturekit.host.json \
  "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.gesturekit.host.json"
```

启动 App：

```bash
swift run GestureKitApp
```

重新构建 Chrome 扩展后，需要到 `chrome://extensions` 手动刷新 GestureKit 扩展。

## 日志

运行日志保存在：

```text
~/Library/Logs/GestureKit/GestureKitApp.log
```

日志级别：`error` / `warn` 始终输出到终端；`info` 仅写文件；`debug` 仅在诊断模式开启时输出。

诊断模式：

```bash
GESTUREKIT_DEBUG=1 swift run GestureKitApp
```

或在控制中心设置中启用诊断日志开关。调试手势识别时建议开启。

日志文件有大小限制和轮转机制：单文件约 1 MB，最多保留 3 个文件，不记录原始触控板帧。

## 测试

```bash
swift test
swift build
swift run GestureKitHost --self-test

cd extensions/chrome
npm test
npm run build
```

## 主要文档

- [V1 契约](docs/product/gesturekit-v1-contract.md)
- [V2 UI 信息架构](docs/architecture/gesturekit-v2-ui-information-architecture.md)
- [可靠性、可观测性与可扩展动作平台架构](docs/architecture/gesturekit-reliability-observability-platform-architecture.md)
- [V2 UI 框架实施计划](docs/plans/gesturekit-v2-ui-scaffold-plan.md)
- [实施计划](docs/plans/gesturekit-reliability-platform-implementation-plan.md)
- [架构决策记录](docs/adr/)
- [本地安装说明](docs/operations/gesturekit-v1-local-install.md)
- [端到端验收清单](docs/operations/gesturekit-v1-e2e-checklist.md)

## 后续方向

- 第二个真实 Provider（Edge / Safari 等浏览器支持）
- 简单动作换绑 UI / 自定义手势组合
- Provider 安装、分发和市场
- 原生 InteractionShield（CGEventTapShield）接入
- 完善安装脚本、发布说明和开源贡献文档

## 开源边界

仓库中应该包含：

- Swift App、Native Host、GestureKitCore 和 Chrome 扩展源码。
- Swift / TypeScript 测试、协议 fixtures、架构文档、安装说明和研究记录。
- 不包含本机路径、密钥、个人扩展 ID 的模板配置。

仓库中不应该包含：

- `.build/`、`node_modules/`、`dist/`、coverage、编辑器本地状态。
- `.obsidian/`、`.env*`、本地日志、生成的 App bundle、个人 Chrome 扩展 ID。
- 安装到 `~/Library/Application Support/...` 后的 Native Messaging manifest。

发布前建议运行：

```bash
rg -n "(/Users/|chrome-extension://[a-z]{32}|token|secret|password)" .
git diff --check
```

## 许可证

MIT。见 [LICENSE](LICENSE)。

## English

GestureKit is an experimental macOS trackpad gesture tool for Google Chrome.

It combines a native macOS app, a Chrome MV3 extension, and a Native Messaging host to map trackpad gestures to browser tab actions.

### Current gestures

- Three-finger tap on a link: open in a new tab and switch to it.
- Three-finger tap near the left edge of the trackpad: switch to the previous tab.
- Three-finger tap near the right edge of the trackpad: switch to the next tab.
- Three-finger double-tap in the center: close the current tab.
- Three-finger quick flick left: switch to the next tab.
- Three-finger quick flick right: switch to the previous tab.

### Architecture

**GestureKitApp** — macOS menu bar app with a 6-page control center window. Touch input, gesture recognition, rule engine, operation journal (SQLite), provider session management.

**GestureKitHost** — Transparent bridge between Chrome Native Messaging (stdio) and App IPC (Unix socket).

**GestureKitCore** — Shared Swift library: gesture models, rule engine, IPC protocol, Provider Protocol v2 types, settings storage.

**Chrome extension** — MV3 ActionProvider: content script (click/select/drag protection), background Service Worker (provider session, action execution, IndexedDB operation ledger and telemetry outbox).

### Architecture layers

```
TouchBackend → GestureRecognizer → GestureSessionCoordinator
  → BindingResolver → RuleEngine → ProviderRouter
  → Authenticated IPC → Native Host → Chrome Provider
```

Gesture recognition is decoupled from gesture meaning. "Three-finger swipe left" is a primitive; mapping it to "activate next tab" lives in `BindingResolver`. All 6 current bindings are defined in `DefaultRules.v1Bindings`.

### Popup

The Chrome toolbar popup is a read-only context display showing page support status, connection state, current preset name, and the latest operation result. All configuration has been moved to the macOS control center.

### Build and test

```bash
swift build
swift test

cd extensions/chrome
npm install
npm test
npm run build
```

For installation details, see [Local install guide](docs/operations/gesturekit-v1-local-install.md).
