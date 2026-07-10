# GestureKit V1 设计开发契约

日期：2026-06-23

更新日期：2026-07-10

相关文档：

- `docs/product/gesturekit-v1-requirements.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
- `docs/architecture/gesturekit-reliability-observability-platform-architecture.md`
- `docs/plans/gesturekit-v1-predevelopment-plan.md`
- `docs/research/trackpad-gesture-stability-matrix.md`
- `docs/adr/0001-use-native-host-shim.md`
- `docs/adr/0002-use-extension-last-pointer-position.md`
- `docs/adr/0003-use-rules-engine-from-v1.md`

## 1. 契约目的

本契约定义 GestureKit V1 的设计、开发、审核和验收边界。后续实现、代码审核、测试验收和需求讨论都以本契约为基准。

契约目标：

- 防止 V1 范围在开发中漂移。
- 防止审核无限扩大到 V1 以外的问题。
- 防止实现为了通过局部审核而偏离已批准架构。
- 给每个阶段提供可判定的完成标准。

## 2. 契约层级

后续工作按以下优先级判断：

1. 用户明确的新指令。
2. 本契约。
3. V1 技术设计文档。
4. 实施计划。
5. 代码实现细节。

如果实施计划或代码实现与本契约冲突，必须先更新契约或设计文档并获得确认，再继续实现。

## 3. V1 交付范围

V1 交付以下用户可见行为：

- 三指点按普通网页链接，在当前 Chrome 窗口的当前标签右侧打开并自动切换到新标签。
- 三指点按空白处左/右边缘，切换当前 Chrome 窗口的左/右标签页。
- 三指双击空白处中间区域，关闭当前标签页。
- 三指快速左轻扫，切换到当前 Chrome 窗口右侧标签页。
- 三指快速右轻扫，切换到当前 Chrome 窗口左侧标签页。

V1 必须保留扩展空间，但不交付完整扩展能力。

## 4. V1 非目标

以下内容不得在 V1 中作为必须完成项：

- 完整规则编辑器。
- 多浏览器支持。
- Safari 或 Firefox 支持。
- 多 App 自动化平台。
- 复杂手势录制。
- 云同步。
- AppleScript 动作。
- shell command 动作。
- Mac App Store 分发。
- Chrome Web Store 发布。
- 复杂 iframe 链接识别。
- closed shadow DOM 链接识别。
- JS click handler 导航识别。
- tab group、pinned tab、split view 的特殊语义处理。

V1 不实现其他浏览器或其他 App Provider，但 Core、手势定义、动作描述和 Provider 接口不得与 Chrome 强绑定。

如果开发或审核发现这些能力相关的问题，应记录为后续事项，除非它们阻断 V1 核心功能。

## 5. 架构约束

V1 实现必须遵守以下架构边界：

- macOS App 负责触控板输入、手势原语识别、手势组合、规则配置、动作绑定、Provider 路由、本地事件源和持久化诊断。
- Chrome 扩展是 V1 的首个 `ActionProvider`，负责网页语义、链接识别和 Chrome 动作，不得成为 Core 的固定依赖。
- Chrome Native Messaging 的连接方向必须是扩展通过 `connectNative()` 连接 native host。
- V1 使用独立 native host shim 桥接 Chrome stdio 协议和 GestureKit App 本地 IPC。
- 触控板输入必须通过 `TouchBackend` 抽象，`MultitouchSupportBackend` 不得泄漏到业务规则层。
- 用户配置的唯一 source of truth 是 macOS App 的 `SettingsStore`，包括规则、动作绑定、阈值、冷却、开关和轻扫灵敏度。
- Chrome `chrome.storage.local` 或等价扩展存储只允许保存扩展侧状态、配置缓存和待补交诊断，不得成为用户配置或历史诊断主存储。
- 规则匹配必须通过 `RuleEngine`，不得把核心三条动作硬编码在 UI、输入层或 Chrome 执行层。
- 手势原语、手势组合、动作绑定和动作执行必须分层；已有原语的次数、方向、区域、时间窗口和动作含义应能通过配置变更。
- 动作使用标准 `ActionDescriptor`，由 `ProviderRouter` 按能力选择 Provider；Core 不得引用 Chrome API 或 Chrome 专用动作枚举。
- 每次三指候选从开始阶段建立统一关联 ID，成功、拒绝、中断和结果未知都必须写入 App `OperationJournal`。
- App `OperationJournal` 是历史诊断的唯一可信源；扩展待补交队列必须在 App 确认持久化后才能删除。
- V1 不把 native 屏幕坐标转换为 DOM 坐标作为链接识别主路径。
- 三指点按链接识别主路径是 content script 记录最近网页 viewport pointer 坐标。

## 6. 安全和隐私约束

V1 必须遵守：

- 不上传浏览历史、页面内容、原始触控数据或规则配置。
- 本地诊断允许记录页面域名、移除 query 和 hash 的路径、目标元素类型、脱敏目标地址和事件时序，用于事后定位。
- 本地诊断不得记录 Cookie、表单值、键盘输入、网页正文或完整 DOM。
- 结构化操作记录默认最长保留 7 天且数据库最多 50 MB，任一上限达到时清理最旧的已完成操作。
- 不记录连续原始输入流，除非用户显式开启诊断模式。
- Native message 只在本机扩展、native host 和 GestureKit App 之间传输。
- 网页 DOM 命中结果视为不可信输入，URL 必须规范化和过滤。
- V1 只允许打开 `http:` 和 `https:` 链接。
- Native host manifest 的 `allowed_origins` 必须绑定具体扩展 ID，不能使用通配符。

## 7. 权限约束

V1 权限说明必须精确：

- `MultitouchSupport.framework` 是私有 API，自用和开源实验可接受，不适合 Mac App Store。
- Accessibility 只在读取 AX、模拟键鼠或控制 UI 时需要。
- Input Monitoring 或 Accessibility 不得成为基础方案的隐式必需权限。原生 `InteractionShield` 必须先通过独立 Spike，明确主动过滤实际权限、误拦截和 fail-open 行为，再决定是否启用。
- 原生 `InteractionShield` 不得注册键盘事件，不得持久化原始鼠标事件，并必须在 App 异常时最多 800ms 自动放行。
- Automation 只在使用 AppleScript、ScriptingBridge 或 Apple Events 控制 Chrome 时需要。
- Chrome `activeTab` 不作为主权限模型。
- Chrome `<all_urls>` 如在 V1 使用，必须在文档中说明用途和后续收窄方向。

## 8. 验收标准

V1 只有在以下条件满足时才能判定完成：

### 8.1 功能验收

- 在普通 Chrome 网页中，三指点按普通 `<a href>` 链接能打开 `http:` 或 `https:` 链接。
- 新标签打开在当前标签右侧，且自动切换到新标签。
- 当前标签页不得跳转到被三指点按的链接。
- 三指点按未命中链接时，触控板左侧边缘切左侧标签页，右侧边缘切右侧标签页。
- 三指点按未命中链接且落在触控板中间区域时，单点不得执行标签页动作。
- 三指双击空白处中间区域关闭当前标签页；双击窗口内第一下不得先触发切 tab。关闭 GestureKit 打开的新标签页后优先回到来源标签页，否则优先切到左侧标签页，最左侧再切到右侧标签页。
- 异常短触、过长点按和动作后的短暂抖动不得执行标签页动作。
- macOS App 主窗口能切换手势方案、功能开关和轻扫灵敏度，并显示当前生效状态。
- Chrome 扩展 popup 只显示当前页面支持状态、App 与 Provider 连接状态、当前方案和当前页面最近一次结果。
- macOS App 主窗口能查询最近操作、查看面向用户的失败原因并导出开发者证据包。
- 三指快速左轻扫能切到同一 Chrome 窗口右侧标签页。
- 三指快速右轻扫能切到同一 Chrome 窗口左侧标签页。
- 到达最左或最右标签页时在当前窗口内循环切换：最右左滑到第一个标签页，最左右滑到最后一个标签页。
- 在无链接位置三指点按不会误打开页面。
- 在不可注入页面或不支持 URL scheme 上不会执行危险动作。

### 8.2 架构验收

- 存在独立 native host shim 或等价边界，且 Chrome 侧使用 `connectNative()`。
- 存在明确 message schema，包含 `version`、`id`、`type`、`timestamp`、`payload`、`error`。
- 存在 `TouchBackend` 抽象。
- 存在 `RuleEngine`，三条 V1 动作通过规则匹配触发。
- 存在 Chrome Provider action executor 或等价浏览器执行边界。
- 规则配置只有一个主存储源。
- 存在标准 `ActionProvider`、能力声明和 `ProviderRouter` 边界，Chrome 是 V1 Provider 实现而不是 Core 依赖。
- 存在 App `OperationJournal` 和扩展持久化 outbox，历史诊断不依赖 popup 或 Service Worker 生命周期。
- 存在统一的诊断展示映射，普通界面不得直接显示内部状态码。

### 8.3 测试验收

- RuleEngine 匹配和优先级有单元测试。
- MessageCodec 或协议 schema 有编解码测试。
- URL scheme 过滤有测试。
- Chrome tab 左右切换边界有测试。
- content script 普通链接识别有测试。
- 至少完成一次手动端到端验证：三指点按链接、边缘三指点按切 tab、中间三指双击关闭 tab、三指快速左轻扫、三指快速右轻扫。
- `docs/research/trackpad-gesture-stability-matrix.md` 的人工手势稳定性矩阵已完成，且结论没有阻断 V1 核心功能。

### 8.4 失败处理验收

- 扩展未连接时有可诊断状态。
- Native host 断开时有可诊断状态。
- GestureKit App 未运行时有可诊断状态。
- 当前页面不可注入时有可诊断状态。
- 最近 pointer 位置过期时有可诊断状态。
- 当前窗口或活动标签页不可用时有可诊断状态。
- 未被识别为有效手势的三指候选也有可诊断状态。
- 动作结果不确定时标记为结果未知，不自动重放，并且不阻塞后续操作。
- App、native host 或 Provider 短暂断开后，尚未确认持久化的诊断可以补交。

## 9. 正式开发前关口

正式产品实现开始前必须满足以下条件：

- `docs/product/gesturekit-v1-requirements.md` 已明确 V1 用户可见行为、非目标、失败状态和验收输出。
- 三个正式开发前 spike 已完成或给出明确替代方案。
- 手势稳定性矩阵已完成，至少覆盖 Chrome 前台三指点按、三指快速左轻扫、三指快速右轻扫各 10 次。
- 非 Chrome 前台输入可观测性和 macOS 三指系统手势冲突已有观察记录。
- 后续正式产品实现计划已单独产出；现有 `docs/plans/gesturekit-v1-implementation-plan.md` 是 spike 执行计划，不作为正式产品实现计划。
- Spike 发现已同步到本契约、技术设计或研究文档，不存在未处理的架构冲突。
- 用户明确确认进入正式实现阶段。

如果任一关口失败，不能通过局部代码修补绕过；必须先回到规格、技术设计或手势方案重新评审。

## 10. 审核原则

代码审核和架构审核按以下原则进行：

- 审核只判断变更是否满足本契约和已批准设计。
- V1 非目标不得作为阻塞问题提出。
- 发现 V1 非目标相关缺陷时，默认记录为 follow-up。
- Critical 问题必须证明会破坏 V1 核心功能、安全边界、隐私边界或已批准架构。
- Important 问题应在当前阶段修复，除非用户明确接受为后续事项。
- Minor 问题不得阻塞验收。
- 如果审核意见要求扩大范围，必须先更新本契约并获得确认。

## 11. 变更控制

以下情况必须先更新契约或设计文档：

- 新增 V1 用户可见功能。
- 改变 Chrome Native Messaging 连接模型。
- 移除 native host shim 边界。
- 改变规则配置 source of truth。
- 引入 AppleScript、shell command 或通用 App 自动化。
- 把 native 屏幕坐标转换 DOM 坐标作为链接识别主路径。
- 扩展支持到其他浏览器或其他 App。
- 改变 `ActionProvider`、`ActionDescriptor`、手势组合或 `OperationJournal` 的公共契约。
- 改变安全或隐私承诺。

## 12. 文档命名和目录规则

长期项目文档使用稳定路径，不用日期作为主文件名。

文档语言规则：

- 项目文档叙述默认使用中文。
- API 名称、命令、文件路径、协议字段、代码片段和外部标准名保持原文。
- 如果必须保留英文说明，中文说明必须先出现，并且承担主要解释职责。
- 后续设计审核和代码审核需要把“文档是否中文优先”作为非功能审核项。

目录规则：

- `docs/product/`：产品目标、范围、契约、用户故事。
- `docs/architecture/`：当前有效技术设计和架构说明。
- `docs/adr/`：已批准且不应轻易改变的架构决策。
- `docs/plans/`：实施计划和阶段任务。
- `docs/research/`：调研笔记、方案比较和外部项目参考。

命名规则：

- 产品范围：`gesturekit-v1-requirements.md`
- 项目契约：`gesturekit-v1-contract.md`
- 主技术设计：`gesturekit-v1-technical-design.md`
- 架构专题：`<topic>-architecture.md`
- ADR：`0001-short-decision-title.md`
- Spike 执行计划：`gesturekit-v1-implementation-plan.md`
- 正式产品实现计划：`gesturekit-v1-product-implementation-plan.md`

## 13. 当前契约状态

本契约已于 2026-07-10 纳入可靠性、可观测性、通用 Provider 和可配置手势架构。进入实施前必须满足：

- 用户完成对书面架构规格的最终审阅。
- V1 产品规格与本契约保持一致。
- V1 技术设计与专题架构文档不存在未说明的冲突。
- 分阶段实施计划能映射到本契约的验收标准。
