import { describe, expect, it, vi } from "vitest";
import { runConnectionProbe } from "../src/background/connectionProbe";

describe("runConnectionProbe", () => {
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

  it("maps v2 health_response app_unavailable to app_unavailable status instead of timeout", async () => {
    const postMessage = vi.fn();
    const addListener = vi.fn();
    const port = {
      postMessage,
      onMessage: { addListener },
      onDisconnect: { addListener: vi.fn() }
    };

    const promise = runConnectionProbe(port as never);
    const listener = addListener.mock.calls[0][0];
    // Host 自愈后断连期回包：v2 health_response + error.code == app_unavailable。
    listener({
      protocolVersion: 2,
      messageId: "host-app-unavailable",
      providerSessionId: "host-bridge",
      gestureSessionId: null,
      operationId: null,
      type: "health_response",
      timestamp: 0,
      payload: { probeSequence: 0, healthy: false },
      error: { code: "app_unavailable", message: "GestureKit App 不可用" }
    });

    await expect(promise).resolves.toEqual({
      hostConnected: true,
      appConnected: false,
      status: "app_unavailable",
      message: "app_unavailable"
    });
  });
});
