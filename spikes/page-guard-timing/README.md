# Page Guard Timing Spike

该页面用于记录链接点击、文本选择和图片拖动的 DOM 单调时间。它必须与真实打包的 Chrome 扩展、native host 和 App 同时运行，不能用 jsdom 结果代替。

通过条件：同一 `gestureSessionId` 的 `guard_armed` 必须早于目标 DOM 事件；出现 `late` 或 `unavailable` 时，三指点按链接保持 fail-closed，不能执行链接动作。

每个场景至少记录：`candidate_started`、`guard_requested`、`guard_armed`、DOM 事件、`guard_consumed`、`guard_released` 或 `guard_expired`。
