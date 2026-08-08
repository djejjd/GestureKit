# Page Guard Timing Spike

日期：2026-07-10

## 结论

当前候选期 page guard 结论为 `failed`，不能作为 V2 链接动作的唯一保护机制。

隔离 Chrome profile 已成功加载本地扩展，并访问 `http://127.0.0.1:8798/guard-timing.html`。但现有链路没有 `candidate_started` 或 `gesturekit.guardArm` 消息：App 只在手势识别完成后发布 `gesture_event`，Chrome 后台再发送 `gesturekit.resolveLastPointer`。因此 guard 不可能在未知的 DOM 点击、`selectstart` 或 `dragstart` 之前被可靠建立。

## 代码链路证据

1. `GestureKitRuntime.handle(_:)` 在 `GestureRecognizer` 已返回完整手势后才调用 `LocalEventServer.publish`。
2. Chrome `background.ts` 收到 native gesture 后调用 `resolveLastPointer()`，再向当前 tab 发送 `gesturekit.resolveLastPointer`。
3. 现有 `pointerTracker.ts` 以所有普通 HTTP 链接的 180 ms 拦截来缓解竞态；它没有候选 session、lease、tab/frame/page 绑定或单调时钟证据。

现有 jsdom 测试不能替代真实 Chrome 导航时序；timing 页面只作为后续端到端采样夹具。

## V2 决策

链接、文本选择和图片拖动的首要保护改为本地路径：`TouchBackend` 发现三指候选后立即创建一次性 `gestureSessionId`，并在短 lease 内调用已验证的 `InteractionShield`。这样浏览器默认副作用在本机输入层被拦截，不依赖 App-host-extension 往返先于 DOM。

页面 guard 保留为辅助能力和证据链：它必须记录 `candidate_started`、`guard_requested`、`guard_armed` 与 DOM 事件。未 armed、late 或 Provider 不可用时，链接动作 fail-closed；没有 `InteractionShield` 权限时，保留 V1 的有界链接点击保护作为降级路径，并记录原因。

## 后续验证

1. 将 `GestureSessionCoordinator` 与 `InteractionShield` 绑定，验证候选开始到输入屏蔽的实际时延。
2. 在真实 Chrome 中记录完整关联 ID 时间线，并覆盖标签切换、导航、worker 冷启动、断连和 iframe。
3. 验证降级路径不会让普通点击、输入框和非 Chrome 应用持续受影响。
