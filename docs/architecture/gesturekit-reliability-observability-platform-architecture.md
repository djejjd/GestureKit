# GestureKit 可靠性、可观测性与可扩展动作平台架构

日期：2026-07-10

状态：设计已确认，待实施计划

相关文档：

- `docs/product/gesturekit-v1-contract.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
- `docs/plans/gesturekit-p6-three-finger-tap-reliability-design.md`
- `docs/research/trackpad-gesture-stability-matrix.md`

## 1. 决策摘要

GestureKit 采用“macOS App 作为控制与诊断中心，动作能力通过标准 Provider 接入”的架构。

本次设计确认以下决策：

- macOS App 提供主窗口，统一承载设置、运行状态、历史诊断和证据导出。
- 菜单栏只保留常驻状态与生命周期控制；Chrome popup 只显示当前页面和连接相关信息。
- 每次三指候选从开始阶段建立统一证据链，不再只记录已经识别成功的手势。
- App 使用 SQLite 持久化结构化操作轨迹，默认保留 7 天且最多占用 50 MB。
- Chrome 扩展降级为首个 `ActionProvider`，GestureKit Core 不依赖 Chrome 专用动作。
- 手势原语、组合规则、动作绑定和动作执行分层，允许后续通过配置调整手势含义和增加适度 DIY 组合。
- 原生 `InteractionShield` 是可选增强，必须先完成权限与可靠性 Spike；失败时回退到不含原生屏蔽的基础方案，不阻塞主架构。
- 执行结果不确定时不自动重放动作，但必须记录原因并自动恢复后续通信能力。

## 2. 目标与非目标

### 2.1 目标

- 最大程度减少三指手势未生效、链接原地打开、文本选中和图片拖动等输入竞争问题。
- 让一次故障在不依赖现场复现的情况下尽可能具备事后定位证据。
- 消除 App 文件日志、扩展诊断数组和 popup 展示之间的证据割裂。
- 保持 V1 只实现 Chrome Provider，同时避免 Core、手势语义和配置模型与 Chrome 强绑定。
- 为简单手势组合和动作换绑预留稳定数据模型，不要求每次增加组合手势都修改底层识别代码。

### 2.2 非目标

- 当前阶段不实现 Safari、Firefox 或通用 macOS App Provider。
- 当前阶段不交付复杂规则编辑器、任意轨迹录制、脚本执行或通用自动化平台。
- 不承诺仅凭日志百分之百修复所有第三方页面问题；目标是将复现从必要条件降为补充手段。
- 不默认记录连续原始触控帧、键盘输入、网页正文、Cookie、表单内容或完整带参数 URL。

## 3. 总体架构

```text
macOS App
├─ GestureSessionCoordinator
├─ PrimitiveRecognizer
├─ GestureComposer
├─ BindingEngine
├─ ProviderRouter
├─ OperationJournal
├─ HealthSupervisor
├─ SettingsStore
├─ InteractionShieldBackend
│  ├─ NoopShield
│  └─ CGEventTapShield
└─ Window UI
         ↕ Local IPC
Native Host Shim
         ↕ Chrome Native Messaging / connectNative()
Chrome ActionProvider
├─ BrowserActionCoordinator
├─ ContentInteractionGuard
├─ CapabilityReporter
├─ TelemetryOutbox
└─ Popup
```

### 3.1 macOS App

macOS App 是运行时、配置和诊断的控制中心：

- `GestureSessionCoordinator`：在三指候选开始时建立会话和关联 ID。
- `PrimitiveRecognizer`：识别通用 `tap`、`swipe` 等原语及其手指数、方向、区域、时长和指标。
- `GestureComposer`：通过配置把原语组合成单击、双击、三击等手势。
- `BindingEngine`：把组合手势和上下文映射为标准 `ActionDescriptor`。
- `ProviderRouter`：根据前台上下文和 Provider 能力选择执行方。
- `OperationJournal`：持久化完整操作证据链，是历史诊断的唯一可信源。
- `HealthSupervisor`：维护监听、IPC、Provider、outbox 和超时状态，只恢复连接，不擅自重放结果不确定的动作。
- `SettingsStore`：保存全部用户配置，是唯一配置主存储。
- `InteractionShieldBackend`：隔离可选的原生输入屏蔽能力。

### 3.2 Native Host Shim

Native host 继续只做 Chrome stdio 与 App IPC 的透明桥接，不承载规则、配置、日志聚合或动作决策。Chrome Native Messaging 的连接方向仍是扩展通过 `connectNative()` 发起。

### 3.3 ActionProvider

Chrome 扩展是 V1 的首个 `ActionProvider`，而不是 Core 的固定组成部分。Provider 必须：

- 声明稳定的 `providerId`、协议版本、运行环境和能力集合。
- 接收标准 `ActionDescriptor`，自行翻译为平台 API。
- 返回接受状态和最终执行结果。
- 使用 `operationId` 去重。
- 产生可补交的阶段证据，不把 popup 生命周期当作持久化边界。

### 3.4 Provider Protocol

Provider 使用与具体浏览器无关的双向消息协议。通用 envelope 至少包含：

```json
{
  "version": 1,
  "messageId": "01J...",
  "sessionId": "provider-session-id",
  "operationId": "operation-id-or-null",
  "type": "action_request",
  "timestamp": 1782200000000,
  "payload": {},
  "error": null
}
```

标准消息类型：

- `provider_hello`：Provider 声明身份、协议版本和运行环境。
- `capability_snapshot`：Provider 声明当前支持的标准动作和上下文能力。
- `configuration_snapshot`：App 下发权威配置快照。
- `configuration_ack`：Provider 确认已应用的配置版本。
- `action_request`：App 请求执行标准 `ActionDescriptor`。
- `action_accepted`：Provider 确认已接管动作；此后结果不确定时不得自动重放。
- `action_result`：Provider 返回成功、明确失败或结果未知。
- `telemetry_batch`：Provider 批量补交阶段事件。
- `telemetry_ack`：App 确认已经持久化的事件 ID。
- `health_probe` / `health_response`：检查 Provider 和 App 会话健康状态。

协议约束：

- App 配置包含单调递增的 `configurationVersion`，Provider 只接受更新版本。
- `action_request` 必须包含 `operationId` 和动作截止时间。
- `action_accepted` 是自动重试边界，不是动作成功回执。
- `telemetry_ack` 只能在 SQLite 事务提交后发送。
- Provider 必须忽略未知可选字段，并明确拒绝不支持的主版本。
- 现有 Chrome V1 消息在迁移期间由 Chrome Provider adapter 转换，不能把旧动作枚举继续泄漏到 Core。

## 4. 手势和动作扩展模型

### 4.1 分层模型

```text
TouchBackend
→ PrimitiveRecognizer
→ GestureComposer
→ BindingEngine
→ ProviderRouter
→ ActionProvider
```

手势识别与手势含义必须解耦。Core 不得把“三指左滑”等价于“切换右侧 Chrome 标签页”。

### 4.2 GestureDefinition

适度 DIY 使用受约束的数据模型表达：

```json
{
  "id": "three-finger-triple-tap",
  "primitive": "tap",
  "fingers": 3,
  "repetitions": 3,
  "maxIntervalMs": 350,
  "region": "any"
}
```

当前模型预留以下参数：

- 原语：`tap`、`swipe`
- 手指数
- 重复次数
- 方向
- 触发区域
- 单次持续时间
- 组合间隔
- 识别阈值档位

最长匹配优先。存在三击绑定时，组合器不得在第二击后提前执行较短组合。

新增旋转、压力或任意轨迹等新原语仍需修改 `PrimitiveRecognizer`。配置扩展只承诺覆盖已有原语的参数和组合。

### 4.3 ActionDescriptor 与能力

动作使用命名空间标识，例如：

- `browser.history.back`
- `browser.history.forward`
- `browser.page.reload`
- `browser.tab.activate_previous`
- `browser.tab.activate_next`
- `browser.link.open_adjacent`

Provider 通过能力清单声明支持项。`BindingEngine` 不直接引用 `chrome.tabs`，Provider 不支持某动作时必须在保存绑定前阻止，并提供面向用户的说明。

V1 可以只提供预设和简单下拉换绑；复杂 DIY UI 是后续增强，但数据模型、接口和契约测试必须先稳定。

## 5. 单次操作状态机

每次三指候选建立 `gestureSessionId`，每个最终动作建立 `operationId`。阶段事件采用追加式记录：

```text
candidate_started
→ primitive_classified | primitive_rejected
→ composition_pending | gesture_composed
→ binding_resolved
→ provider_selected
→ interaction_guard_armed
→ action_dispatched
→ action_succeeded | action_failed | result_unknown
→ session_completed
```

约束：

- 阶段推进前先写入本地 Journal，崩溃后仍能看到最后成功位置。
- 未识别手势也必须记录距离、方向比例、持续时间、阈值和拒绝原因。
- Provider 返回 `accepted` 前发生的明确投递失败可以在有效期限内安全重试。
- Provider 已返回 `accepted` 或执行状态不确定时不得自动重放。
- Provider 使用 `operationId` 在短期窗口内拒绝重复动作。
- 旧操作进入 `result_unknown` 后不得阻塞后续新手势。
- 所有内部状态码只用于协议、数据库和证据包，不直接出现在普通界面。

## 6. OperationJournal 与证据包

### 6.1 持久化

App 使用 SQLite WAL 模式保存追加式阶段事件。默认保留策略：

- 最长 7 天。
- 数据库最多 50 MB。
- 任一限制达到时清理最旧的已完成操作。
- 正在执行的操作不得因清理任务被删除。
- UI 使用分页和聚合查询，不一次性加载全部历史。

预计单次结构化操作占用约 1 至 3 KB；默认上限下运行内存只保留当前会话和页面查询结果。

### 6.2 扩展 outbox

扩展在本地持久化尚未被 App 确认的阶段事件。App 确认写入 SQLite 后，扩展才能删除对应 outbox 项。以下情况不得丢失记录：

- popup 关闭。
- MV3 Service Worker 被回收。
- native host 或 App 短暂断开。
- 多条诊断并发产生。

App 侧以事件 ID 去重，保证补交不会生成重复记录。

### 6.3 页面证据与隐私

默认允许本地记录：

- 页面域名。
- 去除 query 和 hash 的路径。
- 目标元素类型和角色。
- 脱敏后的目标 URL 域名与路径。
- 元素定位指纹、命中结果和事件时序。
- App、Provider、协议和配置版本。

默认禁止记录：

- Cookie、Authorization、表单值和键盘输入。
- 网页正文、完整 DOM 或屏幕内容。
- URL query、hash 和连续原始触控流。
- 未经用户明确启用的网络上传。

单次操作可以导出开发者证据包，包含阶段时间线、配置快照、环境版本和脱敏页面上下文。证据包必须与普通 UI 分离。

## 7. 可靠性和交互保护

### 7.1 页面侧保护

`ContentInteractionGuard` 负责标准网页范围内的 click、`selectstart` 和 `dragstart` 防护，并记录：

- 是否命中标准链接。
- 保护是否及时建立。
- 原生 click 是否已经发生。
- 保护窗口是否过期。
- 页面是否重新触发导航。
- 指针目标是否发生变化。

页面保护失败必须产生明确阶段证据，不能归并为宽泛的“未知错误”。

### 7.2 原生 Interaction Shield

原生屏蔽不是基础方案的依赖。正式实现前先完成独立 Spike：

- 验证主动过滤需要 Input Monitoring、Accessibility，还是两者。
- 确认只注册必要的鼠标事件，不注册键盘事件。
- 验证三指候选与普通鼠标操作可以可靠区分。
- 验证文字选中、链接点击和图片拖动可以被稳定阻止。
- 验证 App 卡顿、停止或崩溃时最多 800ms 自动放行。

判定：

- `passed`：效果稳定、无普通操作误伤、权限范围可接受，允许接入 `CGEventTapShield`。
- `passed_with_notes`：需要更强权限或存在边界限制，不默认启用，提交证据后单独决策。
- `failed`：无法可靠区分或存在鼠标卡住、正常操作误伤风险，使用 `NoopShield`。

Spike 失败不得阻塞 OperationJournal、App UI、Provider 抽象或页面侧保护。

## 8. 用户界面职责

### 8.1 App 主窗口

主窗口包含：

- 概览：监听状态、Provider 状态、今日成功率和最近持续异常。
- 操作记录：按时间、手势、动作、页面、Provider 和结果筛选。
- 手势与动作：当前提供预设与简单动作换绑，为后续傻瓜式 DIY 预留入口。
- Provider：显示能力、版本和连接状态。
- 隐私与存储：保留策略、清理和证据导出。
- 高级设置：识别阈值等低频配置，默认折叠。

界面必须通过 `DiagnosticPresentationMapper` 把内部状态转换为完整中文说明。任何未知内部值都显示通用用户说明，不得直接回退显示枚举值。

### 8.2 菜单栏

菜单栏只保留：

- 正常、暂停和持续故障状态。
- 打开 GestureKit。
- 暂停或恢复手势。
- 一条最近持续故障摘要。
- 退出。

普通成功手势不得造成高频图标闪烁。

### 8.3 Chrome popup

Popup 只显示当前 Chrome 环境：

- 当前页面是否支持。
- App 和 Chrome Provider 是否连接。
- 当前手势方案名称。
- 当前页面最近一次操作结果。
- 打开 GestureKit 和查看相关操作入口。

Popup 不再承载完整设置、推荐、历史日志或开发者诊断面板。

### 8.4 通知

单次失败只写入操作记录。连续失败、Provider 持续断开或监听停止才允许产生通知，避免高频操作造成通知噪音。

## 9. 测试与验收

### 9.1 可靠性

- 三指候选无论成功、拒绝或中断都产生可查询记录。
- 普通网页标准链接三指点按连续 30 次，不得造成当前页原地打开或重复开页。
- 三指左右轻扫各 30 次，每次都有明确成功或失败结论。
- 结果未知的动作不自动重放，后续操作不受影响。
- App、host 或 Provider 断开时能指出最后完成的用户可理解阶段。

### 9.2 证据完整性

- App 重启后历史仍可查询。
- Service Worker 回收、popup 关闭和短暂断连后 outbox 能补交记录。
- 连续写入 1,000 条测试事件，不丢失、不重复、关联正确。
- 清理任务遵守 7 天和 50 MB 上限，不删除执行中操作。
- 任一失败记录可以导出独立证据包。

### 9.3 扩展性

- Core 不引用 `chrome.tabs` 或 Chrome 专用动作枚举。
- Chrome Provider 通过标准 Provider 契约测试。
- Fake Provider 可以执行相同的标准动作请求。
- 三指滑动从切换标签页改为页面后退时只修改配置。
- 三指三击可以通过配置完成组合匹配测试，不要求当前阶段提供 UI。

### 9.4 界面

- App、菜单栏和 popup 不显示内部状态码。
- 用户可以在三步内找到最近失败及其原因。
- Popup 只展示当前页面和连接相关信息。
- 菜单栏只对持续问题改变状态。

### 9.5 Interaction Shield Spike

- 文字、链接和图片上的三指左右滑各 20 次，不产生选中、拖动或原地点击。
- 普通点击、文本选择和图片拖动各 30 次，不被误拦截。
- 强制超时、停止监听和终止 App 后立即恢复正常输入。
- 未注册键盘事件，未持久化原始鼠标事件。

## 10. 对现有 V1 架构的影响

本设计不改变：

- Chrome 扩展通过 `connectNative()` 建立 Native Messaging 连接。
- 独立 native host shim 的透明桥接边界。
- `TouchBackend`、`RuleEngine` 和 App IPC 的核心职责。
- V1 只交付 Chrome 的产品范围。

本设计更新：

- 全部用户配置统一由 App `SettingsStore` 持有，扩展只保留缓存、状态和 outbox。
- Chrome 执行边界升级为通用 `ActionProvider` 接口。
- 诊断主存储从 popup/扩展环形数组迁移到 App `OperationJournal`。
- App 从纯菜单栏界面升级为菜单栏加主窗口。
- 手势识别升级为原语、组合和动作绑定分层。
- 可选增加原生 Interaction Shield 权限验证，但不将其设为基础方案必需权限。

上述更新已同步到 `docs/product/gesturekit-v1-contract.md`。进入实施前仍需基于本设计产出分阶段实施计划。
