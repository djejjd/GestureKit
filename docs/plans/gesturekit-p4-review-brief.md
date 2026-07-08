# GestureKit P4 推荐应用闭环 — 代码审核摘要

> **目标读者：** AI 代码审核代理。本文件包含审核所需的全部上下文、变更范围、架构约束和验证方法。

---

## 1. 项目背景

GestureKit 是 macOS 触控板手势增强工具。通过 Swift App（采集输入、识别手势） + Chrome MV3 扩展（执行浏览器动作），实现三指点按打开链接、三指轻扫切换标签页等功能。

**通信链路：** GestureKitApp → Local IPC → Native Host Shim → Chrome Native Messaging stdio → Chrome Extension Background → Content Script

**技术栈：** Swift 6.2 / AppKit / Chrome MV3 / TypeScript / Vitest / XCTest

---

## 2. P4 目标

把现有"只读展示推荐档位/推荐最小距离"推进为**用户可以显式应用推荐设置，并且能确认是否真正生效**的闭环。

核心约束：
- 推荐应用只允许修改轻扫灵敏度和识别阈值，不改 action 绑定
- 扩展侧（`chrome.storage.local`）仍是设置持久化 source of truth
- `settings_ack` 不表示"永久生效"，只表示"当前 App 会话已接受"
- 必须区分五种同步状态：`saved_only / pending / applied / failed / stale`
- `appSessionId`（UUID，App 启动时生成）是唯一新增的跨端状态锚点

---

## 3. 变更范围

**分支：** `plan/v1-spikes`  
**基准：** `8fb075c` → 当前 HEAD `403aaf4`  
**统计：** 13 提交，27 文件，+1423 / -308 行

### 3.1 Swift 侧

| 文件 | 改动 |
|------|------|
| `Sources/GestureKitCore/Protocol/GestureKitMessage.swift` | `ProbeResponsePayload` 新增可选 `appSessionId: String?`；`SettingsAckPayload` 新增必填 `appSessionId: String` 和 `recognitionSettings: GestureRecognitionSettings` |
| `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift` | 1) `init` 中生成 `appSessionId = UUID().uuidString`；2) `handleProbeRequest` 回传 `appSessionId`；3) `applySettingsUpdate` 回传 `recognitionSettings` 快照；4) `handleIPCEnvelope` 新增 `actionResult` 日志记录 |
| `Tests/GestureKitCoreTests/GestureKitMessageTests.swift` | 新增编解码测试：`testProbeResponseDecodesAppSessionId`、`testSettingsAckEncodesRuntimeSessionAndThresholds`、`testSettingsAckDecodesRecognitionSettingsFromJSON` |
| `Tests/GestureKitAppTests/RuntimeSettingsTests.swift` | 新增行为测试：`testSettingsAckIncludesCurrentRuntimeSession`、`testProbeResponseIncludesAppSessionId` |

### 3.2 TS 侧 — 核心逻辑

| 文件 | 改动 | 审核重点 |
|------|------|---------|
| `extensions/chrome/src/settings/swipeRecognition.ts` | **新增文件**。`SwipeRecognitionOverride` 类型、`SWIPE_RECOGNITION_PRESETS` 三档阈值表、`resolveEffectiveSwipeRecognition`（override 优先于 preset）、`buildRecommendedSettings`（从诊断摘要构造设置）、`describeRecognitionDelta`（中文差异摘要） | 阈值表是否与 Swift `GestureRecognitionSettings` 一致；`recommendedMinDistance === null` 时安全回退 |
| `extensions/chrome/src/settings/gestureSettings.ts` | `GestureSettings` 新增 `swipeRecognitionOverride: SwipeRecognitionOverride \| null`；`normalizeGestureSettings` 新增 `normalizeSwipeRecognitionOverride` 校验（范围 0.05-0.20，source 合法性） | 非法输入降级为 null；预设默认值为 null |
| `extensions/chrome/src/background/settingsSync.ts` | **重写**。废弃旧 `{applied, swipeSensitivity, lastSyncedAt}` 扁平模型。新 `SettingsSyncStatus` 含 `phase`、双端 sensitivity、`appSessionId`、`deltaSummary`。五个工厂函数：`createPendingSettingsSyncStatus`、`settingsSyncStatusFromAck`、`markSettingsSyncFailed`、`markSettingsSyncStale`。`createSettingsUpdateMessage` 改用 `resolveEffectiveSwipeRecognition` | 状态转换完整性；`isSettingsSyncStatus` 类型守卫 |
| `extensions/chrome/src/background/background.ts` | `syncGestureSettings` 先写 pending 再 post；ack 处理器传 settings；`port.onDisconnect` 写 failed；probe 后检查 stale；新增 `cancelPendingTap` | 异步竞态；storage 读写顺序 |
| `extensions/chrome/src/background/nativePortManager.ts` | `Dependencies` 新增 `cancelPendingTap?`；不稳定 tap 被拒时调用；`clickAlreadyFired` 携带 `resolveDetail`；`scheduleSingleTapFallback` 接收 `resolveDetail` | `cancelPendingTap?.()` 可选链安全性 |
| `extensions/chrome/src/background/connectionProbe.ts` | `ConnectionProbeResult` 新增 `appSessionId`；probe 响应中提取 | 向后兼容（字段可选） |
| `extensions/chrome/src/protocol/messages.ts` | `ProbeResponseMessage` 新增 `appSessionId?: string`；`SettingsAckMessage` 新增 `appSessionId: string` 和 `recognitionSettings` | TS 类型与 Swift Codable 一致 |

### 3.3 TS 侧 — 诊断与链接解析

| 文件 | 改动 |
|------|------|
| `extensions/chrome/src/content/linkResolver.ts` | `LinkResolveResult` 的 `no_target`、`unsupported_url_scheme`、`no_recent_pointer` 新增 `detail?: string`；`resolveLinkAtPoint` 返回命中元素信息 |
| `extensions/chrome/src/content/pointerTracker.ts` | 1) `resolveLinkAtLastPointer` 无指针时返回详细原因；2) `clickAlreadyFired` 时返回 `protection=ON/OFF clickAge=XXms`；3) 新增 `cancelProtectedClick` 导出；4) 新增 `gesturekit.cancelTap` 消息处理 |
| `extensions/chrome/src/diagnostics/diagnostics.ts` | `formatDiagnosticsForClipboard` 新增可选参数 `current`、`recommended`、`syncStatus`；`diagnosticFromActionResult` 提取 `resolveDetail` 到 `message` |
| `extensions/chrome/src/popup/popup.ts` | `renderStatus` 新增圆点 className；`renderRecommendationCard` 和 `applyRecommendedSettings`（P4 核心 UI）；`diagnosticRow` 展示 `message`；`formatPopupDiagnostics` 携带 delta；清空诊断时重置 toggle |
| `extensions/chrome/src/popup/popup.css` | 卡片化布局；圆点样式；推荐区样式；展开箭头动画；`[hidden]` 防御 |
| `extensions/chrome/popup.html` | 新增推荐卡片区（`#recommendationSection`） |

### 3.4 测试

| 文件 | 新增测试 |
|------|---------|
| `extensions/chrome/tests/swipeRecognition.test.ts` | **新增** 10 个测试：resolve、build、describe 全覆盖 |
| `extensions/chrome/tests/settingsSync.test.ts` | **重写** 10 个测试：五态转换、pending→applied→stale→failed |
| `extensions/chrome/tests/gestureSettings.test.ts` | +3：override 持久化、非法降级、默认 null |
| `extensions/chrome/tests/popup.test.ts` | +4：推荐入口显隐、确认、状态分离、失败展示 |
| `extensions/chrome/tests/diagnostics.test.ts` | +2：delta 输出、applyPhase 输出 |
| `extensions/chrome/tests/linkResolver.test.ts` | 适配 detail 字段 |
| `extensions/chrome/tests/pointerTracker.test.ts` | 适配 detail 字段 |

---

## 4. 架构约束（审核时不得违反）

1. **source of truth** — 扩展侧 `chrome.storage.local` 是设置持久化源，App 侧只存当前运行时状态
2. **推荐范围** — 只允许改 `swipeSensitivity` 和 `swipeMinDistance`，不改 tap/edge/cooldown 等
3. **`settings_ack` 语义** — 仅表示"当前 App 会话已接受"，不代表永久生效
4. **不做** — 规则编辑器、任意动作绑定、自动应用推荐、多浏览器支持
5. **中文文档优先** — 所有新增文档和注释用中文
6. **不新增用户可见手势动作**

---

## 5. 数据流（P4 关键路径）

```
用户点 popup "应用推荐设置"
  → buildRecommendedSettings(settings, summary) 构造带 override 的设置
  → saveGestureSettings(storage, next) 写入 chrome.storage.local
  → storage.onChanged 触发 background.syncGestureSettings()
    → createPendingSettingsSyncStatus → storage.set (phase=pending)
    → createSettingsUpdateMessage → resolveEffectiveSwipeRecognition → port.postMessage
      → Native host → App IPC → Runtime.applySettingsUpdate
        → recognizer.updateSettings(recognitionSettings)
        → SettingsAckPayload(appSessionId, recognitionSettings)
      ← settings_ack
    ← settingsSyncStatusFromAck(message, settings) → storage.set (phase=applied)

App 重启后 popup 刷新：
  → runConnectionProbe → probeResponse.appSessionId
  → markSettingsSyncStale(status, newSessionId) → phase=stale
```

```
不稳定点按被拒：
  → nativePortManager 判定 tap_duration_unstable
  → cancelPendingTap() → chrome.tabs.sendMessage("gesturekit.cancelTap")
  → content script cancelProtectedClick() → clearTimeout → 不跳转
```

---

## 6. 验证命令

```bash
# Swift（需 Xcode）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # 期望 41 passed
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build

# TS
cd extensions/chrome
npm test   # 期望 97 passed
npm run build
```

---

## 7. 已知问题（审核时可忽略）

- `ipc_message_decode_failed: expected String but found number, path payload.details.targetIndex` — `ActionResultPayload.details` 类型为 `[String: String]`，但 `actionExecutor.ts` 的 `targetIndex` 是 number。不影响功能，P5 处理。
- 日志仅限 Swift App 端；扩展侧 `console` 输出不可见（已移除）。

---

## 8. 建议审核顺序

1. `swipeRecognition.ts`（新增，了解推荐模型）
2. `settingsSync.ts`（状态机核心）
3. `background.ts`（状态迁移链路）
4. `nativePortManager.ts`（cancelPendingTap）
5. `pointerTracker.ts`（点击保护取消）
6. `GestureKitMessage.swift` + `Runtime.swift`（协议变更）
7. 其余文件（UI、测试、文档）
