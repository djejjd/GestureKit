import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("candidate drag protection", () => {
  let listeners: [string, EventListenerOrEventListenerObject, boolean | AddEventListenerOptions | undefined][];
  let receive: (message: any, sender: any, respond: (value: any) => void) => void;
  beforeEach(async () => {
    vi.resetModules();
    listeners = [];
    const add = window.addEventListener.bind(window);
    vi.spyOn(window, "addEventListener").mockImplementation((type, listener, options) => {
      listeners.push([type, listener, options]);
      add(type, listener, options);
    });
    document.body.innerHTML = `<a id="link" href="/target">Link<img id="image" src="/image.png"></a><p id="text">Text</p>`;
    vi.stubGlobal("chrome", {
      runtime: {
        onMessage: { addListener: (handler: typeof receive) => { receive = handler; } },
        sendMessage: vi.fn().mockResolvedValue(undefined)
      },
      storage: { local: { get: vi.fn().mockResolvedValue({}) }, onChanged: { addListener: vi.fn() } }
    });
    await import("../src/content/pointerTracker");
  });
  afterEach(() => {
    for (const [type, listener, options] of listeners) window.removeEventListener(type, listener, options);
    vi.unstubAllGlobals(); vi.restoreAllMocks();
  });
  function arm(leaseMs = 800, features = ["drag_selection"]) {
    receive({ type: "gesturekit.linkGuardArm", gestureSessionId: "swipe", leaseMs, features }, {}, () => {});
  }
  function eventOn(id: string, type: string) {
    const event = new Event(type, { bubbles: true, cancelable: true });
    document.getElementById(id)!.dispatchEvent(event);
    return event;
  }
  it.each(["link", "image", "text"])("blocks dragstart on %s only during a matching lease", (id) => {
    expect(eventOn(id, "dragstart").defaultPrevented).toBe(false);
    arm();
    expect(eventOn(id, "dragstart").defaultPrevented).toBe(true);
    receive({ type: "gesturekit.linkGuardDiscard", gestureSessionId: "other" }, {}, () => {});
    expect(eventOn(id, "dragstart").defaultPrevented).toBe(true);
    receive({ type: "gesturekit.linkGuardDiscard", gestureSessionId: "swipe" }, {}, () => {});
    expect(eventOn(id, "dragstart").defaultPrevented).toBe(false);
  });
  it("blocks selection during candidate and restores after expiration", () => {
    const now = vi.spyOn(performance, "now").mockReturnValue(0);
    arm();
    expect(eventOn("text", "selectstart").defaultPrevented).toBe(true);
    now.mockReturnValue(801);
    expect(eventOn("text", "selectstart").defaultPrevented).toBe(false);
  });
  it("discards a click arriving after swipe classification without navigating or leaving a reusable guard", () => {
    const now = vi.spyOn(performance, "now").mockReturnValue(0);
    arm();
    receive({ type: "gesturekit.linkGuardDiscard", gestureSessionId: "swipe" }, {}, () => {});
    now.mockReturnValue(10);
    const click = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 });
    document.getElementById("link")!.dispatchEvent(click);
    expect(click.defaultPrevented).toBe(true);
    now.mockReturnValue(121);
    const ordinary = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 });
    let reachedTarget = false;
    document.getElementById("link")!.addEventListener("click", event => {
      reachedTarget = true;
      event.preventDefault(); // jsdom 无真实导航；先验证生产捕获监听器已放行。
    }, { once: true });
    document.getElementById("link")!.dispatchEvent(ordinary);
    expect(reachedTarget).toBe(true);
  });

  it("keeps a link guard alive through a 450ms tap, arbitration and delayed preflight, then expires", () => {
    const now = vi.spyOn(performance, "now").mockReturnValue(0);
    arm(1200, ["link_click", "drag_selection"]);
    now.mockReturnValue(450 + 300 + 300);
    let response: any;
    receive({ type: "gesturekit.guardConsume", gestureSessionId: "swipe", url: "http://localhost:3000/target" }, {}, value => { response = value; });
    expect(response.status).toBe("guard_consumed");
    now.mockReturnValue(2000); arm(1200, ["link_click"]);
    now.mockReturnValue(3201);
    receive({ type: "gesturekit.guardConsume", gestureSessionId: "swipe" }, {}, value => { response = value; });
    expect(response.status).toBe("guard_unavailable");
  });

  it("does not turn link-only guard into a drag blocker", () => {
    arm(800, ["link_click"]);
    expect(eventOn("image", "dragstart").defaultPrevented).toBe(false);
  });
});
