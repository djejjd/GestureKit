# macOS 触控板输入方案调研

日期：2026-06-30

## 结论

GestureKit V1 的触控板输入 spike 采用 `OpenMultitouchSupport` 作为验证 backend。该库封装 macOS 私有 `MultitouchSupport.framework`，适合自用和开源实验，不适合 Mac App Store 分发。

当前上游 HEAD：

```text
15c6bb0c6a2d2858559493a28ab23f7ac58648a3
```

核对命令：

```bash
git ls-remote https://github.com/Kyome22/OpenMultiTouchSupport.git HEAD
```

## 上游 API 核对

- 上游仓库：`https://github.com/Kyome22/OpenMultiTouchSupport.git`
- Swift package name：`OpenMultitouchSupport`
- Swift package product name：`OpenMultitouchSupport`
- import module name：`OpenMultitouchSupport`
- 监听入口：`OMSManager.shared`
- 启动监听：`OMSManager.startListening() -> Bool`
- 停止监听：`OMSManager.stopListening() -> Bool`
- 监听状态：`OMSManager.isListening`
- 事件入口：`OMSManager.touchDataStream`
- app-facing event callback type：不是闭包 callback，而是 `any AsyncShareStream<[OMSTouchData]>`
- 底层 ObjC callback type：`OpenMTEventCallback(OpenMTEvent *event)`，Swift probe 不直接使用。

`OMSTouchData` 字段：

- `id: Int32`
- `position: OMSPosition`，包含 `x: Float`、`y: Float`
- `total: Float`
- `pressure: Float`
- `axis: OMSAxis`，包含 `major: Float`、`minor: Float`
- `angle: Float`
- `density: Float`
- `state: OMSState`
- `timestamp: String`

`OMSState` 取值：

- `notTouching`
- `starting`
- `hovering`
- `making`
- `touching`
- `breaking`
- `lingering`
- `leaving`

用于三指 tap 和左右 swipe 的最小字段：

- `id`：区分同一帧内手指。
- `position.x`、`position.y`：计算三指质心、位移和方向。
- `state`：过滤有效触摸状态，识别三指序列开始和结束。
- `timestamp` 或本地 `Date`：估算手势持续时间。
- `pressure`、`total`、`axis`、`angle`、`density`：V1 spike 暂不作为判定条件，但可辅助后续诊断。

## macOS 和构建要求

上游 `Package.swift` 声明：

- `swift-tools-version: 6.2`
- `.macOS(.v15)`
- 依赖 `swift-async-algorithms`
- 二进制 target `OpenMultitouchSupportXCF`

上游 README 额外说明：

- 需要 Xcode 26.2+ 做开发。
- 兼容 macOS 15.0+。
- 使用 OpenMultitouchSupport 时 App Sandbox 必须关闭。

因此本 spike 把根 `Package.swift` 的 macOS platform 从 13 调整到 15。若 GestureKit V1 需要支持 macOS 13 或 14，需要另行评估旧版 OpenMultitouchSupport、fork、或其他触控板输入方案。

## probe 行为

`TrackpadInputProbe` 使用 `OMSManager.touchDataStream` 读取触摸帧，只向 stdout 打印摘要，不把连续原始输入流写入磁盘。

当前分类逻辑：

- 把 `starting`、`making`、`touching`、`breaking` 视为有效触摸状态。
- 每帧计算有效手指数和三指质心。
- 三指序列结束后，根据持续时间、质心位移和方向输出候选事件：
  - `three_finger_tap`
  - `three_finger_swipe_left`
  - `three_finger_swipe_right`
  - `unclear`

阈值是 spike 级经验值，只用于手动验证可观测性，不作为最终 `GestureRecognizer` 规则。

## 手动验证记录

当前已完成最小启动验证：

- 构建命令：`zsh -lc 'source ~/.zshrc; proxy_on >/dev/null 2>&1; swift build'`
- 构建结果：通过。
- 运行命令：`swift run TrackpadInputProbe`
- 运行结果：probe 成功启动默认 multitouch listener。
- 停止方式：`Ctrl-C`。
- 停止结果：打印 `device_status=listener_stopped stopped=true`。

观测到的设备输出：

```text
GUID: 1D010000-0000-0000-0200-000000000000
Driver Type: 4
DeviceID: 504403158265495837
FamilyID: 109
Surface Dimensions: 12480 x 7680
Dimensions: 18 x 24
Opaque: false
```

观测到的 probe 输出摘要：

```text
device_status=default_multitouch_listener_started is_listening=true
[event] normalized_finger_count=3 ...
[candidate:start] fingers=3 ...
[candidate:three_finger_tap] ...
device_status=listener_stopped stopped=true
```

人工稳定性验证进展：

- Chrome 普通窗口前台三指点按 10 次：通过，10/10 输出 `three_finger_tap`。
- Chrome 普通窗口前台三指左滑 10 次：通过，10/10 输出 `three_finger_swipe_left`。
- Chrome 普通窗口前台三指右滑 10 次：按物理方向“左侧向右侧推”重测后有效段通过，10/10 输出 `three_finger_swipe_right`。
- 右滑首次测试按浏览器语义方向操作时失败，观察到大量 `three_finger_swipe_left`，说明后续文档和 UI 必须明确物理方向和产品语义映射。
- 非 Chrome 前台观察结果：2026-07-01 曾启动观察 probe，但未按矩阵完成 3 类各 3 次测试，当前仍视为待测。
- macOS 三指系统手势冲突观察：待测。

稳定性验证记录位置：

- `docs/research/trackpad-gesture-stability-matrix.md`

当前结论：OpenMultitouchSupport backend 可以在本机启动并接收触控板事件，Chrome 普通窗口前台三类主手势在明确物理方向后均能达到 10/10 有效识别。但矩阵尚未完成非 Chrome 前台、Chrome 全屏、显示器环境和系统手势冲突观察；矩阵完成前，不进入正式产品实现。

## 网络和构建环境记录

直接运行 `git ls-remote` 或 `swift build` 时，当前 Codex shell 没有继承代理环境，访问 GitHub 会超时或出现 empty reply。

已验证可用的方式：

```bash
zsh -lc 'source ~/.zshrc; proxy_on >/dev/null 2>&1; git ls-remote https://github.com/Kyome22/OpenMultiTouchSupport.git HEAD'
zsh -lc 'source ~/.zshrc; proxy_on >/dev/null 2>&1; swift build'
```

原因：

- 默认 `env` 中没有 `http_proxy`、`https_proxy`、`all_proxy`。
- `proxy_on` 会设置代理到 `127.0.0.1:7897`。
- 本地 `verge-mih` 进程监听 `7897`。
- sandbox 内直接连本地代理会失败；提升权限后通过代理访问 GitHub 成功。

## 风险

- `MultitouchSupport.framework` 是私有 API，系统升级可能破坏行为或审核可接受性。
- 当前上游要求 macOS 15+，会影响 V1 的最低系统版本。
- 上游依赖二进制 `OpenMultitouchSupportXCF`，需要网络下载 release artifact。
- 三指系统手势可能与 macOS 设置冲突，需要手动验证。
