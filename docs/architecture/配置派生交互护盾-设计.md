# 配置派生的交互保护特征

> 状态：已确认，2026-07-16。

## 目标

使 GestureKit 根据用户配置的手势-动作绑定，在候选期仅为可能触发浏览器副作用的手势启用相应交互保护。首个特征为 `linkClick`：它阻止同一次链接点击在原标签页导航，并仅在最终动作确认打开链接时由 Provider 创建新标签。

## 设计原则

- 手势识别与浏览器动作保持分离；识别层识别 `GestureDefinition`，不识别 Chrome 动作。
- App 是配置和绑定的权威方；Chrome Provider 不保存手势映射，也不猜测手指数或手势类型。
- 交互保护特征由启用的 `BindingRule` 编译得出，而不是由手势名称硬编码。
- 不带 `linkClick` 的候选不应影响普通网页点击。

## 配置与编译

`AppConfiguration` 增加 `gestureDefinitions`。每个 `BindingRule.gestureDefinitionId` 必须引用其中一个定义。

配置加载后，App 编译出 `RecognitionPlan`。每个计划项包含手势定义、可用绑定和派生特征：

```swift
enum InteractionGuardFeature: String, Codable, Sendable {
    case linkClick
}
```

若启用绑定的 `actionId == .browserLinkOpenAdjacent`，其对应手势定义获得 `.linkClick`。初始预设将“三指点按”定义绑定到该特征；未来用户改为二指点按时，仅更新定义和绑定即可。

## 候选期协议

候选事件必须携带 `gestureDefinitionID` 与派生的 guard 特征。`GestureSessionCoordinator` 在候选开始时只为带 `.linkClick` 的会话调用 guard router，发送 `guardArm` 和短时 deadline。

Content script 仅在有效的 `.linkClick` guard 内暂存一次可取消的 HTTP/HTTPS 主链接点击。动作结果按以下规则收敛：

- `browser.link.open_adjacent` 成功 preflight：消费暂存点击并创建新标签。
- 手势拒绝、解析为其他动作、上下文失败、Provider 断连或 deadline 到期：释放 guard；若已有暂存点击，恢复原页面导航。
- 未 arm 的普通点击不得被暂存或阻止。

## 验收条件

- 默认三指点按打开链接时，原标签页不导航，新标签正常打开。
- 普通单指链接点击立即按网页默认行为导航。
- 将链接动作绑定换为二指点按后，二指候选获得保护，三指候选不获得保护。
- 将候选解析为非链接动作、拒绝候选或超时时，暂存点击恢复原页面导航。
- Provider 与 content script 不显示或存储用户手势绑定、凭据、会话标识或未脱敏页面数据。
