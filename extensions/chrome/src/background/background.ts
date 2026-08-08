import { executeGestureAction, executeStandardAction } from "./actionExecutor";
import { chromeApi } from "./chromeApi";
import { createNativePortManager } from "./nativePortManager";
import { runConnectionProbe } from "./connectionProbe";
import { createReconnectableNativePort, type PortLike } from "./reconnectableNativePort";
import {
  decodeProviderEnvelope,
  type ConfigurationSnapshotPayload,
  type ProviderEnvelope
} from "../provider/protocol";
import { ContextProvider } from "../provider/contextProvider";
import { ChromeActionAdapter } from "../provider/actionAdapter";
import { ChromeProvider } from "../provider/chromeProvider";
import { V2Dispatcher } from "../provider/v2Dispatcher";
import { createOperationLedgerStore } from "../provider/operationLedger";
import { TelemetryConnection } from "../provider/telemetryConnection";
import { ChromeProviderCapabilities } from "../provider/chromeCapabilities";
import { createControlCenterRequestForwarder } from "./controlCenterRequest";
import { loadGestureSettings } from "../settings/gestureSettings";
import {
  isSettingsSyncStatus,
  markSettingsSyncFailed,
  markSettingsSyncStale,
  SETTINGS_SYNC_STATUS_STORAGE_KEY
} from "./settingsSync";
import { cacheAppConfigurationSnapshot } from "../settings/appConfigurationCache";
import {
  appendDiagnostic,
  diagnosticEntryFromMessage,
  diagnosticFromActionResult,
  isDiagnosticEventMessage
} from "../diagnostics/diagnostics";
import { diagnosticLoggingEnabledFromSnapshot } from "../settings/appConfigurationCache";

// E2E 构建（scripts/build.mjs 设 GESTUREKIT_HOST_NAME）可通过 define 覆盖 host 名，
// 使 E2E 扩展连接独立 host（com.gesturekit.host.e2e），完全避开用户级真实 manifest。
// 生产构建不注入 define；typeof 守卫对未声明全局安全，回退到默认名。
declare const __GESTUREKIT_HOST_NAME__: string | undefined;
const HOST_NAME = typeof __GESTUREKIT_HOST_NAME__ !== "undefined" ? __GESTUREKIT_HOST_NAME__ : "com.gesturekit.host";
const STATUS_STORAGE_KEY = "gesturekitStatus";

let manager: ReturnType<typeof createNativePortManager>;
const v2Contexts = new ContextProvider();
const providerLedger = createOperationLedgerStore();
const producerSessionId = crypto.randomUUID();
let authenticatedProviderSessionId: string | null = null;
let controlCenterRequestForwarder: ReturnType<typeof createControlCenterRequestForwarder> | null = null;
const MAX_GUARD_STAGES_PER_OPERATION = 15;
const GUARD_DIAGNOSTIC_LIMIT = 50;
type GuardTrace = { timestamp: number; stage: string; detail: string };
const guardTraces = new Map<string, GuardTrace[]>();
let diagnosticLoggingEnabled = false;
// v2 boundary keeps resolved page URLs and target references inside Chrome.
const chromeProvider = new ChromeProvider(chromeApi, async (tabId, message) => {
  try { return await chrome.tabs.sendMessage(tabId, message); }
  catch { return { status: "page_unavailable" as const }; }
});

async function resolveLastPointer() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab?.id) {
    return { status: "page_unavailable" as const };
  }

  try {
    return await chrome.tabs.sendMessage(tab.id, {
      type: "gesturekit.resolveLastPointer",
      consumeNextClick: true
    });
  } catch {
    return { status: "page_unavailable" as const };
  }
}

void chrome.storage.local.set({
  [STATUS_STORAGE_KEY]: {
    nativeConnected: true,
    appConnected: true,
    lastResult: "connected",
    timestamp: Date.now()
  }
});

function cancelPendingTap() {
  void (async () => {
    const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (tab?.id) {
      chrome.tabs.sendMessage(tab.id, { type: "gesturekit.cancelTap" }).catch(() => {});
    }
  })();
}

function createManager(port: PortLike) {
  return createNativePortManager({
    port,
    resolveLastPointer,
    executeAction: (intent) => executeGestureAction(chromeApi, intent),
    getSettings: () => loadGestureSettings(chrome.storage.local),
    cancelPendingTap,
    onActionResult: (message) => {
      if (shouldRecordDiagnostic(message)) {
        void appendDiagnostic(
          chrome.storage.local,
          diagnosticFromActionResult(message)
        );
      }
      void chrome.storage.local.set({
        [STATUS_STORAGE_KEY]: {
          nativeConnected: true,
          appConnected: true,
          lastResult: `${message.payload.action} ${message.payload.status}`,
          timestamp: Date.now()
        }
      });
    }
  });
}

function createV2Dispatcher(port: PortLike, ledger: Awaited<typeof providerLedger>) {
  // V2 side effects are routed through ChromeProvider and its injected ChromeApi.
  // This adapter remains only as the legacy-dispatcher dependency; its link path
  // deliberately uses the same injected API rather than global chrome.tabs.
  const adapter = new ChromeActionAdapter(
    v2Contexts,
    async (url) => { await executeStandardAction(chromeApi, "browser.link.open_adjacent", url); },
    async (action) => { await executeStandardAction(chromeApi, action.actionId); }
  );
  return new V2Dispatcher(v2Contexts, adapter, async () => {
    const resolved = await resolveLastPointer();
    return resolved.status === "success" ? resolved.url : null;
  }, (message) => port.postMessage(message), ledger, producerSessionId, chromeProvider);
}

function shouldRecordDiagnostic(message: { payload: { status: string; details?: Record<string, unknown> } }): boolean {
  if (message.payload.status === "no_target") return false;
  if (message.payload.status !== "gesture_unstable") return true;
  const knownReason = typeof message.payload.details?.reason === "string" &&
    ["superseded_by_tap", "cooldown", "tap_duration_unstable"].includes(message.payload.details.reason);
  return knownReason;
}

function handlePortDisconnect() {
  const timestamp = Date.now();
  void appendDiagnostic(chrome.storage.local, {
    id: `connection-${timestamp}`,
    timestamp,
    source: "extension",
    kind: "connection",
    status: "native_host_disconnected",
    reason: "native_host_disconnected",
    message: chrome.runtime.lastError?.message ?? "Native host disconnected"
  });
  void (async () => {
    const result = await chrome.storage.local.get(SETTINGS_SYNC_STATUS_STORAGE_KEY);
    const previousStatus = result[SETTINGS_SYNC_STATUS_STORAGE_KEY];
    await chrome.storage.local.set({
      [SETTINGS_SYNC_STATUS_STORAGE_KEY]: markSettingsSyncFailed(
        isSettingsSyncStatus(previousStatus) ? previousStatus : null,
        "native_host_disconnected",
        timestamp
      )
    });
  })();
  void chrome.storage.local.set({
    [STATUS_STORAGE_KEY]: {
      nativeConnected: false,
      appConnected: false,
      lastResult: "native_host_disconnected",
      timestamp
    },
    gesturekitLastError: {
      status: "native_host_disconnected",
      timestamp,
      message: chrome.runtime.lastError?.message ?? "Native host disconnected"
    }
  });
}

const reconnectablePort = createReconnectableNativePort({
  connect: () => chrome.runtime.connectNative(HOST_NAME),
  attach: (port) => {
    manager = createManager(port);
    authenticatedProviderSessionId = null;
    controlCenterRequestForwarder = createControlCenterRequestForwarder(
      () => port,
      () => authenticatedProviderSessionId
    );
    const v2Dispatcher = providerLedger.then((ledger) => createV2Dispatcher(port, ledger));
    const telemetryConnection = providerLedger.then((store) => new TelemetryConnection(store, producerSessionId, (message) => port.postMessage(message)));
    port.onMessage.addListener((message) => {
      try {
        const envelope = decodeProviderEnvelope(message) as ProviderEnvelope;
        if (controlCenterRequestForwarder.handle(envelope)) return;
        if (envelope.type === "configuration_snapshot") {
          authenticatedProviderSessionId = envelope.providerSessionId;
          void handleConfigurationSnapshot(
            port,
            envelope,
            envelope.payload as ConfigurationSnapshotPayload
          );
          return;
        }
        if (envelope.type === "interaction_guard_arm" || envelope.type === "interaction_guard_release") {
          void routeInteractionGuard(envelope);
          return;
        }
        void telemetryConnection.then((connection) => connection.handle(envelope));
        void v2Dispatcher.then((dispatcher) => dispatcher.handle(envelope));
        return;
      } catch {
        // 旧消息仅在迁移窗口进入 V1 manager；v2 边界不会宽松降级。
      }
      if (isDiagnosticEventMessage(message)) {
        void appendDiagnostic(chrome.storage.local, diagnosticEntryFromMessage(message));
        return;
      }
      void manager.handleNativeMessage(message);
    });
  },
  onDisconnect: handlePortDisconnect
});

async function routeInteractionGuard(envelope: ProviderEnvelope): Promise<void> {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab?.id) {
    recordGuardTrace(envelope.gestureSessionId, "forward_failed", "active_tab_unavailable");
    return;
  }
  if (envelope.type === "interaction_guard_arm") {
    const payload = envelope.payload;
    if (!("features" in payload) || !payload.features.includes("link_click")) {
      recordGuardTrace(envelope.gestureSessionId, "forward_skipped", "link_click_not_requested");
      return;
    }
    recordGuardTrace(payload.gestureSessionId, "forwarding", "content_script");
    const response = await chrome.tabs.sendMessage(tab.id, {
      type: "gesturekit.linkGuardArm",
      gestureSessionId: payload.gestureSessionId,
      leaseMs: Math.max(0, payload.deadline - Date.now())
    }).catch(() => null) as { status?: string } | null;
    recordGuardTrace(payload.gestureSessionId, response?.status === "guard_armed" ? "forwarded" : "forward_failed", response?.status ?? "content_script_unavailable");
    return;
  }
  const payload = envelope.payload;
  if (!("gestureSessionId" in payload)) return;
  await chrome.tabs.sendMessage(tab.id, {
    type: "gesturekit.linkGuardRelease",
    gestureSessionId: payload.gestureSessionId
  }).catch(() => {});
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "gesturekit.guardTrace") {
    recordGuardTrace(message.gestureSessionId, message.stage, message.detail);
    return false;
  }
  if (message?.type === "gesturekit.openControlCenter") {
    (controlCenterRequestForwarder?.open() ?? Promise.resolve({ status: "unavailable" }))
      .then(sendResponse)
      .catch(() => sendResponse({ status: "unavailable" }));
    return true;
  }

  if (message?.type !== "gesturekit.runConnectionProbe") {
    return false;
  }

  runConnectionProbe(reconnectablePort.ensureConnected() as chrome.runtime.Port)
    .then((probe) => {
      sendResponse(probe);
      void chrome.storage.local.set({
        [STATUS_STORAGE_KEY]: {
          nativeConnected: probe.hostConnected,
          appConnected: probe.appConnected,
          lastResult: probe.status,
          timestamp: Date.now()
        }
      });
      void (async () => {
        const result = await chrome.storage.local.get(SETTINGS_SYNC_STATUS_STORAGE_KEY);
        const status = result[SETTINGS_SYNC_STATUS_STORAGE_KEY];
        if (probe.appSessionId && isSettingsSyncStatus(status) && status.phase === "applied") {
          if (probe.appSessionId !== status.currentAppSessionId) {
            await chrome.storage.local.set({
              [SETTINGS_SYNC_STATUS_STORAGE_KEY]: markSettingsSyncStale(
                status,
                probe.appSessionId,
                Date.now()
              )
            });
          }
        }
      })();
    })
    .catch((error: Error) => sendResponse({
      hostConnected: false,
      appConnected: false,
      status: "error",
      message: error.message
    }));

  return true;
});

function recordGuardTrace(gestureSessionId: unknown, stage: unknown, detail: unknown) {
  if (typeof gestureSessionId !== "string" || typeof stage !== "string" || typeof detail !== "string") return;
  const trace: GuardTrace = { timestamp: Date.now(), stage, detail };
  const traces = [...(guardTraces.get(gestureSessionId) ?? []), trace].slice(-MAX_GUARD_STAGES_PER_OPERATION);
  guardTraces.set(gestureSessionId, traces);

  if (diagnosticLoggingEnabled) {
    console.debug(`interaction_guard session=${gestureSessionId} stage=${stage} detail=${detail}`);
    void appendGuardTrace(gestureSessionId, trace, traces.length - 1);
  }

  if (!isGuardTerminalStage(stage)) return;
  const failed = isGuardFailureStage(stage);
  const summary = traces.map((entry) => `${entry.stage}:${entry.detail}`).join(">");
  // Keep one normal-path summary; preserve the bounded pre-failure capsule only on failure.
  void appendDiagnostic(chrome.storage.local, {
    id: `interaction-guard-summary-${gestureSessionId}-${trace.timestamp}`,
    timestamp: trace.timestamp,
    source: "extension",
    kind: "action",
    reason: failed ? "chrome_action_failed" : "success",
    message: `guard_summary terminal=${stage}:${detail} stages=${summary}`
  }, GUARD_DIAGNOSTIC_LIMIT);
  if (failed && !diagnosticLoggingEnabled) {
    void persistGuardTraces(gestureSessionId, traces);
  }
  guardTraces.delete(gestureSessionId);
}

async function persistGuardTraces(gestureSessionId: string, traces: GuardTrace[]) {
  for (const [index, trace] of traces.entries()) {
    await appendGuardTrace(gestureSessionId, trace, index);
  }
}

function appendGuardTrace(gestureSessionId: string, trace: GuardTrace, index: number) {
  return appendDiagnostic(chrome.storage.local, {
    id: `interaction-guard-stage-${gestureSessionId}-${trace.timestamp}-${index}`,
    timestamp: trace.timestamp,
    source: "extension",
    kind: "action",
    reason: "unknown",
    message: `guard_stage session=${gestureSessionId} stage=${trace.stage} detail=${trace.detail}`
  }, GUARD_DIAGNOSTIC_LIMIT);
}

function isGuardTerminalStage(stage: string) {
  return stage === "consume_acknowledged" || stage === "consume_rejected" || stage === "forward_failed" || stage === "lease_expired";
}

function isGuardFailureStage(stage: string) {
  return stage !== "consume_acknowledged";
}

async function handleConfigurationSnapshot(
  port: PortLike,
  envelope: ProviderEnvelope,
  snapshot: ConfigurationSnapshotPayload
): Promise<void> {
  port.postMessage({
    ...envelope,
    messageId: crypto.randomUUID(),
    type: "capability_snapshot",
    timestamp: Date.now(),
    payload: { capabilities: [...ChromeProviderCapabilities.standard], capabilityVersion: 1 },
    error: null
  } satisfies ProviderEnvelope);
  try {
    const applied = await cacheAppConfigurationSnapshot(chrome.storage.local, snapshot);
    diagnosticLoggingEnabled = diagnosticLoggingEnabledFromSnapshot(applied);
    void appendDiagnostic(chrome.storage.local, {
      id: `settings-${envelope.messageId}`,
      timestamp: envelope.timestamp,
      source: "extension",
      kind: "settings",
      reason: "success",
      message: diagnosticLoggingEnabledFromSnapshot(applied)
        ? "diagnostic_logging_enabled=true"
        : "diagnostic_logging_enabled=false"
    });
    port.postMessage({
      ...envelope,
      messageId: crypto.randomUUID(),
      type: "configuration_ack",
      timestamp: Date.now(),
      payload: { appliedVersion: applied.configurationVersion, applied: true },
      error: null
    } satisfies ProviderEnvelope);
  } catch {
    // ACK 只表示 Provider 缓存状态，绝不反馈或覆盖 App 的权威配置。
    port.postMessage({
      ...envelope,
      messageId: crypto.randomUUID(),
      type: "configuration_ack",
      timestamp: Date.now(),
      payload: { appliedVersion: snapshot.configurationVersion, applied: false },
      error: null
    } satisfies ProviderEnvelope);
  }
}
