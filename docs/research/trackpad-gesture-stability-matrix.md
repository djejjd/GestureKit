# 触控板手势稳定性验证矩阵

日期：2026-07-01

相关文档：

- `docs/product/gesturekit-v1-requirements.md`
- `docs/product/gesturekit-v1-contract.md`
- `docs/research/macos-trackpad-input-options.md`
- `spikes/trackpad-input/README.md`

## 1. 目的

本矩阵用于补齐 GestureKit V1 正式开发前的人工手势证据。它只验证触控板输入和候选手势分类稳定性，不验证 Chrome 动作执行，也不验证 RuleEngine 或 Chrome tab 动作。

正式开发前，本文件必须从“待测”更新为实际观察结果。

## 2. 测试环境记录

| 项目 | 当前记录 |
| --- | --- |
| 测试日期 | 2026-07-01 |
| macOS 版本 | 26.5.1，Build 25F80 |
| 设备 | MacBook 内置触控板，设备输出显示 `FamilyID: 109`、`Dimensions: 18 x 24` |
| Chrome 版本 | 149.0.7827.201 |
| OpenMultitouchSupport revision | `15c6bb0c6a2d2858559493a28ab23f7ac58648a3` |
| 系统三指相关设置 | `TrackpadThreeFingerDrag=1`；`TrackpadThreeFingerHorizSwipeGesture=0`；`TrackpadThreeFingerVertSwipeGesture=0`；`TrackpadThreeFingerTapGesture=0`；用户在系统手势冲突观察中未看到 Mission Control、切桌面、窗口拖移、页面切换等系统动作 |
| 显示器环境 | Chrome 普通窗口和全屏窗口已测；用户确认当前只有内置屏幕；外接屏组合按当前环境记为 `N/A` |

## 3. 运行命令

优先使用代理环境构建：

```bash
zsh -lc 'source ~/.zshrc; proxy_on >/dev/null 2>&1; swift build'
```

运行 probe：

```bash
swift run TrackpadInputProbe
```

结束 probe：

```text
Ctrl-C
```

结束时必须看到：

```text
device_status=listener_stopped stopped=true
```

## 4. Chrome 前台稳定性矩阵

Chrome 处于前台，打开普通网页即可。本矩阵只看 probe 是否输出期望候选事件。

| 手势 | 次数 | 期望候选 | 成功次数 | 误识别次数 | 未识别次数 | 结论 | 备注 |
| --- | ---: | --- | ---: | ---: | ---: | --- | --- |
| 三指点按 | 10 | `three_finger_tap` | 10 | 0 | 0 | 通过 | 有效 10 次全部输出 `three_finger_tap`，计数从 `tap=1` 到 `tap=10` |
| 三指左滑 | 10 | `three_finger_swipe_left` | 10 | 0 | 0 | 通过 | 有效 10 次全部输出 `three_finger_swipe_left`，计数从 `left=1` 到 `left=10` |
| 三指右滑 | 10 | `three_finger_swipe_right` | 10 | 0 | 0 | 通过但需备注 | 首次按浏览器语义方向操作失败，差分为 `right=1`、`left=9`、`tap=5`、`unclear=1`；重测按物理方向“左侧向右侧推”后，有效段从 `right=1` 到 `right=10` 连续通过。重测开始前存在 `tap=3 left=2` 预备误触，不计入有效 10 次 |

probe 候选行会输出累计计数，例如 `[counts tap=3 left=0 right=0 unclear=1]`。每组测试应优先使用累计计数填表。

硬性通过标准：

- 单类手势 10 次中至少 8 次识别为期望候选。
- 任一类别误识别为另一个 V1 手势的次数必须为 0。
- 三类手势总计 `unclear` 或未识别次数不得超过 6 次。

如果无法达到上述硬性标准，不直接进入正式开发，应先调整 `GestureRecognizer` 设计或重新评审 V1 手势选择。

## 5. 非 Chrome 前台观察

目的：确认输入 backend 是全局可观测的。`TrackpadInputProbe` 不验证产品动作状态，因此本节不要求证明 `unsupported_app`；非 Chrome 不触发 Chrome 动作由后续 RuleEngine、AppContextResolver 和端到端测试验收。

| 前台 App | 手势 | 次数 | probe 是否有候选 | 产品动作验收 | 结论 | 备注 |
| --- | --- | ---: | --- | --- | --- | --- |
| 非 Chrome App，具体 App 未记录 | 三指点按 | 3 | 有候选，`tap=3` | 后续端到端测试覆盖 `unsupported_app` 或等价状态 | 通过 | 2026-07-02 重测通过；2026-07-01 曾中止一次，不作为验收记录 |
| 非 Chrome App，具体 App 未记录 | 三指左滑 | 3 | 有候选，`left=3` | 后续端到端测试覆盖 `unsupported_app` 或等价状态 | 通过 | 2026-07-02 重测通过 |
| 非 Chrome App，具体 App 未记录 | 三指右滑 | 3 | 有候选，`right=3` | 后续端到端测试覆盖 `unsupported_app` 或等价状态 | 通过 | 2026-07-02 重测通过，物理方向为从触控板左侧向右侧推 |

## 6. 环境覆盖矩阵

本节用于对齐既有技术设计中的手动验证范围。当前机器不具备的硬件或显示器组合可以标记为 `N/A`，但必须写明原因。

| 场景 | 要求 | 结果 | 备注 |
| --- | --- | --- | --- |
| MacBook 内置触控板 | 必测，如果当前设备具备 | 已测 | 当前测试使用内置触控板 |
| Magic Trackpad | 当前环境具备时必测，否则 `N/A` | `N/A` | `system_profiler SPBluetoothDataType` 未返回蓝牙控制器信息，`system_profiler SPUSBDataType` 未返回外接触控板信息；当前测试只确认内置触控板 |
| Chrome 普通窗口 | 必测 | 已测 | 三类主矩阵在 Chrome 普通窗口前台完成 |
| Chrome 全屏窗口 | 必测 | 已测 | 2026-07-02 观察通过：三指点按 3/3、三指左滑 3/3、三指右滑 3/3，`unclear=0` |
| 单显示器 | 当前环境具备时必测，否则 `N/A` | 已确认 | 用户确认当前只有内置屏幕 |
| 双显示器 | 当前环境具备时必测，否则 `N/A` | `N/A` | 用户确认当前只有内置屏幕 |
| Retina 外接屏 | 当前环境具备时必测，否则 `N/A` | `N/A` | 当前无外接屏 |
| 非 Retina 外接屏 | 当前环境具备时必测，否则 `N/A` | `N/A` | 当前无外接屏 |

## 7. macOS 系统手势冲突观察

目的：确认 Mission Control、App Expose、Swipe between pages、三指拖移等系统设置是否吞掉或干扰三指手势。

| 系统设置状态 | 手势 | 次数 | probe 观察 | 系统行为 | V1 影响 | 处理建议 |
| --- | --- | ---: | --- | --- | --- | --- |
| `TrackpadThreeFingerDrag=1`；三指水平/垂直系统滑动和三指点按系统手势为 `0` | 三指点按 | 3 | 观察到 tap 候选；本轮输出存在额外触摸候选，不作为稳定性计数复测 | 用户未观察到 Mission Control、切桌面、窗口拖移、页面切换等系统动作 | `acceptable_with_note` | 记录当前系统设置；后续用户文档说明三指拖移开启时本轮未观察到系统动作 |
| 同上 | 三指左滑 | 3 | 观察到 left 候选；本轮输出存在额外触摸候选，不作为稳定性计数复测 | 用户未观察到系统动作 | `acceptable_with_note` | 同上 |
| 同上 | 三指右滑 | 3 | 观察到 right 候选；本轮输出存在额外触摸候选，不作为稳定性计数复测 | 用户未观察到系统动作 | `acceptable_with_note` | 同上 |

冲突分级：

- `blocking`：系统手势导致 V1 手势无法稳定识别，必须调整设计或要求用户关闭特定设置。
- `acceptable_with_note`：存在系统行为，但 probe 仍可稳定识别，文档中说明即可。
- `none`：未观察到冲突。

## 8. 结论

当前状态：`passed_with_notes`。

通过依据：

- Chrome 普通窗口前台三类主手势均达到 10/10 有效识别。
- 非 Chrome 前台三类手势均可观测到候选事件。
- Chrome 全屏窗口三类手势均可观测到候选事件。
- 当前只有内置单屏；外接屏和 Magic Trackpad 均按当前环境记为 `N/A`。
- 当前系统设置下未观察到 macOS 系统动作被三指手势触发。

备注：

- 三指右滑必须明确为物理方向“从触控板左侧向右侧推”，不能只用浏览器前进/后退语义描述。
- 系统手势冲突观察本轮输出存在额外触摸候选，因此只作为冲突观察，不作为稳定性主矩阵复测。

正式开发前必须给出以下结论之一：

- `passed`：手势稳定性足以支撑 V1 正式开发。
- `passed_with_notes`：可以进入正式开发，但需要在技术设计中记录限制或推荐设置。
- `blocked`：不能进入正式开发，必须先调整手势方案、阈值或输入 backend。

判定规则：

- `passed`：Chrome 前台稳定性矩阵满足硬性通过标准，环境覆盖矩阵没有未解释的缺口，系统手势冲突为 `none`。
- `passed_with_notes`：Chrome 前台稳定性矩阵满足硬性通过标准，但存在已记录的 `N/A` 环境项或 `acceptable_with_note` 冲突。
- `blocked`：Chrome 前台稳定性矩阵不满足硬性通过标准，或系统手势冲突为 `blocking`。

## 9. 记录原则

- 不保存连续原始触控流。
- 不记录浏览历史或页面内容。
- 只记录候选事件摘要、成功次数、失败次数和必要环境信息。
- 如果使用日志片段，只保留足以说明结论的短摘要。

## 10. 补充说明：协议 smoke 不是手势矩阵替代品

2026-07-14 已补充自动化协议 smoke 脚本 `./scripts/dev/test-provider-protocol.sh`，并在自动化环境中输出 `provider_protocol_ok`。它验证的是 Provider、host、App 和 Chrome 之间的协议链路，不替代本文件里的人工手势稳定性结果。

因此：

- 本矩阵的结论仍以 2026-07-01 记录为准。
- `provider_protocol_ok` 只能作为端到端协议连通性的补充证据，不能把人工手势证据从本文件中省略。
