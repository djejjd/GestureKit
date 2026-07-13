import { describe, expect, it, vi } from "vitest";
import { ChromeProvider } from "../src/provider/chromeProvider";
import type { ChromeApi } from "../src/background/chromeApi";

function makeApi(): ChromeApi {
  return {
    tabs: {
      query: vi.fn(async () => [{ id: 10, index: 1, windowId: 4, active: true, url: "https://example.com/current?secret=raw" }]),
      create: vi.fn(async () => ({ id: 11, index: 2, windowId: 4 })),
      update: vi.fn(async (id) => ({ id })),
      remove: vi.fn(async () => {}),
      goBack: vi.fn(async () => {}),
      goForward: vi.fn(async () => {}),
      reload: vi.fn(async () => {})
    }
  };
}

function bridge(frame = () => 0, guard = () => "guard_consumed") {
  return async (_tabId: number, message: Record<string, unknown>) => {
    if (message.type === "gesturekit.guardArm") return { status: "guard_armed" };
    if (message.type === "gesturekit.guardConsume") return { status: guard() };
    return { status: "success", url: "https://example.com/a", frameId: frame() };
  };
}

describe("ChromeProvider", () => {
  it("rejects link action when guard is not armed", async () => {
    const api = makeApi();
    const provider = new ChromeProvider(api, bridge());
    const snapshot = await provider.context({ gestureSessionId: "g-1", requiresTargetRef: true, deadline: Date.now() + 1_000 });

    await expect(provider.execute({ operationId: "op-1", actionId: "browser.link.open_adjacent", contextId: snapshot.contextId, targetRef: snapshot.targetRef, gestureSessionId: "wrong", deadline: Date.now() + 1_000 })).resolves.toMatchObject({ status: "guard_unavailable" });
    expect(api.tabs.create).not.toHaveBeenCalled();
  });

  it("rejects a released or expired provider guard without opening the link", async () => {
    const api = makeApi();
    const provider = new ChromeProvider(api, bridge(() => 0, () => "guard_expired"));
    const snapshot = await provider.context({ gestureSessionId: "g-1", requiresTargetRef: true, deadline: Date.now() + 1_000 });

    await expect(provider.execute({ operationId: "op-expired", actionId: "browser.link.open_adjacent", contextId: snapshot.contextId, targetRef: snapshot.targetRef, gestureSessionId: "g-1", deadline: Date.now() + 1_000 })).resolves.toMatchObject({ status: "guard_expired" });
    expect(api.tabs.create).not.toHaveBeenCalled();
  });

  it("executes browser.tab.activate_next without a link targetRef", async () => {
    const api = makeApi();
    const provider = new ChromeProvider(api, bridge());
    const deadline = Date.now() + 1_000;
    const snapshot = await provider.context({ gestureSessionId: "g-1", requiresTargetRef: false, deadline });

    await expect(provider.execute({ operationId: "op-2", actionId: "browser.tab.activate_next", contextId: snapshot.contextId, gestureSessionId: "g-1", deadline })).resolves.toMatchObject({ status: "success" });
    expect(api.tabs.update).toHaveBeenCalled();
  });

  it("creates a live tab context and executes a swipe when no recent pointer exists", async () => {
    const api = makeApi();
    const messages: Record<string, unknown>[] = [];
    const provider = new ChromeProvider(api, async (_tabId, message) => {
      messages.push(message);
      return { status: "no_recent_pointer" };
    });
    const deadline = Date.now() + 1_000;

    const snapshot = await provider.context({
      gestureSessionId: "g-swipe-no-pointer",
      deadline,
      requiresTargetRef: false
    });

    expect(snapshot).toMatchObject({
      targetKind: "no_target",
      pageIdentity: "https://example.com/current",
      expiresAt: deadline
    });
    expect(messages).toEqual([]);
    await expect(provider.execute({
      operationId: "op-swipe-no-pointer",
      actionId: "browser.tab.activate_next",
      contextId: snapshot.contextId,
      targetRef: null,
      gestureSessionId: "g-swipe-no-pointer",
      deadline
    })).resolves.toMatchObject({ status: "success" });
    expect(api.tabs.update).toHaveBeenCalled();
  });

  it("expires a link target when the content frame changes", async () => {
    const api = makeApi();
    let frameId = 0;
    const provider = new ChromeProvider(api, bridge(() => frameId));
    const snapshot = await provider.context({ gestureSessionId: "g-1", deadline: Date.now() + 1_000 });
    frameId = 3;

    await expect(provider.execute({ operationId: "op-3", actionId: "browser.link.open_adjacent", contextId: snapshot.contextId, targetRef: snapshot.targetRef, gestureSessionId: "g-1", deadline: Date.now() + 1_000 })).resolves.toMatchObject({ status: "context_expired" });
    expect(api.tabs.create).not.toHaveBeenCalled();
  });

  it("releases the armed guard when context resolution has no target", async () => {
    const api = makeApi();
    const messages: Record<string, unknown>[] = [];
    const provider = new ChromeProvider(api, async (_tabId, message) => {
      messages.push(message);
      if (message.type === "gesturekit.guardArm") return { status: "guard_armed" };
      if (message.type === "gesturekit.guardRelease") return { status: "guard_released" };
      return { status: "no_target" };
    });

    await expect(provider.context({ gestureSessionId: "g-no-target", requiresTargetRef: true, deadline: Date.now() + 1_000 })).resolves.toMatchObject({ targetKind: "no_target" });
    expect(messages).toContainEqual({ type: "gesturekit.guardRelease", gestureSessionId: "g-no-target" });
    expect(api.tabs.create).not.toHaveBeenCalled();
  });

  it("releases an armed guard when link preflight fails before consumption", async () => {
    const api = makeApi();
    let frameId = 0;
    const messages: Record<string, unknown>[] = [];
    const provider = new ChromeProvider(api, async (_tabId, message) => {
      messages.push(message);
      if (message.type === "gesturekit.guardArm") return { status: "guard_armed" };
      if (message.type === "gesturekit.guardRelease") return { status: "guard_released" };
      if (message.type === "gesturekit.guardConsume") return { status: "guard_consumed" };
      return { status: "success", url: "https://example.com/a", frameId };
    });
    const snapshot = await provider.context({ gestureSessionId: "g-frame", requiresTargetRef: true, deadline: Date.now() + 1_000 });
    frameId = 1;

    await expect(provider.execute({ operationId: "op-frame", actionId: "browser.link.open_adjacent", contextId: snapshot.contextId, targetRef: snapshot.targetRef, gestureSessionId: "g-frame", deadline: Date.now() + 1_000 })).resolves.toMatchObject({ status: "context_expired" });
    expect(messages).toContainEqual({ type: "gesturekit.guardRelease", gestureSessionId: "g-frame" });
    expect(messages).not.toContainEqual({ type: "gesturekit.guardConsume", gestureSessionId: "g-frame" });
    expect(api.tabs.create).not.toHaveBeenCalled();
  });
});
