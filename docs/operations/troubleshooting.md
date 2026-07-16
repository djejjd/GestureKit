# GestureKit 排障说明

## 1. 先执行健康检查

从仓库根目录运行：

```bash
./scripts/dev/health-check.sh
```

按输出的失败或等待阶段处理：

- `FAIL 开发环境`：确认 Xcode、Swift、Node.js 和扩展依赖可用，再运行 `./scripts/dev/install-local.sh`。
- `FAIL 构建产物`：运行 `./scripts/dev/install-local.sh` 重新构建 host。
- `FAIL Native Messaging`：运行 `./scripts/dev/install-local.sh` 重新生成 manifest；不要手工编辑扩展 ID。
- `WAITING Chrome 到 Host`：在 `chrome://extensions` 加载或刷新 `extensions/chrome`，再运行 `./scripts/dev/smoke-check.sh`。
- `WAITING Host 到 App`：启动 `GestureKitApp` 后刷新 smoke 页面。

`smoke-check.sh` 会构建协议检查所需产物并在 Google Chrome 打开 smoke 页面；如需只检查将执行的命令，可运行：

```bash
./scripts/dev/smoke-check.sh --dry-run
```

脚本默认由仓库公钥推导稳定扩展 ID，用户无需提供 `--extension-id`。

## 2. `swift run GestureKitHost --self-test` 失败

先单独执行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test
```

常见原因：

- 当前目录不在仓库根目录，导致 Swift Package 解析错误。
- `.build/debug/GestureKitHost` 还没生成，先执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`。
- 当前机器的 Xcode Developer 路径不是 `/Applications/Xcode.app/Contents/Developer`，需要先设置正确的 `DEVELOPER_DIR`。

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
   实际建议命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test`
2. 打开 `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.gesturekit.host.json`，确认：
   - `path` 是实际 `GestureKitHost` 绝对路径。
   - `allowed_origins` 是安装脚本推导出的稳定扩展 origin。
3. 重新运行：

```bash
./scripts/dev/smoke-check.sh
```

如果 manifest 缺失或来源不匹配，重新执行：

```bash
./scripts/dev/install-local.sh
```

## 5. smoke 页面显示 `app_unavailable`

先区分你在哪个阶段：

- 如果你刚跑完 `./scripts/dev/smoke-check.sh`，但还没启动 `GestureKitApp`，首次看到 `app_unavailable` 是预期结果，说明阶段一只做到“页面已打开，等待 App”。
- 如果你已经启动了 `GestureKitApp`，仍然看到 `app_unavailable`，这通常表示扩展能连到 native host，但 App 没起来或本机 IPC 不通。先确认：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitApp
```

再查看日志：

```bash
tail -n 200 ~/Library/Logs/GestureKit/GestureKitApp.log
```

必要时开详细日志重跑：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer GESTUREKIT_DEBUG=1 swift run GestureKitApp
```

## 6. 手势识别不稳定或三指轻扫方向不符合预期

先确认这不是安装链路问题，而是输入识别问题。现有结论是 `passed_with_notes`，其中三指快速右轻扫按物理方向定义为“从触控板左侧向右侧移动”。如果观测结果和预期不一致：

- 先确认是否触发了系统三指手势冲突。
- 结合 `~/Library/Logs/GestureKit/GestureKitApp.log` 看 `gesture_unstable`、发布结果和连接数。
- 回到手势矩阵记录实际设备、系统版本和冲突现象，不要在本任务里改 Task 3 协议或 probe 逻辑。

## 7. 推荐应用同步状态异常

推荐应用闭环（P4）的五种同步状态和对应排查入口：

- `saved_only`：扩展设置已写入，但 App 还未 ack。先确认 App 是否运行；如果 App 已运行但长期处于此状态，检查 native host 连接。
- `pending`：已发出 settings_update，等待 host/App 返回。如果长时间不消失，先跑 `smoke-check.sh` 确认连通性。
- `applied`：App 已确认应用推荐设置，当前 App 会话中生效。
- `failed`：host 断开或 ack 返回失败。先跑 smoke probe；检查 `~/Library/Logs/GestureKit/GestureKitApp.log` 中的 settings_applied 日志。
- `stale`：App 会话已变化（重启或崩溃后重新启动），旧 ack 作废。需要重新应用推荐设置或等待自动重同步。

常见问题：

- **推荐按钮不显示**：需要 popup 中有足够的轻扫诊断数据（至少一条成功轻扫记录）才会出现推荐。
- **点击应用后状态一直显示"等待确认"**：检查 GestureKitApp 是否运行，以及 native host 是否连接正常。
- **关闭 App 后状态仍然显示"已应用"**：刷新 popup（重新打开）以触发探针检查，状态应转为 `stale`。

## 8. 菜单栏状态词与排障映射

菜单栏状态词的含义和对应排查入口：

- **监听：运行中** — App 正常监听触控板输入。
- **监听：已停止** — 用户通过菜单栏点击了"停止监听"或 App 未启动。点击"启动监听"恢复。
- **监听：输入错误** — 触控板 backend 启动失败。确认系统已授予辅助功能权限，检查是否有其他程序占用触控板输入。
- **监听：IPC 错误** — 本机 IPC 服务启动失败。检查端口 17653 是否被占用。
- **连接：未连接** — 无 Chrome 扩展或 native host 连接。先跑 `smoke-check.sh` 确认安装链路。
- **连接：已连接(N)** — N 个客户端已连接（通常为 1，即 native host）。
- **最近错误：no_rule** — 手势已识别但没有匹配的规则（Chrome 前台时出现）。检查 popup 中手势开关是否开启。
- **最近错误：unsupported_app** — 手势已识别但当前前台 App 不是 Chrome。这是正常行为，在非 Chrome 应用中操作触控板时会出现。
- **最近错误：touch_backend_start_failed** — 触控板输入模块启动失败。确认系统权限。

常见问题：

- **菜单栏文档打开失败**：设置 `GESTUREKIT_REPO_ROOT` 环境变量指向仓库根目录，或从仓库目录启动 App。
- **菜单栏状态不更新**：点击"刷新状态"手动触发更新。

## 9. 不确定从哪里开始排查

建议固定顺序，不要跳步：

1. `./scripts/dev/health-check.sh`
2. `./scripts/dev/install-local.sh`
3. 在 `chrome://extensions` 刷新 `extensions/chrome` 扩展
4. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitApp`
5. `./scripts/dev/smoke-check.sh`
