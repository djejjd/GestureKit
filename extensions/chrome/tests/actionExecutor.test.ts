import { describe, expect, it, vi } from "vitest";
import { executeGestureAction, executeStandardAction } from "../src/background/actionExecutor";
import type { ChromeApi } from "../src/background/chromeApi";

type MockTab = { id: number; index: number; active?: boolean; windowId: number; pinned?: boolean; mutedInfo?: { muted: boolean }; url?: string };

function makeChromeApi(tabs: MockTab[]): ChromeApi {
  return {
    tabs: {
      query: vi.fn(async (queryInfo) => {
        if (queryInfo.active) {
          return tabs.filter((tab) => tab.active);
        }
        if (queryInfo.currentWindow) {
          return tabs;
        }
        return tabs;
      }),
      create: vi.fn(async (createProperties) => {
        const tab = {
          id: 100,
          index: createProperties.index ?? 0,
          active: Boolean(createProperties.active),
          windowId: createProperties.windowId ?? 1
        };
        tabs.push(tab);
        return tab;
      }),
      update: vi.fn(async (tabId, updateProperties) => ({
        id: tabId,
        active: Boolean(updateProperties.active),
        pinned: Boolean(updateProperties.pinned),
        muted: Boolean(updateProperties.muted),
        index: 0,
        windowId: 1
      })),
      remove: vi.fn(async (tabIds) => {
        const ids = Array.isArray(tabIds) ? tabIds : [tabIds];
        for (const id of ids) {
          const index = tabs.findIndex((tab) => tab.id === id);
          if (index >= 0) {
            tabs.splice(index, 1);
          }
        }
      }),
      goBack: vi.fn(async () => {}),
      goForward: vi.fn(async () => {}),
      reload: vi.fn(async () => {}),
      sendMessage: vi.fn(async () => ({ status: "success" }))
    },
    sessions: {
      restore: vi.fn(async () => ({}))
    }
  };
}

describe("executeGestureAction", () => {
  it("maps browser.history.back to Chrome tabs.goBack", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7 }]);

    await expect(executeStandardAction(api, "browser.history.back")).resolves.toEqual({ status: "success" });
    expect(api.tabs.goBack).toHaveBeenCalledWith(10);
  });

  it("opens http link next to active tab in the background", async () => {
    const api = makeChromeApi([{ id: 10, index: 2, active: true, windowId: 7 }]);

    const result = await executeGestureAction(api, {
      action: "open_link_background",
      url: "https://example.com/docs"
    });

    expect(result.status).toBe("success");
    expect(api.tabs.create).toHaveBeenCalledWith({
      url: "https://example.com/docs",
      active: true,
      index: 3,
      windowId: 7
    });
  });

  it("rejects unsupported link scheme", async () => {
    const api = makeChromeApi([{ id: 10, index: 2, active: true, windowId: 7 }]);

    const result = await executeGestureAction(api, {
      action: "open_link_background",
      url: "javascript:alert(1)"
    });

    expect(result.status).toBe("unsupported_url_scheme");
    expect(api.tabs.create).not.toHaveBeenCalled();
  });

  it("wraps left edge to the last tab in the same window", async () => {
    const api = makeChromeApi([
      { id: 10, index: 0, active: true, windowId: 7 },
      { id: 11, index: 1, windowId: 7 },
      { id: 12, index: 2, windowId: 7 }
    ]);

    const result = await executeGestureAction(api, { action: "activate_left_tab" });

    expect(result.status).toBe("success");
    expect(api.tabs.update).toHaveBeenCalledWith(12, { active: true });
  });

  it("activates right tab in same window", async () => {
    const api = makeChromeApi([
      { id: 20, index: 0, windowId: 7 },
      { id: 21, index: 1, active: true, windowId: 7 },
      { id: 22, index: 2, windowId: 7 }
    ]);

    const result = await executeGestureAction(api, { action: "activate_right_tab" });

    expect(result.status).toBe("success");
    expect(api.tabs.update).toHaveBeenCalledWith(22, { active: true });
  });

  it("wraps right edge to the first tab in the same window", async () => {
    const api = makeChromeApi([
      { id: 20, index: 0, windowId: 7 },
      { id: 21, index: 1, active: true, windowId: 7 }
    ]);

    const result = await executeGestureAction(api, { action: "activate_right_tab" });

    expect(result.status).toBe("success");
    expect(api.tabs.update).toHaveBeenCalledWith(20, { active: true });
  });

  it("closes the active tab", async () => {
    const api = makeChromeApi([{ id: 20, index: 0, active: true, windowId: 7 }]);

    const result = await executeGestureAction(api, { action: "close_tab" });

    expect(result.status).toBe("success");
    expect(api.tabs.remove).toHaveBeenCalledWith(20);
  });

  it("returns to the opener tab when closing a GestureKit-opened tab", async () => {
    const api = makeChromeApi([
      { id: 10, index: 0, active: true, windowId: 7 },
      { id: 11, index: 1, windowId: 7 }
    ]);

    await executeGestureAction(api, {
      action: "open_link_background",
      url: "https://example.com/docs"
    });
    const openedTab = await api.tabs.create.mock.results[0].value;
    const tabs = [
      { id: 10, index: 0, windowId: 7 },
      { id: openedTab.id!, index: 1, active: true, windowId: 7 },
      { id: 11, index: 2, windowId: 7 }
    ];
    const closeApi = makeChromeApi(tabs);

    const result = await executeGestureAction(closeApi, { action: "close_tab" });

    expect(result.status).toBe("success");
    expect(closeApi.tabs.update).toHaveBeenCalledWith(10, { active: true });
    expect(closeApi.tabs.remove).toHaveBeenCalledWith(openedTab.id);
  });

  it("activates the left tab before closing when no opener is available", async () => {
    const api = makeChromeApi([
      { id: 10, index: 0, windowId: 7 },
      { id: 11, index: 1, active: true, windowId: 7 },
      { id: 12, index: 2, windowId: 7 }
    ]);

    const result = await executeGestureAction(api, { action: "close_tab" });

    expect(result.status).toBe("success");
    expect(api.tabs.update).toHaveBeenCalledWith(10, { active: true });
    expect(api.tabs.remove).toHaveBeenCalledWith(11);
  });

  it("activates the right tab before closing when the active tab is leftmost", async () => {
    const api = makeChromeApi([
      { id: 10, index: 0, active: true, windowId: 7 },
      { id: 11, index: 1, windowId: 7 },
      { id: 12, index: 2, windowId: 7 }
    ]);

    const result = await executeGestureAction(api, { action: "close_tab" });

    expect(result.status).toBe("success");
    expect(api.tabs.update).toHaveBeenCalledWith(11, { active: true });
    expect(api.tabs.remove).toHaveBeenCalledWith(10);
  });
});

describe("executeStandardAction V2.5 新增动作", () => {
  it("opens a new tab in the active window", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7 }]);

    const result = await executeStandardAction(api, "browser.tab.open_new");

    expect(result.status).toBe("success");
    expect(api.tabs.create).toHaveBeenCalledWith({ active: true, windowId: 7 });
  });

  it("pins the active tab", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7 }]);

    const result = await executeStandardAction(api, "browser.tab.pin");

    expect(result.status).toBe("success");
    expect(api.tabs.update).toHaveBeenCalledWith(10, { pinned: true });
  });

  it("unpins the active tab", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7, pinned: true }]);

    const result = await executeStandardAction(api, "browser.tab.unpin");

    expect(result.status).toBe("success");
    expect(api.tabs.update).toHaveBeenCalledWith(10, { pinned: false });
  });

  it("mutes an unmuted active tab", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7, mutedInfo: { muted: false } }]);

    const result = await executeStandardAction(api, "browser.tab.toggle_mute");

    expect(result.status).toBe("success");
    expect(api.tabs.update).toHaveBeenCalledWith(10, { muted: true });
  });

  it("unmutes a muted active tab", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7, mutedInfo: { muted: true } }]);

    const result = await executeStandardAction(api, "browser.tab.toggle_mute");

    expect(result.status).toBe("success");
    expect(api.tabs.update).toHaveBeenCalledWith(10, { muted: false });
  });

  it("closes all tabs except the active and pinned ones", async () => {
    const api = makeChromeApi([
      { id: 10, index: 0, active: true, windowId: 7 },
      { id: 11, index: 1, windowId: 7 },
      { id: 12, index: 2, windowId: 7, pinned: true },
      { id: 13, index: 3, windowId: 7 }
    ]);

    const result = await executeStandardAction(api, "browser.tab.close_others");

    expect(result.status).toBe("success");
    expect(api.tabs.remove).toHaveBeenCalledWith([11, 13]);
  });

  it("restores the most recently closed tab", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7 }]);

    const result = await executeStandardAction(api, "browser.tab.restore");

    expect(result.status).toBe("success");
    expect(api.sessions.restore).toHaveBeenCalledOnce();
  });

  it("copies the resolved link URL to the clipboard via the active tab content script", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7 }]);

    const result = await executeStandardAction(api, "browser.link.copy", "https://example.com/a");

    expect(result.status).toBe("success");
    expect(api.tabs.sendMessage).toHaveBeenCalledWith(10, { type: "gesturekit.copyText", text: "https://example.com/a" });
  });

  it("returns page_unavailable when copying a link without a resolved URL", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7 }]);

    const result = await executeStandardAction(api, "browser.link.copy");

    expect(result.status).toBe("page_unavailable");
    expect(api.tabs.sendMessage).not.toHaveBeenCalled();
  });

  it("copies the active tab URL to the clipboard", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7, url: "https://example.com/current" }]);

    const result = await executeStandardAction(api, "browser.page.copy_url");

    expect(result.status).toBe("success");
    expect(api.tabs.sendMessage).toHaveBeenCalledWith(10, { type: "gesturekit.copyText", text: "https://example.com/current" });
  });

  it("scrolls to the top by default", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7 }]);

    const result = await executeStandardAction(api, "browser.page.scroll_top_bottom");

    expect(result.status).toBe("success");
    expect(api.tabs.sendMessage).toHaveBeenCalledWith(10, { type: "gesturekit.scroll", position: "top" });
  });

  it("scrolls to the bottom when parameters specify position=bottom", async () => {
    const api = makeChromeApi([{ id: 10, index: 0, active: true, windowId: 7 }]);

    const result = await executeStandardAction(api, "browser.page.scroll_top_bottom", undefined, { position: "bottom" });

    expect(result.status).toBe("success");
    expect(api.tabs.sendMessage).toHaveBeenCalledWith(10, { type: "gesturekit.scroll", position: "bottom" });
  });
});
