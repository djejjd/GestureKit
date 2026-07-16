# GestureKit P4 推荐应用闭环实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把当前“推荐档位/推荐最小距离”的只读展示，推进到“用户可显式应用推荐设置，并能确认是否已保存到扩展、是否已真正应用到 App 运行时”的闭环。

**Architecture:** 扩展侧继续保留设置 source of truth，推荐应用本质上是一次受控的设置写回；Swift App 只负责接收当前生效的识别阈值并返回带会话标识的 `settings_ack`。popup 不直接推断“已应用”，而是消费后台维护的同步状态对象，区分 `saved`、`pending`、`applied`、`failed`、`stale` 五类状态。

**Tech Stack:** Swift 6.2 / GestureKitCore protocol / Chrome MV3 / TypeScript / Vitest / XCTest / `chrome.storage.local`。

## Global Constraints

- 项目文档默认中文优先。
- 不新增用户可见手势动作，不做规则编辑器，不做任意动作绑定。
- 推荐应用只允许修改轻扫灵敏度和轻扫识别阈值，不改 tap/edge/cooldown 等非推荐项。
- 扩展侧仍是设置的持久化 source of truth；App 侧只保存当前运行时已应用值，不新增长期配置文件。
- 不做自动应用推荐，必须有显式确认。
- `settings_ack` 不得再被解释为“永久生效”；它只能表示“某个 App 会话中，某次 settings_update 已被当前运行时接受”。
- 推荐失败、host 断开、App 未运行、ack 缺失、App 重启导致的失效都必须有明确状态文本，不允许静默吞掉。

---

## 文件结构

- `Sources/GestureKitCore/Protocol/GestureKitMessage.swift`
  - 扩展 `ProbeResponsePayload` 和 `SettingsAckPayload`，让协议能表达 `appSessionId` 与当前运行时应用的阈值快照。
- `Tests/GestureKitCoreTests/GestureKitMessageTests.swift`
  - 覆盖新的协议编码/解码契约。
- `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
  - 为 Runtime 引入稳定的 `appSessionId`，并在 `probe_response` / `settings_ack` 中返回。
- `Tests/GestureKitAppTests/RuntimeSettingsTests.swift`
  - 验证应用设置后 ack 带回当前 session 和阈值；验证新会话会产生新的 `appSessionId`。
- `extensions/chrome/src/settings/gestureSettings.ts`
  - 扩展持久化设置模型，允许在“不开放任意编辑”的前提下保存推荐产生的轻扫阈值覆盖。
- `extensions/chrome/src/settings/swipeRecognition.ts`
  - 新增轻扫识别阈值解析、推荐应用写回、当前值与推荐值差异摘要。
- `extensions/chrome/tests/gestureSettings.test.ts`
  - 覆盖推荐设置持久化、回退和归一化。
- `extensions/chrome/tests/swipeRecognition.test.ts`
  - 覆盖推荐阈值构造、delta 摘要和“无推荐时不可应用”。
- `extensions/chrome/src/diagnostics/diagnostics.ts`
  - 输出结构化推荐结果与 clipboard delta 文本。
- `extensions/chrome/tests/diagnostics.test.ts`
  - 覆盖“当前设置 vs 推荐设置”摘要输出。
- `extensions/chrome/src/background/settingsSync.ts`
  - 维护同步状态机和状态文案，避免 popup 直接拼接布尔值。
- `extensions/chrome/src/background/background.ts`
  - 在设置变更、ack、disconnect、probe 结果之间推进状态机并写入 storage。
- `extensions/chrome/src/background/connectionProbe.ts`
  - 把 `appSessionId` 暴露给扩展侧，用于识别 App 重启后的 stale 状态。
- `extensions/chrome/tests/settingsSync.test.ts`
  - 覆盖 `pending -> applied -> stale/failed` 转换。
- `extensions/chrome/popup.html`
  - 增加推荐应用卡片、确认交互、保存状态、运行时状态、失败原因。
- `extensions/chrome/src/popup/popup.ts`
  - 渲染推荐卡片、触发确认、执行“应用推荐设置”、刷新 probe 状态、复制包含 delta 的诊断。
- `extensions/chrome/src/popup/popup.css`
  - 增加推荐卡片与状态标签样式。
- `extensions/chrome/tests/popup.test.ts`
  - 覆盖推荐按钮显隐、确认、状态文案和失败表现。
- `docs/operations/e2e-checklist.md`
  - 增加推荐应用闭环验收步骤。
- `docs/operations/troubleshooting.md`
  - 增加 `saved_only` / `pending` / `stale` / `failed` 的排查入口。
- `docs/plans/gesturekit-v1-progress-archive.md`
  - 实现完成后补记 P4 完成状态。

### Task 1: 协议契约与 App 会话标识

**Files:**
- Modify: `Sources/GestureKitCore/Protocol/GestureKitMessage.swift`
- Modify: `Tests/GestureKitCoreTests/GestureKitMessageTests.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- Modify: `Tests/GestureKitAppTests/RuntimeSettingsTests.swift`

**Interfaces:**
- Produces:

```swift
public struct ProbeResponsePayload: Codable, Equatable, Sendable {
    public let hostConnected: Bool
    public let appConnected: Bool
    public let appSessionId: String?
    public let message: String?
}

public struct SettingsAckPayload: Codable, Equatable, Sendable {
    public let applied: Bool
    public let swipeSensitivity: SwipeSensitivity
    public let appSessionId: String
    public let recognitionSettings: GestureRecognitionSettings
    public let message: String?
}
```

- Produces:

```swift
@MainActor
final class GestureKitRuntime {
    private let appSessionId: String
}
```

- Consumes later in TS:

```ts
type ProbeResponseMessage["payload"] = {
  hostConnected: boolean;
  appConnected: boolean;
  appSessionId?: string;
  message?: string;
};

type SettingsAckMessage["payload"] = {
  applied: boolean;
  swipeSensitivity: SwipeSensitivity;
  appSessionId: string;
  recognitionSettings: GestureRecognitionSettings;
  message?: string;
};
```

- [ ] **Step 1: 先写 Swift 协议失败测试**

```swift
func testSettingsAckEncodesRuntimeSessionAndThresholds() throws {
    let message = GestureKitMessage.settingsAck(
        id: "settings-ack-1",
        timestamp: 20,
        payload: SettingsAckPayload(
            applied: true,
            swipeSensitivity: .standard,
            appSessionId: "session-1",
            recognitionSettings: .standard
        )
    )

    let json = String(decoding: try JSONEncoder.gestureKit.encode(message), as: UTF8.self)
    XCTAssertTrue(json.contains("\"appSessionId\":\"session-1\""))
    XCTAssertTrue(json.contains("\"swipeMinDistance\":0.09"))
}
```

- [ ] **Step 2: 先写 Runtime 失败测试，约束会话语义**

```swift
func testSettingsAckIncludesCurrentRuntimeSession() {
    let runtime = GestureKitRuntime(...)
    let ack = runtime.applySettingsUpdate(SettingsUpdatePayload(...))

    XCTAssertEqual(ack.appSessionId.count > 0, true)
    XCTAssertEqual(ack.recognitionSettings.swipeSensitivity, .sensitive)
}
```

- [ ] **Step 3: 实现协议字段扩展**

```swift
public init(
    applied: Bool,
    swipeSensitivity: SwipeSensitivity,
    appSessionId: String,
    recognitionSettings: GestureRecognitionSettings,
    message: String? = nil
) {
    self.applied = applied
    self.swipeSensitivity = swipeSensitivity
    self.appSessionId = appSessionId
    self.recognitionSettings = recognitionSettings
    self.message = message
}
```

- [ ] **Step 4: 在 Runtime 中生成稳定会话号并回传**

```swift
init(...) {
    ...
    self.appSessionId = UUID().uuidString
}

private func handleProbeRequest(_ id: String) -> LocalIPCEnvelope {
    LocalIPCEnvelope(message: .probeResponse(
        id: id,
        timestamp: currentTimestampMs(),
        payload: ProbeResponsePayload(
            hostConnected: true,
            appConnected: true,
            appSessionId: appSessionId,
            message: "app_ready"
        )
    ))
}
```

- [ ] **Step 5: 返回 ack 时带上当前阈值快照**

```swift
func applySettingsUpdate(_ payload: SettingsUpdatePayload) -> SettingsAckPayload {
    recognizer.updateSettings(payload.recognitionSettings)
    return SettingsAckPayload(
        applied: true,
        swipeSensitivity: payload.swipeSensitivity,
        appSessionId: appSessionId,
        recognitionSettings: payload.recognitionSettings
    )
}
```

- [ ] **Step 6: 运行 Swift 定向测试**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GestureKitMessageTests --filter RuntimeSettingsTests`

Expected: `Test Suite ... passed`

- [ ] **Step 7: 提交**

```bash
git add Sources/GestureKitCore/Protocol/GestureKitMessage.swift \
  Tests/GestureKitCoreTests/GestureKitMessageTests.swift \
  apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift \
  Tests/GestureKitAppTests/RuntimeSettingsTests.swift
git commit -m "feat: add app session to settings ack"
```

### Task 2: 扩展侧推荐设置模型与有效阈值解析

**Files:**
- Modify: `extensions/chrome/src/settings/gestureSettings.ts`
- Create: `extensions/chrome/src/settings/swipeRecognition.ts`
- Modify: `extensions/chrome/tests/gestureSettings.test.ts`
- Create: `extensions/chrome/tests/swipeRecognition.test.ts`

**Interfaces:**
- Produces:

```ts
export type SwipeRecognitionOverride = {
  source: "preset" | "recommended";
  recommendedMinDistance: number | null;
};

export type EffectiveSwipeRecognition = {
  swipeSensitivity: SwipeSensitivity;
  swipeMinDistance: number;
  swipeHorizontalRatio: number;
  swipeMinDurationMs: number;
  swipeMaxDurationMs: number;
  source: "preset" | "recommended";
};
```

- Produces:

```ts
export function resolveEffectiveSwipeRecognition(settings: GestureSettings): EffectiveSwipeRecognition;
export function buildRecommendedSettings(
  settings: GestureSettings,
  summary: DiagnosticsSummary
): GestureSettings | null;
export function describeRecognitionDelta(
  current: EffectiveSwipeRecognition,
  recommended: EffectiveSwipeRecognition
): string[];
```

- [ ] **Step 1: 先写 `gestureSettings` 失败测试，约束持久化形状**

```ts
it("keeps recommendation override when normalized", () => {
  const normalized = normalizeGestureSettings({
    mode: "safe",
    swipeSensitivity: "standard",
    swipeRecognitionOverride: {
      source: "recommended",
      recommendedMinDistance: 0.084
    }
  });

  expect(normalized.swipeRecognitionOverride).toEqual({
    source: "recommended",
    recommendedMinDistance: 0.084
  });
});
```

- [ ] **Step 2: 先写 `swipeRecognition` 失败测试，约束推荐转换**

```ts
it("builds recommended settings from diagnostics summary", () => {
  const next = buildRecommendedSettings(GESTURE_SETTINGS_PRESETS.safe, {
    ...summaryFixture,
    recommendedSensitivity: "sensitive",
    recommendedMinDistance: 0.084
  });

  expect(next).toMatchObject({
    swipeSensitivity: "sensitive",
    swipeRecognitionOverride: {
      source: "recommended",
      recommendedMinDistance: 0.084
    }
  });
});
```

- [ ] **Step 3: 实现推荐覆盖字段的归一化**

```ts
export type GestureSettings = {
  ...
  swipeRecognitionOverride: SwipeRecognitionOverride | null;
};
```

```ts
const override = normalizeSwipeRecognitionOverride(merged.swipeRecognitionOverride);
...
return {
  ...,
  swipeRecognitionOverride: override
};
```

- [ ] **Step 4: 实现有效轻扫阈值解析**

```ts
export function resolveEffectiveSwipeRecognition(settings: GestureSettings): EffectiveSwipeRecognition {
  const preset = SWIPE_RECOGNITION_PRESETS[settings.swipeSensitivity];
  if (settings.swipeRecognitionOverride?.source !== "recommended" ||
      settings.swipeRecognitionOverride.recommendedMinDistance === null) {
    return { ...preset, source: "preset" };
  }
  return {
    ...preset,
    swipeMinDistance: settings.swipeRecognitionOverride.recommendedMinDistance,
    source: "recommended"
  };
}
```

- [ ] **Step 5: 实现推荐应用与差异摘要**

```ts
export function describeRecognitionDelta(current: EffectiveSwipeRecognition, recommended: EffectiveSwipeRecognition): string[] {
  return [
    current.swipeSensitivity === recommended.swipeSensitivity
      ? "推荐档位与当前一致"
      : `灵敏度 ${current.swipeSensitivity} -> ${recommended.swipeSensitivity}`,
    current.swipeMinDistance === recommended.swipeMinDistance
      ? "推荐最小距离与当前一致"
      : `最小距离 ${current.swipeMinDistance.toFixed(3)} -> ${recommended.swipeMinDistance.toFixed(3)}`
  ];
}
```

- [ ] **Step 6: 运行 TS 定向测试**

Run: `cd extensions/chrome && npm test -- gestureSettings swipeRecognition`

Expected: `PASS extensions/chrome/tests/gestureSettings.test.ts` 和 `PASS extensions/chrome/tests/swipeRecognition.test.ts`

- [ ] **Step 7: 提交**

```bash
git add extensions/chrome/src/settings/gestureSettings.ts \
  extensions/chrome/src/settings/swipeRecognition.ts \
  extensions/chrome/tests/gestureSettings.test.ts \
  extensions/chrome/tests/swipeRecognition.test.ts
git commit -m "feat: add recommendation-aware swipe settings"
```

### Task 3: 后台同步状态机与 stale/failed 语义

**Files:**
- Modify: `extensions/chrome/src/protocol/messages.ts`
- Modify: `extensions/chrome/src/background/connectionProbe.ts`
- Modify: `extensions/chrome/src/background/settingsSync.ts`
- Modify: `extensions/chrome/src/background/background.ts`
- Modify: `extensions/chrome/tests/settingsSync.test.ts`

**Interfaces:**
- Produces:

```ts
export type SettingsSyncPhase = "saved_only" | "pending" | "applied" | "failed" | "stale";

export type SettingsSyncStatus = {
  phase: SettingsSyncPhase;
  savedSwipeSensitivity: SwipeSensitivity;
  runtimeSwipeSensitivity: SwipeSensitivity | null;
  currentAppSessionId: string | null;
  requestedAt: number | null;
  appliedAt: number | null;
  messageId: string | null;
  deltaSummary: string[];
  message?: string;
};
```

- Produces:

```ts
export function createSettingsUpdateMessage(
  settings: GestureSettings,
  timestamp?: number
): SettingsUpdateMessage;

export function createPendingSettingsSyncStatus(
  settings: GestureSettings,
  timestamp: number
): SettingsSyncStatus;

export function settingsSyncStatusFromAck(
  message: SettingsAckMessage,
  settings: GestureSettings
): SettingsSyncStatus;

export function markSettingsSyncFailed(
  previous: SettingsSyncStatus | null,
  reason: string,
  timestamp: number
): SettingsSyncStatus;

export function markSettingsSyncStale(
  previous: SettingsSyncStatus | null,
  appSessionId: string | null,
  timestamp: number
): SettingsSyncStatus;
```

- [ ] **Step 1: 先写状态机失败测试**

```ts
it("marks settings as pending when storage changes before ack", () => {
  const status = createPendingSettingsSyncStatus(recommendedSettingsFixture, 100);
  expect(status.phase).toBe("pending");
  expect(status.runtimeSwipeSensitivity).toBeNull();
});

it("marks settings as stale when probe sees a new app session", () => {
  const stale = markSettingsSyncStale({
    ...appliedFixture,
    currentAppSessionId: "session-old"
  }, "session-new", 200);
  expect(stale.phase).toBe("stale");
});
```

- [ ] **Step 2: 让 `settings_update` 基于有效阈值而不是纯 preset**

```ts
const recognition = resolveEffectiveSwipeRecognition(settings);
return {
  ...,
  payload: {
    swipeSensitivity: recognition.swipeSensitivity,
    swipeMinDistance: recognition.swipeMinDistance,
    swipeHorizontalRatio: recognition.swipeHorizontalRatio,
    swipeMinDurationMs: recognition.swipeMinDurationMs,
    swipeMaxDurationMs: recognition.swipeMaxDurationMs
  }
};
```

- [ ] **Step 3: 实现 ack -> applied 转换**

```ts
export function settingsSyncStatusFromAck(message: SettingsAckMessage, settings: GestureSettings): SettingsSyncStatus {
  return {
    phase: message.payload.applied ? "applied" : "failed",
    savedSwipeSensitivity: settings.swipeSensitivity,
    runtimeSwipeSensitivity: message.payload.swipeSensitivity,
    currentAppSessionId: message.payload.appSessionId,
    requestedAt: null,
    appliedAt: message.timestamp,
    messageId: message.id,
    deltaSummary: describeRecognitionDelta(
      resolveEffectiveSwipeRecognition(settings),
      {
        ...message.payload.recognitionSettings,
        swipeSensitivity: message.payload.swipeSensitivity,
        source: "recommended"
      }
    ),
    message: message.payload.message
  };
}
```

- [ ] **Step 4: 在 background 中接入完整状态迁移**

```ts
async function syncGestureSettings() {
  const settings = await loadGestureSettings(chrome.storage.local);
  await chrome.storage.local.set({
    [SETTINGS_SYNC_STATUS_STORAGE_KEY]: createPendingSettingsSyncStatus(settings, Date.now())
  });
  port.postMessage(createSettingsUpdateMessage(settings));
}
```

```ts
if (isSettingsAckMessage(message)) {
  const settings = await loadGestureSettings(chrome.storage.local);
  await chrome.storage.local.set({
    [SETTINGS_SYNC_STATUS_STORAGE_KEY]: settingsSyncStatusFromAck(message, settings)
  });
  return;
}
```

- [ ] **Step 5: 接入 probe session 检查和 disconnect 失败态**

```ts
const probe = await runConnectionProbe(port);
if (probe.appSessionId && probe.appSessionId !== status.currentAppSessionId) {
  await chrome.storage.local.set({
    [SETTINGS_SYNC_STATUS_STORAGE_KEY]: markSettingsSyncStale(status, probe.appSessionId, Date.now())
  });
}
```

```ts
port.onDisconnect.addListener(() => {
  void chrome.storage.local.set({
    [SETTINGS_SYNC_STATUS_STORAGE_KEY]: markSettingsSyncFailed(previousStatus, "native_host_disconnected", Date.now())
  });
});
```

- [ ] **Step 6: 运行 TS 定向测试**

Run: `cd extensions/chrome && npm test -- settingsSync`

Expected: `PASS extensions/chrome/tests/settingsSync.test.ts`

- [ ] **Step 7: 提交**

```bash
git add extensions/chrome/src/protocol/messages.ts \
  extensions/chrome/src/background/connectionProbe.ts \
  extensions/chrome/src/background/settingsSync.ts \
  extensions/chrome/src/background/background.ts \
  extensions/chrome/tests/settingsSync.test.ts
git commit -m "feat: track recommendation apply sync state"
```

### Task 4: popup 推荐应用、确认与诊断 delta 展示

**Files:**
- Modify: `extensions/chrome/popup.html`
- Modify: `extensions/chrome/src/popup/popup.ts`
- Modify: `extensions/chrome/src/popup/popup.css`
- Modify: `extensions/chrome/src/diagnostics/diagnostics.ts`
- Modify: `extensions/chrome/tests/diagnostics.test.ts`
- Modify: `extensions/chrome/tests/popup.test.ts`

**Interfaces:**
- Consumes:

```ts
type DiagnosticsSummary = {
  ...
  recommendedSensitivity: SwipeSensitivity;
  recommendedMinDistance: number | null;
  recommendationText: string;
};
```

- Produces:

```ts
function formatRecommendationStatus(status: SettingsSyncStatus | null): string;
function canApplyRecommendation(summary: DiagnosticsSummary): boolean;
async function applyRecommendedSettings(doc: Document, storage: PopupStorage): Promise<void>;
```

- UI ids:

```html
<section class="recommendation">
  <div id="recommendationDelta"></div>
  <strong id="recommendationSavedStatus"></strong>
  <strong id="recommendationRuntimeStatus"></strong>
  <strong id="recommendationFailureReason"></strong>
  <button id="applyRecommendedSettings" type="button">应用推荐设置</button>
</section>
```

- [ ] **Step 1: 先写 popup 失败测试，覆盖推荐入口**

```ts
it("applies recommended settings after confirmation", async () => {
  vi.spyOn(window, "confirm").mockReturnValue(true);
  const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe, appliedStatusFixture, recommendationDiagnosticsFixture);

  await initializeGestureSettingsPopup(document, storage);
  (document.querySelector("#applyRecommendedSettings") as HTMLButtonElement).click();
  await flushPromises();

  expect(storage.set).toHaveBeenCalledWith({
    [GESTURE_SETTINGS_STORAGE_KEY]: expect.objectContaining({
      swipeSensitivity: "sensitive",
      swipeRecognitionOverride: {
        source: "recommended",
        recommendedMinDistance: 0.084
      }
    })
  });
});
```

- [ ] **Step 2: 再写 popup 失败测试，覆盖状态语义**

```ts
it("renders saved and runtime status separately", async () => {
  const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe, {
    phase: "saved_only",
    savedSwipeSensitivity: "sensitive",
    runtimeSwipeSensitivity: null
  }, recommendationDiagnosticsFixture);

  await initializeGestureSettingsPopup(document, storage);

  expect(document.querySelector("#recommendationSavedStatus")?.textContent).toContain("已保存到扩展");
  expect(document.querySelector("#recommendationRuntimeStatus")?.textContent).toContain("等待 App 应用");
});
```

- [ ] **Step 3: 扩展诊断摘要输出 delta 文本**

```ts
export function formatDiagnosticsForClipboard(
  events: GestureDiagnosticEntry[],
  current?: EffectiveSwipeRecognition,
  recommended?: EffectiveSwipeRecognition | null,
  syncStatus?: SettingsSyncStatus | null
): string
```

```ts
const lines = [
  "GestureKit Diagnostics",
  `recommendation=${summary.recommendationText}`,
  `currentRecognition=${formatRecognition(current)}`,
  `recommendedRecognition=${recommended ? formatRecognition(recommended) : "none"}`,
  `applyPhase=${syncStatus?.phase ?? "unknown"}`
];
```

- [ ] **Step 4: 在 popup 中渲染推荐卡片和确认流程**

```ts
element(doc, "#applyRecommendedSettings").addEventListener("click", () => {
  void applyRecommendedSettings(doc, storage);
});
```

```ts
async function applyRecommendedSettings(doc: Document, storage: PopupStorage) {
  const next = buildRecommendedSettings(readSettings(doc), currentSummary);
  if (!next) {
    renderRecommendationFailure(doc, "当前推荐数据不足，暂不应用");
    return;
  }
  if (!window.confirm("将把推荐档位和推荐最小距离写入扩展设置，并等待 App 运行时确认。继续吗？")) {
    return;
  }
  await saveAndRender(doc, storage, next);
}
```

- [ ] **Step 5: popup 初始化时主动刷新一次 probe，并处理 stale 状态**

```ts
await chrome.runtime.sendMessage({ type: "gesturekit.runConnectionProbe" });
```

```ts
if (status.phase === "stale") {
  element(doc, "#recommendationFailureReason").textContent = "App 已重启，需要重新应用或等待自动重同步";
}
```

- [ ] **Step 6: 运行 TS 定向测试**

Run: `cd extensions/chrome && npm test -- popup diagnostics`

Expected: `PASS extensions/chrome/tests/popup.test.ts` 和 `PASS extensions/chrome/tests/diagnostics.test.ts`

- [ ] **Step 7: 提交**

```bash
git add extensions/chrome/popup.html \
  extensions/chrome/src/popup/popup.ts \
  extensions/chrome/src/popup/popup.css \
  extensions/chrome/src/diagnostics/diagnostics.ts \
  extensions/chrome/tests/diagnostics.test.ts \
  extensions/chrome/tests/popup.test.ts
git commit -m "feat: add recommendation apply flow in popup"
```

### Task 5: 文档、全量验证与收口

**Files:**
- Modify: `docs/operations/e2e-checklist.md`
- Modify: `docs/operations/troubleshooting.md`
- Modify: `docs/plans/gesturekit-v1-progress-archive.md`

**Interfaces:**
- Produces:

```text
验收口径：
1. 推荐可以显示、确认、写回。
2. UI 明确区分“已保存到扩展”和“App 运行时已应用”。
3. host 断开、ack 缺失、App 重启都会进入明确失败/失效态。
4. 复制诊断包含当前值、推荐值、delta 和 applyPhase。
```

- [ ] **Step 1: 更新中文验收文档**

```md
1. 打开 popup，确认出现“应用推荐设置”按钮。
2. 点击后出现确认；确认后 `推荐保存状态` 变为“已保存到扩展”。
3. App 在线时，等待状态变为“App 运行时已应用”。
4. 关闭 App 后再次打开 popup，确认状态不会继续误报“已应用”。
```

- [ ] **Step 2: 更新排障文档**

```md
- `saved_only`：扩展设置已写入，但 App 还未 ack；先看 App 是否运行。
- `pending`：已发出 settings_update，等待 host/App 返回。
- `failed`：host 断开或 ack 返回失败；先跑 smoke probe。
- `stale`：App 会话已变化，旧 ack 作废；重新应用推荐设置。
```

- [ ] **Step 3: 跑 Swift 全量验证**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

Expected: 全部 `passed`

- [ ] **Step 4: 跑 Swift build 和 host 自检**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`

Expected: `Build complete`

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GestureKitHost --self-test`

Expected: 包含 `self-test passed`

- [ ] **Step 5: 跑扩展全量验证**

Run: `cd extensions/chrome && npm test`

Expected: 所有 Vitest 通过

Run: `cd extensions/chrome && npm run build`

Expected: 构建产物成功输出到 `dist/`

- [ ] **Step 6: 跑格式检查**

Run: `git diff --check`

Expected: 无输出

- [ ] **Step 7: 归档并提交**

```bash
git add docs/operations/e2e-checklist.md \
  docs/operations/troubleshooting.md \
  docs/plans/gesturekit-v1-progress-archive.md
git commit -m "docs: document recommendation apply workflow"
```

## 自检

- 已覆盖路线图中 `P4` 的 6 个核心要求：入口、确认、持久化语义、应用状态、诊断 delta、失败/恢复路径。
- 未扩大到规则编辑器、多浏览器、新动作、菜单栏 UI 或自动应用。
- 类型命名统一围绕 `SwipeRecognitionOverride`、`EffectiveSwipeRecognition`、`SettingsSyncStatus.phase`，避免同义字段并存。
- `App 重启` 的识别依赖 `appSessionId`；这是本计划中唯一新增的跨端状态锚点，后续实现不得再退回纯布尔 ack。
