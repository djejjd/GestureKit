# GestureKit V1 本地安装说明

## 1. 构建

```bash
swift build
cd extensions/chrome
npm install
npm run build
```

## 2. 加载 Chrome 扩展

1. 打开 `chrome://extensions`。
2. 开启 Developer mode。
3. 选择 Load unpacked。
4. 选择 `extensions/chrome`。
5. 记录扩展 ID。

## 3. 安装 native host manifest

把 `spikes/native-messaging/host-manifest/com.gesturekit.host.json` 中的 `path` 改为本机 `GestureKitHost` 绝对路径。开发构建通常是：

```text
<repo>/.build/debug/GestureKitHost
```

把 `allowed_origins` 改为实际扩展 ID：

```json
["chrome-extension://<extension-id>/"]
```

复制 manifest 到 Chrome native messaging host 目录：

```bash
mkdir -p "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
cp spikes/native-messaging/host-manifest/com.gesturekit.host.json "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.gesturekit.host.json"
```

## 4. 启动

```bash
swift run GestureKitApp
```

## 5. 权限和限制

- V1 使用私有 `MultitouchSupport.framework`，不适合 Mac App Store。
- V1 当前验证环境是内置触控板和内置单屏。
- 如果 macOS 系统三指手势吞掉输入，需要关闭冲突手势或重新运行手势矩阵。
- App 与 native host 的本机 IPC 使用 `127.0.0.1:17653` TCP NDJSON 通道，只应监听 loopback。
