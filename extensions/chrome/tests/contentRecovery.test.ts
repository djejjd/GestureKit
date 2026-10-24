import { afterEach, describe, expect, it, vi } from "vitest";

afterEach(() => {
  (window as any).__gestureKitContentLifecycle?.dispose();
  vi.unstubAllGlobals(); vi.restoreAllMocks(); vi.useRealTimers();
});

describe("content script replacement", () => {
  async function inject() {
    vi.resetModules();
    const listeners = new Set<any>();
    const runtime = {
      id: "extension", sendMessage: vi.fn(async () => {}),
      onMessage: { addListener: (f: any) => listeners.add(f), removeListener: (f: any) => listeners.delete(f) }
    };
    vi.stubGlobal("chrome", { runtime });
    await import("../src/content/pointerTracker");
    const message = (value: any) => { const replies: unknown[] = []; for (const f of listeners) f(value, {}, (v: unknown) => replies.push(v)); return replies; };
    return { runtime, listeners, message };
  }
  it("replaces old DOM and runtime listeners without changing form contents", async () => {
    document.body.innerHTML = '<input value="unsaved"><p id="text">Text</p>';
    const first = await inject();
    first.message({ type: "gesturekit.linkGuardArm", gestureSessionId: "old", features: ["drag_selection"], leaseMs: 800 });
    const before = new Event("selectstart", { bubbles: true, cancelable: true });
    document.getElementById("text")!.dispatchEvent(before); expect(before.defaultPrevented).toBe(true);
    const second = await inject();
    expect(first.listeners.size).toBe(0);
    expect(second.listeners.size).toBe(1);
    const after = new Event("selectstart", { bubbles: true, cancelable: true });
    document.getElementById("text")!.dispatchEvent(after); expect(after.defaultPrevented).toBe(false);
    expect(document.querySelector("input")!.value).toBe("unsaved");
  });
  it("fails open immediately when the old extension context becomes invalid", async () => {
    document.body.innerHTML = '<p id="text">Text</p>';
    const { runtime, message, listeners } = await inject();
    message({ type: "gesturekit.linkGuardArm", gestureSessionId: "old", features: ["drag_selection"], leaseMs: 800 });
    runtime.id = undefined as any;
    const event = new Event("selectstart", { bubbles: true, cancelable: true });
    document.getElementById("text")!.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(false);
    expect(listeners.size).toBe(0);
  });
});
