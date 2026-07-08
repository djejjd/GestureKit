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
});
