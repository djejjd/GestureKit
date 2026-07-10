# GestureKit V1 技术选型与架构设计

日期：2026-06-23

相关文档：

- `docs/product/gesturekit-v1-requirements.md`
- `docs/product/gesturekit-v1-contract.md`
- `docs/architecture/gesturekit-reliability-observability-platform-architecture.md`
- `docs/plans/gesturekit-v1-predevelopment-plan.md`
- `docs/research/trackpad-gesture-stability-matrix.md`
- `docs/adr/0001-use-native-host-shim.md`
- `docs/adr/0002-use-extension-last-pointer-position.md`
- `docs/adr/0003-use-rules-engine-from-v1.md`

> 2026-07-10 架构演进说明：可靠性证据链、App 主窗口、统一配置主存储、手势组合和通用 `ActionProvider` 边界以 `docs/architecture/gesturekit-reliability-observability-platform-architecture.md` 为准。本文保留 V1 Chrome 实现基线与既有通信、坐标和安全决策。

## 1. 背景和目标

GestureKit 是一个 macOS 自用优先、后续可开源的触控板手势增强工具。V1 聚焦 Chrome，通过三指点按和三指快速轻扫替代高频浏览器操作。

V1 实现以下用户可见动作：

- 三指点按链接：新标签页打开链接并自动切换过去。
- 三指点按空白处左/右边缘：切到左/右标签页。
- 三指双击空白处中间区域：关闭当前标签页。
- 三指快速左轻扫：切到右侧标签页。
- 三指快速右轻扫：切到左侧标签页。

三指点按路径会过滤异常短触、过长点按和动作后的短暂抖动。中间区域单点不执行动作，避免高强度使用时误切 tab。

内部架构按可扩展规则平台设计，但 V1 不交付完整规则编辑器、多浏览器、多 App 自动化或复杂手势录制。

## 2. 技术选型

macOS 侧：

- Swift
- AppKit
- Swift Package Manager
- OpenMultitouchSupport 作为 V1 触控板输入 backend
- UserDefaults 作为本地规则和设置主存储

Chrome 侧：

- Chrome Extension Manifest V3
- TypeScript
- Background Service Worker
- Content Script
- Chrome Native Messaging

通信侧：

- Chrome 扩展使用 `chrome.runtime.connectNative()` 连接 native host。
- Native host 通过 Chrome Native Messaging 的 stdio 协议与扩展通信。
- GestureKit 主 App 与 native host shim 通过本机 IPC 传递手势事件。

## 3. 核心结论

V1 采用：

```text
GestureKit App
+ GestureKit Native Host Shim
+ Chrome MV3 Extension
```

不采用“macOS App 主动发消息给 Chrome 扩展”的模型。Chrome Native Messaging 的连接方向是扩展连接 native host，Chrome 启动或连接 host 后通过 stdio 交换消息。

## 4. 总体架构

```text
Trackpad
  ↓
GestureKit App
  ├─ TouchBackend
  │   ├─ MultitouchSupportBackend
  │   └─ FuturePublicInputBackend
  ├─ GestureRecognizer
  ├─ AppContextResolver
  ├─ CoordinateService
  ├─ RuleEngine
  ├─ SettingsStore
  └─ LocalEventBus / IPC Server
        ↓
GestureKit Native Host Shim
  ├─ Chrome Native Messaging stdio protocol
  ├─ MessageCodec
  └─ IPC Client
        ↓
Chrome MV3 Extension
  ├─ NativePortManager
  ├─ Background Service Worker
  ├─ BrowserContextProvider
  ├─ Content Script
  └─ ChromeActionExecutor
```

### 4.1 GestureKit App

GestureKit App 是常驻菜单栏 App，负责采集触控板输入、识别手势、维护规则配置和提供本地事件源。

模块职责：

- `TouchBackend`：抽象触控板输入来源。
- `MultitouchSupportBackend`：V1 使用 OpenMultitouchSupport 和私有 `MultitouchSupport.framework` 的 backend。
- `FuturePublicInputBackend`：预留公开 API 或降级输入实现。
- `GestureRecognizer`：把原始触控数据识别为 `three_finger_tap`、`three_finger_swipe_left`、`three_finger_swipe_right`。
- `AppContextResolver`：获取前台 App、bundle id、窗口状态等事实。
- `CoordinateService`：统一 native 侧坐标模型，但 V1 不把 native 坐标作为链接命中的主路径。
- `RuleEngine`：根据手势和上下文匹配动作意图。
- `SettingsStore`：保存规则和开关，是规则配置的唯一 source of truth。
- `LocalEventBus / IPC Server`：把动作意图或手势事件提供给 native host shim。

### 4.2 GestureKit Native Host Shim

Native host shim 是 Chrome Native Messaging host。它只负责桥接，不负责手势识别或规则决策。

职责：

- 实现 Chrome Native Messaging stdio 协议。
- 校验消息版本、类型和请求 ID。
- 连接 GestureKit App 的本地 IPC。
- 将 App 侧事件转发给 Chrome 扩展。
- 将 Chrome 扩展的执行结果、错误和手感设置回传给 App。

V1 推荐使用单独 shim，而不是让主 App 直接作为 native host。这样主 App 生命周期不被 Chrome 启停影响，Chrome 侧崩溃或断连也不会带走手势采集进程。

### 4.3 Chrome MV3 Extension

Chrome 扩展负责网页语义和 Chrome tab 操作。

模块职责：

- `NativePortManager`：使用 `connectNative()` 建立长连接；处理断开、重连和端口错误。
- `Background Service Worker`：调度 native message、content script 和 Chrome API。
- `BrowserContextProvider`：获取当前 tab、窗口、URL、frame 和页面可用性。
- `Content Script`：记录网页内最近鼠标位置，执行链接命中识别。
- `ChromeActionExecutor`：执行 `open_link_background`、`activate_left_tab`、`activate_right_tab`。

## 5. Legacy Native Messaging 协议

本节记录当前 Chrome V1 实现的 legacy `GestureKitMessage version: 1`，用于迁移和兼容测试，不再是目标 Provider 公共协议。目标协议为 `docs/architecture/gesturekit-reliability-observability-platform-architecture.md` 定义的 Provider Protocol v2。

通用消息结构：

```json
{
  "version": 1,
  "id": "01J...",
  "type": "gesture_event",
  "timestamp": 1782200000000,
  "payload": {
    "gesture": "three_finger_tap",
    "appBundleId": "com.google.Chrome",
    "confidence": 1,
    "touchX": 0.25,
    "durationMs": 96
  },
  "error": null
}
```

字段语义：

- `version`：协议版本。V1 固定为 `1`。
- `id`：请求或事件 ID，用于关联响应和诊断。
- `type`：消息类型。
- `timestamp`：native 侧生成事件的毫秒时间戳。
- `payload`：消息内容。
- `error`：错误对象。正常消息为 `null`。

Legacy v1 消息类型：

- `hello`：连接握手。
- `gesture_event`：native host 转发 App 侧手势事件。
- `action_result`：扩展回传动作执行结果。
- `settings_update`：扩展下发轻扫灵敏度及识别阈值。
- `settings_ack`：GestureKit App 回传轻扫灵敏度是否已应用。
- `error`：协议、权限或执行错误。
- `heartbeat`：可选心跳，用于诊断连接状态。

安全和可靠性要求：

- Native host manifest 的 `allowed_origins` 只能包含 GestureKit 扩展 ID，不能使用通配符。
- 扩展只接受符合 schema 的消息。
- App 只接受通过 Provider Protocol v2 完成安装身份认证的本地 Provider 会话；`allowed_origins` 不能替代 App IPC 认证。
- 所有动作执行都必须返回成功、失败或不可用状态，不能静默失败。
- V1 不允许网页内容直接构造 native message。

## 6. 坐标和链接识别策略

### 6.1 核心问题

macOS App 可以拿到的是屏幕坐标或 native point。`document.elementFromPoint(x, y)` 需要的是当前 document viewport 左上角为原点的 CSS 像素坐标。二者不能直接等价。

影响因素包括：

- Chrome 窗口位置和大小。
- 标签栏、地址栏、书签栏高度。
- Retina scale、CSS pixel、native point 的差异。
- 多显示器、不同 scale、负坐标。
- 页面缩放、滚动、全屏、Stage Manager。
- iframe、shadow DOM、PDF viewer、Chrome 内部页面。

### 6.2 V1 策略

V1 不把 native 屏幕坐标转换为 DOM 坐标作为主路径。

Content script 在网页内监听 `pointermove` / `mousemove`，记录最近一次网页 viewport 坐标：

```json
{
  "x": 420,
  "y": 260,
  "frameId": 0,
  "timestamp": 1782200000000
}
```

三指点按发生时：

```text
GestureKit App 识别 three_finger_tap
-> App 向选中的 Chrome Provider 请求短时效 context snapshot
-> Chrome Provider 使用最近的 viewport 坐标做 elementFromPoint
-> Provider 返回标准页面事实和不透明 targetRef
-> RuleEngine 根据手势、触控区域和页面事实生成标准 ActionDescriptor
-> Provider 校验 contextId / targetRef 后调用 chrome.tabs.create
-> accepted/result 与页面保护阶段进入 outbox 并回传 App Journal
```

如果最近位置不存在或过期，返回 `no_recent_pointer`，不做 native 坐标猜测。如果最近位置有效但没有命中支持的链接，返回 `no_target`。

V1 位置新鲜度建议：

- 最近网页内 pointer 位置超过 1500ms 未更新时，视为过期。
- 最近位置所在 tab 不是当前活跃 tab 时，视为无效。
- 位置所在页面不可注入时，返回 `page_unavailable`。

### 6.3 V1 链接识别范围

V1 支持：

- 普通网页。
- 顶层 document。
- 普通 `<a href>` 链接。
- 图片或子元素包裹在 `<a href>` 内的链接。

V1 降级或不支持：

- `chrome://` 页面。
- Chrome Web Store。
- 扩展页面。
- PDF viewer。
- closed shadow DOM。
- JS click handler 伪链接。
- ARIA role link 但无真实 URL 的元素。
- 复杂 iframe 内链接。

后续版本可以通过 all-frames content script、frame 坐标转换、open shadow DOM 递归 hit-test 扩展能力。

### 6.4 URL 规范化和过滤

Content script 返回链接时使用 `HTMLAnchorElement.href` 获取绝对 URL，不使用原始 `href` 字符串。

V1 允许：

- `http:`
- `https:`

V1 默认拒绝：

- `javascript:`
- `data:`
- `blob:`
- `file:`
- `mailto:`
- `tel:`
- 浏览器内部 scheme

被拒绝时返回 `unsupported_url_scheme`。

## 7. Legacy V1 规则模型

本节记录当前代码中的 Chrome 专用规则输入，供迁移 adapter 和回归测试使用。目标规则模型以 `RuleEngine` 为唯一门面，使用标准 `GestureDefinition`、Provider context facts 和 `ActionDescriptor`，见专题架构文档。

V1 内置三条规则，但所有动作都通过规则引擎执行。

示例规则：

```json
{
  "id": "chrome-open-link-background",
  "enabled": true,
  "priority": 100,
  "scope": {
    "appBundleId": "com.google.Chrome",
    "browserKind": "chrome",
    "urlPattern": "*",
    "elementType": "link"
  },
  "gesture": {
    "type": "three_finger_tap"
  },
  "action": {
    "type": "open_link_background"
  }
}
```

V1 内置规则：

- `Chrome + link + three_finger_tap -> open_link_background`
- `Chrome + any + three_finger_swipe_left -> activate_right_tab`
- `Chrome + any + three_finger_swipe_right -> activate_left_tab`

### 7.1 规则边界

- `GestureEvent`：只描述已识别手势，不包含业务规则。
- `Context`：只描述当前 App、浏览器、页面、元素、坐标、URL 等事实。
- `RuleMatcher`：纯匹配和排序，不执行副作用。
- `ActionExecutor`：执行动作，处理权限、失败和回执。

### 7.2 匹配排序

规则匹配顺序：

```text
enabled
-> explicit priority
-> scope specificity
-> gesture specificity
-> stable tie-breaker
```

`scope specificity` 包括：

- 站点或 URL 条件比浏览器条件更具体。
- elementType 条件比 any 更具体。
- windowState 或 browserKind 条件比全局条件更具体。

V1 不允许规则使用任意正则。`urlPattern` 暂时只支持 `*` 和未来兼容 Chrome extension match pattern 的结构化模式。

### 7.3 配置 source of truth

规则和全局设置的唯一 source of truth 是 GestureKit App 的 `SettingsStore`。

Chrome `chrome.storage.local` 或等价扩展持久化只保存：

- 扩展侧连接状态。
- App 下发的只读配置缓存和版本。
- 尚未被 App `OperationJournal` 确认持久化的诊断 outbox。
- 最近一次配置应用状态。
- content script 的局部缓存。
- 必要的页面上下文缓存。

V1 不允许 Chrome 扩展单独编辑规则、识别参数或动作绑定，避免双写和同步冲突。全部用户配置由 App `SettingsStore` 持有，并通过 Provider Protocol 的权威配置快照同步到扩展；现有 `settings_update` / `settings_ack` 在迁移期间只作为 adapter 内部兼容消息。

## 8. Chrome 动作语义

### 8.1 打开链接并切换过去

动作：`open_link_background`

行为：

- 在当前窗口、当前 tab 右侧打开新 tab。
- 新 tab `active: true`。
- URL 必须通过 scheme 过滤。
- 若当前窗口不可确定，则使用 Chrome `lastFocusedWindow`。
- 若 incognito 或受限页面导致动作不可用，返回错误。

### 8.2 切换左侧标签页

动作：`activate_left_tab`

行为：

- 在当前 Chrome 窗口内查找 active tab。
- 激活同一窗口内 `index - 1` 的 tab。
- 到达第一个 tab 时循环激活同一窗口最后一个 tab。

### 8.3 切换右侧标签页

动作：`activate_right_tab`

行为：

- 在当前 Chrome 窗口内查找 active tab。
- 激活同一窗口内 `index + 1` 的 tab。
- 到达最后一个 tab 时循环激活同一窗口第一个 tab。

V1 暂不特殊处理 tab group、pinned tab、split view。它们仍按同一窗口的 tab index 处理。后续版本如需改变语义，需要引入更细的 tab scope。

## 9. 权限模型

### 9.1 macOS 权限

`MultitouchSupport.framework`：

- 私有、未文档化 API。
- 自用和开源实验可接受。
- 不适合 Mac App Store。
- 不能把它描述为稳定公开能力。
- macOS 升级可能导致 ABI、字段、设备枚举或回调失效。

Accessibility：

- 仅在需要读取 AX 结构、模拟键鼠或控制 UI 时需要。
- V1 主路径尽量不依赖模拟键鼠。

Input Monitoring：

- 仅在使用 `CGEventTap` 或公开全局输入监听时需要。
- 使用私有 MultitouchSupport 不等价于获得 Input Monitoring 授权。

Automation：

- 仅在使用 AppleScript、ScriptingBridge 或 Apple Events 控制 Chrome 时需要。
- V1 主路径不依赖 Automation。

### 9.2 Chrome 权限

V1 扩展需要：

- `nativeMessaging`
- host permissions，初期可用 `<all_urls>`，后续应收窄或提供清晰说明
- content script matches 覆盖目标页面

视实现需要：

- `storage`：保存扩展侧状态、只读配置缓存、operation ledger 和待补交 outbox，不作为历史诊断主存储。
- `tabs`：读取 tab URL、title 等敏感字段时需要。
- `scripting`：如果采用程序化注入 content script 才需要。

`activeTab` 不作为主权限模型。macOS 三指手势经 native messaging 进入扩展，不等价于 Chrome 扩展 invocation gesture。

## 10. 失败处理

V1 必须显式处理以下失败：

- Chrome 扩展未安装。
- Native host manifest 未安装。
- Native host 未连接或断开。
- GestureKit App 未运行。
- 当前前台 App 不是支持的 Chrome。
- 当前页面不可注入。
- 最近网页 pointer 位置不存在或过期。
- 命中元素不是支持的链接。
- 链接 scheme 不支持。
- 当前窗口或活动标签页不可用。
- Chrome API 返回错误。

用户可见反馈：

- 菜单栏状态显示连接状态。
- 最近错误写入 App `OperationJournal`，由主窗口显示面向用户的原因。
- V1 不强制弹出频繁 toast，避免干扰。

## 11. 设备和系统边界

V1 目标设备：

- MacBook 内置触控板。
- Magic Trackpad。

不承诺支持：

- 普通鼠标。
- Sidecar / Universal Control 输入。
- 远程桌面。
- 虚拟机。
- 特殊驱动触控板。

需要处理：

- 设备枚举失败。
- 热插拔。
- 休眠唤醒后重订阅。
- 回调中断。
- 系统手势设置冲突。

三指 swipe 可能和 Mission Control、Spaces、App Expose、Swipe between pages、三指拖移等系统设置冲突。V1 应提供调试状态，说明手势未识别或被系统消费。

## 12. V1 不做的内容

V1 不做：

- 完整规则编辑器。
- 多浏览器适配。
- Firefox。
- Safari。
- 复杂手势录制。
- 云同步。
- AppleScript 动作。
- shell command 动作。
- Mac App Store 分发。
- 通用 App 自动化平台。
- 复杂 iframe 链接识别。
- closed shadow DOM 链接识别。
- JS click handler 导航识别。

## 13. 测试策略

macOS App：

- 手势识别状态机单元测试。
- RuleEngine 表驱动测试。
- priority 和 specificity 冲突测试。
- SettingsStore 读写测试。
- MessageCodec 编解码测试。

Chrome 扩展：

- Native message schema 校验测试。
- `open_link_background` mock Chrome API 测试。
- 左右 tab 切换边界测试。
- content script link resolver 测试。
- URL scheme 过滤测试。

集成验证：

- 扩展 `connectNative()` 连接和断线重连。
- 三指点按普通链接打开并切换到新标签。
- 三指点按空白处左/右边缘切换标签页。
- 三指双击空白处中间区域关闭当前标签页。
- 关闭 GestureKit 打开的新标签页时优先激活来源标签页；无来源时优先左侧，最左侧时右侧。
- 三指快速左右轻扫在单窗口多 tab 中切换。
- 无链接、当前窗口或活动标签页不可用、页面不可注入时返回明确错误。

手动验证矩阵：

- 内置触控板：当前设备具备时必测。
- Magic Trackpad：当前环境具备时必测，否则记录为 `N/A`。
- 单显示器：当前环境具备时必测，否则记录为 `N/A`。
- 双显示器：当前环境具备时必测，否则记录为 `N/A`。
- Retina 和非 Retina 外接屏：当前环境具备时必测，否则记录为 `N/A`。
- Chrome 普通窗口：必测。
- Chrome 全屏窗口：必测。

正式开发前的触控板输入稳定性以 `docs/research/trackpad-gesture-stability-matrix.md` 为准。产品动作端到端验收在正式产品实现阶段单独执行。

## 14. 分发策略

自用阶段：

- 本地构建 GestureKit App。
- Chrome 开发者模式加载 unpacked extension。
- 手动安装 native messaging host manifest。

开源阶段：

- GitHub Release。
- 提供安装脚本。
- README 明确说明私有 API 风险、权限用途、非 Mac App Store 分发和兼容性边界。

暂不承诺：

- Mac App Store。
- Chrome Web Store 发布。
- Apple notarization。

## 15. 主要风险

### 15.1 私有触控板 API 风险

`MultitouchSupport.framework` 是私有 API。它可能随 macOS 升级失效，也不适合 Mac App Store 分发。V1 必须把它封装成可替换 backend，而不是把私有 API 泄漏到业务逻辑中。

### 15.2 Native Messaging 生命周期风险

MV3 service worker 生命周期受 Chrome 管理。V1 必须使用 `connectNative()` 长连接，并处理 native host 断开、service worker 重启和端口重连。

### 15.3 链接命中准确性风险

V1 采用 extension 记录最近 viewport 坐标的策略，避免 native 坐标转换，但这仍是 best-effort。iframe、shadow DOM、JS 导航和不可注入页面会降级。

### 15.4 权限和隐私风险

项目涉及触控板输入、浏览器页面上下文和 native messaging。开源前必须清楚说明：

- 不记录原始输入流。
- 不上传浏览历史或页面内容。
- native message 只在本机扩展和本机 host 间传输。
- 规则配置由用户本地保存。

## 16. 后续扩展方向

可扩展但不进入 V1：

- Chrome Beta / Dev / Canary / Chromium / Edge / Brave / Arc adapter。
- Firefox WebExtension adapter。
- App-specific keyboard shortcut adapter。
- AppleScript adapter。
- URL scheme adapter。
- 站点规则 UI。
- 规则导入导出。
- frame-aware link resolver。
- open shadow DOM resolver。
- tab group / split view aware tab navigation。

## 17. 设计审核修正记录

本设计已根据三类审核意见修正：

- macOS 输入层审核：补充私有 API 风险、权限拆分、设备边界、系统手势冲突、坐标模型和 backend 可替换性。
- Chrome 扩展审核：修正 Native Messaging 连接方向，加入 native host shim、`connectNative()` 长连接、MV3 生命周期、权限拆分、链接识别降级和 tab 操作边界。
- 平台架构审核：补充消息 schema、信任边界、配置 source of truth、规则 specificity、adapter 边界和测试策略。
