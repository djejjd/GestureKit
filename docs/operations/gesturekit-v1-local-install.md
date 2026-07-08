# GestureKit V1 本地安装说明

## 1. 准备依赖

先在仓库根目录构建 host，并安装扩展依赖：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
cd extensions/chrome
npm install
```

如果只是更新扩展前端，后续可直接复用已有依赖执行 `npm run build`。

当前仓库环境默认 `swift` 可能解析到 Command Line Tools。Task 4 的主入口 `./scripts/dev/smoke-check.sh` 在未显式设置时会自动优先使用：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

如果你需要手动执行 Swift 命令，建议沿用同一策略；如果本机 Xcode 路径不同，可先自行导出 `DEVELOPER_DIR` 再运行脚本或手工命令。

## 2. 加载 Chrome 扩展

1. 打开 `chrome://extensions`。
2. 开启 Developer mode。
3. 选择 Load unpacked。
4. 选择 `extensions/chrome`。
5. 记录扩展 ID，后续所有安装和 smoke check 都要用这个 ID。

## 3. 阶段一：预检查

这一阶段只负责把构建、自检、扩展构建、manifest 安装和 smoke 页面入口串起来，不负责自动启动 `GestureKitApp`。

推荐直接运行开发入口：

```bash
./scripts/dev/smoke-check.sh --extension-id <extension-id>
```

这个命令会依次执行：

1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test`
3. `cd extensions/chrome && npm run build`
4. `./scripts/dev/install-native-host.sh --extension-id <extension-id> --host-path "<repo>/.build/debug/GestureKitHost"`
5. `open "chrome-extension://<extension-id>/smoke.html"`

阶段一的成功标准：

- `swift build`、`GestureKitHost --self-test`、扩展构建和 native host manifest 安装都成功。
- 浏览器能打开 `smoke.html`。
- 如果此时还没启动 `GestureKitApp`，`smoke.html` 首次出现 `app_unavailable` 属于预期现象，不表示 `smoke-check.sh` 失败。

如果只想确认命令链路，不实际执行，可先 dry run：

```bash
./scripts/dev/smoke-check.sh --extension-id <extension-id> --dry-run
```

如果 `GestureKitHost` 不在默认开发路径，可显式覆盖：

```bash
./scripts/dev/smoke-check.sh \
  --extension-id <extension-id> \
  --host-path /absolute/path/to/GestureKitHost
```

## 4. 阶段二：连通性探针

预检查成功后，再单独启动 App：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitApp
```

然后回到已经打开的 `smoke.html`，或者重新打开：

```bash
open "chrome-extension://<extension-id>/smoke.html"
```

阶段二的成功标准：

- smoke 页面不再显示 `app_unavailable`。
- extension 能连到 native host，且 App 侧有正常连接日志。

如果你就是要验证“App 没启动时 extension 会给出什么状态”，可以只做阶段一，不做阶段二。

## 5. 手动安装 native host（仅在需要单独排查时）

`smoke-check.sh` 内部会调用：

```bash
./scripts/dev/install-native-host.sh \
  --extension-id <extension-id> \
  --host-path "$(pwd)/.build/debug/GestureKitHost"
```

安装结果会写入：

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.gesturekit.host.json
```

如果需要核对 manifest 内容，至少确认两项：

- `path` 指向本机 `GestureKitHost` 绝对路径。
- `allowed_origins` 包含 `chrome-extension://<extension-id>/`。

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

- V1 使用私有 `MultitouchSupport.framework`，不适合 Mac App Store。
- V1 当前验证环境是内置触控板和内置单屏。
- 如果 macOS 系统三指手势吞掉输入，需要关闭冲突手势或重新运行手势矩阵。
- App 与 native host 的本机 IPC 使用 `127.0.0.1:17653` TCP NDJSON 通道，只应监听 loopback。
- 常见失败场景和排查步骤见 `docs/operations/gesturekit-v1-troubleshooting.md`。
