# GestureKit P1.5 Swipe Sensitivity Sync Plan

**Goal:** Let Chrome extension settings control Swift-side swipe recognition sensitivity and report whether the Swift app applied the setting.

**Scope:**

- Add `GestureRecognitionSettings` presets in Swift: `robust`, `standard`, `sensitive`.
- Add protocol messages: `settings_update` and `settings_ack`.
- Make `GestureRecognizer` read configurable swipe thresholds.
- Forward extension-to-app messages through the native host and local IPC.
- Add popup control for swipe sensitivity and show the last sync status.
- Update Chinese-first docs.

**Out of scope:**

- Full macOS settings UI.
- Arbitrary gesture-action binding.
- Long diagnostic history; this remains a follow-up.

**Verification:**

- [x] `swift test`
- [x] `swift run GestureKitHost --self-test`
- [x] `npm test`
- [x] `npm run build`
- [x] `git diff --check`
