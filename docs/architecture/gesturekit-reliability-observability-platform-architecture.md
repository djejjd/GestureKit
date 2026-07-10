# GestureKit 可靠性、可观测性与可扩展动作平台架构

日期：2026-07-10

状态：独立复审通过，待用户最终确认

相关文档：

- `docs/product/gesturekit-v1-contract.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
- `docs/research/trackpad-gesture-stability-matrix.md`

## 1. 决策摘要

GestureKit 采用“macOS App 作为控制与诊断中心，动作能力通过标准 Provider 接入”的架构。

本次设计确认以下决策：

- macOS App 提供主窗口，统一承载设置、运行状态、历史诊断和证据导出。
- 菜单栏只保留常驻状态与生命周期控制；Chrome popup 只显示当前页面和连接相关信息。
- 每次三指候选从开始阶段建立统一证据链，不再只记录已经识别成功的手势。
- App 使用 SQLite 持久化结构化操作轨迹，受管理诊断存储默认保留 7 天且总预算 50 MB。
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
├─ RuleEngine
│  └─ BindingResolver
├─ ProviderRouter
├─ ProviderSessionRegistry
├─ OperationJournal
├─ HealthSupervisor
├─ SettingsStore
├─ InteractionShieldBackend
│  ├─ NoopShield
│  └─ CGEventTapShield
└─ Window UI
         ↕ Authenticated Local IPC
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
- `GestureComposer`：组合 V1 已启用的单击和双击；数据模型为后续三击等组合预留扩展。
- `RuleEngine`：唯一动作决策入口；内部 `BindingResolver` 把组合手势和上下文映射为标准 `ActionDescriptor`。
- `ProviderRouter`：根据前台上下文和 Provider 能力选择执行方。
- `ProviderSessionRegistry`：认证 Provider、绑定安装身份和会话，并提供定向发送，禁止广播动作。
- `OperationJournal`：持久化完整操作证据链，是历史诊断的唯一可信源。
- `HealthSupervisor`：维护监听、IPC、Provider、outbox 和超时状态，只恢复连接，不擅自重放结果不确定的动作。
- `SettingsStore`：保存全部用户配置，是唯一配置主存储。
- `InteractionShieldBackend`：隔离可选的原生输入屏蔽能力。

### 3.2 Native Host Shim

Native host 继续只做 Chrome stdio 与 App IPC 的透明桥接，不承载规则、配置、日志聚合或动作决策。Chrome Native Messaging 的连接方向仍是扩展通过 `connectNative()` 发起。

App IPC 优先使用位于 `0700` 私有目录、权限为 `0600` 的 Unix domain socket；如果 Spike 证明目标打包环境不适用，才允许使用显式绑定 loopback 的 TCP。无论使用哪种传输，都必须满足：

- App 为每个已批准 Provider 安装生成独立凭据。
- Provider 使用安装身份、随机 challenge 和 session nonce 完成握手，不能只自声明 `providerId`。
- 一个 Provider 安装同时只允许一个活动会话；新会话替换旧会话时必须产生诊断记录。
- 手势、配置和动作只定向发送给 `ProviderRouter` 选中的已认证会话，禁止向全部本地连接广播。
- 消息大小、频率、字段和能力使用白名单校验；未认证消息不得进入 `OperationJournal`。
- V1 只批准内置 Chrome Provider。第三方 Provider 接入前必须另做威胁模型和用户授权设计。

V1 威胁范围明确为：防止误连接、陈旧 host、其他 UID 进程和未注册 Provider，不声称抵御已经在同一 macOS 用户身份下执行的恶意进程。首次安装由安装脚本生成 256-bit Provider secret，保存在 `0700` GestureKit 私有目录下的 `0600` 凭据文件中；App 保存注册记录，native host 使用 secret 对随机 challenge 做 HMAC。App 提供轮换和撤销操作，secret 不进入日志或协议明文。未来若要防御同 UID 恶意进程，必须升级到 Keychain/code-signing identity、audit token/XPC 等独立设计，不能沿用 V1 承诺。

### 3.3 ActionProvider

Chrome 扩展是 V1 的首个 `ActionProvider`，而不是 Core 的固定组成部分。Provider 必须：

- 声明稳定的 `providerId`、协议版本、运行环境和能力集合。
- 使用 App 分配的稳定安装身份完成认证，并把活动连接绑定到 `providerSessionId`。
- 接收标准 `ActionDescriptor`，自行翻译为平台 API。
- 返回接受状态和最终执行结果。
- 使用 `operationId` 去重。
- 产生可补交的阶段证据，不把 popup 生命周期当作持久化边界。

### 3.4 Provider Protocol v2

Provider 使用与具体浏览器无关的双向 v2 协议。旧 `GestureKitMessage version: 1` 是迁移输入，不得与新协议共用版本号。通用 envelope 至少包含：

```json
{
  "protocolVersion": 2,
  "messageId": "01J...",
  "providerSessionId": "provider-session-id",
  "gestureSessionId": "gesture-session-id-or-null",
  "operationId": "operation-id-or-null",
  "type": "action_request",
  "timestamp": 1782200000000,
  "payload": {},
  "error": null
}
```

标准消息类型：

- `provider_hello`：Provider 声明身份、协议版本和运行环境。
- `provider_challenge` / `provider_authenticate`：把 Provider 安装身份绑定到本次会话。
- `capability_snapshot`：Provider 声明当前支持的标准动作和上下文能力。
- `context_request`：App 请求完成规则匹配所需的当前环境事实。
- `context_snapshot`：Provider 返回带 `contextId`、页面身份、采集时间和过期时间的只读事实。
- `configuration_snapshot`：App 下发权威配置快照。
- `configuration_ack`：Provider 确认已应用的配置版本。
- `action_request`：App 请求执行标准 `ActionDescriptor`。
- `action_accepted`：Provider 确认已接管动作；此后结果不确定时不得自动重放。
- `action_result`：Provider 返回成功、明确失败或结果未知。
- `telemetry_batch`：Provider 批量补交阶段事件。
- `telemetry_ack`：App 确认已经持久化的事件 ID。
- `health_probe` / `health_response`：检查 Provider 和 App 会话健康状态。
- `operation_status_request` / `operation_status_response`：重连后查询已接受动作的持久化状态。

协议约束：

- App 配置包含单调递增的 `configurationVersion`，Provider 只接受更新版本。
- App 配置存储包含稳定 `storeEpoch` 和 `schemaVersion`；Provider 缓存的 epoch 不匹配时必须丢弃缓存并等待 App 快照。
- `action_request` 必须包含 `operationId` 和动作截止时间。
- `action_request` 必须引用仍有效的 `contextId`；Provider 必须验证页面、窗口和目标引用未过期。
- `action_accepted` 是自动重试边界，不是动作成功回执。
- `telemetry_ack` 只能在 SQLite 事务提交后发送。
- Provider 必须忽略未知可选字段，并明确拒绝不支持的主版本。
- 现有 Chrome V1 消息只在 Chrome Provider adapter 内转换为 v2；adapter 负责保存 `id -> messageId / gestureSessionId / operationId` 映射，迁移完成后删除旧协议入口。
- `context_snapshot` 只提供规则需要的标准事实和不透明 `targetRef`，不得让 Provider 根据用户绑定自行替换动作。

配置迁移采用一次性 cutover：App 尚无迁移标记时，可以向旧 Chrome adapter 请求一份 legacy 设置快照，完成校验后与迁移标记、`storeEpoch`、`configurationVersion` 在同一持久化事务中保存。此后 popup 和旧协议禁止写用户配置，任何冲突都由 App 权威快照覆盖；Provider 只能报告“已应用”或结构化失败，不能反向覆盖 App。

## 4. 手势和动作扩展模型

### 4.1 分层模型

```text
TouchBackend
→ PrimitiveRecognizer
→ GestureComposer
→ RuleEngine / BindingResolver
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

最长匹配只适用于已经启用且共享前缀的组合。每个组合定义必须声明总仲裁期限；启用较长组合时，UI 必须说明它会增加短组合等待时间，页面 guard 必须覆盖完整仲裁窗口。禁用较长组合后不得继续引入额外等待。

新增旋转、压力或任意轨迹等新原语仍需修改 `PrimitiveRecognizer`。配置扩展只承诺覆盖已有原语的参数和组合。

### 4.3 ActionDescriptor 与能力

动作使用命名空间标识，例如：

- `browser.history.back`
- `browser.history.forward`
- `browser.page.reload`
- `browser.tab.activate_previous`
- `browser.tab.activate_next`
- `browser.tab.close_current`
- `browser.link.open_adjacent`

标准动作描述至少包含：

```json
{
  "actionId": "browser.link.open_adjacent",
  "contextId": "short-lived-context-id",
  "targetRef": "opaque-provider-target-ref-or-null",
  "parameters": { "activate": true },
  "deadline": 1782200001000
}
```

`targetRef` 是否必需由动作 schema 决定；页面链接动作必须提供，标签页切换等上下文动作可以为空。Provider 通过能力清单声明支持项。`RuleEngine` 不直接引用 `chrome.tabs`，Provider 也不得改变 `actionId`。绑定可以在 Provider 离线或暂不支持时保存，但必须标记目标 Provider scope 和验证状态；只有 schema 无效的动作才禁止保存。执行时由 `ProviderRouter` 使用最新能力快照判断，并返回结构化不可用原因。

V1 UI 只提供预设，不交付动作换绑编辑器。三击、任意新组合、简单下拉换绑、完整 DIY UI 和分享配置属于后续增强；当前实现配置驱动的规则输入并冻结版本化 `GestureDefinition` / `ActionDescriptor` schema、组合期限字段和迁移规则，不把三击匹配或换绑 UI 作为 V1 验收项。

## 5. 单次操作状态机

每次三指候选建立 `gestureSessionId`，每个最终动作建立 `operationId`。候选保护与手势决策是两条共享 session 的并行轨迹，不能用一个错误的串行状态机表达：

```text
候选保护轨：
candidate_started
→ guard_requested
→ guard_armed | guard_unavailable | guard_late
→ guard_consumed | guard_released | guard_expired

决策执行轨：
candidate_started
→ primitive_classified | primitive_rejected
→ provider_selected
→ [composition_pending || context_requested]
→ [gesture_composed || context_received | context_unavailable | context_expired]
→ binding_resolved | no_binding
→ action_requested
→ action_accepted | action_rejected
→ action_succeeded | action_failed | result_unknown
→ session_completed
```

约束：

- `gestureSessionId` 由 App 在候选开始时生成；一个组合手势可以引用多个输入 `gestureSessionId`。
- `operationId` 由 `RuleEngine` 产生，一个组合结果可以产生零或一个 V1 动作。
- `messageId` 标识一次传输消息，`eventId` 标识一条不可变阶段事件；补交时 `eventId` 保持不变。
- 每个生产者记录 `producerSessionId`、单调递增 `producerSequence`、单调时钟和 wall-clock；`causedByEventId` 表达跨进程因果关系。
- App 本地产生的阶段在推进前写入 Journal；Provider 产生的阶段在推进前写入自己的事务性 outbox，不能假装远端 App 已经持久化。
- `guard_requested` 必须由候选开始直接触发，不等待原语分类、context snapshot 或规则绑定。
- 原语分类后，组合仲裁与 context 获取并行。标准链接事实一旦返回，立即剪枝只适用于 `no link` 的双击规则；边缘单击同样不等待中间双击窗口。
- 未识别手势也必须记录距离、方向比例、持续时间、阈值和拒绝原因。
- Provider 必须在执行副作用前把 `operationId` 和 `accepted` 状态提交到持久化 operation ledger；提交失败则不得执行动作。
- Provider ledger 已存在相同 `operationId` 时返回已有接受状态或最终结果，不得再次执行。
- App 只有在收到明确的认证/传输拒绝且 Provider ledger 确认不存在该 `operationId` 时才允许在截止时间前重发；其他不确定情况进入对账，不能自动重放。
- Provider 重启或 Service Worker 回收后必须保留 ledger，保留期覆盖 Journal 保留期；无法确认副作用是否发生时返回 `result_unknown`。
- 旧操作进入 `result_unknown` 后不得阻塞后续新手势。
- 所有内部状态码只用于协议、数据库和证据包，不直接出现在普通界面。

## 6. OperationJournal 与证据包

### 6.1 持久化

App 使用 SQLite WAL 模式保存追加式阶段事件。Schema 至少包含 session、operation、event、provider session 和 configuration snapshot 表，并满足：

- `eventId` 唯一索引，重复补交不重复落库。
- `producerSessionId + producerSequence` 唯一约束，用于检测缺口和乱序。
- session、operation 和输入 session 关系使用外键；组合手势保留全部输入关联。
- 只接受声明过的状态迁移；乱序事件先保存为待归并事实，不覆盖已经确认的终态。
- App 启动时扫描超过 lease/deadline 的未完成记录，按最后可靠阶段收敛为“操作中断”或“结果未知”，之后才允许进入清理。

受管理诊断存储总预算为 50 MB：App 主库、WAL、SHM 和辅助结构化日志合计最多 45 MB，V1 Chrome Provider 的 outbox、operation ledger 和诊断缓存合计最多 5 MB。默认保留策略：

- 最长 7 天。
- 总受管理诊断存储最多 50 MB。
- 任一限制达到时清理最旧的已完成操作。
- 正在执行的操作不得因清理任务被删除。
- 超过 lease/deadline 的孤儿记录必须先收敛为终态，不能永久绕过容量限制。
- 清理后执行 WAL checkpoint；磁盘不足或 checkpoint 失败时停止采集低优先级成功指标，但保留失败、结果未知和存储降级摘要。
- 如果 Journal 无法持久化新的 `candidate_started` 或 operation 关键阶段，HealthSupervisor 必须暂停新动作派发并显示持续故障，禁止产生无证据副作用。
- UI 使用分页和聚合查询，不一次性加载全部历史。

预计单次结构化操作占用约 1 至 3 KB；默认上限下运行内存只保留当前会话和页面查询结果。

### 6.2 扩展 outbox

扩展使用 IndexedDB 事务或等价单写者事务队列，持久化尚未被 App 确认的全部 Provider 生命周期事件，包括 `action_accepted`、`action_result` 和一般 telemetry。App 确认写入 SQLite 后，扩展才能删除对应 outbox 项。以下情况不得静默丢失记录：

- popup 关闭。
- MV3 Service Worker 被回收。
- native host 或 App 短暂断开。
- 多条诊断并发产生。

App 侧以事件 ID 去重，保证补交不会生成重复记录。

Outbox 规则：

- `telemetry_ack` 明确列出已经提交的 `eventId`，不使用可能跨并发写入的模糊高水位。
- `ledger.accepted` 与对应 `action_accepted` outbox event 必须在同一个 IndexedDB 事务提交；`ledger.final` 与对应 `action_result` event 也必须在同一个事务提交。
- ACK 删除只删除已确认 outbox event，不得修改 operation ledger；其他一般 telemetry 的追加、批量发送和 ACK 删除必须事务化或由单写者串行化。
- 达到 5 MB 或 7 天上限时，优先保留失败、`action_accepted`、`action_result` 和结果未知事件；成功指标可以压缩为带缺口范围的 `telemetry_gap_summary`，不得无提示覆盖。
- 如果 operation ledger 和关键 outbox 事件仍无法持久化，Provider 必须在副作用前拒绝新动作并返回 `provider_storage_full`，不能执行没有持久证据的动作。
- 重连先完成 Provider 会话认证，再执行 operation ledger 对账，最后按 producer sequence 补交 outbox。

容量策略：App 确认最终事件后，Provider 在 10 分钟对账宽限期结束时把完整 completed ledger 压缩为只含 `operationId`、终态、result digest 和 expiry 的去重 tombstone。Tombstone 连同 IndexedDB 索引开销目标不超过 256 bytes，保留 7 天；5 MB 中至少预留 1 MB 给未确认关键事件。验收必须用 10,000 个 tombstone、24 小时离线 outbox 峰值和满载后 ACK 回收证明预算可行，不能只依据字段估算。

### 6.3 页面证据与隐私

默认允许本地记录：

- 页面 scheme 分类和 host；可显示域名与敏感值分开处理。
- 永久移除 query 和 hash 的脱敏路径：Provider 在采集源把邮箱、UUID、长数字、疑似 token 等敏感段替换为使用本地 redaction key 生成的 HMAC 短指纹，只传输指纹。
- 目标元素类型和角色。
- 脱敏后的目标 URL host 与路径指纹。
- 枚举化 tag/role、命中结果和事件时序。
- App、Provider、协议和配置版本。

默认禁止记录：

- Cookie、Authorization、表单值和键盘输入。
- 网页正文、完整 DOM、屏幕内容、原始 element id/class/text。
- URL query、hash 和连续原始触控流。
- 未经用户明确启用的网络上传。

脱敏必须执行两次：Provider 采集源只产生结构化白名单字段，App 入库前再次校验和脱敏。Provider 自由文本 `message/details` 不得直接持久化；无法映射的字段只记录字段名和拒绝原因。

单次操作可以导出版本化开发者证据包，包含阶段时间线、配置 hash/允许字段、环境版本、脱敏页面上下文以及 schema/redaction 版本。导出前再次脱敏并由用户确认，文件权限使用 `0600`；UI 必须说明导出副本不再受 7 天/50 MB 自动清理控制。证据包必须与普通 UI 分离。

证据包 manifest 至少包含：

- `evidenceSchemaVersion`、`redactionVersion` 和导出时间。
- App、Provider 和 producer boot/session ID。
- `gestureSessionId`、输入 session 列表、`operationId`、`eventId`、`causedByEventId`。
- producer sequence、wall-clock、单调时钟值及各进程时间基准。
- 配置 `storeEpoch/schemaVersion/configurationVersion/hash` 和执行时能力快照版本。
- context/guard/action 的结构化阶段、终态、缺失事件范围及缺失原因。
- 脱敏页面指纹和目标类型，不包含可逆 targetRef。

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

页面 guard 默认处于未 armed 状态。App 在候选开始时通过已认证 Provider 会话发送带 `gestureSessionId`、单调时间和 lease 的 guard 请求；Provider 只允许当前页面消费一次。Spike 必须先证明候选信号能在目标 DOM 事件前到达。若无法满足时序，页面 guard 只能作为降低概率的兼容措施，不得宣称能够完全阻止原地点击、选择或拖动，也不得通过长期拦截所有普通点击规避该限制。

对链接点按，`guard_armed` 是动作派发前置条件。Guard 未及时 armed 时 Provider 必须拒绝 `browser.link.open_adjacent`；如果时序 Spike 无法稳定做到先于目标 DOM 事件 armed，则链接点按功能不得通过 V1 验收。该阻塞只针对基础页面 guard；原生 `CGEventTapShield` 仍是可选增强。

V1 延迟预算：正常已连接状态下，context snapshot 从请求到返回硬上限 120ms；标准链接和边缘单击从原语分类到 `action_requested` 硬上限 150ms。中间双击仲裁窗口默认最多 300ms，第二次点按分类后 150ms 内发出动作请求。Guard lease 默认 800ms，并允许在同一有效候选持续期间有界续租；所有 SLA 使用单调时钟记录并进入证据包。

### 7.2 原生 Interaction Shield

原生屏蔽不是基础方案的依赖。正式实现前先完成独立 Spike：

- 验证主动过滤需要 Input Monitoring、Accessibility，还是两者。
- 确认只注册必要的鼠标事件，不注册键盘事件。
- 验证三指候选与普通鼠标操作可以可靠区分。
- 验证文字选中、链接点击和图片拖动可以被稳定阻止。
- 将 fail-open 定义为“候选 lease 到期后不再拦截后续事件”；已经被 active filter 删除的事件不恢复、不缓存重放。
- 验证 App 卡顿、停止、SIGKILL、睡眠唤醒和权限撤销后，后续事件恢复时间及系统行为。
- 验证干净 TCC、正式签名和打包形态下，基础 TouchBackend 与 active event filter 分别需要哪些权限。

判定：

- `passed`：效果稳定、无普通操作误伤、权限范围可接受，并且 800ms 候选 lease 目标有实测证据，允许接入 `CGEventTapShield`。
- `passed_with_notes`：需要更强权限或存在边界限制，不默认启用，提交证据后单独决策。
- `failed`：无法可靠区分或存在鼠标卡住、正常操作误伤风险，使用 `NoopShield`。

Spike 失败不得阻塞 OperationJournal、App UI、Provider 抽象或页面侧保护。完成 clean-TCC Spike 前，文档和 UI 只能表述“基础方案预期不需要 Input Monitoring/Accessibility”，不能表述为已经证实。

## 8. 用户界面职责

### 8.1 App 主窗口

主窗口包含：

- 概览：监听状态、Provider 状态、今日成功率和最近持续异常。
- 操作记录：按时间、手势、动作、页面、Provider 和结果筛选。
- 手势与动作：V1 提供预设，并为后续简单换绑和傻瓜式 DIY 预留入口。
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
- 对 action ledger 的写入前后、动作前后、结果写入前后和回执发送前后逐点故障注入；每个 `operationId` 的副作用最多执行一次。
- 链接单击、边缘单击和中间双击分别验证 120/150/300ms 延迟预算以及 guard lease 覆盖，不允许较长组合给无共享前缀动作增加等待。

### 9.2 证据完整性

- App 重启后历史仍可查询。
- Service Worker 回收、popup 关闭和短暂断连后 outbox 能补交记录。
- 并发写入、重复 batch、乱序 ACK、Service Worker 强杀和短暂断连后，不丢失关键事件、不重复落库，并能识别压缩缺口。
- 清理任务遵守 7 天和 50 MB 上限，不删除执行中操作。
- 任一失败记录可以导出独立证据包。
- 证据包完整性校验器能验证 ID 关系、producer sequence、配置/能力版本、guard 时序、终态和缺失原因。
- 故障矩阵固定覆盖断连 1/10/60 秒、4 个并发事件来源、100 events/s 持续 60 秒，以及 worker 在 accepted/final 原子事务提交前后强杀。每个 golden fixture 明确期望终态、最后可靠阶段、副作用是否发生、缺失范围和禁止重放结论。

### 9.3 扩展性

- Core 不引用 `chrome.tabs` 或 Chrome 专用动作枚举。
- Chrome Provider 通过标准 Provider 契约测试。
- V1 使用 Fake Provider 验证认证、上下文快照、标准动作请求和结果回执，不要求交付第二个真实 Provider。
- 使用 Fake Provider 验证三指滑动从切换标签页改为页面后退时 Core 只修改配置；V1 Chrome UI 不要求暴露该换绑入口。
- `GestureDefinition` schema 能向前兼容包含重复次数的未来 fixture；V1 不要求实现三指三击匹配或 UI。

### 9.4 界面

- App、菜单栏和 popup 不显示内部状态码。
- 用户可以在三步内找到最近失败及其原因。
- Popup 只展示当前页面和连接相关信息。
- 菜单栏只对持续问题改变状态。

### 9.5 Interaction Shield Spike

- 文字、链接和图片上的三指左右滑各 20 次，不产生选中、拖动或原地点击。
- 普通点击、文本选择和图片拖动各 30 次，不被误拦截。
- 强制超时、停止监听、SIGKILL、睡眠唤醒和权限撤销后，后续输入按实测结论恢复；已删除事件不要求重放。
- 未注册键盘事件，未持久化原始鼠标事件。

## 10. V1 必需项与后续增强

### 10.1 V1 必需项

- App 主窗口、`OperationJournal`、用户可理解诊断和证据导出。
- Provider Protocol v2 的认证、能力、上下文、配置、动作、operation ledger、结果、telemetry ACK 和健康最小消息集。
- Chrome Provider adapter 与一个 Fake Provider 契约测试。
- 当前三指点按、双击、左右轻扫行为；Core 使用配置驱动规则，不交付动作换绑 UI。
- App 配置单一主存储和 legacy 设置一次性迁移。
- 页面 guard 时序 Spike；无法证明及时 arm 时明确降级能力。

### 10.2 后续非阻塞增强

- 第二个真实浏览器或 App Provider。
- 第三方 Provider 安装、分发和权限市场。
- 三击及更多组合手势的运行时匹配。
- 简单动作换绑 UI、完整 DIY 编辑器、配置分享和任意轨迹录制。
- `CGEventTapShield` 正式接入；只有独立 Spike 为 `passed` 且用户接受权限后才进入实施。

## 11. 对现有 V1 架构的影响

本设计不改变：

- Chrome 扩展通过 `connectNative()` 建立 Native Messaging 连接。
- 独立 native host shim 的透明桥接边界。
- `TouchBackend`、`RuleEngine` 和 App IPC 作为本地桥接的角色；App IPC 的传输、认证和路由实现会升级。
- V1 只交付 Chrome 的产品范围。

本设计更新：

- 全部用户配置统一由 App `SettingsStore` 持有，扩展只保留缓存、状态和 outbox。
- Chrome 执行边界升级为通用 `ActionProvider` 接口。
- 诊断主存储从 popup/扩展环形数组迁移到 App `OperationJournal`。
- App 从纯菜单栏界面升级为菜单栏加主窗口。
- 手势识别升级为原语、组合和动作绑定分层。
- App IPC 升级为已认证 Provider 会话和定向路由，移除本地广播语义。
- 可选增加原生 Interaction Shield 权限验证，但不将其设为基础方案必需权限。

上述更新已同步到 `docs/product/gesturekit-v1-contract.md`。进入实施前仍需基于本设计产出分阶段实施计划。
