# GestureKit P2 诊断面板实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Chrome popup 中增加可折叠诊断面板，记录最近手势、动作和连接问题，并为后续个人轻扫灵敏度推荐保留可用数据。

**Architecture:** Swift App 在手势结束时生成诊断摘要，Native Host 透传给扩展；扩展维护 `chrome.storage.local` 中的限量 ring buffer。popup 保留现有设置控件，在下方增加诊断摘要、最近记录、复制诊断和清空诊断。

**Tech Stack:** Swift 6.2 / GestureKitCore protocol / Chrome MV3 / TypeScript / Vitest / XCTest。

## Global Constraints

- 项目文档默认中文优先。
- 不记录原始触控帧、网页内容、URL 或浏览历史。
- 诊断数据只存本机 `chrome.storage.local`，保留最近 100 条；popup 默认展示最近 5 条，展开最多 10 条。
- 终端默认不刷屏；重要 warning/error 仍可打印，普通诊断只写文件或扩展 storage。
- 不做自动应用推荐灵敏度；本期只预留数据和显示“建议”文本。

---

## 文件结构

- `Sources/GestureKitCore/Protocol/GestureKitMessage.swift`：增加 `diagnostic_event` 协议 payload。
- `Sources/GestureKitCore/Gestures/GestureRecognizer.swift`：为轻扫失败补充原因和阈值摘要。
- `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`：发布诊断事件。
- `extensions/chrome/src/diagnostics/diagnostics.ts`：新增诊断数据模型、ring buffer、摘要和复制文本。
- `extensions/chrome/src/background/background.ts`：接收 `diagnostic_event` 并写入诊断 buffer。
- `extensions/chrome/src/background/nativePortManager.ts`：动作结果也写入诊断 buffer。
- `extensions/chrome/src/popup/popup.ts` / `popup.html` / `popup.css`：新增可折叠诊断 UI、复制、清空。
- `Tests/GestureKitCoreTests/*`、`Tests/GestureKitAppTests/*`、`extensions/chrome/tests/*`：覆盖协议、诊断 buffer、popup 行为。
- `README.md`、`docs/operations/e2e-checklist.md`：更新使用和验收说明。

## Task 1: 协议和 Swift 诊断摘要

**Files:**
- Modify: `Sources/GestureKitCore/Protocol/GestureKitMessage.swift`
- Modify: `Sources/GestureKitCore/Gestures/TouchSample.swift`
- Modify: `Sources/GestureKitCore/Gestures/GestureRecognizer.swift`
- Modify: `Tests/GestureKitCoreTests/GestureKitMessageTests.swift`
- Modify: `Tests/GestureKitCoreTests/GestureRecognizerTests.swift`

**Interfaces:**
- Produces: `DiagnosticEventPayload`, `DiagnosticSource`, `DiagnosticEventKind`, `GestureFailureReason`。
- Produces: `RecognizedGesture.reason`, `RecognizedGesture.thresholds`。

- [x] Add failing XCTest for `diagnostic_event` encode/decode with swipe fields.
- [x] Add failing XCTest for a short swipe returning `reason == .distanceTooShort`.
- [x] Implement protocol payload and message factory.
- [x] Implement failure reason classification without changing default recognition thresholds.
- [x] Run `swift test --filter GestureKitMessageTests --filter GestureRecognizerTests`.

## Task 2: App 发布诊断事件

**Files:**
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- Modify: `Tests/GestureKitAppTests/RuntimeSettingsTests.swift`

**Interfaces:**
- Consumes: `GestureKitMessage.diagnosticEvent(...)`
- Produces: App -> Host -> Extension 的 `diagnostic_event` NDJSON 行。

- [x] Add failing Runtime test that an unstable swipe publishes one diagnostic event with `reason=distance_too_short`.
- [x] Publish diagnostic event for recognized gestures, unstable gestures, and settings applied.
- [x] Keep terminal output unchanged for routine diagnostics.
- [x] Run `swift test --filter RuntimeSettingsTests`.

## Task 3: 扩展诊断 buffer 和摘要

**Files:**
- Create: `extensions/chrome/src/diagnostics/diagnostics.ts`
- Create: `extensions/chrome/tests/diagnostics.test.ts`
- Modify: `extensions/chrome/src/protocol/messages.ts`
- Modify: `extensions/chrome/src/background/background.ts`
- Modify: `extensions/chrome/src/background/nativePortManager.ts`
- Modify: `extensions/chrome/tests/nativePortManager.test.ts`

**Interfaces:**
- Produces: `DIAGNOSTICS_STORAGE_KEY = "gesturekitDiagnostics"`
- Produces: `appendDiagnostic(storage, event, limit = 100)`
- Produces: `summarizeDiagnostics(events)` with recent swipe success rate, main failure reason, and suggestion.

- [x] Add failing Vitest for ring buffer keeping the newest 100 entries.
- [x] Add failing Vitest for swipe summary: success `7 / 10`, main failure `distance_too_short`, suggestion `可以尝试“灵敏”`。
- [x] Implement diagnostics module and background wiring.
- [x] Run `npm test -- diagnostics`.

## Task 4: popup 诊断 UI

**Files:**
- Modify: `extensions/chrome/popup.html`
- Modify: `extensions/chrome/src/popup/popup.ts`
- Modify: `extensions/chrome/src/popup/popup.css`
- Modify: `extensions/chrome/tests/popup.test.ts`

**Interfaces:**
- Consumes: `gesturekitDiagnostics` and `summarizeDiagnostics(events)`.
- Produces: UI controls `#diagnosticsToggle`, `#diagnosticsList`, `#copyDiagnostics`, `#clearDiagnostics`。

- [x] Add failing popup test that settings controls remain and diagnostics summary renders.
- [x] Add failing popup test for expand/collapse showing recent records.
- [x] Add failing popup test for clear diagnostics writing an empty list.
- [x] Add failing popup test for copy diagnostics using `navigator.clipboard.writeText`.
- [x] Implement compact UI below existing status section.
- [x] Run `npm test -- popup diagnostics`.

## Task 5: 文档、验证和提交

**Files:**
- Modify: `README.md`
- Modify: `docs/operations/e2e-checklist.md`
- Modify: `docs/plans/gesturekit-p2-diagnostics-panel-plan.md`

- [x] Update README with diagnostic panel behavior and privacy boundary.
- [x] Update E2E checklist with copy/clear diagnostics checks.
- [x] Run `swift test`.
- [x] Run `swift build`.
- [x] Run `swift run GestureKitHost --self-test`.
- [x] Run `cd extensions/chrome && npm test`.
- [x] Run `cd extensions/chrome && npm run build`.
- [x] Run `git diff --check`.
- [x] Commit with `feat: add diagnostics panel`.
- [x] Push `plan/v1-spikes`.

## 自检

- 覆盖 P2 核心目标：诊断面板、最近记录、复制/清空、限量存储、个人灵敏度数据字段。
- 未扩大到自动应用推荐、长期历史、菜单栏 UI 或多浏览器。
- 计划保留中文优先文档，所有诊断文本面向本地自用。
