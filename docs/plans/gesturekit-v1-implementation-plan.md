# GestureKit V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and validate the predevelopment spike foundation for GestureKit V1: trackpad input, Chrome Native Messaging, and Chrome link hit testing.

**Architecture:** This plan does not deliver the full product V1. It creates the smallest testable scaffolds needed to prove the risky paths before committing to product implementation. Each spike must produce runnable evidence and update the contract or design only when observed behavior requires it.

**Tech Stack:** Swift + Swift Package Manager for native probes and native host shim; Chrome Manifest V3 + TypeScript + Vitest for extension probes; JSON Schema for shared protocol messages.

---

## Contract Baseline

Implementation must comply with:

- `docs/product/gesturekit-v1-contract.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
- `docs/plans/gesturekit-v1-predevelopment-plan.md`
- `docs/adr/0001-use-native-host-shim.md`
- `docs/adr/0002-use-extension-last-pointer-position.md`
- `docs/adr/0003-use-rules-engine-from-v1.md`

If a spike finds evidence that contradicts the contract, stop the affected task, write the evidence into `docs/research/`, and update the contract only after user approval.

## Target File Structure

Create or modify these paths during this plan:

```text
Package.swift
.gitignore
README.md

apps/macos/GestureKitApp/
  Sources/GestureKitApp/main.swift

native-host/gesturekit-host/
  Sources/GestureKitHost/main.swift
  Sources/GestureKitHost/NativeMessageCodec.swift
  Sources/GestureKitHost/LocalEventClient.swift

extensions/chrome/
  manifest.json
  package.json
  tsconfig.json
  vitest.config.ts
  scripts/build.mjs
  src/background/nativePort.ts
  src/background/actions.ts
  src/content/pointerTracker.ts
  src/content/linkResolver.ts
  src/protocol/messages.ts
  tests/linkResolver.test.ts
  tests/actions.test.ts
  tests/nativePort.test.ts

packages/protocol/
  schemas/message.schema.json
  schemas/gesture-event.schema.json
  schemas/action-result.schema.json
  fixtures/gesture-tap.json
  fixtures/action-result-success.json

spikes/trackpad-input/
  README.md
  Sources/TrackpadInputProbe/main.swift

spikes/native-messaging/
  README.md
  host-manifest/com.gesturekit.host.json

spikes/link-hit-test/
  README.md
  pages/basic-links.html
  pages/no-link.html

docs/research/
  macos-trackpad-input-options.md
  chrome-native-messaging-notes.md
  chrome-link-hit-test-notes.md
```

## Task 1: Repository Foundation

**Files:**

- Create: `.gitignore`
- Create: `README.md`
- Create: `Package.swift`
- Create directories listed in Target File Structure.
- Modify: none

- [ ] **Step 1: Create `.gitignore`**

Create `.gitignore` with:

```gitignore
.DS_Store
.build/
DerivedData/
*.xcodeproj/project.xcworkspace/xcuserdata/
*.xcworkspace/xcuserdata/
node_modules/
dist/
coverage/
.env
.env.*
!.env.example
```

- [ ] **Step 2: Create root `README.md`**

Create `README.md` with:

```markdown
# GestureKit

GestureKit is a macOS trackpad gesture extension project for Chrome-first browser workflows.

Current status: V1 predevelopment spikes.

Primary documents:

- `docs/product/gesturekit-v1-contract.md`
- `docs/architecture/gesturekit-v1-technical-design.md`
- `docs/plans/gesturekit-v1-predevelopment-plan.md`
- `docs/plans/gesturekit-v1-implementation-plan.md`
```

- [ ] **Step 3: Create initial Swift package**

Create `Package.swift` with:

```swift
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "GestureKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GestureKitHost", targets: ["GestureKitHost"]),
        .executable(name: "TrackpadInputProbe", targets: ["TrackpadInputProbe"])
    ],
    targets: [
        .executableTarget(
            name: "GestureKitHost",
            path: "native-host/gesturekit-host/Sources/GestureKitHost"
        ),
        .executableTarget(
            name: "TrackpadInputProbe",
            path: "spikes/trackpad-input/Sources/TrackpadInputProbe"
        )
    ]
)
```

- [ ] **Step 4: Create minimal Swift executables**

Create `native-host/gesturekit-host/Sources/GestureKitHost/main.swift`:

```swift
import Foundation

print("GestureKitHost spike executable")
```

Create `spikes/trackpad-input/Sources/TrackpadInputProbe/main.swift`:

```swift
import Foundation

print("TrackpadInputProbe spike executable")
```

- [ ] **Step 5: Verify Swift package builds**

Run:

```bash
swift build
```

Expected:

```text
Build complete!
```

- [ ] **Step 6: Commit repository foundation**

Run:

```bash
git add .gitignore README.md Package.swift native-host spikes
git commit -m "chore: add project foundation"
```

Expected: commit succeeds.

## Task 2: Shared Protocol Schema

**Files:**

- Create: `packages/protocol/schemas/message.schema.json`
- Create: `packages/protocol/schemas/gesture-event.schema.json`
- Create: `packages/protocol/schemas/action-result.schema.json`
- Create: `packages/protocol/fixtures/gesture-tap.json`
- Create: `packages/protocol/fixtures/action-result-success.json`
- Modify: none

- [ ] **Step 1: Create base message schema**

Create `packages/protocol/schemas/message.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://gesturekit.local/schemas/message.schema.json",
  "type": "object",
  "additionalProperties": false,
  "required": ["version", "id", "type", "timestamp", "payload", "error"],
  "properties": {
    "version": { "const": 1 },
    "id": { "type": "string", "minLength": 1 },
    "type": {
      "type": "string",
      "enum": ["hello", "gesture_event", "action_result", "error", "heartbeat"]
    },
    "timestamp": { "type": "integer", "minimum": 0 },
    "payload": { "type": "object" },
    "error": {
      "anyOf": [
        { "type": "null" },
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["code", "message"],
          "properties": {
            "code": { "type": "string", "minLength": 1 },
            "message": { "type": "string", "minLength": 1 }
          }
        }
      ]
    }
  }
}
```

- [ ] **Step 2: Create gesture event schema**

Create `packages/protocol/schemas/gesture-event.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://gesturekit.local/schemas/gesture-event.schema.json",
  "allOf": [
    { "$ref": "./message.schema.json" },
    {
      "type": "object",
      "properties": {
        "type": { "const": "gesture_event" },
        "payload": {
          "type": "object",
          "additionalProperties": false,
          "required": ["gesture", "appBundleId"],
          "properties": {
            "gesture": {
              "type": "string",
              "enum": ["three_finger_tap", "three_finger_swipe_left", "three_finger_swipe_right"]
            },
            "appBundleId": { "type": "string", "minLength": 1 },
            "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
          }
        }
      }
    }
  ]
}
```

- [ ] **Step 3: Create action result schema**

Create `packages/protocol/schemas/action-result.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://gesturekit.local/schemas/action-result.schema.json",
  "allOf": [
    { "$ref": "./message.schema.json" },
    {
      "type": "object",
      "properties": {
        "type": { "const": "action_result" },
        "payload": {
          "type": "object",
          "additionalProperties": false,
          "required": ["action", "status"],
          "properties": {
            "action": {
              "type": "string",
              "enum": ["open_link_background", "activate_left_tab", "activate_right_tab"]
            },
            "status": {
              "type": "string",
              "enum": ["success", "edge_reached", "no_target", "page_unavailable", "unsupported_url_scheme", "native_host_disconnected", "extension_unavailable", "error"]
            },
            "details": { "type": "object" }
          }
        }
      }
    }
  ]
}
```

- [ ] **Step 4: Create protocol fixtures**

Create `packages/protocol/fixtures/gesture-tap.json`:

```json
{
  "version": 1,
  "id": "fixture-gesture-tap",
  "type": "gesture_event",
  "timestamp": 1782200000000,
  "payload": {
    "gesture": "three_finger_tap",
    "appBundleId": "com.google.Chrome",
    "confidence": 0.97
  },
  "error": null
}
```

Create `packages/protocol/fixtures/action-result-success.json`:

```json
{
  "version": 1,
  "id": "fixture-action-result-success",
  "type": "action_result",
  "timestamp": 1782200000100,
  "payload": {
    "action": "open_link_background",
    "status": "success",
    "details": {
      "url": "https://example.com/"
    }
  },
  "error": null
}
```

- [ ] **Step 5: Commit protocol schema**

Run:

```bash
git add packages/protocol
git commit -m "feat: define v1 native message protocol"
```

Expected: commit succeeds.

## Task 3: Chrome Extension Link Hit-Test Spike

**Files:**

- Create: `extensions/chrome/package.json`
- Create: `extensions/chrome/tsconfig.json`
- Create: `extensions/chrome/vitest.config.ts`
- Create: `extensions/chrome/scripts/build.mjs`
- Create: `extensions/chrome/manifest.json`
- Create: `extensions/chrome/src/background/nativePort.ts`
- Create: `extensions/chrome/src/content/linkResolver.ts`
- Create: `extensions/chrome/src/content/pointerTracker.ts`
- Create: `extensions/chrome/src/protocol/messages.ts`
- Create: `extensions/chrome/tests/linkResolver.test.ts`
- Create: `spikes/link-hit-test/README.md`
- Create: `spikes/link-hit-test/pages/basic-links.html`
- Create: `spikes/link-hit-test/pages/no-link.html`

- [ ] **Step 1: Create Chrome extension package files**

Create `extensions/chrome/package.json`:

```json
{
  "name": "@gesturekit/chrome-extension",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "node scripts/build.mjs",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "devDependencies": {
    "@types/chrome": "^0.0.268",
    "@types/node": "^26.0.0",
    "esbuild": "^0.25.11",
    "jsdom": "^27.0.1",
    "typescript": "^5.5.4",
    "vitest": "^2.0.5"
  }
}
```

Create `extensions/chrome/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "types": ["chrome", "vitest/globals"],
    "noEmit": true
  },
  "include": ["src", "tests"]
}
```

Create `extensions/chrome/vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom"
  }
});
```

Create `extensions/chrome/scripts/build.mjs`:

```js
import { build } from "esbuild";

await Promise.all([
  build({
    entryPoints: ["src/background/nativePort.ts"],
    bundle: true,
    format: "esm",
    outfile: "dist/background/nativePort.js",
    sourcemap: false
  }),
  build({
    entryPoints: ["src/content/pointerTracker.ts"],
    bundle: true,
    format: "iife",
    outfile: "dist/content/pointerTracker.js",
    sourcemap: false
  })
]);
```

- [ ] **Step 2: Create extension manifest**

Create `extensions/chrome/manifest.json`:

```json
{
  "manifest_version": 3,
  "name": "GestureKit Spike",
  "version": "0.1.0",
  "permissions": ["nativeMessaging", "storage"],
  "host_permissions": ["<all_urls>"],
  "background": {
    "service_worker": "dist/background/nativePort.js",
    "type": "module"
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["dist/content/pointerTracker.js"],
      "run_at": "document_idle"
    }
  ]
}
```

- [ ] **Step 3: Write link resolver tests first**

Create `extensions/chrome/tests/linkResolver.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { resolveLinkAtPoint } from "../src/content/linkResolver";

describe("resolveLinkAtPoint", () => {
  it("returns absolute http link for anchor at point", () => {
    document.body.innerHTML = `<a id="target" href="/docs">Docs</a>`;
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    document.elementFromPoint = () => anchor;

    const result = resolveLinkAtPoint(10, 20);

    expect(result).toEqual({
      status: "success",
      url: "http://localhost:3000/docs"
    });
  });

  it("returns no_target when point is not inside a link", () => {
    document.body.innerHTML = `<button id="target">Open</button>`;
    const button = document.getElementById("target") as HTMLButtonElement;
    document.elementFromPoint = () => button;

    const result = resolveLinkAtPoint(10, 20);

    expect(result).toEqual({ status: "no_target" });
  });

  it("rejects javascript links", () => {
    document.body.innerHTML = `<a id="target" href="javascript:alert(1)">Bad</a>`;
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    document.elementFromPoint = () => anchor;

    const result = resolveLinkAtPoint(10, 20);

    expect(result).toEqual({ status: "unsupported_url_scheme" });
  });
});
```

- [ ] **Step 4: Implement link resolver**

Create `extensions/chrome/src/content/linkResolver.ts`:

```ts
export type LinkResolveResult =
  | { status: "success"; url: string }
  | { status: "no_target" }
  | { status: "unsupported_url_scheme" }
  | { status: "page_unavailable" };

export function resolveLinkAtPoint(x: number, y: number): LinkResolveResult {
  const element = document.elementFromPoint(x, y);
  if (!element) {
    return { status: "no_target" };
  }

  const anchor = element.closest("a[href]") as HTMLAnchorElement | null;
  if (!anchor) {
    return { status: "no_target" };
  }

  let url: URL;
  try {
    url = new URL(anchor.href);
  } catch {
    return { status: "unsupported_url_scheme" };
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return { status: "unsupported_url_scheme" };
  }

  return { status: "success", url: url.toString() };
}
```

- [ ] **Step 5: Implement background simulated gesture bridge**

Create `extensions/chrome/src/background/nativePort.ts`:

```ts
import type { LinkResolveResult } from "../content/linkResolver";

type ResolveLastPointerResponse =
  | LinkResolveResult
  | { status: "no_recent_pointer" };

type SimulatedGestureMessage = {
  type: "gesturekit.simulateTap";
};

async function resolveActiveTabLink(): Promise<ResolveLastPointerResponse> {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab?.id) {
    return { status: "page_unavailable" };
  }

  const response = await chrome.tabs.sendMessage(tab.id, {
    type: "gesturekit.resolveLastPointer"
  });
  return response as ResolveLastPointerResponse;
}

chrome.runtime.onMessage.addListener(
  (
    message: SimulatedGestureMessage,
    _sender,
    sendResponse: (response: ResolveLastPointerResponse) => void
  ) => {
    if (message.type !== "gesturekit.simulateTap") {
      return false;
    }

    resolveActiveTabLink()
      .then(sendResponse)
      .catch(() => sendResponse({ status: "page_unavailable" }));
    return true;
  }
);
```

- [ ] **Step 6: Implement pointer tracker**

Create `extensions/chrome/src/content/pointerTracker.ts`:

```ts
import { resolveLinkAtPoint } from "./linkResolver";

export type PointerSnapshot = {
  x: number;
  y: number;
  timestamp: number;
};

const MAX_POINTER_AGE_MS = 1500;
let lastPointer: PointerSnapshot | null = null;

window.addEventListener(
  "pointermove",
  (event) => {
    lastPointer = {
      x: event.clientX,
      y: event.clientY,
      timestamp: Date.now()
    };
  },
  { passive: true }
);

export function resolveLinkAtLastPointer(now: number = Date.now()) {
  if (!lastPointer || now - lastPointer.timestamp > MAX_POINTER_AGE_MS) {
    return { status: "no_recent_pointer" as const };
  }

  return resolveLinkAtPoint(lastPointer.x, lastPointer.y);
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type !== "gesturekit.resolveLastPointer") {
    return false;
  }

  sendResponse(resolveLinkAtLastPointer());
  return false;
});
```

- [ ] **Step 7: Create spike pages and notes**

Create `spikes/link-hit-test/pages/basic-links.html`:

```html
<!doctype html>
<html>
  <body>
    <a href="https://example.com/">Example</a>
    <a href="/relative">Relative link</a>
    <a href="javascript:alert(1)">Unsupported link</a>
  </body>
</html>
```

Create `spikes/link-hit-test/pages/no-link.html`:

```html
<!doctype html>
<html>
  <body>
    <button>Button without href</button>
    <div>Plain text</div>
  </body>
</html>
```

Create `spikes/link-hit-test/README.md`:

```markdown
# 链接命中验证 Spike

目标：验证 Chrome 扩展侧记录最近 pointer 位置的策略，确认它能识别普通网页链接。

手动验证步骤：

1. 在 Chrome 中打开 `pages/basic-links.html`。
2. 把指针移动到每个链接上。
3. 在 `extensions/chrome` 中运行 `npm run build`。
4. 从 `extensions/chrome` 加载 unpacked extension。
5. 从 background script 触发一次模拟手势事件：

   ```js
   chrome.runtime.sendMessage({ type: "gesturekit.simulateTap" }, console.log)
   ```

   这段代码从扩展 service worker console 中运行。

6. 确认 `http:` 和 `https:` 链接会被接受。
7. 确认 `javascript:` 链接会被拒绝。
8. 打开 `pages/no-link.html`，确认不会执行链接动作。
```

- [ ] **Step 8: Run Chrome extension tests**

Run:

```bash
cd extensions/chrome
npm install
npm test
npm run build
npx tsc --noEmit
```

Expected:

```text
Test Files  1 passed
Tests  3 passed
Build command exits with status 0
TypeScript no-emit check exits with status 0
```

If network access is blocked during `npm install`, request escalation and retry the same command.

- [ ] **Step 9: Commit link hit-test spike**

Run:

```bash
git add extensions/chrome spikes/link-hit-test
git commit -m "feat: add chrome link hit-test spike"
```

Expected: commit succeeds.

## Task 4: Native Messaging Host Spike

**Files:**

- Create: `native-host/gesturekit-host/Sources/GestureKitHost/NativeMessageCodec.swift`
- Modify: `native-host/gesturekit-host/Sources/GestureKitHost/main.swift`
- Create: `spikes/native-messaging/README.md`
- Create: `spikes/native-messaging/host-manifest/com.gesturekit.host.json`

- [ ] **Step 1: Implement codec**

Create `native-host/gesturekit-host/Sources/GestureKitHost/NativeMessageCodec.swift`:

```swift
import Foundation

public enum NativeMessageCodecError: Error {
    case messageTooShort
    case lengthMismatch(expected: Int, actual: Int)
}

public enum NativeMessageCodec {
    public static func encode(_ payload: Data) -> Data {
        var length = UInt32(payload.count).littleEndian
        var output = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        output.append(payload)
        return output
    }

    public static func decode(_ input: Data) throws -> Data {
        guard input.count >= 4 else {
            throw NativeMessageCodecError.messageTooShort
        }

        let expectedLength = input.prefix(4).withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self).littleEndian
        }
        let payload = input.dropFirst(4)
        guard payload.count == Int(expectedLength) else {
            throw NativeMessageCodecError.lengthMismatch(expected: Int(expectedLength), actual: payload.count)
        }
        return Data(payload)
    }
}
```

- [ ] **Step 2: Update host main for handshake and self-test spike**

Replace `native-host/gesturekit-host/Sources/GestureKitHost/main.swift` with:

```swift
import Foundation

enum GestureKitHostSelfTest {
    static func run() throws {
        let payload = Data("{\"version\":1}".utf8)
        let encoded = NativeMessageCodec.encode(payload)
        guard encoded.prefix(4) == Data([13, 0, 0, 0]) else {
            throw NSError(domain: "GestureKitHostSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid length prefix"])
        }

        let decoded = try NativeMessageCodec.decode(encoded)
        guard decoded == payload else {
            throw NSError(domain: "GestureKitHostSelfTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Decoded payload mismatch"])
        }

        print("GestureKitHost self-test passed")
    }
}

if CommandLine.arguments.contains("--self-test") {
    do {
        try GestureKitHostSelfTest.run()
        exit(0)
    } catch {
        fputs("GestureKitHost self-test failed: \(error)\n", stderr)
        exit(1)
    }
}

let response = Data("""
{"version":1,"id":"host-hello","type":"hello","timestamp":0,"payload":{"host":"GestureKitHost"},"error":null}
""".utf8)

FileHandle.standardOutput.write(NativeMessageCodec.encode(response))
```

- [ ] **Step 3: Create host manifest sample**

Create `spikes/native-messaging/host-manifest/com.gesturekit.host.json`:

```json
{
  "name": "com.gesturekit.host",
  "description": "GestureKit Native Messaging Host Spike",
  "path": "/absolute/path/to/GestureKit/.build/debug/GestureKitHost",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://REPLACE_WITH_LOCAL_EXTENSION_ID/"
  ]
}
```

Create `spikes/native-messaging/README.md`:

```markdown
# Native Messaging Spike

Goal: validate Chrome MV3 `connectNative()` with the GestureKit host shim.

Manual setup:

1. Build the host with `swift build`.
2. Replace the manifest `path` with the absolute `.build/debug/GestureKitHost` path.
3. Replace `REPLACE_WITH_LOCAL_EXTENSION_ID` with the unpacked extension ID.
4. Install the manifest into Chrome's native messaging host directory for local testing.
5. Load the Chrome extension from `extensions/chrome`.
6. Confirm the extension receives the `hello` message.

The checked-in manifest is a template. It must not contain a machine-specific path or real extension ID.
```

- [ ] **Step 4: Run host codec self-test**

Run:

```bash
swift run GestureKitHost --self-test
```

Expected:

```text
GestureKitHost self-test passed
```

- [ ] **Step 5: Commit native messaging spike**

Run:

```bash
git add native-host/gesturekit-host spikes/native-messaging
git commit -m "feat: add native messaging host spike"
```

Expected: commit succeeds.

## Task 5: Trackpad Input Spike

**Files:**

- Modify: `Package.swift`
- Modify: `spikes/trackpad-input/Sources/TrackpadInputProbe/main.swift`
- Create: `spikes/trackpad-input/README.md`
- Create: `docs/research/macos-trackpad-input-options.md`

- [ ] **Step 1: Inspect OpenMultitouchSupport package API**

Run:

```bash
git ls-remote https://github.com/Kyome22/OpenMultiTouchSupport.git HEAD
```

Expected:

```text
<commit-sha>	HEAD
```

Then inspect the package API from the current upstream source and record:

- package product name
- import module name
- event callback type
- finger data fields needed for tap and swipe
- macOS version requirement

Write the result into `docs/research/macos-trackpad-input-options.md`.

If network access is blocked, request escalation and retry the same command.

- [ ] **Step 2: Add dependency after API inspection**

Modify `Package.swift` only after Step 1 confirms the package product and module names. Add the OpenMultitouchSupport dependency using the current upstream URL:

```swift
.package(url: "https://github.com/Kyome22/OpenMultiTouchSupport.git", branch: "main")
```

Add the confirmed product to the `TrackpadInputProbe` target dependencies.

- [ ] **Step 3: Implement trackpad probe**

Replace `spikes/trackpad-input/Sources/TrackpadInputProbe/main.swift` with a probe that:

- starts the OpenMultitouchSupport listener
- prints device connection status
- prints normalized finger count
- prints candidate events for three-finger tap
- prints candidate events for three-finger left and right swipe
- exits cleanly on `SIGINT`

The probe must not record continuous raw input to disk.

- [ ] **Step 4: Create trackpad spike README**

Create `spikes/trackpad-input/README.md`:

```markdown
# Trackpad Input Spike

Goal: validate whether OpenMultitouchSupport can support GestureKit V1 gestures.

Manual checks:

1. Run `swift run TrackpadInputProbe`.
2. Perform three-finger tap 10 times.
3. Perform three-finger left swipe 10 times.
4. Perform three-finger right swipe 10 times.
5. Record recognition stability in `docs/research/macos-trackpad-input-options.md`.
6. Test with Chrome foreground and non-Chrome foreground.
7. Test once with conflicting macOS three-finger system gestures enabled if available.

Pass condition:

- Three-finger tap is distinguishable from swipe.
- Left and right swipe direction are distinguishable.
- Failure modes are documented.
```

- [ ] **Step 5: Build and run trackpad probe**

Run:

```bash
swift build
swift run TrackpadInputProbe
```

Expected:

```text
The probe starts and prints input events or a clear backend unavailable error.
```

- [ ] **Step 6: Commit trackpad input spike**

Run:

```bash
git add Package.swift spikes/trackpad-input docs/research/macos-trackpad-input-options.md
git commit -m "feat: add trackpad input spike"
```

Expected: commit succeeds.

## Task 6: Spike Evidence Review and Design Update

**Files:**

- Modify: `docs/research/chrome-native-messaging-notes.md`
- Modify: `docs/research/chrome-link-hit-test-notes.md`
- Modify: `docs/research/macos-trackpad-input-options.md`
- Modify if evidence requires: `docs/product/gesturekit-v1-contract.md`
- Modify if evidence requires: `docs/architecture/gesturekit-v1-technical-design.md`

- [ ] **Step 1: Write native messaging evidence note**

Create or update `docs/research/chrome-native-messaging-notes.md` with:

```markdown
# Chrome Native Messaging Notes

## Result

- Status: pass
- Connection model: extension calls `connectNative()`
- Host executable: `GestureKitHost`
- Message codec: 4-byte little-endian length prefix plus UTF-8 JSON payload

## Evidence

- `swift run GestureKitHost --self-test` passed.
- Manual Chrome connection result recorded during spike execution.

## V1 Impact

- Keep native host shim.
- Keep `connectNative()` as the only main channel.
```

If the spike fails, set `Status: failed` and include the exact failing command and observed output.

- [ ] **Step 2: Write link hit-test evidence note**

Create or update `docs/research/chrome-link-hit-test-notes.md` with:

```markdown
# Chrome Link Hit-Test Notes

## Result

- Status: pass
- Strategy: content script stores recent viewport pointer position
- Supported V1 target: ordinary top-level `<a href>` links

## Evidence

- `npm test` in `extensions/chrome` passed.
- Manual checks against `spikes/link-hit-test/pages/basic-links.html` and `spikes/link-hit-test/pages/no-link.html` completed.

## V1 Impact

- Keep last-pointer strategy.
- Keep iframe and closed shadow DOM as non-goals for V1.
```

If the spike fails, set `Status: failed` and include the exact failing command and observed output.

- [ ] **Step 3: Review trackpad evidence note**

Ensure `docs/research/macos-trackpad-input-options.md` contains:

```markdown
# macOS Trackpad Input Options

## Result

- Status: pass
- Backend: OpenMultitouchSupport / MultitouchSupport.framework

## Evidence

- Three-finger tap recognition:
- Three-finger left swipe recognition:
- Three-finger right swipe recognition:
- System gesture conflicts:
- Device observations:

## V1 Impact

- Keep `TouchBackend` abstraction.
- Keep MultitouchSupport as V1 backend only if recognition is stable enough for personal use.
```

If the spike fails, set `Status: failed` and document the fallback design recommendation.

- [ ] **Step 4: Update design documents only if evidence requires it**

If all spikes pass, do not expand V1 scope. Add a short "Spike Evidence" section to `docs/architecture/gesturekit-v1-technical-design.md` linking the three research notes.

If a spike fails, update the contract and technical design to reflect the revised architecture before any product implementation begins.

- [ ] **Step 5: Commit evidence review**

Run:

```bash
git add docs
git commit -m "docs: record v1 spike evidence"
```

Expected: commit succeeds.

## Execution Notes for Main Agent

- Task 1 and Task 2 are sequential foundations.
- Task 3 and Task 4 can be assigned to separate subagents after Task 2.
- Task 5 can run in parallel with Task 3 and Task 4 after Task 1, but it may require network access to inspect the dependency.
- Task 6 must run after all three spikes complete.
- Do not start product V1 implementation until Task 6 completes and the user confirms the revised design.

## Self-Review

Spec coverage:

- Contract scope is covered by Task 6 and the spike pass/fail gates.
- Native host shim is covered by Task 4.
- Extension last pointer strategy is covered by Task 3.
- Trackpad backend risk is covered by Task 5.
- Message schema is covered by Task 2.

Unfinished-entry scan:

- This plan contains no unfinished entries or unspecified implementation slots.
- The native host manifest uses `REPLACE_WITH_LOCAL_EXTENSION_ID` as an intentional local installation token and is documented as a template, not an unfinished plan item.

Type consistency:

- Protocol message fields match `docs/product/gesturekit-v1-contract.md`.
- Action and status names match the V1 contract and technical design.
