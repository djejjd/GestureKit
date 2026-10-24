import { afterEach, describe, expect, it, vi } from "vitest";
import { createNativeConnection } from "../src/background/nativeConnection";

function port() {
  function event() {
    const listeners = new Set<(...args: any[]) => void>();
    return { addListener: (f: any) => listeners.add(f), removeListener: (f: any) => listeners.delete(f),
      emit: (...args: any[]) => { for (const f of [...listeners]) f(...args); }, listeners };
  }
  return { postMessage: vi.fn(), disconnect: vi.fn(), onMessage: event(), onDisconnect: event() };
}
afterEach(() => vi.useRealTimers());
describe("Native port ownership", () => {
  it("coalesces disconnects, drops old callbacks and closes exactly once on stop", async () => {
    vi.useFakeTimers();
    const ports: ReturnType<typeof port>[] = [];
    const connect = vi.fn(() => { const p = port(); ports.push(p); return p; });
    const message = vi.fn();
    const controller = createNativeConnection({ connect, opened: () => {}, closed: () => {}, message });
    controller.start(); controller.start();
    const oldMessage = [...ports[0].onMessage.listeners][0];
    ports[0].onDisconnect.emit(); ports[0].onDisconnect.emit();
    await vi.advanceTimersByTimeAsync(1_000);
    expect(connect).toHaveBeenCalledTimes(2);
    oldMessage("stale"); expect(message).not.toHaveBeenCalled();
    expect(ports[0].onMessage.listeners.size).toBe(0);
    controller.stop(); controller.stop();
    expect(ports[1].disconnect).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(60_000); expect(connect).toHaveBeenCalledTimes(2);
  });
  it("backs off repeated failures and resets retry delay only after configuration readiness", async () => {
    vi.useFakeTimers();
    const ports: ReturnType<typeof port>[] = [];
    const connect = vi.fn(() => { const p = port(); ports.push(p); return p; });
    const controller = createNativeConnection({ connect, opened: () => {}, closed: () => {}, message: () => {} });
    controller.start();
    for (const delay of [1_000, 2_000, 4_000, 8_000, 16_000, 30_000, 30_000]) {
      const count = connect.mock.calls.length;
      ports.at(-1)!.onDisconnect.emit();
      await vi.advanceTimersByTimeAsync(delay - 1); expect(connect).toHaveBeenCalledTimes(count);
      await vi.advanceTimersByTimeAsync(1); expect(connect).toHaveBeenCalledTimes(count + 1);
    }
    controller.ready(ports.at(-1)!);
    ports.at(-1)!.onDisconnect.emit(); await vi.advanceTimersByTimeAsync(1_000);
    expect(connect).toHaveBeenCalledTimes(9);
    controller.stop();
  });
});
