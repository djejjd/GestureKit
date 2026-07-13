import { describe, expect, it, vi } from "vitest";
import { ChromeProvider } from "../src/provider/chromeProvider";
import type { ChromeApi } from "../src/background/chromeApi";

function makeApi(): ChromeApi {
  return {
    tabs: {
      query: vi.fn(async () => [{ id: 10, index: 1, windowId: 4, active: true }]),
      create: vi.fn(async () => ({ id: 11, index: 2, windowId: 4 })),
      update: vi.fn(async (id) => ({ id })),
      remove: vi.fn(async () => {}),
      goBack: vi.fn(async () => {}),
      goForward: vi.fn(async () => {}),
      reload: vi.fn(async () => {})
    }
  };
}

describe("ChromeProvider", () => {
  it("rejects link action when guard is not armed", async () => {
    const api = makeApi();
    const provider = new ChromeProvider(api, async () => ({ status: "success", url: "https://example.com/a", frameId: 0 }));
    const snapshot = await provider.context({ gestureSessionId: "g-1", deadline: Date.now() + 1_000 });

    await expect(provider.execute({ operationId: "op-1", actionId: "browser.link.open_adjacent", contextId: snapshot.contextId, targetRef: snapshot.targetRef, guardState: "guard_unavailable", deadline: Date.now() + 1_000 })).resolves.toMatchObject({ status: "guard_unavailable" });
    expect(api.tabs.create).not.toHaveBeenCalled();
  });

  it("executes browser.tab.activate_next without a link targetRef", async () => {
    const api = makeApi();
    const provider = new ChromeProvider(api, async () => ({ status: "no_target" }));

    await expect(provider.execute({ operationId: "op-2", actionId: "browser.tab.activate_next", contextId: "unused", deadline: Date.now() + 1_000 })).resolves.toMatchObject({ status: "success" });
    expect(api.tabs.update).toHaveBeenCalled();
  });

  it("expires a link target when the content frame changes", async () => {
    const api = makeApi();
    let frameId = 0;
    const provider = new ChromeProvider(api, async () => ({ status: "success", url: "https://example.com/a", frameId }));
    const snapshot = await provider.context({ gestureSessionId: "g-1", deadline: Date.now() + 1_000 });
    frameId = 3;

    await expect(provider.execute({ operationId: "op-3", actionId: "browser.link.open_adjacent", contextId: snapshot.contextId, targetRef: snapshot.targetRef, guardState: "guard_armed", deadline: Date.now() + 1_000 })).resolves.toMatchObject({ status: "context_expired" });
    expect(api.tabs.create).not.toHaveBeenCalled();
  });
});
