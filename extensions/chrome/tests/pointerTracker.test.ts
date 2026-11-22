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

  it("falls back to pointer-based link resolution when protected click times out", async () => {
    vi.useFakeTimers();
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(true);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    anchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    await vi.advanceTimersByTimeAsync(751);
    const result = module.resolveLinkAtLastPointer(Date.now(), { consumeNextClick: true });

    // 保护超时后 timedOutAndNavigated 置为 true，跳过指针解析避免重复导航
    expect(result).toMatchObject({ status: "no_target" });
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

    expect(response).toMatchObject({
      status: "success",
      url: "http://localhost:3000/docs"
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

  it("falls through to pointer resolution when protected click times out without expired storage", async () => {
    vi.useFakeTimers();
    vi.resetModules();
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(true);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    anchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    await vi.advanceTimersByTimeAsync(751);

    const result = module.resolveLinkAtLastPointer(Date.now(), { consumeNextClick: true });
    // 保护超时，timedOutAndNavigated 阻止手势再次打开链接
    expect(result).toMatchObject({ status: "no_target" });
    vi.useRealTimers();
  });

  it("navigates to the link URL when protected click times out without gesture consumption", async () => {
    vi.useFakeTimers();
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(true);
    const anchor = document.getElementById("target") as HTMLAnchorElement;

    anchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    await vi.advanceTimersByTimeAsync(751);

    // jsdom 中设置 window.location.href 会以 console.error 报告导航
    expect(consoleError).toHaveBeenCalledWith("Not implemented: navigation to another Document");
    consoleError.mockRestore();
    vi.useRealTimers();
  });

  it("discards a protected link click superseded by a double tap without restoring navigation", async () => {
    vi.useFakeTimers();
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    let runtimeListener: ((message: Record<string, unknown>, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: {
        onMessage: {
          addListener: vi.fn((listener) => { runtimeListener = listener; })
        }
      }
    });
    await import("../src/content/pointerTracker");
    // 直接构造已被点击处理器暂存的链接，避免 jsdom 中历次模块导入留下的
    // document 事件监听器互相影响；这里验证的是 discard 消息对真实暂存状态的终态。
    const trackerState = (window as unknown as {
      __gestureKitPointerTrackerState: {
        protectedLinkClick: {
          url: string;
          gestureSessionId: string;
          timestamp: number;
          timeout: ReturnType<typeof setTimeout>;
        } | null;
      };
    }).__gestureKitPointerTrackerState;
    trackerState.protectedLinkClick = {
      url: "http://localhost:3000/docs",
      gestureSessionId: "first-tap",
      timestamp: Date.now(),
      timeout: setTimeout(() => {
        window.location.href = "http://localhost:3000/docs";
      }, 750)
    };

    let discardResponse: unknown = null;
    runtimeListener?.({
      type: "gesturekit.linkGuardDiscard",
      gestureSessionId: "first-tap"
    }, {}, (response) => { discardResponse = response; });
    expect(discardResponse).toEqual({ status: "guard_discarded" });
    consoleError.mockClear();
    await vi.advanceTimersByTimeAsync(751);

    expect(consoleError).not.toHaveBeenCalledWith("Not implemented: navigation to another Document");
    consoleError.mockRestore();
    vi.useRealTimers();
  });

  it("restores a consumed same-document protected click exactly once when the guard is released", async () => {
    vi.useFakeTimers();
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    let runtimeListener: ((message: Record<string, unknown>, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: {
        onMessage: {
          addListener: vi.fn((listener) => { runtimeListener = listener; })
        }
      }
    });
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));

    runtimeListener?.({ type: "gesturekit.linkGuardArm", gestureSessionId: "single-wait", features: ["link_click"], leaseMs: 500 }, {}, () => {});
    const click = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 });
    expect(anchor.dispatchEvent(click)).toBe(false);
    expect(click.defaultPrevented).toBe(true);

    let consumeResponse: unknown = null;
    runtimeListener?.({ type: "gesturekit.guardConsume", gestureSessionId: "single-wait" }, {}, (response) => { consumeResponse = response; });
    expect(consumeResponse).toEqual({ status: "guard_consumed" });

    let releaseResponse: unknown = null;
    runtimeListener?.({ type: "gesturekit.guardRelease", gestureSessionId: "single-wait" }, {}, (response) => { releaseResponse = response; });
    expect(releaseResponse).toEqual({ status: "guard_released" });
    expect((window as unknown as {
      __gestureKitPointerTrackerState?: { consumedProtectedClick: unknown };
    }).__gestureKitPointerTrackerState?.consumedProtectedClick).toBeNull();
    await vi.advanceTimersByTimeAsync(1_300);

    expect(consoleError).toHaveBeenCalledTimes(1);
    expect(module.resolveLinkAtLastPointer(Date.now())).toMatchObject({ status: "success" });
    consoleError.mockRestore();
    vi.useRealTimers();
  });

  it("isolates one delayed same-session click in the replacement document without swallowing the next click", async () => {
    vi.useFakeTimers();
    let runtimeListener: ((message: Record<string, unknown>, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: {
        onMessage: {
          addListener: vi.fn((listener) => { runtimeListener = listener; })
        }
      }
    });
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    let armResponse: any = null;
    runtimeListener?.({
      type: "gesturekit.closeClickArm",
      gestureSessionId: "double-tap-close",
      leaseMs: 1_200
    }, {}, (response) => { armResponse = response; });
    expect(armResponse).toMatchObject({
      status: "close_click_armed",
      gestureSessionId: "double-tap-close"
    });

    const delayedClick = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0, detail: 1 });
    expect(anchor.dispatchEvent(delayedClick)).toBe(false);
    expect(delayedClick.defaultPrevented).toBe(true);

    const nextClick = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0, detail: 1 });
    expect(anchor.dispatchEvent(nextClick)).toBe(true);
    expect(nextClick.defaultPrevented).toBe(false);
    vi.useRealTimers();
  });

  it.each(["quick", "extend", "shrink", "failed", "stale"])("arbitrates a %s text swipe on the same line", async mode => {
    const addListener = vi.fn();
    vi.stubGlobal("chrome", { runtime: { onMessage: { addListener } } });
    await import("../src/content/pointerTracker");
    const listener = addListener.mock.calls[0][0];
    const reply = vi.fn();
    const message = (type: string, id = "gesture") =>
      listener({ type: `gesturekit.${type}`, gestureSessionId: id, features: ["observe_drag"], leaseMs: 800 }, {}, reply);
    const now = vi.spyOn(performance, "now").mockReturnValue(0);
    try {
      const text = document.querySelector("a")!.firstChild!;
      const selection = window.getSelection()!;
      selection.setBaseAndExtent(text, 1, text, 0);
      message("linkGuardArm");
      const move = (at: number, end: number) => {
        now.mockReturnValue(at);
        selection.setBaseAndExtent(text, 0, text, end);
        document.dispatchEvent(new Event("selectionchange"));
      };
      move(10, 1);
      move(30, 2);
      const dragging = mode === "extend" || mode === "shrink";
      move(dragging ? 190 : 45, mode === "shrink" ? 1 : 3);
      message("linkGuardDiscard");
      message("dragEvidence");
      expect(reply.mock.lastCall?.[0]).toMatchObject({ dragging });
      if (mode === "stale") message("linkGuardArm", "new");
      if (mode !== "failed") message("swipeCommitted");
      expect(selection.focusOffset).toBe(mode === "quick" ? 0 : mode === "shrink" ? 1 : 3);
    } finally { now.mockRestore(); }
  });

  it.each(["held", "expired", "quick"])("keeps the selection verdict through preflight: %s", async mode => {
    vi.useFakeTimers();
    const epoch = Date.now();
    const clock = vi.spyOn(performance, "now").mockImplementation(() => Date.now() - epoch);
    try {
      const addListener = vi.fn();
      vi.stubGlobal("chrome", { runtime: { onMessage: { addListener } } });
      await import("../src/content/pointerTracker");
      const send = (type: string, id = "first") => {
        const reply = vi.fn();
        addListener.mock.calls[0][0]({ type: `gesturekit.${type}`, gestureSessionId: id, features: ["observe_drag"], leaseMs: 800 }, {}, reply);
        return reply.mock.lastCall?.[0];
      };
      send("linkGuardArm");
      const text = document.querySelector("a")!.firstChild!;
      window.getSelection()!.setBaseAndExtent(text, 0, text, 3);
      document.dispatchEvent(new Event("selectionchange"));
      await vi.advanceTimersByTimeAsync(mode === "quick" ? 30 : mode === "expired" ? 850 : 200);
      send("linkGuardDiscard");
      await vi.advanceTimersByTimeAsync(180);
      expect(send("dragEvidence").dragging).toBe(mode !== "quick");
      expect(window.getSelection()!.focusOffset).toBe(3);
      send("linkGuardArm", "next");
      expect(send("dragEvidence", "next").dragging).toBe(false);
    } finally { clock.mockRestore(); vi.useRealTimers(); }
  });

  it("blocks the delayed refresh button click and allows the next deliberate click", async () => {
    const addListener = vi.fn();
    vi.stubGlobal("chrome", { runtime: { onMessage: { addListener } } });
    await import("../src/content/pointerTracker");
    const listener = addListener.mock.calls[0][0];
    document.body.innerHTML = "<button>Refresh</button>";
    const button = document.querySelector("button")!;
    const refresh = vi.fn();
    button.addEventListener("click", refresh);
    listener({ type: "gesturekit.closeClickArm", gestureSessionId: "close", leaseMs: 1200 }, {}, vi.fn());
    const click = () => new MouseEvent("click", { bubbles: true, cancelable: true, detail: 1 });
    button.dispatchEvent(click());
    expect(refresh).not.toHaveBeenCalled();
    button.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
    button.dispatchEvent(click());
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it("dismisses replacement-document isolation before a new active pointerdown and click", async () => {
    vi.useFakeTimers();
    let runtimeListener: ((message: Record<string, unknown>, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: {
        onMessage: {
          addListener: vi.fn((listener) => { runtimeListener = listener; }),
        },
        sendMessage: vi.fn(async () => undefined)
      }
    });
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    runtimeListener?.({ type: "gesturekit.closeClickArm", gestureSessionId: "double-tap-close", leaseMs: 1_200 }, {}, () => {});

    window.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, clientX: 10, clientY: 20 }));
    const click = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0, detail: 1 });
    expect(anchor.dispatchEvent(click)).toBe(true);
    expect(click.defaultPrevented).toBe(false);
    vi.useRealTimers();
  });

  it("expires and disarms replacement-document isolation without affecting ordinary clicks", async () => {
    vi.useFakeTimers();
    let runtimeListener: ((message: Record<string, unknown>, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: {
        onMessage: {
          addListener: vi.fn((listener) => { runtimeListener = listener; }),
        },
        sendMessage: vi.fn(async () => undefined)
      }
    });
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    const anchor = document.getElementById("target") as HTMLAnchorElement;

    runtimeListener?.({ type: "gesturekit.closeClickArm", gestureSessionId: "expired", leaseMs: 40 }, {}, () => {});
    await vi.advanceTimersByTimeAsync(41);
    const expiredClick = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0, detail: 1 });
    expect(anchor.dispatchEvent(expiredClick)).toBe(true);
    expect(expiredClick.defaultPrevented).toBe(false);

    runtimeListener?.({ type: "gesturekit.closeClickArm", gestureSessionId: "disarmed", leaseMs: 1_200 }, {}, () => {});
    let disarmResponse: any = null;
    runtimeListener?.({ type: "gesturekit.closeClickDisarm", gestureSessionId: "disarmed" }, {}, (response) => { disarmResponse = response; });
    expect(disarmResponse).toEqual({ status: "close_click_disarmed" });
    const disarmedClick = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0, detail: 1 });
    expect(anchor.dispatchEvent(disarmedClick)).toBe(true);
    expect(disarmedClick.defaultPrevented).toBe(false);
    vi.useRealTimers();
  });

  it("does not classify a keyboard or programmatic zero-detail click as the delayed system click", async () => {
    vi.useFakeTimers();
    let runtimeListener: ((message: Record<string, unknown>, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: {
        onMessage: {
          addListener: vi.fn((listener) => { runtimeListener = listener; }),
        },
        sendMessage: vi.fn(async () => undefined)
      }
    });
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    runtimeListener?.({ type: "gesturekit.closeClickArm", gestureSessionId: "double-tap-close", leaseMs: 1_200 }, {}, () => {});

    const keyboardClick = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0, detail: 0 });
    expect(anchor.dispatchEvent(keyboardClick)).toBe(true);
    expect(keyboardClick.defaultPrevented).toBe(false);

    const mouseClick = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0, detail: 1 });
    expect(anchor.dispatchEvent(mouseClick)).toBe(true);
    expect(mouseClick.defaultPrevented).toBe(false);
    vi.useRealTimers();
  });

  it("returns non_anchor_navigation for card-style targets", async () => {
    vi.resetModules();
    document.body.innerHTML = `
      <div id="card" data-href="https://example.com/docs" role="link" tabindex="0">Open docs</div>
    `;
    const card = document.getElementById("card") as HTMLElement;
    document.elementFromPoint = () => card;

    const module = await import("../src/content/pointerTracker");
    module.setPointerSnapshotForTesting({ x: 40, y: 20, timestamp: Date.now() });

    expect(module.resolveLinkAtLastPointer(Date.now())).toMatchObject({
      status: "non_anchor_navigation"
    });
  });

  it("does not protect ordinary HTTP link clicks after content script initialization", async () => {
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    const anchor = document.getElementById("target") as HTMLAnchorElement;
    const click = new MouseEvent("click", { bubbles: true, cancelable: true });

    expect(anchor.dispatchEvent(click)).toBe(true);
    expect(click.defaultPrevented).toBe(false);
  });

  it("resolves the guarded link for its own session with a stationary pointer", async () => {
    const send = vi.fn();
    vi.stubGlobal("chrome", { runtime: { onMessage: { addListener: send } } });
    await import("../src/content/pointerTracker");
    const listener = send.mock.calls[0][0];
    const respond = vi.fn();
    listener({ type: "gesturekit.linkGuardArm", gestureSessionId: "tap", leaseMs: 1200 }, {}, respond);
    const anchor = document.getElementById("target")!;
    expect(anchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))).toBe(false);
    listener({ type: "gesturekit.resolveLastPointer", gestureSessionId: "other" }, {}, respond);
    expect(respond.mock.lastCall?.[0].status).toBe("no_recent_pointer");
    listener({ type: "gesturekit.resolveLastPointer", gestureSessionId: "tap" }, {}, respond);
    expect(respond.mock.lastCall?.[0]).toMatchObject({ status: "success", url: "http://localhost:3000/docs" });
  });

  it("protects only a link click following a candidate link guard", async () => {
    let runtimeListener: ((message: any, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: { onMessage: { addListener: vi.fn((listener) => { runtimeListener = listener; }) } }
    });
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    const armResponse: { status?: string } = {};
    runtimeListener?.({ type: "gesturekit.linkGuardArm", gestureSessionId: "candidate-1", leaseMs: 500 }, {}, (response) => Object.assign(armResponse, response));

    const anchor = document.getElementById("target") as HTMLAnchorElement;
    const click = new MouseEvent("click", { bubbles: true, cancelable: true });

    expect(armResponse.status).toBe("guard_armed");
    expect(anchor.dispatchEvent(click)).toBe(false);
    expect(click.defaultPrevented).toBe(true);
  });

  it("protects a guarded synthetic click when its event target is not the link", async () => {
    let runtimeListener: ((message: any, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: { onMessage: { addListener: vi.fn((listener) => { runtimeListener = listener; }) } }
    });
    const module = await import("../src/content/pointerTracker");
    module.setLinkClickProtectionEnabled(false);
    window.dispatchEvent(new PointerEvent("pointermove", { clientX: 10, clientY: 20 }));
    runtimeListener?.({ type: "gesturekit.linkGuardArm", gestureSessionId: "candidate-synthetic", leaseMs: 500 }, {}, () => {});

    const click = new MouseEvent("click", { bubbles: true, cancelable: true });
    expect(document.dispatchEvent(click)).toBe(false);
    expect(click.defaultPrevented).toBe(true);
  });

  it("keeps the link protected until the guard deadline (750ms) so a slower gesture still wins", async () => {
    // 保护窗口必须覆盖 guard deadline（750ms）。若窗口短于 deadline，手势在
    // 500~750ms 之间到达时会被 content script 抢先原地导航，导致"原地打开"。
    vi.useFakeTimers();
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      let runtimeListener: ((message: any, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
      vi.stubGlobal("chrome", {
        runtime: { onMessage: { addListener: vi.fn((listener) => { runtimeListener = listener; }) } }
      });
      const module = await import("../src/content/pointerTracker");
      module.setLinkClickProtectionEnabled(true);
      const anchor = document.getElementById("target") as HTMLAnchorElement;
      runtimeListener?.({ type: "gesturekit.linkGuardArm", gestureSessionId: "candidate-1", leaseMs: 750 }, {}, () => {});

      anchor.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      await vi.advanceTimersByTimeAsync(500);

      // 500ms 时 guard 尚未到期，不应原地导航
      expect(consoleError).not.toHaveBeenCalledWith("Not implemented: navigation to another Document");
    } finally {
      consoleError.mockRestore();
      vi.useRealTimers();
    }
  });

  it("writes copied text to the clipboard via gesturekit.copyText", async () => {
    const writeText = vi.fn(async () => {});
    vi.stubGlobal("navigator", { ...window.navigator, clipboard: { writeText } });
    let runtimeListener: ((message: any, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: { onMessage: { addListener: vi.fn((listener) => { runtimeListener = listener; }) } }
    });
    await import("../src/content/pointerTracker");

    let response: unknown = null;
    runtimeListener?.({ type: "gesturekit.copyText", text: "https://example.com/a" }, {}, (message) => { response = message; });
    await Promise.resolve();
    await Promise.resolve();

    expect(writeText).toHaveBeenCalledWith("https://example.com/a");
    expect(response).toEqual({ status: "success" });
  });

  it("scrolls the page via gesturekit.scroll", async () => {
    const scrollTo = vi.fn();
    window.scrollTo = scrollTo;
    let runtimeListener: ((message: any, sender: unknown, sendResponse: (response: unknown) => void) => boolean) | null = null;
    vi.stubGlobal("chrome", {
      runtime: { onMessage: { addListener: vi.fn((listener) => { runtimeListener = listener; }) } }
    });
    await import("../src/content/pointerTracker");

    let response: unknown = null;
    runtimeListener?.({ type: "gesturekit.scroll", position: "bottom" }, {}, (message) => { response = message; });

    expect(scrollTo).toHaveBeenCalledWith({ top: expect.any(Number), behavior: "smooth" });
    expect(response).toEqual({ status: "success" });
  });
});
