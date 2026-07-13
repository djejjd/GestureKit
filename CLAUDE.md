# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build, Test, and Run

```bash
# Swift (macOS 15, Swift 6.2)
swift build
swift test
swift test --filter TestSuiteName    # single test suite
swift test --filter testMethodName   # single test
swift run GestureKitApp              # launch the menu bar app
swift run GestureKitHost --self-test # native host self-check

# Chrome extension
cd extensions/chrome
npm install
npm test                  # vitest run (jsdom)
npm test -- --run tests/file.test.ts  # single test file
npm run build             # esbuild bundle
```

Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before Swift commands if Xcode command-line tools aren't the default. Debug gesture recognition with `GESTUREKIT_DEBUG=1 swift run GestureKitApp`.

Logs: `~/Library/Logs/GestureKit/GestureKitApp.log` (1 MB rotation, 3 files).

## Architecture: Three-Tier Gesture → Browser Pipeline

GestureKit is a macOS trackpad gesture tool for Chrome, split across three processes connected by a defined protocol chain:

```
Trackpad Hardware
  → MultitouchSupportBackend (private framework, via OpenMultitouchSupport)
  → GestureRecognizer (primitive: tap/swipe, 3-finger, region, duration)
  → RuleEngine / BindingResolver (gesture + context → ActionDescriptor)
  → ProviderRouter → authenticated IPC → Native Host Shim → Chrome Native Messaging
  → Chrome Extension (ActionProvider: executes browser.tabs / browser.link actions)
```

**The critical design rule**: Core (`GestureKitCore`) must never reference `chrome.tabs`, Chrome action enums, or `connectNative()`. Gesture recognition is decoupled from gesture meaning — "three-finger swipe left" is a primitive; mapping it to "activate next tab" happens in `BindingResolver` via standard `ActionDescriptor` (e.g., `browser.tab.activate_next`).

## Package / Target Map

| Target | Path | Role |
|---|---|---|
| `GestureKitCore` (library) | `Sources/GestureKitCore/` | Shared: gestures, rules, IPC protocol, settings, protocol v2 models |
| `GestureKitApp` (executable) | `apps/macos/GestureKitApp/Sources/GestureKitApp/` | macOS menu bar app, control center UI, runtime loop, operation journal, provider sessions |
| `GestureKitHost` (executable) | `native-host/gesturekit-host/Sources/GestureKitHost/` | Chrome Native Messaging stdio ↔ App IPC transparent bridge |
| `GestureKitCoreTests` | `Tests/GestureKitCoreTests/` | Unit tests for shared core |
| `GestureKitAppTests` | `Tests/GestureKitAppTests/` | Unit tests for app layer |
| Chrome extension | `extensions/chrome/` | MV3 extension: background SW, content scripts, popup |
| Probes (4) | `spikes/` | Standalone research executables for trackpad input, IPC, TCC, interaction shield |

## Provider Protocol v2 (the key abstraction)

Defined in `Sources/GestureKitCore/Provider/ProviderProtocolV2.swift`. A bidirectional, typed protocol between App and any ActionProvider:

- **17 message types** with strict type↔payload mapping (fail-closed decoding — unknown combinations rejected)
- **7 standard action IDs**: `browser.link.open_adjacent`, `browser.tab.activate_previous/next`, `browser.tab.close_current`, `browser.history.back/forward`, `browser.page.reload`
- **3 terminal outcomes**: `succeeded`, `failed`, `result_unknown`
- JSON schemas in `packages/protocol/schemas/`, TypeScript types in `extensions/chrome/src/provider/protocol.ts`

Chrome adapter maps legacy `GestureKitMessage` (version:1) to v2 internally; v2 is the forward path.

## Operation Journal & Evidence Chain

Every 3-finger candidate produces a `gestureSessionId` and a full evidence chain persisted in SQLite WAL (`apps/.../OperationJournal.swift`):
- Append-only stage events with unique `eventId`, monotonic `producerSequence`
- 50 MB managed storage budget (App 45 MB, Chrome Provider 5 MB), 7-day retention
- Evidence bundle export with manifest, redacted page fingerprints, phase timeline
- Double redaction: Provider source → App入库, both must strip query/hash, cookies, DOM text

Chrome extension mirrors with IndexedDB operation ledger + telemetry outbox for offline resilience.

## V1 → V2 Migration (current state)

The project is mid-refactoring from v1 to v2. Key shifts in authority:
- **Config sovereignty**: App `SettingsStore` is sole writer; extension popup is read-only context display
- **Diagnostics**: moved from extension ring buffer to App `OperationJournal`
- **IPC**: from broadcast to authenticated provider sessions with per-provider credentials
- **UI**: App now has 6-page control center window; menu bar shows only lifecycle + persistent faults; popup shows only page context + connection status

Implementation order: `Task 1/2/2A (spikes) → Task 3 (protocol) → Task 4 (journal) → Task 5 (auth IPC) → Task 10A (UI scaffold) → Task 6/7 (ledger/sessions) → Task 8 (Chrome guard/action) → Task 9 (config migration) → Task 10B (UI data wiring) → Task 11 (E2E/cleanup)`.

Full plan: `docs/plans/gesturekit-reliability-platform-implementation-plan.md`
UI contract: `docs/architecture/gesturekit-v2-ui-information-architecture.md`
Architecture decisions: `docs/adr/0001-use-native-host-shim.md` through `0003`

## Key Conventions

- User-facing text and code comments in Chinese; protocol fields, paths, API names in English
- Every task follows TDD: write failing test → confirm failure → minimal implementation → full suite pass → commit
- `RuleEngine` is the single action decision gate; `BindingResolver` is internal — providers must not modify `actionId`
- `operationId` side effects execute at most once; uncertain results trigger reconciliation, never auto-replay
- `guard_armed` is a hard prerequisite for `browser.link.open_adjacent` — link tap actions must not proceed without it

## Workflow Rules

**Step 1: Problem Analysis.** When asked about a bug, feature, or architectural question — always first trace the relevant code paths and present the root cause. No implementation, no fix proposals, no code changes at this stage.

**Step 2: Solution Plan.** After confirming the root cause with the user, propose a concrete plan: which files to change, what to change in each, and why. For complex changes (spanning 3+ files, or touching a protocol boundary), spawn an agent to review the plan's feasibility and edge cases before presenting it.

**Step 3: User Confirmation.** Wait for explicit approval before writing any code. "看起来合理" or "可以" or "做吧" or any affirmative is sufficient — but never assume.

**Step 4: Implement.** Only after confirmation, proceed with TDD: write failing test → confirm failure → implement → full suite pass.

## Behavioral Log

| Date | Pattern | Fix |
|---|---|---|
| 2026-07-14 | Skipped root-cause presentation and plan confirmation, jumped directly into editing code. | Added Workflow Rules section above (Step 1-4). Code reverted. |

## Logging Conventions

Logger (`GestureKitLogger`) has 4 levels: `debug`, `info`, `warn`, `error`.

- **debug** — Only emits when diagnostic logging is enabled (settings toggle or `GESTUREKIT_DEBUG=1`). Use for: per-frame touch data, timing breakdowns, internal state transitions, protocol message verbatim, context request/response fields. Anything that would be noise during normal operation.
- **info** — Written to log file only (not terminal). Use for: gesture recognition outcomes (classified AND rejected), action dispatch/result, provider connection state changes, settings applied.
- **warn** — Written to file + terminal. Use for: transient failures (provider unavailable, context send failed, timeout), unexpected protocol messages, degraded operation that self-recovers.
- **error** — Written to file + terminal. Use for: startup failure, backend crash, journal write failure, permanent capability loss.

Choice heuristic: If you need this log to answer "what happened just now" without debug mode — use `info`/`warn`/`error`. If it's only useful when actively debugging a specific issue — use `debug`. Use `rateLimitKey` for any log that could fire more than once per second in normal operation to prevent log spam.
