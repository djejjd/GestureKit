import { beforeEach, describe, expect, it, vi } from "vitest";

describe("pointerTracker", () => {
  beforeEach(() => {
    vi.useRealTimers();
    vi.resetModules();
    document.body.innerHTML = `<a id="target" href="/docs">Docs</a>`;
    document.elementFromPoint = () => document.getElementById("target");
  });

  it("returns no_recent_pointer before any pointer move", async () => {
    const module = await import("../src/content/pointerTracker");

    expect(module.resolveLinkAtLastPointer(1000)).toEqual({ status: "no_recent_pointer" });
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
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    anchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    const result = module.resolveLinkAtLastPointer(Date.now(), { consumeNextClick: true });

    expect(result).toEqual({
      status: "success",
      url: "http://localhost:3000/docs",
      clickAlreadyFired: true
    });
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
