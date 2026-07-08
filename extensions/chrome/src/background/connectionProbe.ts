import type {
  ActionResultMessage,
  ProbeRequestMessage,
  ProbeResponseMessage
} from "../protocol/messages";

export type ConnectionProbeResult = {
  hostConnected: boolean;
  appConnected: boolean;
  appSessionId?: string;
  status: string;
  message: string;
};

const PROBE_TIMEOUT_MS = 1500;

export async function runConnectionProbe(port: chrome.runtime.Port): Promise<ConnectionProbeResult> {
  return new Promise((resolve, reject) => {
    let settled = false;
    const timeout = setTimeout(() => {
      finish({
        hostConnected: false,
        appConnected: false,
        status: "timeout",
        message: "probe_timeout"
      });
    }, PROBE_TIMEOUT_MS);

    const cleanup = () => {
      clearTimeout(timeout);
      port.onMessage.removeListener?.(onMessage);
      port.onDisconnect.removeListener?.(onDisconnect);
    };

    const finish = (result: ConnectionProbeResult) => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      resolve(result);
    };

    const onMessage = (message: ProbeResponseMessage | ActionResultMessage) => {
      if (message.type === "probe_response") {
        finish({
          hostConnected: true,
          appConnected: message.payload.appConnected,
          appSessionId: message.payload.appSessionId,
          status: message.payload.appConnected ? "connected" : "app_unavailable",
          message: message.payload.message ?? "probe_response"
        });
        return;
      }

      if (message.type === "action_result" && message.payload.status === "app_unavailable") {
        finish({
          hostConnected: true,
          appConnected: false,
          status: "app_unavailable",
          message: "app_unavailable"
        });
      }
    };

    const onDisconnect = () => {
      finish({
        hostConnected: false,
        appConnected: false,
        status: "native_host_disconnected",
        message: chrome.runtime.lastError?.message ?? "native_host_disconnected"
      });
    };

    port.onMessage.addListener(onMessage);
    port.onDisconnect.addListener(onDisconnect);

    try {
      port.postMessage(createProbeRequest());
    } catch (error) {
      cleanup();
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}

function createProbeRequest(): ProbeRequestMessage {
  return {
    version: 1,
    id: globalThis.crypto?.randomUUID?.() ?? `probe-${Date.now()}`,
    type: "probe_request",
    timestamp: Date.now(),
    payload: { source: "extension_smoke_page" },
    error: null
  };
}
