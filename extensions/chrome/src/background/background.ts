import { executeGestureAction } from "./actionExecutor";
import { chromeApi } from "./chromeApi";
import { createNativePortManager } from "./nativePortManager";

const HOST_NAME = "com.gesturekit.host";

async function resolveLastPointer() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab?.id) {
    return { status: "page_unavailable" as const };
  }

  try {
    return await chrome.tabs.sendMessage(tab.id, { type: "gesturekit.resolveLastPointer" });
  } catch {
    return { status: "page_unavailable" as const };
  }
}

const port = chrome.runtime.connectNative(HOST_NAME);
const manager = createNativePortManager({
  port,
  resolveLastPointer,
  executeAction: (intent) => executeGestureAction(chromeApi, intent)
});

port.onMessage.addListener((message) => {
  void manager.handleNativeMessage(message);
});

port.onDisconnect.addListener(() => {
  chrome.storage.local.set({
    gesturekitLastError: {
      status: "native_host_disconnected",
      timestamp: Date.now(),
      message: chrome.runtime.lastError?.message ?? "Native host disconnected"
    }
  });
});
