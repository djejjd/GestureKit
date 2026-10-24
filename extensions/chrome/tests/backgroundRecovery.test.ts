import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

function event<T extends (...args: any[]) => any>() {
  const listeners = new Set<T>();
  return {
    addListener: (listener: T) => { listeners.add(listener); },
    removeListener: (listener: T) => { listeners.delete(listener); },
    emit: (...args: Parameters<T>) => { for (const listener of [...listeners]) listener(...args); }
  };
}

function browser() {
  const ports: any[] = [];
  const saved: Record<string, any> = {};
  const runtime = {
    id: "test-extension", getURL: (path: string) => `chrome-extension://test-extension/${path}`,
    onMessage: event(), onStartup: event(), onInstalled: event(),
    lastError: undefined, reload: vi.fn(),
    connectNative: vi.fn(() => {
      const port = { postMessage: vi.fn(), disconnect: vi.fn(), onMessage: event(), onDisconnect: event() };
      ports.push(port); return port;
    })
  };
  vi.stubGlobal("chrome", {
    runtime,
    management: { getSelf: async () => ({ installType: "normal" }) },
    alarms: { create: vi.fn(), clear: vi.fn(), onAlarm: event() },
    scripting: { executeScript: vi.fn(async () => []) },
    tabs: { query: vi.fn(async () => []), sendMessage: vi.fn(async () => null) },
    sessions: {},
    storage: { local: {
      get: async (key: string) => ({ [key]: saved[key] }),
      set: async (values: Record<string, unknown>) => { Object.assign(saved, values); }
    } }
  });
  return { runtime, ports, saved };
}

const configuration = (session: string) => ({
  protocolVersion: 2, messageId: `configuration-${session}`, providerSessionId: session,
  gestureSessionId: null, operationId: null, type: "configuration_snapshot", timestamp: 1,
  payload: { storeEpoch: "store", schemaVersion: 3, configurationVersion: 1, configJSON: "{}" }, error: null
});

beforeEach(() => { vi.resetModules(); vi.useFakeTimers(); });
afterEach(() => { vi.clearAllTimers(); vi.useRealTimers(); vi.unstubAllGlobals(); });

describe("background Native connection recovery", () => {
  it("cancels a guard query when its native connection closes", async () => {
    const { ports } = browser();
    await import("../src/background/background");
    ports[0].onMessage.emit(configuration("app"));
    await vi.advanceTimersByTimeAsync(0);
    let finish!: (tabs: { id: number }[]) => void;
    vi.mocked(chrome.tabs.query).mockImplementationOnce(() => new Promise(resolve => { finish = resolve as typeof finish; }));
    ports[0].onMessage.emit({ ...configuration("app"), type: "interaction_guard_arm", payload: {
      gestureSessionId: "old", features: ["drag_selection"], deadline: Date.now() + 800
    } });
    ports[0].onDisconnect.emit();
    finish([{ id: 10 }]);
    await vi.advanceTimersByTimeAsync(0);
    expect(chrome.tabs.sendMessage).not.toHaveBeenCalled();
  });
  it("wakes recovery immediately on the extension installed/update lifecycle event", async () => {
    const { runtime, ports } = browser();
    await import("../src/background/background");
    ports[0].onDisconnect.emit();
    runtime.onInstalled.emit({ reason: "update" });
    expect(runtime.connectNative).toHaveBeenCalledTimes(2);
  });
  it("reconnects after a real Native port disconnect without reloading the extension", async () => {
    const { runtime, ports } = browser();
    await import("../src/background/background");
    ports[0].onDisconnect.emit();
    await vi.advanceTimersByTimeAsync(1_000);
    expect(runtime.connectNative).toHaveBeenCalledTimes(2);
    expect(runtime.reload).not.toHaveBeenCalled();
  });

  it("does not report App connected before configuration is applied", async () => {
    const { ports, saved } = browser();
    await import("../src/background/background");
    expect(saved.gesturekitStatus.appConnected).toBe(false);
    ports[0].onMessage.emit(configuration("new-app"));
    await vi.advanceTimersByTimeAsync(0);
    expect(saved.gesturekitStatus.appConnected).toBe(true);
  });

  it("ignores stale messages after reconnect and applies the new App session", async () => {
    const { ports, saved } = browser();
    await import("../src/background/background");
    ports[0].onDisconnect.emit();
    await vi.advanceTimersByTimeAsync(1_000);
    ports[0].onMessage.emit(configuration("old-app"));
    await vi.advanceTimersByTimeAsync(0);
    expect(ports[0].postMessage).not.toHaveBeenCalled();
    expect(saved.gesturekitStatus.appConnected).toBe(false);
    ports[1].onMessage.emit(configuration("new-app"));
    await vi.advanceTimersByTimeAsync(0);
    expect(ports[1].postMessage).toHaveBeenCalledWith(expect.objectContaining({ type: "configuration_ack", providerSessionId: "new-app" }));
    expect(saved.gesturekitStatus.appConnected).toBe(true);
  });

  it("survives a synchronous connect failure and retries", async () => {
    const { runtime } = browser();
    runtime.connectNative.mockImplementationOnce(() => { throw new Error("host unavailable"); });
    await expect(import("../src/background/background")).resolves.toBeDefined();
    await vi.advanceTimersByTimeAsync(1_000);
    expect(runtime.connectNative).toHaveBeenCalledTimes(2);
  });
});
