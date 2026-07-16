# GestureKit 本地安装说明

## 1. 首次安装

先安装扩展依赖：

```bash
cd extensions/chrome
npm install
```

回到仓库根目录，执行唯一安装入口：

```bash
./scripts/dev/install-local.sh
```

它会构建 `GestureKitHost`、构建扩展、推导稳定扩展 ID 并安装 Native Messaging manifest。不会要求输入或复制扩展 ID。

## 2. 加载 Chrome 扩展

1. 打开 `chrome://extensions`。
2. 开启 Developer mode。
3. 选择 Load unpacked。
4. 选择 `extensions/chrome`。
5. 首次加载后确认扩展 ID 为 `pdegbjhgibenmgaaplhnpbnhaaipndoh`。

Chrome 的 Load unpacked 是浏览器安全确认，不能由脚本自动绕过。后续更新只需重新执行 `./scripts/dev/install-local.sh`，再在此页面点击扩展刷新按钮。

## 3. 健康检查

运行：

```bash
./scripts/dev/health-check.sh
```

预期 `开发环境`、`构建产物`、`Native Messaging` 为 `PASS`；Chrome 和 App 两段在尚未启动 App 时为 `WAITING`。

## 4. 阶段二：连通性探针

预检查成功后，再单独启动 App：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitApp
```

另开终端运行 `./scripts/dev/smoke-check.sh`。脚本会执行协议自检，并明确使用 Google Chrome 打开 smoke 页面。

阶段二的成功标准：

- smoke 页面显示 `hostConnected: true`、`appConnected: true` 和 `status: "connected"`。

如果你就是要验证“App 没启动时 extension 会给出什么状态”，可以只做阶段一，不做阶段二。

## 5. 单独排查 manifest（仅在需要时）

`install-local.sh` 内部会调用：

```bash
./scripts/dev/install-native-host.sh \
  --host-path "$(pwd)/.build/debug/GestureKitHost"
```

安装结果会写入：

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.gesturekit.host.json
```

如果需要核对 manifest 内容，至少确认两项：

- `path` 指向本机 `GestureKitHost` 绝对路径。
- `allowed_origins` 包含稳定扩展 origin。

需要分析手势识别不稳定时使用详细日志：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer GESTUREKIT_DEBUG=1 swift run GestureKitApp
```

## 6. 日志位置

运行时终端默认只打印启动/停止摘要、影响执行的错误和警告，并保存一份受限本地日志：

```text
~/Library/Logs/GestureKit/GestureKitApp.log
```

日志不记录每一帧触控板输入；本地文件默认记录启动、手势完成结果、IPC 发布、连接数、错误和警告。成功手势默认不逐条打印到终端。日志单文件约 1 MB，最多保留 3 个文件，避免无限写入。

## 7. 权限和限制

- 当前版本使用私有 `MultitouchSupport.framework`，不适合 Mac App Store。
- 当前验证环境是内置触控板和内置单屏。
- 如果 macOS 系统三指手势吞掉输入，需要关闭冲突手势或重新运行手势矩阵。
- App 与 native host 的本机 IPC 使用 `127.0.0.1:17653` TCP NDJSON 通道，只应监听 loopback。
- 常见失败场景和排查步骤见 `docs/operations/troubleshooting.md`。
