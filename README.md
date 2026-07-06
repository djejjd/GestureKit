# GestureKit

GestureKit 是一个面向 Google Chrome 的 macOS 触控板手势工具。

它由一个 macOS 原生 App、一个 Chrome MV3 扩展和一个 Native Messaging host 组成，用触控板手势执行常用标签页操作。

当前项目仍处于本地开发和自用实验阶段。它还没有做打包、签名、公证，也不适合作为通用发行版安装。

English version: [English](#english)

## 手势

当前支持的 Chrome 手势：

- 三指点按链接：在当前标签页右侧打开新标签页，并自动切换过去。
- 三指点按空白处左半区：切换到左侧标签页。
- 三指点按空白处右半区：切换到右侧标签页。
- 三指双击空白处：关闭当前标签页。
- 三指快速左轻扫：切换到左侧标签页。
- 三指快速右轻扫：切换到右侧标签页。

标签页切换只作用于当前 Chrome 窗口。到达最左或最右标签页时会循环切换。

左右轻扫只识别短促的 flick。慢速三指拖动会被判为不稳定手势，以减少 Chrome 页面文本被拖选的情况。

## 工作方式

- `GestureKitApp`：macOS App，监听触控板输入，并在本机开启 IPC 服务。
- `GestureKitHost`：Chrome Native Messaging host，负责连接 Chrome 扩展和本机 App。
- `extensions/chrome`：Chrome MV3 扩展，解析链接并通过 Chrome API 执行标签页动作。
- `GestureKitCore`：Swift 共享核心，包含手势识别、规则引擎和协议模型。

主要文档：

- [V1 契约](docs/product/gesturekit-v1-contract.md)
- [V1 需求](docs/product/gesturekit-v1-requirements.md)
- [技术设计](docs/architecture/gesturekit-v1-technical-design.md)
- [本地安装说明](docs/operations/gesturekit-v1-local-install.md)
- [端到端验收清单](docs/operations/gesturekit-v1-e2e-checklist.md)

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

默认情况下，终端只显示启动、停止、警告和错误。日志文件有大小限制和轮转机制，不记录原始触控板帧。

需要调试手势识别时：

```bash
GESTUREKIT_DEBUG=1 swift run GestureKitApp
```

## 测试

```bash
swift test
swift build
swift run GestureKitHost --self-test

cd extensions/chrome
npm test
npm run build
```

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

This project is currently intended for local development and personal experimentation. It is not packaged, signed, notarized, or ready for general distribution.

Current gestures:

- Three-finger tap on a link: open it in a new tab and switch to it.
- Three-finger tap on empty space, left half of the trackpad: switch to the previous tab.
- Three-finger tap on empty space, right half of the trackpad: switch to the next tab.
- Three-finger double-tap on empty space: close the current tab.
- Three-finger quick flick left/right: switch tabs.

Build and test:

```bash
swift build
swift test

cd extensions/chrome
npm install
npm test
npm run build
```

For installation details, see [Local install guide](docs/operations/gesturekit-v1-local-install.md).
