# 触控板输入验证 Spike

目标：验证 OpenMultitouchSupport 是否能支撑 GestureKit V1 的触控板手势输入。

## 手动检查

1. 运行 `swift run TrackpadInputProbe`。
2. 连续执行三指点按 10 次。
3. 连续执行三指左滑 10 次。
4. 连续执行三指右滑 10 次。
5. 把识别稳定性记录到 `docs/research/macos-trackpad-input-options.md`。
6. 分别在 Chrome 前台和非 Chrome 前台测试。
7. 如果系统设置里存在冲突的 macOS 三指系统手势，开启后至少测试一次。
8. 使用 `Ctrl-C` 结束 probe，确认它打印 `listener_stopped`。

## 通过条件

- 三指点按可以和滑动区分。
- 左滑和右滑方向可以区分。
- backend 不可用时给出明确错误。
- 失败模式记录在研究笔记中。

## 输出说明

- `[event] normalized_finger_count=...`：当前帧归一化后的有效手指数。
- `[candidate:start]`：开始观察三指候选序列。
- `[candidate:three_finger_tap]`：候选三指点按。
- `[candidate:three_finger_swipe_left]`：候选三指左滑。
- `[candidate:three_finger_swipe_right]`：候选三指右滑。
- `[candidate:unclear]`：三指序列存在，但位移或时长不足以稳定分类。

probe 只向 stdout 打印观测摘要，不会把连续原始输入流写入磁盘。
