# GestureKit V2 UI 框架实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Task 6–9 前完成符合 V2 UI 信息架构契约的 App 控制中心和最小 Chrome popup 框架；页面使用稳定的状态模型与占位数据，后续只需接入真实数据和动作。

**Architecture:** App 使用独立的 `ControlCenterPresentation` 状态模型和数据提供协议，SwiftUI 页面只依赖这些模型而不直接依赖 Chrome 类型。Chrome popup 使用只读 `PopupPageState` 渲染当前页面上下文；旧设置、推荐和历史诊断逻辑保留在迁移适配层，直到 Task 11 通过端到端验收后才删除。

**Tech Stack:** Swift 6.2、AppKit、SwiftUI、XCTest、TypeScript、Chrome MV3、Vitest、jsdom。

## Global Constraints

- 所有面向用户的文案和代码注释使用中文；协议字段、路径和 API 名称保持原样。
- 遵循 [`gesturekit-v2-ui-information-architecture.md`](../architecture/gesturekit-v2-ui-information-architecture.md) 的页面责任、隐私边界和状态文案。
- Task 10A 不接入未完成的 Task 6–9 业务逻辑，不展示伪造的“已连接”“已同步”或“无需权限”状态。
- popup 只读，不得写入用户配置、应用推荐或持久化诊断历史。
- 普通 UI、菜单栏和 popup 不得显示协议枚举、错误码、Provider secret、nonce、session ID、原始 `targetRef`、URL query/hash、Cookie 或网页正文。
- V1 不实现动作换绑、三击、任意新组合、轨迹录制、配置分享或完整 DIY 编辑器。
- 每个任务先写失败测试，再实现最小代码；每个任务独立提交。

---

## 文件结构

| 文件 | 责任 |
| --- | --- |
| `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPresentation.swift` | 页面枚举、状态严重性、用户文案和 UI 独立数据模型。 |
| `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterDataSource.swift` | Task 10A 的只读数据提供协议和静态占位实现；Task 10B 替换为真实适配器。 |
| `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterView.swift` | 仅负责窗口布局、侧边栏路由和页面组合。 |
| `apps/macos/GestureKitApp/Sources/GestureKitApp/OperationHistoryView.swift` | 操作记录双栏、空状态、错误状态和证据导出入口的 UI 框架。 |
| `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPages.swift` | 概览、预设、Provider、隐私和高级设置的可复用页面组件。 |
| `apps/macos/GestureKitApp/Sources/GestureKitApp/MenuBarController.swift` | 仅保留状态、暂停/恢复、打开控制中心、持续故障摘要和退出。 |
| `extensions/chrome/src/popup/popupPageState.ts` | popup 的只读页面状态、中文文案映射和 DOM 渲染。 |
| `extensions/chrome/src/popup/popup.ts` | 读取状态、订阅状态变化、调用只读 renderer、发送“打开 App”请求。 |
| `extensions/chrome/popup.html` | 最小 popup DOM：支持状态、连接、预设、最近结果、打开 App。 |
| `extensions/chrome/src/popup/popup.css` | 340px 窄窗口视觉规范和状态卡片样式。 |

## Task 1: 固化 UI 表现模型和稳定占位数据源

**Files:**
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPresentation.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterDataSource.swift`
- Create: `Tests/GestureKitAppTests/ControlCenterPresentationTests.swift`

**Interfaces:**

```swift
enum ControlCenterPage: String, CaseIterable, Identifiable {
    case overview = "概览"
    case operations = "操作记录"
    case presets = "手势预设"
    case providers = "Provider"
    case privacy = "隐私与存储"
    case advanced = "高级设置"
    var id: String { rawValue }
}

enum ControlCenterNotice: Equatable {
    case preparing
    case providerDisconnected
    case configurationSynchronizing
    case pageUnsupported
    case guardUnavailable
    case resultUnknown
    case listeningUnavailable
    case storageInsufficient
    func presentation() -> OperationPresentation
}

enum PresentationSeverity: Equatable { case informational, warning, critical }

struct OperationPresentation: Equatable {
    let title: String
    let detail: String
    let suggestion: String
}

extension OperationPresentation {
    static let resultUnknown = OperationPresentation(
        title: "操作结果暂时无法确认",
        detail: "系统未在期限内收到明确结果",
        suggestion: "系统已保存完整诊断信息"
    )
}

struct OperationListItem: Identifiable, Equatable {
    let id: String
    let title: String
    let presentation: OperationPresentation
    let eventCount: Int
    let lastEventAt: Date
}

struct OperationPageState: Equatable {
    let items: [OperationListItem]
    let selectedOperationID: String?
    let message: String?
    let canLoadMore: Bool
    static let empty = OperationPageState(items: [], selectedOperationID: nil, message: "暂无操作记录", canLoadMore: false)
}

struct ProviderPageState: Equatable { let cards: [ControlCenterStatusCard] }
struct PrivacyPageState: Equatable { let cards: [ControlCenterStatusCard] }

@MainActor
protocol ControlCenterDataSource {
    func overview() -> ControlCenterOverview
    func operationPage(limit: Int) -> OperationPageState
    func providerPage() -> ProviderPageState
    func privacyPage() -> PrivacyPageState
}
```

- [ ] **Step 1: 写失败测试，固定导航顺序和用户文案**

```swift
func testControlCenterPageOrderMatchesUIContract() {
    XCTAssertEqual(ControlCenterPage.allCases.map(\.rawValue), [
        "概览", "操作记录", "手势预设", "Provider", "隐私与存储", "高级设置"
    ])
}

func testGuardUnavailableNeverLeaksProtocolEnum() {
    let model = ControlCenterNotice.guardUnavailable.presentation()
    XCTAssertEqual(model.title, "为避免误触，本次操作未执行")
    XCTAssertFalse(model.title.contains("guard_unavailable"))
}

func testPlaceholderDataNeverClaimsProviderIsConnected() {
    let model = PreviewControlCenterDataSource().overview()
    XCTAssertEqual(model.provider.detail, "Chrome 尚未连接")
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlCenterPresentationTests`

Expected: FAIL，缺少 `ControlCenterPage`、`ControlCenterNotice` 和 `PreviewControlCenterDataSource`。

- [ ] **Step 3: 实现最小表现模型和预览数据源**

```swift
struct ControlCenterStatusCard: Equatable {
    let title: String
    let detail: String
    let severity: PresentationSeverity
}

struct ControlCenterOverview: Equatable {
    let runtime: ControlCenterStatusCard
    let provider: ControlCenterStatusCard
    let latestOperation: ControlCenterStatusCard
    let attention: ControlCenterStatusCard?
}

@MainActor
final class PreviewControlCenterDataSource: ControlCenterDataSource {
    func overview() -> ControlCenterOverview {
        ControlCenterOverview(
            runtime: .init(title: "运行状态", detail: "正在准备 GestureKit", severity: .informational),
            provider: .init(title: "Provider", detail: "Chrome 尚未连接", severity: .warning),
            latestOperation: .init(title: "最近一次操作", detail: "暂无已记录操作", severity: .informational),
            attention: nil
        )
    }
    func operationPage(limit: Int) -> OperationPageState { .empty }
    func providerPage() -> ProviderPageState {
        ProviderPageState(cards: [.init(title: "Chrome Provider", detail: "Chrome 尚未连接", severity: .warning)])
    }
    func privacyPage() -> PrivacyPageState {
        PrivacyPageState(cards: [.init(title: "本地诊断", detail: "正在准备存储信息", severity: .informational)])
    }
}
```

- [ ] **Step 4: 运行任务级测试**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlCenterPresentationTests`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPresentation.swift \
  apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterDataSource.swift \
  Tests/GestureKitAppTests/ControlCenterPresentationTests.swift
git commit -m "feat: add control center presentation models"
```

## Task 2: 重构控制中心为固定导航和独立页面骨架

**Files:**
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterView.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPages.swift`
- Create: `apps/macos/GestureKitApp/Sources/GestureKitApp/OperationHistoryView.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/AppDelegate.swift`
- Test: `Tests/GestureKitAppTests/ControlCenterPresentationTests.swift`

**Interfaces:**

```swift
struct ControlCenterView: View {
    init(control: any RuntimeControlling, dataSource: any ControlCenterDataSource)
}

struct OperationHistoryView: View {
    let state: OperationPageState
    let onLoadMore: () -> Void
    let onExport: (String) -> Void
}
```

- [ ] **Step 1: 扩展失败测试，覆盖空记录与结果未知详情文案**

```swift
func testResultUnknownDetailExplainsEvidenceWithoutInternalCode() {
    let detail = OperationPresentation.resultUnknown
    XCTAssertEqual(detail.title, "操作结果暂时无法确认")
    XCTAssertEqual(detail.suggestion, "系统已保存完整诊断信息")
    XCTAssertFalse(detail.detail.contains("result_unknown"))
}

func testEmptyOperationPageHasStableCallout() {
    XCTAssertEqual(OperationPageState.empty.message, "暂无操作记录")
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlCenterPresentationTests`

Expected: FAIL，缺少 `OperationPresentation` 或 `OperationPageState.empty`。

- [ ] **Step 3: 实现页面骨架**

```swift
@ViewBuilder
private func page(for page: ControlCenterPage) -> some View {
    switch page {
    case .overview: OverviewPage(state: dataSource.overview())
    case .operations: OperationHistoryView(state: dataSource.operationPage(limit: 20), onLoadMore: loadMore, onExport: export)
    case .presets: PresetPage(state: .preparing)
    case .providers: ProviderPage(state: dataSource.providerPage())
    case .privacy: PrivacyPage(state: dataSource.privacyPage())
    case .advanced: AdvancedPage(state: .preparing)
    }
}
```

实现要求：

- `ControlCenterView` 删除硬编码“已认证”“监听正常”等静态成功文案。
- `OperationHistoryView` 固定为列表/详情双栏；在窄窗口时切为列表优先，详情使用 sheet 或导航返回。
- 证据导出按钮在占位数据源状态下禁用并显示“需要先选择一条已记录操作”，不能打开文件选择器。
- `AppDelegate` 创建 `PreviewControlCenterDataSource` 并注入窗口；Task 10B 才替换为真实适配器。

- [ ] **Step 4: 运行 App 测试与构建**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GestureKitAppTests`

Expected: PASS。

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterView.swift \
  apps/macos/GestureKitApp/Sources/GestureKitApp/ControlCenterPages.swift \
  apps/macos/GestureKitApp/Sources/GestureKitApp/OperationHistoryView.swift \
  apps/macos/GestureKitApp/Sources/GestureKitApp/AppDelegate.swift \
  Tests/GestureKitAppTests/ControlCenterPresentationTests.swift
git commit -m "feat: scaffold control center pages"
```

## Task 3: 收缩菜单栏到生命周期和持续故障入口

**Files:**
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/MenuBarController.swift`
- Modify: `Tests/GestureKitAppTests/MenuBarControllerTests.swift`

**Interfaces:**

```swift
enum MenuBarSummary: Equatable {
    case normal
    case paused
    case persistentProblem(title: String)
}

func apply(summary: MenuBarSummary)
```

- [ ] **Step 1: 写失败测试，禁止单次成功动作改变菜单栏摘要**

```swift
func testSingleSuccessfulGestureDoesNotAddTransientMenuSummary() {
    controller.apply(event: .chromeExecuted(action: "browser.tab.activate_next", success: true, detail: nil))
    XCTAssertEqual(controller.visibleStatusTextForTesting, "GestureKit 正常运行")
    XCTAssertNil(controller.visibleGestureTextForTesting)
}

func testPersistentProblemUsesUserFacingText() {
    controller.apply(summary: .persistentProblem(title: "Chrome 连接已中断"))
    XCTAssertEqual(controller.visibleStatusTextForTesting, "Chrome 连接已中断")
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MenuBarControllerTests`

Expected: FAIL，因为当前控制器会显示最近成功手势和动作结果。

- [ ] **Step 3: 实现最小菜单**

保留状态、暂停/恢复、打开控制中心、持续故障摘要和退出。删除“打开日志目录”及单次手势/动作成功的临时菜单行；单次失败只进入操作记录，只有持续故障才通过 `MenuBarSummary.persistentProblem` 上浮。

- [ ] **Step 4: 运行任务级测试**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MenuBarControllerTests`

Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add apps/macos/GestureKitApp/Sources/GestureKitApp/MenuBarController.swift \
  Tests/GestureKitAppTests/MenuBarControllerTests.swift
git commit -m "feat: reduce menu bar to lifecycle controls"
```

## Task 4: 建立只读最小 popup 状态和渲染器

**Files:**
- Create: `extensions/chrome/src/popup/popupPageState.ts`
- Modify: `extensions/chrome/src/popup/popup.ts`
- Modify: `extensions/chrome/popup.html`
- Modify: `extensions/chrome/src/popup/popup.css`
- Modify: `extensions/chrome/tests/popup.test.ts`

**Interfaces:**

```ts
export type PopupPageState = {
  pageSupport: "supported" | "unsupported" | "checking";
  appConnection: "connected" | "disconnected" | "checking";
  providerConnection: "connected" | "disconnected" | "checking";
  presetName: string | null;
  latestResult: PopupResult | null;
};

export type PopupResult = {
  title: string;
  detail: string;
  severity: "informational" | "warning" | "critical";
};

export function presentPopupState(raw: unknown): PopupPageState;
export function renderPopup(doc: Document, state: PopupPageState): void;
```

- [ ] **Step 1: 替换旧测试 DOM，写最小 popup 失败测试**

```ts
it("renders only page context and a control-center entry", () => {
  renderPopup(document, {
    pageSupport: "supported",
    appConnection: "connected",
    providerConnection: "connected",
    presetName: "标准浏览",
    latestResult: { title: "操作已完成", detail: "已切换到下一个标签页", severity: "informational" }
  });
  expect(document.querySelector("#pageSupport")?.textContent).toBe("当前页面支持手势");
  expect(document.querySelector("#openControlCenter")).toBeInstanceOf(HTMLButtonElement);
  expect(document.querySelector("#mode")).toBeNull();
  expect(document.querySelector("#diagnosticsList")).toBeNull();
});

it("maps a guard failure without leaking internal status", () => {
  expect(presentPopupState({ lastResult: "guard_unavailable" }).latestResult).toMatchObject({
    title: "为避免误触，本次操作未执行"
  });
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd extensions/chrome && npm test -- --run tests/popup.test.ts`

Expected: FAIL，因为当前 DOM 含 `#mode` 和 `#diagnosticsList`，且不存在 `renderPopup`。

- [ ] **Step 3: 实现只读状态映射与最小 DOM**

```ts
export function presentPopupState(raw: unknown): PopupPageState {
  const status = isPopupStatus(raw) ? raw : {};
  return {
    pageSupport: status.pageSupported === false ? "unsupported" : "checking",
    appConnection: status.appConnected ? "connected" : "disconnected",
    providerConnection: status.nativeConnected ? "connected" : "disconnected",
    presetName: null,
    latestResult: presentLatestResult(status.lastResult)
  };
}
```

`popup.html` 只保留 `#pageSupport`、`#appConnection`、`#providerConnection`、`#presetName`、`#latestResult`、`#openControlCenter`。`popup.ts` 不再调用 `saveGestureSettings`、`clearDiagnostics`、`buildRecommendedSettings` 或 `formatDiagnosticsForClipboard`；保留旧设置模块给 Task 9 一次性迁移适配，不能再由 popup 直接触发写入。

`#openControlCenter` 发送 `{ type: "gesturekit.openControlCenter" }`。Task 10A 中 background 未处理该消息时按钮显示“请从菜单栏打开 GestureKit”；Task 10B 再接入真实打开能力。

- [ ] **Step 4: 运行 popup 测试和扩展构建**

Run: `cd extensions/chrome && npm test -- --run tests/popup.test.ts`

Expected: PASS。

Run: `cd extensions/chrome && npm run build`

Expected: exit 0。

- [ ] **Step 5: 提交**

```bash
git add extensions/chrome/popup.html \
  extensions/chrome/src/popup/popup.ts \
  extensions/chrome/src/popup/popupPageState.ts \
  extensions/chrome/src/popup/popup.css \
  extensions/chrome/tests/popup.test.ts
git commit -m "feat: reduce popup to page context"
```

## Task 5: 更新原实施计划顺序并执行 UI 框架验收

**Files:**
- Modify: `docs/plans/gesturekit-reliability-platform-implementation-plan.md`
- Modify: `docs/architecture/gesturekit-v2-ui-information-architecture.md`

- [ ] **Step 1: 记录新的执行顺序**

在原计划的依赖图和顺序说明中，将执行顺序更新为：

```text
Task 1/2/2A -> Task 3 -> Task 4 -> Task 5 -> Task 10A -> Task 6/7 -> Task 8 -> Task 9 -> Task 10B -> Task 11
```

保留 Task 10 的原编号、最终验收项和 Task 11 清理条件；新增的 `Task 10A` 与 `Task 10B` 只是同一 Task 的两个阶段。

- [ ] **Step 2: 执行 UI 框架验收**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

Expected: PASS。

Run: `cd extensions/chrome && npm test -- --run`

Expected: PASS。

Run: `cd extensions/chrome && npm run build`

Expected: exit 0。

手工验收：启动 App，确认六个侧边栏页面均可访问；以无 Provider 的预览数据启动时不显示成功状态；缩窄 popup 到 340px 时仅显示五项允许内容；页面中搜索不到 `primitive_rejected`、`guard_unavailable`、`result_unknown`。

- [ ] **Step 3: 提交**

```bash
git add docs/plans/gesturekit-reliability-platform-implementation-plan.md \
  docs/architecture/gesturekit-v2-ui-information-architecture.md
git commit -m "docs: stage task 10 UI framework before provider work"
```

## 计划自检

- 覆盖性：Task 1 固定用户可见状态模型；Task 2 实现六个 App 页面和操作记录布局；Task 3 约束菜单栏；Task 4 收缩 popup；Task 5 固化执行顺序并验证。覆盖 UI 契约的所有页面、状态、隐私和 Task 映射要求。
- 范围：不实现 Task 6–9 的 ledger、手势 session、guard、Chrome Provider 或配置迁移业务逻辑；只定义它们将来接入的协议边界。
- 一致性：`ControlCenterPage`、`ControlCenterDataSource`、`PopupPageState` 和 Task 10A/10B 在各任务中使用相同命名；popup 始终只读，真实配置写入只在 Task 9 后由 App 承担。
- 无占位：计划不包含 `TODO`、`TBD` 或未指定的测试命令；所有任务都有明确文件、接口、失败测试、通过测试和提交边界。
