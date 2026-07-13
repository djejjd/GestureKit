import { executeGestureAction, executeStandardAction } from "./actionExecutor";
import { chromeApi } from "./chromeApi";
import { createNativePortManager } from "./nativePortManager";
import { runConnectionProbe } from "./connectionProbe";
import { createReconnectableNativePort, type PortLike } from "./reconnectableNativePort";
import { decodeProviderEnvelope, type ProviderEnvelope } from "../provider/protocol";
import { ContextProvider } from "../provider/contextProvider";
import { ChromeActionAdapter } from "../provider/actionAdapter";
import { ChromeProvider } from "../provider/chromeProvider";
import { V2Dispatcher } from "../provider/v2Dispatcher";
import { createOperationLedgerStore } from "../provider/operationLedger";
import { TelemetryConnection } from "../provider/telemetryConnection";
import { GESTURE_SETTINGS_STORAGE_KEY, loadGestureSettings } from "../settings/gestureSettings";
import {
  createSavedOnlySettingsSyncStatus,
  createPendingSettingsSyncStatus,
  createSettingsUpdateMessage,
  isSettingsAckMessage,
  isSettingsSyncStatus,
  markSettingsSyncFailed,
  markSettingsSyncStale,
  SETTINGS_SYNC_STATUS_STORAGE_KEY,
  settingsSyncStatusFromAck
} from "./settingsSync";
import {
  appendDiagnostic,
  diagnosticEntryFromMessage,
  diagnosticFromActionResult,
  isDiagnosticEventMessage
} from "../diagnostics/diagnostics";

const HOST_NAME = "com.gesturekit.host";
const STATUS_STORAGE_KEY = "gesturekitStatus";

let manager: ReturnType<typeof createNativePortManager>;
const v2Contexts = new ContextProvider();
const providerLedger = createOperationLedgerStore();
const producerSessionId = crypto.randomUUID();
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
    const v2Dispatcher = providerLedger.then((ledger) => createV2Dispatcher(port, ledger));
    const telemetryConnection = providerLedger.then((store) => new TelemetryConnection(store, producerSessionId, (message) => port.postMessage(message)));
    port.onMessage.addListener((message) => {
      try {
        const envelope = decodeProviderEnvelope(message) as ProviderEnvelope;
        void telemetryConnection.then((connection) => connection.handle(envelope));
        void v2Dispatcher.then((dispatcher) => dispatcher.handle(envelope));
        return;
      } catch {
        // 旧消息仅在迁移窗口进入 V1 manager；v2 边界不会宽松降级。
      }
      if (isSettingsAckMessage(message)) {
        void (async () => {
          const settings = await loadGestureSettings(chrome.storage.local);
          const result = await chrome.storage.local.get(SETTINGS_SYNC_STATUS_STORAGE_KEY);
          const currentStatus = isSettingsSyncStatus(result[SETTINGS_SYNC_STATUS_STORAGE_KEY])
            ? result[SETTINGS_SYNC_STATUS_STORAGE_KEY]
            : null;
          await chrome.storage.local.set({
            [SETTINGS_SYNC_STATUS_STORAGE_KEY]: settingsSyncStatusFromAck(message, settings, currentStatus)
          });
        })();
        return;
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

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
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

async function syncGestureSettings() {
  const settings = await loadGestureSettings(chrome.storage.local);
  const result = await chrome.storage.local.get(SETTINGS_SYNC_STATUS_STORAGE_KEY);
  const previousStatus = isSettingsSyncStatus(result[SETTINGS_SYNC_STATUS_STORAGE_KEY])
    ? result[SETTINGS_SYNC_STATUS_STORAGE_KEY]
    : null;
  const message = createSettingsUpdateMessage(settings);
  await chrome.storage.local.set({
    [SETTINGS_SYNC_STATUS_STORAGE_KEY]: createSavedOnlySettingsSyncStatus(settings, previousStatus)
  });
  await chrome.storage.local.set({
    [SETTINGS_SYNC_STATUS_STORAGE_KEY]: createPendingSettingsSyncStatus(
      settings,
      message.id,
      previousStatus,
      Date.now()
    )
  });
  reconnectablePort.ensureConnected().postMessage(message);
}

chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName === "local" && changes[GESTURE_SETTINGS_STORAGE_KEY]) {
    void syncGestureSettings();
  }
});

void syncGestureSettings();
