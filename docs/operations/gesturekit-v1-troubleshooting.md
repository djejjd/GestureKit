# GestureKit V1 排障说明

## 1. `smoke-check.sh` 直接失败

先用 dry run 核对当前要执行的命令：

```bash
./scripts/dev/smoke-check.sh --extension-id <extension-id> --dry-run
```

重点确认：

- 扩展 ID 是当前 `chrome://extensions` 里这次加载的 ID。
- 默认 host 路径是否仍然是 `$(pwd)/.build/debug/GestureKitHost`。
- 如果你在别的位置构建过 host，改用 `--host-path /absolute/path/to/GestureKitHost`。

## 2. `swift run GestureKitHost --self-test` 失败

先单独执行：

```bash
swift run GestureKitHost --self-test
```

常见原因：

- 当前目录不在仓库根目录，导致 Swift Package 解析错误。
- `.build/debug/GestureKitHost` 还没生成，先执行 `swift build`。
- 当前机器环境需要按仓库既有方式用非沙箱 Swift 命令执行；如果你是在受限环境里跑自动化，按实际执行方式记录到任务报告。

## 3. 扩展前端构建失败

先进入扩展目录单独确认：

```bash
cd extensions/chrome
npm test
npm run build
```

常见原因：

- 依赖未安装，先执行 `npm install`。
- 在错误目录运行了 `npm run build`。

## 4. 扩展显示未连接

按顺序检查：

1. 运行 `swift run GestureKitHost --self-test`，确认 host 本体可启动。
2. 打开 `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.gesturekit.host.json`，确认：
   - `path` 是实际 `GestureKitHost` 绝对路径。
   - `allowed_origins` 是当前扩展 ID。
3. 重新打开：

```bash
open "chrome-extension://<extension-id>/smoke.html"
```

如果扩展 ID 变了，重新执行：

```bash
./scripts/dev/install-native-host.sh \
  --extension-id <extension-id> \
  --host-path "$(pwd)/.build/debug/GestureKitHost"
```

## 5. smoke 页面显示 `app_unavailable`

这通常表示扩展能连到 native host，但 App 没起来或本机 IPC 不通。先确认：

```bash
swift run GestureKitApp
```

再查看日志：

```bash
tail -n 200 ~/Library/Logs/GestureKit/GestureKitApp.log
```

必要时开详细日志重跑：

```bash
GESTUREKIT_DEBUG=1 swift run GestureKitApp
```

## 6. 手势识别不稳定或三指轻扫方向不符合预期

先确认这不是安装链路问题，而是输入识别问题。V1 现有结论是 `passed_with_notes`，其中三指快速右轻扫按物理方向定义为“从触控板左侧向右侧移动”。如果观测结果和预期不一致：

- 先确认是否触发了系统三指手势冲突。
- 结合 `~/Library/Logs/GestureKit/GestureKitApp.log` 看 `gesture_unstable`、发布结果和连接数。
- 回到手势矩阵记录实际设备、系统版本和冲突现象，不要在本任务里改 Task 3 协议或 probe 逻辑。

## 7. 不确定从哪里开始排查

建议固定顺序，不要跳步：

1. `./scripts/dev/smoke-check.sh --extension-id <extension-id> --dry-run`
2. `swift build`
3. `swift run GestureKitHost --self-test`
4. `cd extensions/chrome && npm run build`
5. `./scripts/dev/install-native-host.sh --extension-id <extension-id> --host-path "$(pwd)/.build/debug/GestureKitHost"`
6. `swift run GestureKitApp`
7. `open "chrome-extension://<extension-id>/smoke.html"`
