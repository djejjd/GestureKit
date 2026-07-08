import { executeGestureAction } from "./actionExecutor";
import { chromeApi } from "./chromeApi";
import { createNativePortManager } from "./nativePortManager";
import { runConnectionProbe } from "./connectionProbe";
import { GESTURE_SETTINGS_STORAGE_KEY, loadGestureSettings } from "../settings/gestureSettings";
import {
  createSettingsUpdateMessage,
  isSettingsAckMessage,
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

const manager = createNativePortManager({
  port,
  resolveLastPointer,
  executeAction: (intent) => executeGestureAction(chromeApi, intent),
  getSettings: () => loadGestureSettings(chrome.storage.local),
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
    .then(sendResponse)
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
  port.postMessage(createSettingsUpdateMessage(settings));
}

port.onMessage.addListener((message) => {
  if (isSettingsAckMessage(message)) {
    void chrome.storage.local.set({
      [SETTINGS_SYNC_STATUS_STORAGE_KEY]: settingsSyncStatusFromAck(message)
    });
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
  chrome.storage.local.set({
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
