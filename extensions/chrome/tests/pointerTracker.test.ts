import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GESTURE_SETTINGS_PRESETS, GESTURE_SETTINGS_STORAGE_KEY } from "../src/settings/gestureSettings";

describe("pointerTracker", () => {
  beforeEach(() => {
    vi.useRealTimers();
    vi.resetModules();
    document.body.innerHTML = `<a id="target" href="/docs">Docs</a>`;
    document.elementFromPoint = () => document.getElementById("target");
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("returns no_recent_pointer before any pointer move", async () => {
    const module = await import("../src/content/pointerTracker");

    expect(module.resolveLinkAtLastPointer(1000)).toMatchObject({ status: "no_recent_pointer" });
    expect(module.resolveLinkAtLastPointer(1000)).toHaveProperty("detail");
  });

  it("resolves the last fresh pointer position", async () => {
    const module = await import("../src/content/pointerTracker");
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    const result = module.resolveLinkAtLastPointer(Date.now());

    expect(result).toEqual({ status: "success", url: "http://localhost:3000/docs" });
  });

  it("prevents the next click on the resolved link after consuming last pointer", async () => {
    const module = await import("../src/content/pointerTracker");
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    const result = module.resolveLinkAtLastPointer(Date.now(), { consumeNextClick: true });
    const click = new MouseEvent("click", { bubbles: true, cancelable: true });
    const wasNotCancelled = anchor.dispatchEvent(click);

    expect(result).toEqual({ status: "success", url: "http://localhost:3000/docs" });
    expect(wasNotCancelled).toBe(false);
    expect(click.defaultPrevented).toBe(true);
  });

  it("reports when the link click already fired before GestureKit can consume it", async () => {
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    anchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const result = module.resolveLinkAtLastPointer(Date.now(), { consumeNextClick: true });

    expect(result).toMatchObject({
      status: "success",
      url: "http://localhost:3000/docs",
      clickAlreadyFired: true
    });
    expect(result).toHaveProperty("detail");
  });

  it("does not prevent ordinary clicks before GestureKit asks to consume one", async () => {
    await import("../src/content/pointerTracker");
    document.body.innerHTML = `<button id="ordinary">Open</button>`;
    const button = document.getElementById("ordinary") as HTMLButtonElement;

    const click = new MouseEvent("click", { bubbles: true, cancelable: true });
    const wasNotCancelled = button.dispatchEvent(click);

    expect(wasNotCancelled).toBe(true);
    expect(click.defaultPrevented).toBe(false);
  });

  it("protects a link click while waiting for GestureKit to resolve the tap", async () => {
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(true);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    const click = new MouseEvent("click", { bubbles: true, cancelable: true });
    const wasNotCancelled = anchor.dispatchEvent(click);
    const result = module.resolveLinkAtLastPointer(Date.now(), { consumeNextClick: true });

    expect(wasNotCancelled).toBe(false);
    expect(click.defaultPrevented).toBe(true);
    expect(result).toEqual({
      status: "success",
      url: "http://localhost:3000/docs",
      clickProtected: true
    });
  });

  it("uses the protected link URL even when the last pointer no longer hits an anchor", async () => {
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(true);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    anchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    document.elementFromPoint = () => document.body;
    const result = module.resolveLinkAtLastPointer(Date.now(), { consumeNextClick: true });

    expect(result).toEqual({
      status: "success",
      url: "http://localhost:3000/docs",
      clickProtected: true
    });
  });

  it("uses the protected link URL even when the last pointer hits another anchor", async () => {
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(true);
    document.body.innerHTML = `
      <a id="target" href="/docs">Docs</a>
      <a id="other" href="/other">Other</a>
    `;
    const protectedAnchor = document.getElementById("target") as HTMLAnchorElement;
    const otherAnchor = document.getElementById("other") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    protectedAnchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    document.elementFromPoint = () => otherAnchor;
    const result = module.resolveLinkAtLastPointer(Date.now(), { consumeNextClick: true });

    expect(result).toEqual({
      status: "success",
      url: "http://localhost:3000/docs",
      clickProtected: true
    });
  });

  it("does not protect non-http links", async () => {
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(true);
    document.body.innerHTML = `<a id="target" href="mailto:test@example.com">Mail</a>`;
    const anchor = document.getElementById("target") as HTMLAnchorElement;

    const click = new MouseEvent("click", { bubbles: true, cancelable: true });
    const wasNotCancelled = anchor.dispatchEvent(click);

    expect(wasNotCancelled).toBe(true);
    expect(click.defaultPrevented).toBe(false);
  });

  it("does not protect modified, non-left, new-window, download, or non-cancelable clicks", async () => {
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(true);
    const cases: Array<{ name: string; setup?: (anchor: HTMLAnchorElement) => void; event: MouseEvent }> = [
      { name: "meta", event: new MouseEvent("click", { bubbles: true, cancelable: true, metaKey: true }) },
      { name: "ctrl", event: new MouseEvent("click", { bubbles: true, cancelable: true, ctrlKey: true }) },
      { name: "shift", event: new MouseEvent("click", { bubbles: true, cancelable: true, shiftKey: true }) },
      { name: "alt", event: new MouseEvent("click", { bubbles: true, cancelable: true, altKey: true }) },
      { name: "middle", event: new MouseEvent("click", { bubbles: true, cancelable: true, button: 1 }) },
      { name: "blank", setup: (anchor) => { anchor.target = "_blank"; }, event: new MouseEvent("click", { bubbles: true, cancelable: true }) },
      { name: "download", setup: (anchor) => { anchor.download = "file.txt"; }, event: new MouseEvent("click", { bubbles: true, cancelable: true }) },
      { name: "not-cancelable", event: new MouseEvent("click", { bubbles: true, cancelable: false }) }
    ];

    for (const item of cases) {
      document.body.innerHTML = `<a id="target" href="/docs">${item.name}</a>`;
      const anchor = document.getElementById("target") as HTMLAnchorElement;
      item.setup?.(anchor);
      const wasNotCancelled = anchor.dispatchEvent(item.event);

      expect(wasNotCancelled, item.name).toBe(true);
      expect(item.event.defaultPrevented, item.name).toBe(false);
    }
  });

  it("reports clickAlreadyFired for late tap confirmation after protection timeout", async () => {
    vi.useFakeTimers();
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(true);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    anchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    await vi.advanceTimersByTimeAsync(181);
    const result = module.resolveLinkAtLastPointer(Date.now(), { consumeNextClick: true });

    expect(result).toMatchObject({
      status: "success",
      url: "http://localhost:3000/docs",
      clickAlreadyFired: true
    });
  });

  it("syncs link protection from Chrome storage and consumes runtime messages", async () => {
    const storageListeners: Array<(changes: Record<string, { newValue: unknown }>, areaName: string) => void> = [];
    let runtimeListener: ((message: unknown, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      storage: {
        local: {
          get: vi.fn(async () => ({
            [GESTURE_SETTINGS_STORAGE_KEY]: {
              ...GESTURE_SETTINGS_PRESETS.safe,
              linkClickProtectionEnabled: true
            }
          }))
        },
        onChanged: {
          addListener: vi.fn((listener) => storageListeners.push(listener))
        }
      },
      runtime: {
        onMessage: {
          addListener: vi.fn((listener) => {
            runtimeListener = listener;
          })
        }
      }
    });
    await import("../src/content/pointerTracker");
    await Promise.resolve();
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    const protectedClick = new MouseEvent("click", { bubbles: true, cancelable: true });
    expect(anchor.dispatchEvent(protectedClick)).toBe(false);
    let response: unknown = null;
    runtimeListener?.({ type: "gesturekit.resolveLastPointer", consumeNextClick: true }, {}, (message) => {
      response = message;
    });

    expect(response).toEqual({
      status: "success",
      url: "http://localhost:3000/docs",
      clickProtected: true
    });

    storageListeners[0]?.({
      [GESTURE_SETTINGS_STORAGE_KEY]: {
        newValue: {
          ...GESTURE_SETTINGS_PRESETS.safe,
          linkClickProtectionEnabled: false
        }
      }
    }, "local");
    // Protection stays active even after storage changes — content script ignores stored value
    const stillProtectedClick = new MouseEvent("click", { bubbles: true, cancelable: true });
    expect(anchor.dispatchEvent(stillProtectedClick)).toBe(false);
    expect(stillProtectedClick.defaultPrevented).toBe(true);
  });

  it("does not protect link clicks when link click protection is disabled", async () => {
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    const anchor = document.getElementById("target") as HTMLAnchorElement;

    const click = new MouseEvent("click", { bubbles: true, cancelable: true });
    const wasNotCancelled = anchor.dispatchEvent(click);

    expect(wasNotCancelled).toBe(true);
    expect(click.defaultPrevented).toBe(false);
  });
});
