import { restoreContentScripts } from "./contentRestore";
import type { GestureEventMessage } from "../protocol/messages";
import { createDevelopmentUpdater, type DevelopmentUpdateStatus } from "./developmentUpdater";
import { createNativeConnection } from "./nativeConnection";
import { createInteractionGuardRouter } from "./interactionGuardRouter";
import { executeGestureAction, executeStandardAction } from "./actionExecutor";
import { chromeApi } from "./chromeApi";
import { createNativePortManager } from "./nativePortManager";
import { runConnectionProbe } from "./connectionProbe";
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
declare const __GESTUREKIT_BUILD_ID__: string | undefined;
const BUILD_ID = typeof __GESTUREKIT_BUILD_ID__ !== "undefined" ? __GESTUREKIT_BUILD_ID__ : "unbuilt";
const HOST_NAME = typeof __GESTUREKIT_HOST_NAME__ !== "undefined" ? __GESTUREKIT_HOST_NAME__ : "com.gesturekit.host";

type PortLike = Pick<chrome.runtime.Port, "postMessage" | "onMessage" | "onDisconnect">;
const STATUS_STORAGE_KEY = "gesturekitStatus";

let workInFlight = 0;
let lastNativeActivity = 0;
let nativeAttempt = { id: "startup", startedAt: Date.now(), stage: "connecting" };
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
    nativeConnected: false,
    appConnected: false,
    lastResult: "connecting",
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

function createManager(port: PortLike, isActive: () => boolean) {
  return createNativePortManager({
    port,
    resolveLastPointer,
    executeAction: (intent) => executeGestureAction(chromeApi, intent),
    getSettings: () => loadGestureSettings(chrome.storage.local),
    cancelPendingTap,
    onActionResult: (message) => {
      if (!isActive()) return;
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

function createV2Dispatcher(port: PortLike, ledger: Awaited<typeof providerLedger>, isActive: (envelope: ProviderEnvelope) => boolean) {
  // V2 side effects are routed through ChromeProvider and its injected ChromeApi.
  // This adapter remains only as the legacy-dispatcher dependency; its link path
  // deliberately uses the same injected API rather than global chrome.tabs.
  const adapter = new ChromeActionAdapter(
    v2Contexts,
    async (url) => { await executeStandardAction(chromeApi, "browser.link.open_adjacent", url); },
    async (action) => { await executeStandardAction(chromeApi, action.actionId, undefined, action.parameters); }
  );
  return new V2Dispatcher(v2Contexts, adapter, async () => {
    const resolved = await resolveLastPointer();
    return resolved.status === "success" ? resolved.url : null;
  }, (message) => port.postMessage(message), ledger, producerSessionId, chromeProvider, isActive);
}

function shouldRecordDiagnostic(message: { payload: { status: string; details?: Record<string, unknown> } }): boolean {
  if (message.payload.status === "no_target") return false;
  if (message.payload.status !== "gesture_unstable") return true;
  const knownReason = typeof message.payload.details?.reason === "string" &&
    ["superseded_by_tap", "cooldown", "tap_duration_unstable"].includes(message.payload.details.reason);
  return knownReason;
}

function handlePortDisconnect() {
  // Access synchronously to consume Chrome's transient error; persist enum facts only.
  void chrome.runtime.lastError;
  manager?.dispose();
  resetPageGuards();
  authenticatedProviderSessionId = null;
  controlCenterRequestForwarder?.dispose();
  controlCenterRequestForwarder = null;
  const timestamp = Date.now();
  void appendDiagnostic(chrome.storage.local, {
    id: `connection-${nativeAttempt.id}`,
    timestamp,
    source: "extension",
    kind: "connection",
    status: "native_host_disconnected",
    reason: "native_host_disconnected",
    message: `connection_summary id=${nativeAttempt.id} outcome=failed stage=${nativeAttempt.stage} duration_ms=${Math.max(0, timestamp - nativeAttempt.startedAt)}`
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
      message: "native_host_disconnected"
    }
  });
}

// Host restores App IPC; this controller also recovers a terminated Native host.
let port: PortLike;
let v2Dispatcher: Promise<V2Dispatcher>;
let telemetryConnection: Promise<TelemetryConnection>;
let configurationWork = Promise.resolve();
const connection = createNativeConnection({
  connect: () => {
    nativeAttempt = { id: crypto.randomUUID(), startedAt: Date.now(), stage: "connecting" };
    return chrome.runtime.connectNative(HOST_NAME);
  },
  opened(current) {
    nativeAttempt.stage = "native_port_opened";
    authenticatedProviderSessionId = null;
    // Async work captures this scoped sender: it cannot target a replacement port.
    const scopedPort: PortLike = {
      onMessage: current.onMessage, onDisconnect: current.onDisconnect,
      postMessage(message: unknown) {
        if (!connection.isCurrent(current)) return;
        const envelope = message as Partial<ProviderEnvelope>;
        if (envelope.protocolVersion === 2 && envelope.providerSessionId !== authenticatedProviderSessionId) return;
        current.postMessage(message);
      }
    };
    port = scopedPort;
    manager = createManager(scopedPort, () => connection.isCurrent(current));
    controlCenterRequestForwarder = createControlCenterRequestForwarder(() => scopedPort, () => authenticatedProviderSessionId);
    v2Dispatcher = providerLedger.then(ledger => createV2Dispatcher(scopedPort, ledger,
      envelope => connection.isCurrent(current) && envelope.providerSessionId === authenticatedProviderSessionId));
    telemetryConnection = providerLedger.then(store => new TelemetryConnection(store, producerSessionId, message => scopedPort.postMessage(message)));
    void chrome.storage.local.set({ [STATUS_STORAGE_KEY]: {
      nativeConnected: true, appConnected: false, lastResult: "connecting", timestamp: Date.now()
    } });
  },
  closed: handlePortDisconnect,
  message(current, message) {
    if (!connection.isCurrent(current)) return;
    lastNativeActivity = Date.now();

  try {
    const envelope = decodeProviderEnvelope(message) as ProviderEnvelope;
    if (controlCenterRequestForwarder?.handle(envelope)) return;
    if (envelope.type === "health_probe") {
      // App 保活心跳：回声响应确认链路；消息本身已唤醒 SW。
      port.postMessage({
        protocolVersion: 2,
        messageId: crypto.randomUUID(),
        providerSessionId: envelope.providerSessionId,
        type: "health_probe",
        timestamp: Date.now(),
        payload: {
          probeSequence: (envelope.payload as { probeSequence: number }).probeSequence,
          sentAt: Date.now()
        }
      });
      return;
    }
    if (envelope.type === "configuration_snapshot") {
      if (authenticatedProviderSessionId !== envelope.providerSessionId) {
        resetPageGuards();
        manager?.dispose();
        manager = createManager(port, () => connection.isCurrent(current));
        controlCenterRequestForwarder?.dispose();
        const sessionPort = port;
        controlCenterRequestForwarder = createControlCenterRequestForwarder(() => sessionPort, () => authenticatedProviderSessionId);
      }
      authenticatedProviderSessionId = envelope.providerSessionId;
      const sessionID = envelope.providerSessionId;
      const responsePort = port;
      configurationWork = configurationWork.then(async () => {
        if (!connection.isCurrent(current) || authenticatedProviderSessionId !== sessionID) return;
        const applied = await handleConfigurationSnapshot(responsePort, envelope, envelope.payload as ConfigurationSnapshotPayload);
        if (!connection.isCurrent(current) || authenticatedProviderSessionId !== sessionID) return;
        if (applied) connection.ready(current);
        nativeAttempt.stage = applied ? "configuration_applied" : "configuration_failed";
        void appendDiagnostic(chrome.storage.local, {
          id: `connection-${nativeAttempt.id}-${envelope.messageId}`, timestamp: Date.now(), source: "extension", kind: "connection",
          reason: applied ? "success" : "unknown",
          message: `connection_summary id=${nativeAttempt.id} outcome=${applied ? "succeeded" : "failed"} stage=${nativeAttempt.stage} duration_ms=${Math.max(0, Date.now() - nativeAttempt.startedAt)}`
        });
        await chrome.storage.local.set({ [STATUS_STORAGE_KEY]: {
          nativeConnected: true, appConnected: applied, lastResult: applied ? "connected" : "configuration_failed", timestamp: Date.now()
        } });
      }).catch(() => {});
      return;
    }
    if (envelope.type === "health_response" && envelope.error?.code === "app_unavailable") {
      authenticatedProviderSessionId = null;
      resetPageGuards();
      manager?.dispose();
      controlCenterRequestForwarder?.dispose();
      controlCenterRequestForwarder = null;
      void chrome.storage.local.set({ [STATUS_STORAGE_KEY]: {
        nativeConnected: true, appConnected: false, lastResult: "app_unavailable", timestamp: Date.now()
      } });
      return;
    }
    if (envelope.providerSessionId !== authenticatedProviderSessionId) return;
    if (envelope.type === "interaction_guard_arm" || envelope.type === "interaction_guard_release") {
      const payload = envelope.payload;
      if ("gestureSessionId" in payload) void routeInteractionGuard({ type: envelope.type, payload });
      return;
    }
    void telemetryConnection.then((connection) => connection.handle(envelope));
    workInFlight += 1;
    void v2Dispatcher.then(dispatcher => dispatcher.handle(envelope)).catch(() => {}).finally(() => { workInFlight -= 1; });
    return;
  } catch {
    // 旧消息仅在迁移窗口进入 V1 manager；v2 边界不会宽松降级。
  }
  if (isDiagnosticEventMessage(message)) {
    void appendDiagnostic(chrome.storage.local, diagnosticEntryFromMessage(message));
    return;
  }
  void manager.handleNativeMessage(message as GestureEventMessage);

  }
});
// Listeners and route dependencies must exist before the first asynchronous message.

function makePageGuardRouter() { return createInteractionGuardRouter({
  query: () => chrome.tabs.query({ active: true, lastFocusedWindow: true }),
  send: (tabId, message) => chrome.tabs.sendMessage(tabId, message, { frameId: 0 }).catch(() => null),
  trace: recordGuardTrace
}); }
let routeInteractionGuard = makePageGuardRouter();
function resetPageGuards() {
  void routeInteractionGuard.dispose();
  routeInteractionGuard = makePageGuardRouter();
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

  const current = connection.current();
  if (!current) {
    connection.ensureConnected();
    sendResponse({ hostConnected: false, appConnected: false, status: "connecting", message: "connecting" });
    return false;
  }
  runConnectionProbe(current)
    .then((probe) => {
      sendResponse(probe);
      if (!connection.isCurrent(current)) return;
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
    message: `guard_summary session=${gestureSessionId} terminal=${stage}:${detail} stages=${summary}`
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
  return ["consume_acknowledged", "consume_rejected", "forward_failed", "lease_expired", "guard_discarded", "guard_released"].includes(stage);
}

function isGuardFailureStage(stage: string) {
  return !["consume_acknowledged", "guard_discarded", "guard_released"].includes(stage);
}

async function handleConfigurationSnapshot(
  port: PortLike,
  envelope: ProviderEnvelope,
  snapshot: ConfigurationSnapshotPayload
): Promise<boolean> {
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
    return true;
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
    return false;
  }
}

const developmentUpdater = createDevelopmentUpdater({
  buildId: BUILD_ID,
  installType: async () => (await chrome.management.getSelf()).installType,
  readBuild: async () => {
    const response = await fetch(chrome.runtime.getURL("dist/build.json"), { cache: "no-store" });
    if (!response.ok) throw Error("build marker unavailable");
    return response.json();
  },
  busy: () => workInFlight > 0 || Date.now() - lastNativeActivity < 2_000,
  load: async () => (await chrome.storage.local.get("gesturekitDevelopmentUpdate")).gesturekitDevelopmentUpdate as DevelopmentUpdateStatus ?? null,
  save: async status => {
    await chrome.storage.local.set({
      gesturekitDevelopmentUpdate: { ...status, pendingWork: workInFlight, idleForMs: Math.max(0, Date.now() - lastNativeActivity) },
      gesturekitRunningBuild: BUILD_ID
    });
    if (status.stage !== "deferred") void appendDiagnostic(chrome.storage.local, {
      id: `development-update-${status.operationId}-${status.stage}`, timestamp: Date.now(), source: "extension",
      kind: "connection", reason: status.stage === "failed" ? "unknown" : "success",
      message: `development_update operation=${status.operationId} build=${status.buildId} stage=${status.stage} failureStage=${status.failureStage ?? "none"}`
    });
  },
  reload: () => chrome.runtime.reload(), now: () => Date.now()
});
const MAINTENANCE_ALARM = "gesturekit-maintenance";
chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name !== MAINTENANCE_ALARM) return;
  connection.ensureConnected();
  void developmentUpdater.check();
});
chrome.runtime.onStartup.addListener(() => connection.ensureConnected());
chrome.runtime.onInstalled.addListener(() => connection.ensureConnected());
void chrome.alarms.create(MAINTENANCE_ALARM, { periodInMinutes: 0.5 });
void chrome.management.getSelf().then(info => {
  if (info.installType === "development") setInterval(() => { void developmentUpdater.check(); }, 2_000);
}).catch(() => {});
void chrome.storage.local.set({ gesturekitRunningBuild: BUILD_ID });
connection.start();
void developmentUpdater.check();

workInFlight += 1;
void restoreContentScripts({
  query: () => chrome.tabs.query({}),
  sendMessage: (tabId, message) => chrome.tabs.sendMessage(tabId, message),
  executeScript: injection => chrome.scripting.executeScript(injection)
}, BUILD_ID).then(summary => {
  void chrome.storage.local.set({ gesturekitContentRestore: summary });
}).catch(() => {}).finally(() => { workInFlight -= 1; });
