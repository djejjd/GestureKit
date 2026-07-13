# Task 7 交接报告：候选手势、组合和 provider-neutral 规则

## 完成内容

- `GestureRecognizer.observe` 现在返回 `GestureSessionEvent` 数组：首次恰好三指触摸产生 `candidateStarted`；会话结束时产生 `primitiveClassified` 或 `primitiveRejected`。
- 新增 `GestureCandidate`、`GestureSessionEvent` 以及已分类手势提取器，旧运行时和 Trackpad 输入 probe 仅适配新事件输出，不改变 V1 手势分类范围。
- 新增 `ComposedGesture`、`ProviderContextSnapshot` 与 `RuleResolving`。`RuleEngine.resolve` 的输入/输出均为 provider-neutral 的组合手势、标准上下文事实和 `ActionDescriptor`。
- `BindingResolver` 在 RuleEngine 内部映射六项 V1 预设：标准链接打开相邻标签、左右边缘点按切换标签、中间双击关闭标签、左右轻扫切换标签。标准链接缺少 `targetRef` 时 fail-closed。
- 新增 `GestureSessionCoordinator`：候选开始先产生 session ID，再同步调用 journal 与定向 guard 路由；原语分类时用单调时钟发起 context 请求并保存 120 ms context、150 ms action、300 ms 中间双击窗口常量。边缘点按和轻扫不等待双击窗口。

## RED -> GREEN 证据

1. 添加 `GestureSessionEventTests` 与规则事实测试后，初次 `swift test --filter GestureSessionEventTests` 因缺失 `GestureSessionEvent` / 新规则上下文 API 无法建立测试；之后本机工具链还暴露出模块缓存权限问题。
2. 添加 coordinator 候选 guard 测试后，协调器类型尚不存在；实现后测试通过。
3. GREEN 聚焦结果：
   - `GestureSessionEventTests`：1 passed。
   - `RuleEngineTests`：6 passed。
   - `GestureSessionCoordinatorTests`：1 passed。

## 最终验证

命令均以 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 和 `/tmp` 模块缓存运行（默认沙箱无法写 Xcode 模块缓存）：

- `swift test`：127 passed，0 failed。
- `swift build`：passed。
- `git diff --check`：passed。

## 范围自审与已知限制

- `spikes/trackpad-input/.../main.swift` 的唯一修改是从事件数组中抽取 `recognizedGesture`，是 `GestureRecognizer.observe` 签名变化的直接编译兼容调整。
- `Runtime.swift` 的修改同样仅为该 API 兼容；完整 runtime 到 coordinator 的替换属于后续集成工作，未在本任务扩大执行路径。
- `guardJournal` / `guardRouter` 由 coordinator 注入，以维持 App 边界和定向路由；Task 8 前没有 Chrome guard 或 `InteractionShield` 行为。
- 项目仍保留旧的 `Rule` / `ActionType` 存量设置模型以避免本任务扩大设置迁移；新的 `RuleResolving` 路径不以该 Chrome 旧动作模型为输入或输出。后续应在配置迁移任务中删除旧模型并将 Runtime 完整切换到 coordinator。
- 未改变 V1 手势识别范围、权限或 TCC 路径；page-guard 仍不是唯一 guard，clean-TCC 仍未验证。
