# GestureKit P2.1 / P2.5 诊断补全与个人灵敏度推荐计划

## 目标

把 P2 诊断面板从“看最近事件”推进到“能解释为什么没切 tab，并给出适合用户的轻扫灵敏度建议”。

## 范围

- P2.1：补全扩展侧失败原因，尤其是识别成功但 tab 没切过去的情况。
- P2.5：基于最近轻扫数据给出推荐档位和推荐最小横向距离。

## 不做

- 不自动修改用户设置。
- 不上传诊断数据。
- 不记录 URL、网页内容、原始触控帧或浏览历史。
- 不做长期统计图和复杂报表。

## 数据策略

- 继续使用 `gesturekitDiagnostics`，最多保留最近 100 条。
- 轻扫推荐优先使用最近 50 条轻扫记录。
- 推荐只展示文本和参数，不自动应用。

## 失败原因补全

扩展侧需要补充：

- `cooldown`：动作冷却中。
- `flick_switch_disabled`：快速轻扫开关关闭。
- `edge_tap_disabled`：边缘点按切 tab 开关关闭。
- `double_tap_disabled`：中间双击关闭 tab 开关关闭。
- `chrome_action_failed`：Chrome API 执行失败。
- `native_host_disconnected`：Native host 断开。
- `page_unavailable`：页面不可用。

## 推荐策略

只做保守建议：

- 最近轻扫失败主要是 `distance_too_short`：建议更灵敏。
- 最近轻扫失败主要是 `horizontal_ratio_too_low`：提示手势偏斜，不建议调灵敏度。
- 最近轻扫失败主要是 `too_slow`：提示动作更短促，不建议调灵敏度。
- 成功率高且当前为灵敏：建议保持或尝试标准。
- 推荐最小横向距离取最近成功轻扫 `abs(dx)` 的第 25 百分位，再限制在 `0.07-0.11` 之间。

## 验收

- popup 能显示“推荐档位”和“推荐最小距离”。
- 复制诊断中包含当前设置、推荐档位和推荐最小距离。
- 扩展侧能区分冷却、开关关闭和 Chrome 执行失败。
- `npm test`、`npm run build`、`swift test`、`swift build`、`GestureKitHost --self-test`、`git diff --check` 全部通过。
