# GestureKit V1 产品规格

日期：2026-07-01

相关文档：

- `docs/product/gesturekit-v1-contract.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
- `docs/plans/gesturekit-v1-predevelopment-plan.md`
- `docs/research/trackpad-gesture-stability-matrix.md`

## 1. 目的

本规格定义 GestureKit V1 对用户可见行为、边界条件和验收证据的要求。后续正式设计、实施计划、代码开发和审核都必须能映射到本规格。

V1 的目标不是做通用自动化平台，而是先把 Chrome 中最高频的三个触控板手势动作做稳定：

- 三指点按链接，打开到新标签页并自动切换过去。
- 三指点按空白处左/右边缘，切换到相邻标签页。
- 三指双击空白处中间区域，关闭当前标签页。
- 三指快速左轻扫，切换到右侧标签页。
- 三指快速右轻扫，切换到左侧标签页。

## 2. 用户范围

V1 面向自用优先场景：

- 用户愿意本地加载 Chrome unpacked extension。
- 用户愿意本地安装 Chrome Native Messaging host manifest。
- 用户接受 `MultitouchSupport.framework` 属于私有 API，不适合 Mac App Store 分发。
- 用户接受 V1 只在受控环境中验证，不承诺覆盖所有 macOS、Chrome、显示器和触控板组合。

V1 固定支持对象：

- 浏览器：Google Chrome Stable。
- macOS bundle id：`com.google.Chrome`。
- Chrome Beta、Dev、Canary、Chromium、Edge、Brave、Arc、Safari 和 Firefox 均为后续扩展方向，不进入 V1。

V1 当前运行约束：

- 最低系统版本：macOS 15。
- 构建工具链：Swift 6.2、Xcode 26.2 或满足 OpenMultitouchSupport 当前上游要求的等价版本。
- App Sandbox：关闭。
- 分发方式：自用本地构建、Chrome 开发者模式加载 unpacked extension、手动安装 Native Messaging host manifest。

后续开源阶段可以扩展安装、诊断和文档，但不得改变 V1 的隐私承诺。

## 3. 用户可见功能

### 3.1 三指点按链接、边缘切换和中间双击关闭

触发条件：

- 前台 App 是 Google Chrome Stable，bundle id 为 `com.google.Chrome`。
- 当前标签页是可注入的普通网页。
- 链接打开路径需要 Chrome extension 记录到当前活跃标签页内的新鲜 pointer viewport 坐标。
- 坐标命中普通 `<a href>` 链接，或命中位于普通 `<a href>` 内的子元素，且链接规范化后的 URL scheme 是 `http:` 或 `https:`。
- 如果没有命中链接、没有新鲜 pointer 坐标或当前页面不可注入，则按三指点按的触控板位置作为 fallback：左侧边缘切左 tab，右侧边缘切右 tab。
- 触控板中间区域的单次空白点按不执行动作。
- 如果合法间隔内连续两次三指点按空白处中间区域，则关闭当前 tab。
- 异常短触、过长点按和动作后的短暂抖动必须返回或记录 `gesture_unstable`，不得执行标签页动作。

动作结果：

- 在当前 Chrome 窗口的当前标签右侧创建新标签页。
- 新标签页 `active: true`，打开后自动切换过去。
- 当前标签页不得跳转到被三指点按的链接。
- 不命中链接时，不打开页面；按触控板左/右边缘切换到相邻 tab，并沿用边界循环语义。
- 空白处左/右边缘三指点按切换 tab。
- 空白处中间区域三指双击关闭当前 tab。
- 空白处中间区域三指单点不执行动作。
- 动作返回成功状态和必要诊断信息。

必须不执行动作的情况：

- 最近 pointer 坐标不存在或过期。
- 当前页面不可注入。
- URL scheme 不支持。
- 前台 App 不是 Google Chrome Stable，或 bundle id 不是 `com.google.Chrome`。

### 3.2 三指快速左轻扫

触发条件：

- 前台 App 是 Google Chrome Stable，bundle id 为 `com.google.Chrome`。
- 当前 Chrome 窗口存在活跃标签页。
- 当前 Chrome 窗口至少存在一个标签页。
- 手势必须是短促的水平轻扫，默认标准档建议时长约 60ms-420ms；慢速拖动不触发标签切换。用户可通过扩展 popup 在稳健、标准、灵敏三档之间切换。

动作结果：

- 激活同一 Chrome 窗口中 `index + 1` 的标签页。
- 不跨窗口查找标签页。
- 如果当前已在最右侧标签页，则循环激活同一窗口第一个标签页。

边界结果：

- 当前窗口没有可用标签页时，返回 `page_unavailable` 或等价诊断状态。

### 3.3 三指快速右轻扫

触发条件：

- 前台 App 是 Google Chrome Stable，bundle id 为 `com.google.Chrome`。
- 当前 Chrome 窗口存在活跃标签页。
- 当前 Chrome 窗口至少存在一个标签页。
- 手势必须是短促的水平轻扫，默认标准档建议时长约 60ms-420ms；慢速拖动不触发标签切换。用户可通过扩展 popup 在稳健、标准、灵敏三档之间切换。

动作结果：

- 激活同一 Chrome 窗口中 `index - 1` 的标签页。
- 不跨窗口查找标签页。
- 如果当前已在最左侧标签页，则循环激活同一窗口最后一个标签页。

边界结果：

- 当前窗口没有可用标签页时，返回 `page_unavailable` 或等价诊断状态。

### 3.4 Chrome 扩展侧手感配置

V1 允许 Chrome 扩展保存本地手感配置，用于调节扩展侧动作执行阈值。该配置不替代 macOS App 的规则 source of truth，不提供任意手势绑定。

必须支持：

- `安全模式`：默认模式，边缘区域更窄，双击关闭更严格，动作冷却更长。
- `高效模式`：响应更快，边缘区域更宽，双击窗口更宽，动作冷却更短。
- 开关：边缘点按切 tab、中间双击关闭 tab、快速轻扫切 tab、防止链接原地跳转。
- 参数：轻扫灵敏度、边缘区域宽度、双击速度、动作冷却。
- 状态：Native host 连接状态、GestureKit App 连接状态、轻扫灵敏度同步状态、最近动作结果。

配置必须保存在 Chrome extension 的 `chrome.storage.local`。修改后影响后续手势，不要求影响已经进入执行中的手势。轻扫灵敏度通过 `settings_update` 消息同步给 GestureKit App，App 应用后通过 `settings_ack` 回传状态。“防止链接原地跳转”默认关闭，开启后只保护普通 `http/https` 链接左键点击，避免三指点按链接时当前页抢先原地跳转。

## 4. 规则雏形

V1 内置三条规则，但必须通过 `RuleEngine` 匹配触发，不允许把手势和动作直接硬编码在输入层或 Chrome 执行层。

V1 规则字段只要求覆盖：

- `id`
- `enabled`
- `priority`
- `scope.appBundleId`
- `scope.browserKind`
- `scope.elementType`
- `gesture.type`
- `action.type`

V1 内置规则：

| 规则 ID | 条件 | 动作 |
| --- | --- | --- |
| `chrome-open-link-background` | Chrome + link + `three_finger_tap` | `open_link_background` |
| `chrome-activate-right-tab` | Chrome + any + `three_finger_swipe_left` | `activate_right_tab` |
| `chrome-activate-left-tab` | Chrome + any + `three_finger_swipe_right` | `activate_left_tab` |

规则匹配必须满足：

- 禁用规则不参与匹配。
- 高 priority 优先。
- 更具体的 scope 优先。
- 同等条件使用稳定 tie-breaker，保证结果可测试。

## 5. 状态和失败码

V1 的失败必须可诊断，不允许静默失败。

必须支持或映射到等价诊断语义的状态：

| 状态 | 语义 |
| --- | --- |
| `success` | 动作已执行成功。 |
| `edge_reached` | 标签页切换无法找到目标时的兼容诊断状态；V1 常规边界应循环切换。 |
| `no_recent_pointer` | 当前活跃标签页没有新鲜 pointer 坐标。 |
| `no_target` | 坐标存在，但没有命中支持的链接。 |
| `page_unavailable` | 页面不可注入或 content script 不可用。 |
| `unsupported_url_scheme` | 命中的链接 scheme 不允许。 |
| `unsupported_app` | 前台 App 不是 V1 支持的 Chrome。 |
| `native_host_disconnected` | Chrome extension 与 native host 断开。 |
| `app_unavailable` | GestureKit App 未运行或本地 IPC 不可用。 |
| `extension_unavailable` | Chrome extension 未安装、未连接或不可用。 |
| `gesture_unstable` | 手势候选存在，但不满足稳定识别阈值。 |
| `error` | 其他未分类错误，必须附带可读诊断信息。 |

状态命名在实现中可以按语言或模块局部调整，但协议、日志和验收文档必须能明确映射。

## 6. 前置验证和正式开发关口

进入正式设计开发前，必须满足以下关口。

### 6.1 Spike 完成关口

- Native Messaging host spike 已能通过 self-test。
- Chrome link hit-test spike 已能通过 TypeScript、测试和 build。
- Trackpad input spike 已能启动监听、输出三指候选事件并正常停止。
- 三个 spike 的发现已写入 `docs/research/` 或相关 spike README。

### 6.2 手势稳定性关口

必须完成 `docs/research/trackpad-gesture-stability-matrix.md` 中的人工验证矩阵。

最低要求：

- Chrome 前台三指点按 10 次。
- Chrome 前台三指快速左轻扫 10 次。
- Chrome 前台三指快速右轻扫 10 次。
- 非 Chrome 前台至少观察一次三类手势不会误触发 Chrome 动作。
- 系统三指手势冲突至少观察一次，并记录 macOS 相关设置状态。

硬性通过标准：

- Chrome 前台三类手势各 10 次测试中，每类至少 8 次识别为期望候选。
- 任一类别不得被误识别为另一个 V1 手势。
- 三类手势总计 `unclear` 或未识别次数不得超过 6 次。
- 非 Chrome 前台观察只验证 probe 是否仍可观测候选手势；是否返回 `unsupported_app` 属于后续 RuleEngine、AppContextResolver 和端到端验收。
- 系统三指手势冲突不得达到 `blocking` 级别；若为 `acceptable_with_note`，必须把推荐系统设置写入技术设计或用户文档。

结论判定：

- `passed`：满足全部硬性通过标准，且未观察到系统冲突。
- `passed_with_notes`：满足识别阈值，但存在需要记录的系统设置、设备或操作限制。
- `blocked`：不满足识别阈值、存在 V1 手势互相误识别，或存在 blocking 级系统冲突。

### 6.3 设计冻结关口

手势稳定性关口完成后，必须检查并更新：

- `docs/product/gesturekit-v1-contract.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
- 后续正式产品实现计划，当前建议路径为 `docs/plans/gesturekit-v1-product-implementation-plan.md`

只有当用户明确确认进入正式实现阶段，才开始写正式开发计划或产品化代码。

## 7. V1 非目标

V1 不交付：

- 完整规则编辑器。
- 多浏览器支持。
- 多 App 自动化平台。
- AppleScript、shell command 或脚本动作。
- 复杂手势录制。
- 云同步。
- Chrome Web Store 发布。
- Mac App Store 分发。
- 复杂 iframe、closed shadow DOM、JS click handler 导航识别。

这些方向可以保留扩展空间，但不得作为 V1 阻塞验收项，除非它们破坏三个核心功能。

## 8. 验收输出

V1 规格验收需要形成以下证据：

- 手势稳定性矩阵完成并归档。
- 单元测试覆盖规则匹配、协议编解码、URL 过滤、tab 边界、链接识别。
- 至少一次手动端到端验证覆盖三指点按链接、三指快速左轻扫、三指快速右轻扫。
- 失败场景至少覆盖无链接、当前窗口或活动标签页不可用、页面不可注入、native host 断开。
- 文档仍保持中文优先，英文只用于 API、命令、协议字段和必要外部术语。
