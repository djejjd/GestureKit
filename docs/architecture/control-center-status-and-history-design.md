# 控制中心状态与操作记录设计

> 状态：已确认，2026-07-16。

## 目标

修复控制中心长期显示“正在准备”的问题，使概览和 Provider 页面反映真实连接状态；同时将操作记录的日常展示限制为最近 50 条，并提供不删除诊断账本的“清空列表显示”功能。

## 范围

本次只修改 macOS 控制中心、Provider v2 连接/能力上报链路及其测试。不会改变手势规则、动作语义、账本自动保留策略、诊断日志或证据包内容。

## 状态模型

运行状态必须由 App 实际监听状态驱动，分为“正在启动”“手势监听正在运行”“手势监听已停止”和“无法开始手势监听”。控制中心在打开期间定时刷新快照，Provider 连接、认证或配置状态发生变化后不需要用户点击页面才能更新。

Chrome Provider 状态分为“Chrome 尚未连接”“正在认证 Chrome Provider”“Chrome Provider 已连接”和“当前预设正在同步”。只有完成 Provider 认证且收到配置确认后，才显示已连接和已应用；断开后立即回落为未连接或中断状态。

## 能力展示

Chrome Provider 在认证完成后发送 `capability_snapshot`，声明实际可执行的标准动作。App 把该快照保存到活动会话，Provider 页面逐项显示已声明能力，而不是使用 App 侧的默认全集或仅显示数量。

当前 Chrome Provider 的标准能力为：

- `browser.link.open_adjacent`：打开链接
- `browser.tab.activate_previous`：切换到前一个标签
- `browser.tab.activate_next`：切换到后一个标签
- `browser.tab.close_current`：关闭当前标签
- `browser.history.back`：后退
- `browser.history.forward`：前进
- `browser.page.reload`：刷新页面

普通 UI 只显示中文名称，不显示协议枚举、安装凭据、会话 ID、nonce 或 HMAC。

## 操作记录

操作记录列表最多展示最近 50 个未隐藏操作，不再提供无限“加载更多”。详情、证据导出和空状态保持现有语义。

“清空列表显示”不是删除操作：它持久化一个展示截点，使截点之前的操作在控制中心中隐藏，截点之后的新操作继续显示。它不得删除或修改 SQLite `OperationJournal`、结构化诊断日志、Provider outbox 或已导出的证据包。7 天/50 MB 的自动保留与容量治理不变。

按钮必须显示为“清空列表显示”，并以二次确认说明“不会删除本地诊断日志或已导出的证据包”。

## 验收标准

- App 启动、监听失败、停止、Provider 未连接、认证中、已连接、配置同步和断连状态均有中文且可自动更新的状态文案。
- 认证后的 Chrome Provider 能力来自其 `capability_snapshot`，页面逐项展示实际声明的能力。
- 操作记录首次和任何刷新后最多显示 50 条；清空列表显示后旧记录不再出现，新记录仍可出现。
- 清空列表显示前后的 `OperationJournal` 查询结果不变，诊断日志和导出证据包不被删除。
- 普通 UI 不泄露协议内部字段或诊断敏感数据。
