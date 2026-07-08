# GestureKit P3 Installation And Connectivity Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 GestureKit 的 native host 安装、Chrome 扩展连通性验证和排障入口收敛成可重复的开发闭环。

**Architecture:** P3 保持既有 `Chrome extension -> connectNative() -> GestureKitHost -> App IPC` 边界，不新增手势能力。安装链路通过 shell 脚本渲染并落地 native host manifest；连通性链路通过 extension 内的 dev smoke page 触发 `probe_request` / `probe_response` 来验证 Chrome、host 和 App IPC 全链路。

**Tech Stack:** zsh shell scripts、Swift 6.2、Swift Package Manager、Chrome MV3、TypeScript、Vitest、esbuild、Chrome Native Messaging、loopback TCP IPC。

## Global Constraints

- 项目文档叙述默认使用中文。
- 最低系统版本保持 `macOS 15`。
- 构建工具链保持 `Swift 6.2` 和现有 `OpenMultitouchSupport` 约束。
- `App Sandbox` 继续保持关闭。
- 不新增用户可见手势能力，不扩展多浏览器支持。
- 不改变 `connectNative()` + native host shim + App IPC 的既定边界。
- 不把个人扩展 ID、本机绝对路径或安装到 `~/Library/...` 后的 manifest 提交到仓库。

---

## Target File Structure

```text
scripts/dev/
  render-native-host-manifest.sh      # 渲染标准 host manifest 到 stdout
  test-render-native-host-manifest.sh # 渲染脚本的无副作用验证
  install-native-host.sh              # 写入 Chrome Native MessagingHosts 目录
  test-install-native-host.sh         # 安装脚本的临时目录验证
  smoke-check.sh                      # 构建 + 本地自检 + 打开 extension smoke page
  test-smoke-check.sh                 # dry-run 验证 smoke-check 输出

extensions/chrome/
  smoke.html                          # dev-only smoke page
  src/smoke/smoke.ts                  # 自动运行 connectNative 全链路探针
  src/background/connectionProbe.ts   # 运行 probe_request / probe_response
  tests/connectionProbe.test.ts       # 探针状态映射测试

Sources/GestureKitCore/Protocol/GestureKitMessage.swift
Tests/GestureKitCoreTests/GestureKitMessageTests.swift
apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift
Tests/GestureKitAppTests/RuntimeProbeTests.swift
extensions/chrome/src/protocol/messages.ts
extensions/chrome/src/background/background.ts
extensions/chrome/manifest.json
extensions/chrome/scripts/build.mjs

docs/operations/
  gesturekit-v1-local-install.md
  gesturekit-v1-e2e-checklist.md
  gesturekit-v1-troubleshooting.md
```

### Task 1: Native Host Manifest Renderer

**Files:**
- Create: `scripts/dev/render-native-host-manifest.sh`
- Create: `scripts/dev/test-render-native-host-manifest.sh`

**Interfaces:**
- Produces: `scripts/dev/render-native-host-manifest.sh --extension-id <32-char-id> --host-path <absolute-path>`
- Produces: stdout JSON with `"name": "com.gesturekit.host"` and a single `allowed_origins` entry

- [ ] **Step 1: Write the failing shell test**

```bash
#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/render-native-host-manifest.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

if "$script" --extension-id abcdefghijklmnopqrstuvwxyzzzzzzz --host-path /tmp/GestureKitHost >"$tmpdir/out.json"; then
  echo "expected render-native-host-manifest.sh to be missing"
  exit 1
fi

echo "render-native-host-manifest missing as expected"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zsh scripts/dev/test-render-native-host-manifest.sh`  
Expected: FAIL with `no such file or directory` for `render-native-host-manifest.sh`

- [ ] **Step 3: Write minimal renderer implementation**

```bash
#!/bin/zsh
set -euo pipefail

extension_id=""
host_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extension-id)
      extension_id="${2:-}"
      shift 2
      ;;
    --host-path)
      host_path="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$extension_id" =~ ^[a-z]{32}$ ]]; then
  echo "extension id must be 32 lowercase letters" >&2
  exit 1
fi

if [[ "$host_path" != /* ]]; then
  echo "host path must be absolute" >&2
  exit 1
fi

cat <<EOF
{
  "name": "com.gesturekit.host",
  "description": "GestureKit Native Messaging Host",
  "path": "$host_path",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$extension_id/"
  ]
}
EOF
```

- [ ] **Step 4: Expand the shell test to assert real output**

```bash
#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/render-native-host-manifest.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

extension_id=abcdefghijklmnopqrstuvwxzyabcdef
host_path=/tmp/GestureKitHost

"$script" --extension-id "$extension_id" --host-path "$host_path" >"$tmpdir/out.json"

rg -q '"name": "com.gesturekit.host"' "$tmpdir/out.json"
rg -q "\"path\": \"$host_path\"" "$tmpdir/out.json"
rg -q "\"chrome-extension://$extension_id/\"" "$tmpdir/out.json"

if "$script" --extension-id not-valid --host-path "$host_path" >/dev/null 2>&1; then
  echo "expected invalid extension id to fail"
  exit 1
fi

if "$script" --extension-id "$extension_id" --host-path relative/path >/dev/null 2>&1; then
  echo "expected relative host path to fail"
  exit 1
fi

echo "render-native-host-manifest ok"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `zsh scripts/dev/test-render-native-host-manifest.sh`  
Expected: PASS with `render-native-host-manifest ok`

- [ ] **Step 6: Commit**

```bash
git add scripts/dev/render-native-host-manifest.sh scripts/dev/test-render-native-host-manifest.sh
git commit -m "feat: add native host manifest renderer"
```

### Task 2: Native Host Installer Command

**Files:**
- Create: `scripts/dev/install-native-host.sh`
- Create: `scripts/dev/test-install-native-host.sh`
- Modify: `scripts/dev/render-native-host-manifest.sh`

**Interfaces:**
- Consumes: `scripts/dev/render-native-host-manifest.sh --extension-id <id> --host-path <path>`
- Produces: `scripts/dev/install-native-host.sh --extension-id <id> --host-path <path> [--manifest-dir <dir>]`
- Produces: `com.gesturekit.host.json` in `${CHROME_NATIVE_HOSTS_DIR:-$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts}`

- [ ] **Step 1: Write the failing installer test**

```bash
#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/install-native-host.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

if "$script" \
  --extension-id abcdefghijklmnopqrstuvwxzyabcdef \
  --host-path /tmp/GestureKitHost \
  --manifest-dir "$tmpdir" >/dev/null 2>&1; then
  echo "expected install-native-host.sh to be missing"
  exit 1
fi

echo "install-native-host missing as expected"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zsh scripts/dev/test-install-native-host.sh`  
Expected: FAIL with `no such file or directory` for `install-native-host.sh`

- [ ] **Step 3: Implement installer with temp-dir support**

```bash
#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
renderer="$repo_root/scripts/dev/render-native-host-manifest.sh"

extension_id=""
host_path=""
manifest_dir="${CHROME_NATIVE_HOSTS_DIR:-$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extension-id)
      extension_id="${2:-}"
      shift 2
      ;;
    --host-path)
      host_path="${2:-}"
      shift 2
      ;;
    --manifest-dir)
      manifest_dir="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$manifest_dir"
target="$manifest_dir/com.gesturekit.host.json"
"$renderer" --extension-id "$extension_id" --host-path "$host_path" >"$target"

echo "installed_manifest=$target"
```

- [ ] **Step 4: Replace the test with real assertions**

```bash
#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/install-native-host.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

extension_id=abcdefghijklmnopqrstuvwxzyabcdef
host_path=/tmp/GestureKitHost

output=$("$script" \
  --extension-id "$extension_id" \
  --host-path "$host_path" \
  --manifest-dir "$tmpdir")

target="$tmpdir/com.gesturekit.host.json"
[[ -f "$target" ]]
rg -q "installed_manifest=$target" <(print -r -- "$output")
rg -q "\"path\": \"$host_path\"" "$target"
rg -q "\"chrome-extension://$extension_id/\"" "$target"

echo "install-native-host ok"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `zsh scripts/dev/test-install-native-host.sh`  
Expected: PASS with `install-native-host ok`

- [ ] **Step 6: Commit**

```bash
git add scripts/dev/install-native-host.sh scripts/dev/test-install-native-host.sh scripts/dev/render-native-host-manifest.sh
git commit -m "feat: add native host installer command"
```

### Task 3: Extension-To-App Connectivity Probe

**Files:**
- Modify: `Sources/GestureKitCore/Protocol/GestureKitMessage.swift`
- Modify: `Tests/GestureKitCoreTests/GestureKitMessageTests.swift`
- Modify: `apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift`
- Create: `Tests/GestureKitAppTests/RuntimeProbeTests.swift`
- Modify: `extensions/chrome/src/protocol/messages.ts`
- Create: `extensions/chrome/src/background/connectionProbe.ts`
- Modify: `extensions/chrome/src/background/background.ts`
- Create: `extensions/chrome/tests/connectionProbe.test.ts`
- Create: `extensions/chrome/smoke.html`
- Create: `extensions/chrome/src/smoke/smoke.ts`
- Modify: `extensions/chrome/manifest.json`
- Modify: `extensions/chrome/scripts/build.mjs`

**Interfaces:**
- Produces: `MessageType.probeRequest = "probe_request"` and `MessageType.probeResponse = "probe_response"`
- Produces: `GestureKitMessage.probeResponse(id:timestamp:payload:)`
- Produces: `runConnectionProbe(port: chrome.runtime.Port): Promise<{ hostConnected: boolean; appConnected: boolean; status: string; message: string }>`
- Produces: extension runtime message `{ type: "gesturekit.runConnectionProbe" }`
- Produces: `smoke.html` auto-run page rendering `hostConnected`, `appConnected`, `status`, `message`

- [ ] **Step 1: Add failing Swift protocol and runtime tests**

```swift
func testProbeResponseDecodesContractShape() throws {
    let data = Data("""
    {"version":1,"id":"probe-1","type":"probe_response","timestamp":10,"payload":{"hostConnected":true,"appConnected":true,"message":"app_ready"},"error":null}
    """.utf8)

    let message = try JSONDecoder.gestureKit.decode(GestureKitMessage.self, from: data)

    XCTAssertEqual(message.type, .probeResponse)
    XCTAssertEqual(message.probeResponsePayload?.appConnected, true)
    XCTAssertEqual(message.probeResponsePayload?.message, "app_ready")
}
```

```swift
@MainActor
func testRuntimeRepliesToProbeRequest() throws {
    let runtime = GestureKitRuntime(
        statusHandler: { _ in },
        touchBackend: StubTouchBackend(),
        settingsStore: StubSettingsStore(),
        logger: GestureKitLogger(terminalWriter: { _ in }),
        diagnosticSink: { _ in }
    )

    let response = runtime.handleProbeRequestForTesting(id: "probe-1")

    XCTAssertEqual(response.type, .probeResponse)
    XCTAssertEqual(response.probeResponsePayload?.hostConnected, true)
    XCTAssertEqual(response.probeResponsePayload?.appConnected, true)
}
```

- [ ] **Step 2: Add failing Vitest for background probe mapping**

```ts
it("maps probe_response to connected status", async () => {
  const postMessage = vi.fn();
  const addListener = vi.fn();
  const port = {
    postMessage,
    onMessage: { addListener },
    onDisconnect: { addListener: vi.fn() }
  };

  const promise = runConnectionProbe(port as never);
  const listener = addListener.mock.calls[0][0];
  listener({
    version: 1,
    id: "probe-1",
    type: "probe_response",
    timestamp: 10,
    payload: { hostConnected: true, appConnected: true, message: "app_ready" },
    error: null
  });

  await expect(promise).resolves.toEqual({
    hostConnected: true,
    appConnected: true,
    status: "connected",
    message: "app_ready"
  });
});
```

- [ ] **Step 3: Implement probe types in Swift and TS**

```swift
public enum MessageType: String, Codable, Equatable, Sendable {
    case hello
    case probeRequest = "probe_request"
    case probeResponse = "probe_response"
    case gestureEvent = "gesture_event"
    case actionResult = "action_result"
    case settingsUpdate = "settings_update"
    case settingsAck = "settings_ack"
    case diagnosticEvent = "diagnostic_event"
    case error
    case heartbeat
}

public struct ProbeResponsePayload: Codable, Equatable, Sendable {
    public let hostConnected: Bool
    public let appConnected: Bool
    public let message: String?
}
```

```ts
export type ProbeRequestMessage = GestureKitMessage<"probe_request", {
  source: "extension_smoke_page";
}>;

export type ProbeResponseMessage = GestureKitMessage<"probe_response", {
  hostConnected: boolean;
  appConnected: boolean;
  message?: string;
}>;
```

- [ ] **Step 4: Implement runtime reply path and background probe helper**

```swift
func handleProbeRequest(_ id: String) -> LocalIPCEnvelope {
    LocalIPCEnvelope(message: .probeResponse(
        id: id,
        timestamp: Int64(Date().timeIntervalSince1970 * 1000),
        payload: ProbeResponsePayload(
            hostConnected: true,
            appConnected: true,
            message: "app_ready"
        )
    ))
}

private func handleIPCEnvelope(_ envelope: LocalIPCEnvelope) {
    if envelope.message.type == .probeRequest {
        _ = eventServer?.publish(handleProbeRequest(envelope.id))
        return
    }
    guard let payload = envelope.message.settingsUpdatePayload else {
        return
    }
    let ackEnvelope = LocalIPCEnvelope(message: .settingsAck(
        id: envelope.id,
        timestamp: Int64(Date().timeIntervalSince1970 * 1000),
        payload: applySettingsUpdate(payload)
    ))
    _ = eventServer?.publish(ackEnvelope)
}
```

```ts
export async function runConnectionProbe(port: chrome.runtime.Port): Promise<{
  hostConnected: boolean;
  appConnected: boolean;
  status: string;
  message: string;
}> {
  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      resolve({
        hostConnected: false,
        appConnected: false,
        status: "timeout",
        message: "probe_timeout"
      });
    }, 1500);

    const onMessage = (message: ProbeResponseMessage | ActionResultMessage) => {
      if (message.type === "probe_response") {
        clearTimeout(timeout);
        resolve({
          hostConnected: true,
          appConnected: message.payload.appConnected,
          status: message.payload.appConnected ? "connected" : "app_unavailable",
          message: message.payload.message ?? "probe_response"
        });
      }
      if (message.type === "action_result" && message.payload.status === "app_unavailable") {
        clearTimeout(timeout);
        resolve({
          hostConnected: true,
          appConnected: false,
          status: "app_unavailable",
          message: "app_unavailable"
        });
      }
    };

    port.onMessage.addListener(onMessage);
    port.postMessage({
      version: 1,
      id: crypto.randomUUID(),
      type: "probe_request",
      timestamp: Date.now(),
      payload: { source: "extension_smoke_page" },
      error: null
    });
  });
}
```

```ts
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "gesturekit.runConnectionProbe") {
    return false;
  }

  runConnectionProbe(port)
    .then(sendResponse)
    .catch((error: Error) => sendResponse({
      hostConnected: false,
      appConnected: false,
      status: "error",
      message: error.message
    }));

  return true;
});
```

- [ ] **Step 5: Implement the smoke page and bundle it**

```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <title>GestureKit Smoke Check</title>
  </head>
  <body>
    <main>
      <h1>GestureKit Smoke Check</h1>
      <p id="status">探针启动中…</p>
      <pre id="details"></pre>
    </main>
    <script type="module" src="dist/smoke/smoke.js"></script>
  </body>
</html>
```

```ts
const status = document.querySelector("#status") as HTMLParagraphElement;
const details = document.querySelector("#details") as HTMLPreElement;

chrome.runtime.sendMessage({ type: "gesturekit.runConnectionProbe" }, (result) => {
  status.textContent = result.status === "connected" ? "通过" : "失败";
  details.textContent = JSON.stringify(result, null, 2);
});
```

```json
{
  "manifest_version": 3,
  "name": "GestureKit",
  "version": "0.1.0",
  "permissions": ["nativeMessaging", "storage", "tabs"],
  "host_permissions": ["<all_urls>"],
  "background": {
    "service_worker": "dist/background/background.js",
    "type": "module"
  },
  "action": {
    "default_popup": "popup.html"
  }
}
```

```js
await Promise.all([
  build({
    entryPoints: ["src/background/background.ts"],
    bundle: true,
    format: "esm",
    outfile: "dist/background/background.js",
    sourcemap: false
  }),
  build({
    entryPoints: ["src/content/pointerTracker.ts"],
    bundle: true,
    format: "iife",
    outfile: "dist/content/pointerTracker.js",
    sourcemap: false
  }),
  build({
    entryPoints: ["src/popup/popup.ts"],
    bundle: true,
    format: "esm",
    outfile: "dist/popup/popup.js",
    sourcemap: false
  }),
  build({
    entryPoints: ["src/smoke/smoke.ts"],
    bundle: true,
    format: "esm",
    outfile: "dist/smoke/smoke.js",
    sourcemap: false
  })
]);
```

- [ ] **Step 6: Run targeted tests**

Run:

```bash
swift test --filter GestureKitMessageTests
swift test --filter RuntimeProbeTests
cd extensions/chrome
npm test -- connectionProbe
npm run build
```

Expected: PASS for both Swift targets, `connectionProbe.test.ts`, and extension build

- [ ] **Step 7: Commit**

```bash
git add \
  Sources/GestureKitCore/Protocol/GestureKitMessage.swift \
  Tests/GestureKitCoreTests/GestureKitMessageTests.swift \
  apps/macos/GestureKitApp/Sources/GestureKitApp/Runtime.swift \
  Tests/GestureKitAppTests/RuntimeProbeTests.swift \
  extensions/chrome/src/protocol/messages.ts \
  extensions/chrome/src/background/connectionProbe.ts \
  extensions/chrome/src/background/background.ts \
  extensions/chrome/tests/connectionProbe.test.ts \
  extensions/chrome/smoke.html \
  extensions/chrome/src/smoke/smoke.ts \
  extensions/chrome/manifest.json \
  extensions/chrome/scripts/build.mjs
git commit -m "feat: add connectivity probe"
```

### Task 4: Smoke Command And Operations Docs

**Files:**
- Create: `scripts/dev/smoke-check.sh`
- Create: `scripts/dev/test-smoke-check.sh`
- Modify: `docs/operations/gesturekit-v1-local-install.md`
- Modify: `docs/operations/gesturekit-v1-e2e-checklist.md`
- Create: `docs/operations/gesturekit-v1-troubleshooting.md`

**Interfaces:**
- Consumes: `scripts/dev/install-native-host.sh`, `swift build`, `swift run GestureKitHost --self-test`, `npm run build`
- Produces: `scripts/dev/smoke-check.sh --extension-id <id> [--host-path <path>] [--dry-run]`
- Produces: `open "chrome-extension://<id>/smoke.html"` as the final extension-side probe step

- [ ] **Step 1: Write the failing dry-run test**

```bash
#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/smoke-check.sh"

if "$script" --extension-id abcdefghijklmnopqrstuvwxzyabcdef --dry-run >/dev/null 2>&1; then
  echo "expected smoke-check.sh to be missing"
  exit 1
fi

echo "smoke-check missing as expected"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zsh scripts/dev/test-smoke-check.sh`  
Expected: FAIL with `no such file or directory` for `smoke-check.sh`

- [ ] **Step 3: Implement smoke-check wrapper**

```bash
#!/bin/zsh
set -euo pipefail

extension_id=""
host_path="$(pwd)/.build/debug/GestureKitHost"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extension-id)
      extension_id="${2:-}"
      shift 2
      ;;
    --host-path)
      host_path="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift 1
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

commands=(
  "swift build"
  "swift run GestureKitHost --self-test"
  "cd extensions/chrome && npm run build"
  "./scripts/dev/install-native-host.sh --extension-id $extension_id --host-path $host_path"
  "open chrome-extension://$extension_id/smoke.html"
)

for command in "${commands[@]}"; do
  if $dry_run; then
    echo "$command"
  else
    eval "$command"
  fi
done
```

- [ ] **Step 4: Replace the test with real dry-run assertions**

```bash
#!/bin/zsh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/scripts/dev/smoke-check.sh"
extension_id=abcdefghijklmnopqrstuvwxzyabcdef

output=$("$script" --extension-id "$extension_id" --dry-run)

rg -q '^swift build$' <(print -r -- "$output")
rg -q '^swift run GestureKitHost --self-test$' <(print -r -- "$output")
rg -q '^cd extensions/chrome && npm run build$' <(print -r -- "$output")
rg -q "^\\./scripts/dev/install-native-host.sh --extension-id $extension_id --host-path " <(print -r -- "$output")
rg -q "^open chrome-extension://$extension_id/smoke.html$" <(print -r -- "$output")

echo "smoke-check dry-run ok"
```

- [ ] **Step 5: Update operations docs**

```md
## 快速安装

1. 先构建：

   ```bash
   swift build
   cd extensions/chrome
   npm install
   npm run build
   ```

2. 加载 unpacked extension，记录扩展 ID。

3. 安装 native host：

   ```bash
   ./scripts/dev/install-native-host.sh \
     --extension-id <extension-id> \
     --host-path "$(pwd)/.build/debug/GestureKitHost"
   ```

4. 启动 App：

   ```bash
   swift run GestureKitApp
   ```

5. 运行 smoke check：

   ```bash
   ./scripts/dev/smoke-check.sh --extension-id <extension-id>
   ```
```

```md
# GestureKit V1 排障说明

## 1. 扩展显示未连接

- 先运行 `swift run GestureKitHost --self-test`
- 再确认 `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.gesturekit.host.json` 中的 `path` 和扩展 ID
- 最后打开 `chrome-extension://<extension-id>/smoke.html`

## 2. smoke page 显示 `app_unavailable`

- 确认 `swift run GestureKitApp` 已启动
- 检查 `~/Library/Logs/GestureKit/GestureKitApp.log`
- 运行 `tail -n 200 ~/Library/Logs/GestureKit/GestureKitApp.log`
```

- [ ] **Step 6: Run validation**

Run:

```bash
zsh scripts/dev/test-render-native-host-manifest.sh
zsh scripts/dev/test-install-native-host.sh
zsh scripts/dev/test-smoke-check.sh
swift test
swift build
swift run GestureKitHost --self-test
cd extensions/chrome
npm test
npm run build
git diff --check
```

Expected: PASS for all script tests, Swift tests, host self-test, extension tests/build, and `git diff --check`

- [ ] **Step 7: Commit**

```bash
git add \
  scripts/dev/smoke-check.sh \
  scripts/dev/test-smoke-check.sh \
  docs/operations/gesturekit-v1-local-install.md \
  docs/operations/gesturekit-v1-e2e-checklist.md \
  docs/operations/gesturekit-v1-troubleshooting.md
git commit -m "docs: close p3 installation workflow"
```
