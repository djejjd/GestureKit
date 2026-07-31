# GestureKit V2.4-A 链接动作可靠性闭环契约

状态：设计已确认，待实施计划审阅

日期：2026-07-31

相关文档：

- `docs/product/gesturekit-v1-contract.md`
- `docs/architecture/gesturekit-reliability-observability-platform-architecture.md`
- `docs/operations/e2e-checklist.md`
- `docs/plans/gesturekit-reliability-platform-implementation-plan.md`

## 1. 目标

V2.4-A 为三指点按链接建立可重复、可诊断的真实 Chrome 质量门。它验证现有 GestureKit App、Native Host 和 Chrome extension 链路在受控页面中能正确保护原页面点击，并在当前标签右侧创建并激活链接标签页。

本期以浏览器动作可靠性为目标，不声称自动化验证真实触控板硬件输入。

## 2. 交付范围

V2.4-A 必须交付：

- 一个仅面向本地开发和 macOS runner 的真实 Chrome 验收入口。
- 隔离 Chrome profile、unpacked extension 加载与受控测试页准备。
- 仅在显式测试模式和受控测试页中可用的触发入口；该入口必须携带唯一 `gestureSessionId` 和 `operationId`，不得在普通网页或生产运行时开放。
- 对以下结果的机器可读断言和脱敏失败摘要：
  - 匹配 session 的 `guard_armed` 先于受控页面的 click 副作用。
  - 原页面没有导航到链接目标。
  - 扩展在来源标签右侧创建新标签，并将其激活。
  - guard lease 到期后，普通 click 正常导航，不遗留可复用 guard。
  - App、Native Host 或 Provider 不可用时，输出关联 ID、失败阶段和终态，且不产生未记录副作用。
- 将 Swift 单元测试、TypeScript 单元/协议测试、现有脚本测试和真实 Chrome 验收的职责写入统一质量门说明。

## 3. 非目标

V2.4-A 不交付：

- 自动化触控板输入、OpenMultitouchSupport 或系统权限验证。
- 新手势、新浏览器动作、新 Provider 或动作换绑。
- Provider Protocol v2 公共字段、`connectNative()` 方向或 App 配置主权的变更。
- 正式签名、公证、Chrome Web Store 发布或通用安装器。
- 把测试触发入口暴露给普通页面、popup 或生产运行时。

## 4. 架构与安全边界

链路保持不变：

```text
Chrome extension -> connectNative() -> GestureKitHost -> App IPC
```

真实 Chrome 验收通过独立临时 profile 运行，只加载仓库构建出的 unpacked extension 和本地受控测试页。测试页不得采集或输出真实浏览历史、完整 URL query/hash、页面正文、Cookie、认证材料或原始 `targetRef`。

测试触发能力必须同时满足以下限制：

- 由显式测试模式开启，默认关闭。
- App 仅在传入 `--e2e-control-token` 时额外启动测试专用 loopback TCP listener，并仅在标准输出输出随机端口；runner 使用该端口发送一次性测试命令。
- listener 同时校验 loopback 对端、随机 token 与未使用的 `operationId`；任一校验失败时拒绝请求且不创建 guard/session。App 退出时必须关闭 listener。
- 仅接受受控测试页的固定 origin 或不可伪造测试令牌。
- session 与 operation ID 均由 App 测试适配层生成并只使用一次。
- 任一校验失败时 fail-closed，返回结构化拒绝原因并释放已创建的 guard/session 资源。

V2.4-A 不得绕过 `OperationJournal`、Provider operation ledger 或 telemetry outbox。每个触发、guard、动作接受、动作终态和超时释放都必须保留现有证据链语义。

## 5. 验收标准

### 5.1 自动化质量门

- `swift test`、`npm test`、`npm run build`、现有 manifest/install/smoke/provider-protocol 脚本均保持通过。
- CI 至少执行不依赖真实 Chrome 图形会话的 Swift、TypeScript、构建和协议质量门。
- 真实 Chrome 验收入口可以完成环境预检，并在缺少 Chrome、App、host、extension 构建产物或测试模式授权时，返回明确阶段和下一步。

### 5.2 真实 Chrome 链接动作验收

在受控页面中，每条验证均需关联同一个 session/operation 的脱敏证据摘要：

1. 成功路径：`guard_armed` 在 click 副作用前成立；来源标签 URL 保持不变；新标签位于来源标签右侧、处于激活状态且目标为固定 `https:` 测试链接。
2. lease 路径：未收到有效动作确认时，guard 在 lease 到期后释放；后续普通 click 正常导航；新的测试操作不能使用前一 session 的 guard。
3. 不可用路径：App、host 或 Provider 任一不可用时，测试不创建新标签或阻止普通 click，并输出失败阶段、关联 ID 与用户可理解的下一步。
4. 结果未知路径：动作已接受但最终结果无法确认时，记录 `result_unknown`，不自动重放，并允许下一次独立操作开始。

### 5.3 人工边界

触控板硬件输入、三指物理手势方向、系统手势冲突和权限结论继续依据 `docs/research/trackpad-gesture-stability-matrix.md` 与端到端人工清单验证。V2.4-A 的真实 Chrome 验收不替代这些人工验证。

## 6. 完成定义

只有在自动化质量门、真实 Chrome 成功/lease/不可用/结果未知四类验收均留下命令输出或脱敏证据后，V2.4-A 才能标记完成。未能在 CI 执行的 macOS/Chrome 验收必须明确标为人工或专用 runner 验证，不得写成已由通用 CI 覆盖。

后续 V2.4-B 将单独处理断线对账、容量与故障恢复压力验证；不得借由本期链接动作质量门扩大到该范围。
