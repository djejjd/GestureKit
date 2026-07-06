import { describe, expect, it, vi } from "vitest";
import { executeGestureAction } from "../src/background/actionExecutor";
import type { ChromeApi } from "../src/background/chromeApi";

function makeChromeApi(tabs: Array<{ id: number; index: number; active?: boolean; windowId: number }>): ChromeApi {
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
      create: vi.fn(async (createProperties) => ({
        id: 100,
        index: createProperties.index ?? 0,
        windowId: createProperties.windowId ?? 1
      })),
      update: vi.fn(async (tabId, updateProperties) => ({
        id: tabId,
        active: Boolean(updateProperties.active),
        index: 0,
        windowId: 1
      })),
      remove: vi.fn(async () => {})
    }
  };
}

describe("executeGestureAction", () => {
  it("opens http link next to active tab and activates it", async () => {
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
});
