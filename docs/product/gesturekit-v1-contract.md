# GestureKit V1 设计开发契约

日期：2026-06-23

更新日期：2026-07-07

相关文档：

- `docs/product/gesturekit-v1-requirements.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
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

V1 只交付三个用户可见功能：

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

如果开发或审核发现这些能力相关的问题，应记录为后续事项，除非它们阻断 V1 三个核心功能。

## 5. 架构约束

V1 实现必须遵守以下架构边界：

- macOS App 负责触控板输入、手势识别、规则配置、规则匹配和本地事件源。
- Chrome 扩展负责网页语义、链接识别和 Chrome tab 动作。
- Chrome Native Messaging 的连接方向必须是扩展通过 `connectNative()` 连接 native host。
- V1 使用独立 native host shim 桥接 Chrome stdio 协议和 GestureKit App 本地 IPC。
- 触控板输入必须通过 `TouchBackend` 抽象，`MultitouchSupportBackend` 不得泄漏到业务规则层。
- 规则配置的唯一 source of truth 是 macOS App 的 `SettingsStore`。
- Chrome `chrome.storage.local` 可以保存扩展侧状态、缓存、诊断信息和不改变规则绑定的手感配置。
- 扩展侧手感配置只允许调节阈值、冷却、开关和轻扫灵敏度，不允许把手势绑定到任意动作。
- 轻扫灵敏度可以由扩展通过 Native Messaging host 同步到 GestureKit App，但只能影响手势识别阈值，不能改变规则 source of truth。
- 规则匹配必须通过 `RuleEngine`，不得把核心三条动作硬编码在 UI、输入层或 Chrome 执行层。
- V1 不把 native 屏幕坐标转换为 DOM 坐标作为链接识别主路径。
- 三指点按链接识别主路径是 content script 记录最近网页 viewport pointer 坐标。

## 6. 安全和隐私约束

V1 必须遵守：

- 不上传浏览历史、页面内容、原始触控数据或规则配置。
- 不记录连续原始输入流，除非用户显式开启诊断模式。
- Native message 只在本机扩展、native host 和 GestureKit App 之间传输。
- 网页 DOM 命中结果视为不可信输入，URL 必须规范化和过滤。
- V1 只允许打开 `http:` 和 `https:` 链接。
- Native host manifest 的 `allowed_origins` 必须绑定具体扩展 ID，不能使用通配符。

## 7. 权限约束

V1 权限说明必须精确：

- `MultitouchSupport.framework` 是私有 API，自用和开源实验可接受，不适合 Mac App Store。
- Accessibility 只在读取 AX、模拟键鼠或控制 UI 时需要。
- Input Monitoring 只在使用 `CGEventTap` 或公开全局输入监听时需要。
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
- Chrome 扩展 popup 能切换安全/高效模式，并开关边缘点按、中间双击、快速轻扫，以及默认关闭的“防止链接原地跳转”实验兼容开关。
- Chrome 扩展 popup 能切换稳健、标准、灵敏三档轻扫灵敏度，并显示最近一次同步到 GestureKit App 的状态。
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
- 存在 Chrome action executor 或等价浏览器执行边界。
- 规则配置只有一个主存储源。

### 8.3 测试验收

- RuleEngine 匹配和优先级有单元测试。
- MessageCodec 或协议 schema 有编解码测试。
- URL scheme 过滤有测试。
- Chrome tab 左右切换边界有测试。
- content script 普通链接识别有测试。
- 至少完成一次手动端到端验证：三指点按链接、边缘三指点按切 tab、中间三指双击关闭 tab、三指快速左轻扫、三指快速右轻扫。
- `docs/research/trackpad-gesture-stability-matrix.md` 的人工手势稳定性矩阵已完成，且结论没有阻断 V1 三个核心功能。

### 8.4 失败处理验收

- 扩展未连接时有可诊断状态。
- Native host 断开时有可诊断状态。
- GestureKit App 未运行时有可诊断状态。
- 当前页面不可注入时有可诊断状态。
- 最近 pointer 位置过期时有可诊断状态。
- 当前窗口或活动标签页不可用时有可诊断状态。

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
- Critical 问题必须证明会破坏 V1 三个核心功能、安全边界、隐私边界或已批准架构。
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

本契约是 V1 的初始约束。进入实现计划前，应先确认：

- 本契约范围是否被用户接受。
- V1 产品规格是否被用户接受。
- V1 技术设计是否与本契约一致。
- 实施计划是否能映射到本契约的验收标准。
