import { describe, expect, it, vi } from "vitest";
import { restoreContentScripts } from "../src/background/contentRestore";

describe("restoring existing pages", () => {
  it("only reinjects missing/old scripts on supported pages, without reloading tabs", async () => {
    const sendMessage = vi.fn(async (id: number) => id === 1 ? { buildId: "new" } : { buildId: "old" });
    const executeScript = vi.fn(async () => []);
    const summary = await restoreContentScripts({
      query: async () => [{ id: 1, url: "https://example.test" }, { id: 2, url: "http://example.test" }, { id: 3, url: "chrome://settings" }],
      sendMessage, executeScript
    }, "new");
    expect(executeScript).toHaveBeenCalledTimes(1);
    expect(executeScript).toHaveBeenCalledWith({ target: { tabId: 2 }, files: ["dist/content/pointerTracker.js"], injectImmediately: true });
    expect(summary).toEqual({ checked: 2, restored: 1, failed: 0 });
  });
  it("contains injection failure to one tab and continues restoring the next", async () => {
    const executeScript = vi.fn().mockRejectedValueOnce(Error("restricted")).mockResolvedValueOnce([]);
    const summary = await restoreContentScripts({
      query: async () => [{ id: 1, url: "https://example.test" }, { id: 2, url: "https://example.test" }],
      sendMessage: async () => { throw Error("no receiver"); }, executeScript
    }, "new");
    expect(summary).toEqual({ checked: 2, restored: 1, failed: 1 });
  });
});
