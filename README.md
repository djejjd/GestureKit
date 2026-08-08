# GestureKit

**macOS 触控板手势工具，用于 Google Chrome**

GestureKit 让你用触控板手势完成 Chrome 常用操作：三指点按打开链接、切换或关闭标签页。它由三个部分组成：macOS 原生 App、Chrome MV3 扩展和 Native Messaging host。

> 当前为本地开发与自用实验阶段，尚未打包、签名或公证，不适合作为通用发行版安装。

[English](#english)

## 功能特性

- 6 种触控板手势，覆盖链接打开、标签页切换与关闭
- 链接点击保护：三指点按时阻止链接原地跳转，改在新标签页打开
- 端到端操作记录：每次操作持久化到 SQLite，支持脱敏证据导出
- 原生 App 与 Chrome 扩展通过认证 IPC 会话安全通信

## 手势

| 手势 | 动作 |
|---|---|
| 三指点按链接 | 在右侧新标签页打开链接 |
| 三指点按左侧边缘 | 切换到左侧标签页 |
| 三指点按右侧边缘 | 切换到右侧标签页 |
| 三指双击中间区域 | 关闭当前标签页 |
| 三指快速左轻扫 | 切换到右侧标签页 |
| 三指快速右轻扫 | 切换到左侧标签页 |

标签页切换仅在当前 Chrome 窗口内生效，到达边缘时循环。灵敏度可在 App 控制中心调整。

## 架构

```
触控板硬件 → MultitouchSupportBackend → GestureRecognizer
  → GestureSessionCoordinator → RuleEngine
  → 认证 IPC → Native Host Shim → Chrome Native Messaging
  → Chrome ActionProvider
```

| 组件 | 职责 |
|---|---|
| `GestureKitApp` | macOS 菜单栏 App：触控板采集、手势识别、规则引擎、操作记录、Provider 会话管理 |
| `GestureKitHost` | Chrome Native Messaging ↔ App IPC 透明桥接 |
| `GestureKitCore` | Swift 共享库：手势模型、规则引擎、IPC 协议、Provider Protocol v2 |
| `extensions/chrome` | Chrome MV3 扩展：页面交互保护、动作执行、离线账本 |

## 环境要求

- macOS 15+
- 兼容 Swift 6.2 的 Xcode / Swift 工具链
- Google Chrome（Developer Mode 加载 unpacked 扩展）

## 安装

```bash
./scripts/dev/install-local.sh
```

该脚本构建 host 与扩展，并安装 Native Messaging manifest。然后在 `chrome://extensions` 开启 Developer Mode，选择 **Load unpacked** 并选中 `extensions/chrome` 目录。详细步骤见[本地安装说明](docs/operations/本地安装.md)。

## 使用

启动 App：

```bash
swift run GestureKitApp
```

验证端到端连通：

```bash
./scripts/dev/smoke-check.sh
```

smoke 页面显示 `status: "connected"` 即表示连通。

## 构建与测试

```bash
swift build
swift test

cd extensions/chrome
npm install
npm test
npm run build
```

## 链接可靠性 E2E 与 CI 质量门

GestureKit 附带一套链接可靠性 E2E 控制平面，用真实 Chrome 验证四类 link 操作场景
（`success`、`leaseExpiry`、`providerUnavailable`、`resultUnknown`），每个场景输出一条
脱敏 `LinkReliabilitySummary` JSON。

- 干跑（不启动 GUI/Chrome，可安全在 CI 执行）：

```bash
zsh scripts/dev/test-link-reliability.sh --dry-run
```

- 真实 Chrome 验收（人工关口，macOS 专用）：

```bash
zsh scripts/dev/test-link-reliability.sh
```

真实 Chrome 验收只在 GitHub Actions 的 `workflow_dispatch` 显式传入 `run_real_chrome=true`
时执行，默认 `false`，不会在通用 CI 自动运行。**通用 CI 不等于真实触控板验证**：它只验证
自动化测试、构建产物与干跑；真实手势→链接链路仍是人工验收关口。已知边界与缺口见
[端到端验收清单](docs/operations/端到端检查清单.md) 与[排障说明](docs/operations/排障手册.md)。

## 文档

- [V1 产品契约](docs/product/v1/v1-产品契约.md)
- [V2 UI 信息架构](docs/architecture/v2-UI信息架构.md)
- [可靠性、可观测性与可扩展动作平台架构](docs/architecture/可靠性可观测平台-架构.md)
- [架构决策记录](docs/adr/)
- [本地安装说明](docs/operations/本地安装.md)
- [端到端验收清单](docs/operations/端到端检查清单.md)
- [排障说明](docs/operations/排障手册.md)

## 贡献

欢迎提交 Issue 与 Pull Request。请阅读[贡献指南](CONTRIBUTING.md)，确保新增改动附带测试。

## 许可证

[MIT](LICENSE)

---

## English

**A macOS trackpad gesture tool for Google Chrome.**

GestureKit maps trackpad gestures to Chrome actions: three-finger tap to open links, switch or close tabs. It consists of a native macOS app, a Chrome MV3 extension, and a Native Messaging host.

> Currently in local, self-use experimental stage — not packaged, signed, or notarized. Not suitable for general distribution.

### Features

- 6 trackpad gestures covering link opening, tab switching and closing
- Link-click protection: prevents in-place navigation so links open in a new tab
- End-to-end operation journal persisted in SQLite with redacted evidence export
- Authenticated IPC sessions between the app and the Chrome extension

### Gestures

| Gesture | Action |
|---|---|
| Three-finger tap on a link | Open the link in a new tab to the right |
| Three-finger tap near the left edge | Switch to the previous tab |
| Three-finger tap near the right edge | Switch to the next tab |
| Three-finger double-tap in the center | Close the current tab |
| Three-finger quick flick left | Switch to the next tab |
| Three-finger quick flick right | Switch to the previous tab |

Tab switching applies only within the current Chrome window and wraps at the edges. Sensitivity is adjustable in the control center.

### Components

- **GestureKitApp** — macOS menu bar app: touch input, gesture recognition, rule engine, operation journal, provider session management
- **GestureKitHost** — transparent bridge between Chrome Native Messaging (stdio) and App IPC
- **GestureKitCore** — shared Swift library: gesture models, rule engine, IPC protocol, Provider Protocol v2
- **extensions/chrome** — Chrome MV3 extension: page interaction protection, action execution, offline ledger

### Requirements

- macOS 15+
- Swift 6.2 toolchain
- Google Chrome with Developer Mode enabled

### Install

```bash
./scripts/dev/install-local.sh
```

Then enable Developer Mode at `chrome://extensions`, choose **Load unpacked**, and select `extensions/chrome`. See the [local install guide](docs/operations/本地安装.md).

### Run

```bash
swift run GestureKitApp
./scripts/dev/smoke-check.sh   # verify end-to-end connectivity
```

### Build & Test

```bash
swift build
swift test

cd extensions/chrome
npm install
npm test
npm run build
```

### Link-reliability E2E & CI quality gate

A link-reliability E2E control plane drives four link-action scenarios
(`success`, `leaseExpiry`, `providerUnavailable`, `resultUnknown`) against real Chrome,
printing one redacted `LinkReliabilitySummary` JSON line per scenario.

- Dry run (no GUI/Chrome): `zsh scripts/dev/test-link-reliability.sh --dry-run`
- Real-Chrome acceptance (manual gate, macOS only): `zsh scripts/dev/test-link-reliability.sh`

The real-Chrome runner only runs via `workflow_dispatch` with `run_real_chrome=true`
(default `false`); it never runs in general CI. General CI is not a substitute for real
trackpad validation. See [端到端检查清单](docs/operations/端到端检查清单.md) and
[排障手册](docs/operations/排障手册.md) for boundaries and known gaps.

### Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and include tests for your changes.

### License

[MIT](LICENSE)
