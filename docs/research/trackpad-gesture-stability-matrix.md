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
| 系统三指相关设置 | 待测，尚未人工确认 Mission Control、App Expose、Swipe between pages、三指拖移等 |
| 显示器环境 | Chrome 普通窗口已测；`system_profiler SPDisplaysDataType` 在当前 shell 只返回 GPU 摘要，显示器组合待人工确认 |

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
| 未确认 | 三指点按 | 3 | 未完成 | 后续端到端测试覆盖 `unsupported_app` 或等价状态 | 中止 | 2026-07-01 启动过非 Chrome 观察 probe，但未按 3 类各 3 次矩阵完成，不能作为有效验收记录 |
| 未确认 | 三指左滑 | 3 | 未完成 | 后续端到端测试覆盖 `unsupported_app` 或等价状态 | 中止 | 同上 |
| 未确认 | 三指右滑 | 3 | 未完成 | 后续端到端测试覆盖 `unsupported_app` 或等价状态 | 中止 | 同上 |

## 6. 环境覆盖矩阵

本节用于对齐既有技术设计中的手动验证范围。当前机器不具备的硬件或显示器组合可以标记为 `N/A`，但必须写明原因。

| 场景 | 要求 | 结果 | 备注 |
| --- | --- | --- | --- |
| MacBook 内置触控板 | 必测，如果当前设备具备 | 已测 | 当前测试使用内置触控板 |
| Magic Trackpad | 当前环境具备时必测，否则 `N/A` | 待测 |  |
| Chrome 普通窗口 | 必测 | 已测 | 三类主矩阵在 Chrome 普通窗口前台完成 |
| Chrome 全屏窗口 | 必测 | 待测 |  |
| 单显示器 | 当前环境具备时必测，否则 `N/A` | 待测 |  |
| 双显示器 | 当前环境具备时必测，否则 `N/A` | 待测 |  |
| Retina 外接屏 | 当前环境具备时必测，否则 `N/A` | 待测 |  |
| 非 Retina 外接屏 | 当前环境具备时必测，否则 `N/A` | 待测 |  |

## 7. macOS 系统手势冲突观察

目的：确认 Mission Control、App Expose、Swipe between pages、三指拖移等系统设置是否吞掉或干扰三指手势。

| 系统设置状态 | 手势 | 次数 | probe 观察 | 系统行为 | V1 影响 | 处理建议 |
| --- | --- | ---: | --- | --- | --- | --- |
| 待测 | 三指点按 | 3 | 待测 | 待测 | 待测 | 待测 |
| 待测 | 三指左滑 | 3 | 待测 | 待测 | 待测 | 待测 |
| 待测 | 三指右滑 | 3 | 待测 | 待测 | 待测 | 待测 |

冲突分级：

- `blocking`：系统手势导致 V1 手势无法稳定识别，必须调整设计或要求用户关闭特定设置。
- `acceptable_with_note`：存在系统行为，但 probe 仍可稳定识别，文档中说明即可。
- `none`：未观察到冲突。

## 8. 结论

当前状态：部分通过；2026-07-01 已按用户要求结束测试，待补齐非 Chrome 前台、Chrome 全屏窗口、显示器环境和系统手势冲突观察。

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
