import { executeGestureAction } from "./actionExecutor";
import { chromeApi } from "./chromeApi";
import { createNativePortManager } from "./nativePortManager";
import { runConnectionProbe } from "./connectionProbe";
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

const port = chrome.runtime.connectNative(HOST_NAME);
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

const manager = createNativePortManager({
  port,
  resolveLastPointer,
  executeAction: (intent) => executeGestureAction(chromeApi, intent),
  getSettings: () => loadGestureSettings(chrome.storage.local),
  cancelPendingTap,
  onActionResult: (message) => {
    void appendDiagnostic(
      chrome.storage.local,
      diagnosticFromActionResult(message)
    );
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

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "gesturekit.runConnectionProbe") {
    return false;
  }

  runConnectionProbe(port)
    .then((probe) => {
      sendResponse(probe);
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
  port.postMessage(message);
}

port.onMessage.addListener((message) => {
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

chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName === "local" && changes[GESTURE_SETTINGS_STORAGE_KEY]) {
    void syncGestureSettings();
  }
});

void syncGestureSettings();

port.onDisconnect.addListener(() => {
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
});
