import { executeGestureAction } from "./actionExecutor";
import { chromeApi } from "./chromeApi";
import { createNativePortManager } from "./nativePortManager";
import { loadGestureSettings } from "../settings/gestureSettings";

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

port.onMessage.addListener((message) => {
  void manager.handleNativeMessage(message);
});

port.onDisconnect.addListener(() => {
  chrome.storage.local.set({
    [STATUS_STORAGE_KEY]: {
      nativeConnected: false,
      appConnected: false,
      lastResult: "native_host_disconnected",
      timestamp: Date.now()
    },
    gesturekitLastError: {
      status: "native_host_disconnected",
      timestamp: Date.now(),
      message: chrome.runtime.lastError?.message ?? "Native host disconnected"
    }
  });
});
