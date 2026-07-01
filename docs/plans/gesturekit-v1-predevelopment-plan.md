# GestureKit V1 正式开发前路线图

日期：2026-06-23

## 1. 目的

本路线图定义进入正式 V1 实施计划前必须完成的前期验证。它不是实现计划，不要求交付产品功能；它只验证 GestureKit V1 中最不确定、最容易影响架构的技术链路。

正式开发前必须先确认：

- 触控板三指事件能否稳定采集。
- Chrome Native Messaging 长连接模型能否稳定工作。
- Chrome extension 能否用最近网页 pointer 位置可靠识别普通链接。

## 2. 原则

- 先验证不确定性，再扩大工程面。
- Spike 只做风险验证，不做产品化 UI。
- 每个 spike 必须有明确退出标准。
- Spike 失败不等于项目失败，但必须回到技术设计修订。
- 不把 spike 中的临时代码直接视为 V1 架构代码。

## 3. Spike 1：触控板输入验证

目标：

- 验证 OpenMultitouchSupport / `MultitouchSupport.framework` 能否在当前 macOS 环境中采集全局触控板输入。
- 验证三指 tap、三指左滑、三指右滑能否被稳定区分。

验证范围：

- MacBook 内置触控板。
- Magic Trackpad，如当前环境具备。
- Chrome 前台、非 Chrome 前台、全屏 Chrome。
- 系统三指手势开启和关闭时的行为差异。

输出：

- 原始事件字段观察记录。
- 手势识别阈值初稿。
- 已知冲突和不可支持场景。
- 是否需要 Accessibility / Input Monitoring 的实际观察。

通过标准：

- 能连续识别三指 tap。
- 能连续识别三指左右滑。
- 能给出误识别和丢失事件的主要原因。
- 能明确私有 API backend 是否足以支撑 V1。

失败处理：

- 如果全局采集不可用，回到输入 backend 选型。
- 如果三指 swipe 与系统手势冲突严重，考虑 V1 改用其他手势或要求用户关闭特定系统手势。

## 4. Spike 2：Native Messaging 长连接验证

目标：

- 验证 Chrome MV3 extension 使用 `connectNative()` 连接 native host。
- 验证 native host shim 能通过 stdio 接收和发送 JSON message。
- 验证 service worker 重启、native host 断开后的诊断和重连策略。

验证范围：

- extension -> native host 的 `hello`。
- native host -> extension 的模拟 `gesture_event`。
- extension -> native host 的 `action_result`。
- native host 退出后的 `onDisconnect`。

输出：

- host manifest 安装路径和格式。
- extension ID 绑定方式。
- 消息 schema 初稿。
- 断线和重连行为记录。

通过标准：

- extension 能稳定连接 native host。
- native host 能向 extension 推送模拟事件。
- 断开后 extension 能记录明确错误。
- 协议字段能覆盖 `version`、`id`、`type`、`timestamp`、`payload`、`error`。

失败处理：

- 如果 long-lived port 不稳定，先修订通信设计。
- 不允许退回到 macOS App 主动向 extension 发消息的错误模型。

## 5. Spike 3：链接命中验证

目标：

- 验证 content script 记录最近 pointer viewport 坐标的策略。
- 验证三指点按事件到达后，extension 能用最近坐标识别普通 `<a href>` 链接。
- 验证无链接、过期坐标、不可注入页面的降级状态。

验证范围：

- 普通文本链接。
- 图片包裹链接。
- 空白区域。
- `chrome://` 页面。
- Chrome Web Store 或其他不可注入页面。
- 页面滚动后的位置新鲜度。

输出：

- link resolver 行为记录。
- URL scheme 过滤记录。
- `no_recent_pointer`、`no_target`、`page_unavailable` 等错误状态验证。
- iframe 和 shadow DOM 的观察记录，只做 follow-up。

通过标准：

- 普通 `<a href>` 能识别并返回绝对 `http:` 或 `https:` URL。
- 非链接区域不会误打开。
- 最近 pointer 过期时不会用旧坐标执行动作。
- 不可注入页面返回明确状态。

失败处理：

- 如果 last pointer 策略不可靠，先修订链接识别设计。
- 不得默认改为 native 屏幕坐标直接转换 DOM 坐标，除非更新契约并重新评审。

## 6. Spike 后设计修订

三个 spike 完成后，必须回到以下文档做一次修订检查：

- `docs/product/gesturekit-v1-contract.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
- `docs/adr/`

修订检查重点：

- V1 三个功能是否仍可按契约交付。
- 技术设计是否需要调整 backend、通信或链接识别策略。
- 验收矩阵是否需要新增或删减。
- 是否有 spike 发现应作为 V1 阻塞项。

## 7. 进入正式产品实现计划的条件

只有满足以下条件，才开始编写或执行后续正式产品实现计划。正式产品实现计划建议使用稳定路径 `docs/plans/gesturekit-v1-product-implementation-plan.md`。

现有 `docs/plans/gesturekit-v1-implementation-plan.md` 是正式开发前 spike 执行计划，不代表后续产品实现计划。

- 三个 spike 均完成或给出明确替代方案。
- `docs/research/trackpad-gesture-stability-matrix.md` 已完成，并给出 `passed` 或 `passed_with_notes` 结论。
- 契约没有未解决冲突。
- 主技术设计已根据 spike 结果更新。
- V1 验收标准仍然可执行。
- 用户确认进入正式实现阶段。

如果手势稳定性矩阵结论为 `blocked`，不得进入正式实现阶段。应先回到输入 backend、手势阈值或 V1 手势选择重新评审。
