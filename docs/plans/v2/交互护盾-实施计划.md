# 配置派生交互保护实施计划

**Goal:** 将链接点击保护从硬编码三指路径迁移为由 App 手势绑定派生的候选期特征。

## Task 1: 配置模型与编译计划

- 在 `GestureKitCore` 增加 `InteractionGuardFeature`、`RecognitionPlan` 和配置化 `gestureDefinitions`。
- 为默认三指点按定义派生 `.linkClick`。
- 为二指点按配置预留相同的定义/绑定路径。
- 测试：链接动作绑定产生 `.linkClick`；非链接绑定不产生；替换定义 ID 后特征跟随新定义。

## Task 2: 候选期 App 路由

- 使候选事件携带定义 ID 和派生 guard 特征。
- `GestureSessionCoordinator` 仅对 `.linkClick` 会话调用 guard router。
- 手势拒绝、非链接解析和 deadline 路径发送 release。
- 测试：非链接候选绝不 arm；链接候选 arm 并在非链接终态 release。

## Task 3: Chrome 暂存点击协议

- Content script 将有效 `linkClick` guard 内的单次 HTTP/HTTPS 主链接点击暂存。
- consume 后由 Provider 创建新标签；release/超时后恢复该点击的原页面导航。
- 删除无条件全局链接拦截，普通点击不受影响。
- 测试：受 guard 的链接不在原标签导航；无 guard 普通点击立即导航；超时恢复导航。

## Task 4: 配置同步与端到端验证

- App 配置快照包含仅需的 guard 计划摘要，不向 Provider 传递完整用户绑定。
- 验证默认三指点按和模拟二指点按定义的保护边界。
- 运行 `swift test`、Chrome `npm test`、`npm run build` 与 Provider 协议 smoke。
