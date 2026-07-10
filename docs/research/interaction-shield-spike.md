# InteractionShield Spike

日期：2026-07-10

## 结论

当前结论为 `passed_with_notes`。

`CGEventTap` 可以在短 lease 内拦截左键下压、拖动和释放。人工验证确认：屏蔽窗口内文本拖选/图片拖动未生效，窗口结束后普通点击恢复正常。

## 执行证据

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run InteractionShieldProbe -- --shield-delay-ms 4000 --shield-ms 4000 --duration-ms 12000
```

日志在屏蔽窗口内记录到：

- `type=1`：左键按下。
- `type=6`：左键拖动。
- `type=2`：左键释放。

上述事件均输出 `interaction_shield_event_suppressed`，进程在 12 秒后自动退出。人工确认窗口结束后普通输入恢复。

## 已确认边界

- 当前 Probe 以固定时间窗口手工触发，不代表已经和三指候选 session 绑定。
- 生产接入必须由 `GestureSessionCoordinator` 提供一次性 `gestureSessionId` 和 lease，权限不可用时回退 `NoopShield`。
- 尚未覆盖输入框、跨窗口切换、Input Monitoring/Accessibility 运行时撤销以及 event tap 超时后的真实恢复矩阵。
- 未完成上述矩阵前，`CGEventTapShield` 不能成为默认生产路径。
