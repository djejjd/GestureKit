# GestureKit P1 Extension Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for behavior changes. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Chrome-extension-side gesture presets, toggles, and a lightweight popup so gesture feel can be adjusted without editing code.

**Architecture:** Gesture execution remains in the Chrome extension. A focused settings module owns defaults, preset application, validation, and `chrome.storage.local` persistence. `nativePortManager` consumes a loaded settings object for thresholds and feature switches, while the popup edits the same storage values.

**Tech Stack:** Chrome MV3, TypeScript, Vitest, existing build script.

## Global Constraints

- Documentation is Chinese-first.
- Do not move the source of truth for this P1 into the Swift app yet.
- Keep P1 small: no arbitrary gesture-action binding, no multi-browser config, no cloud sync.
- Existing Swift protocol and extension behavior from the current working tree must keep passing.

---

### Task 1: Settings Model And Storage

**Files:**
- Create: `extensions/chrome/src/settings/gestureSettings.ts`
- Test: `extensions/chrome/tests/gestureSettings.test.ts`

**Steps:**
- [ ] Write failing tests for safe defaults, efficient preset, custom validation, and storage fallback.
- [ ] Implement `GestureSettings`, `GESTURE_SETTINGS_PRESETS`, `normalizeGestureSettings`, `loadGestureSettings`, and `saveGestureSettings`.
- [ ] Run `npm test -- gestureSettings.test.ts`.

### Task 2: Runtime Settings In Gesture Manager

**Files:**
- Modify: `extensions/chrome/src/background/nativePortManager.ts`
- Test: `extensions/chrome/tests/nativePortManager.test.ts`

**Steps:**
- [ ] Add failing tests for disabled edge tap, disabled double tap, disabled flick, and custom edge width.
- [ ] Inject `getSettings()` into `createNativePortManager` with safe defaults.
- [ ] Replace hard-coded thresholds with settings values.
- [ ] Run `npm test -- nativePortManager.test.ts`.

### Task 3: Popup UI

**Files:**
- Create: `extensions/chrome/popup.html`
- Create: `extensions/chrome/src/popup/popup.ts`
- Create: `extensions/chrome/src/popup/popup.css`
- Modify: `extensions/chrome/manifest.json`
- Modify: `extensions/chrome/scripts/build.mjs`

**Steps:**
- [ ] Add unit tests for popup state rendering and save behavior where practical.
- [ ] Add a compact popup with mode switch, three toggles, three range controls, status summary, and reset button.
- [ ] Extend the build script to bundle popup JS/CSS and copy `popup.html`.
- [ ] Run `npm run build`.

### Task 4: Documentation And Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/operations/gesturekit-v1-e2e-checklist.md`
- Modify: `docs/product/gesturekit-v1-requirements.md`

**Steps:**
- [ ] Document safe/efficient presets and popup usage in Chinese first.
- [ ] Update manual verification checklist for settings changes.
- [ ] Run `npm test`, `npm run build`, `swift test`, `git diff --check`.
