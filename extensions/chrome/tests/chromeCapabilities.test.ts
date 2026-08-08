import { describe, expect, it } from "vitest";
import { ChromeProviderCapabilities } from "../src/provider/chromeCapabilities";

describe("ChromeProviderCapabilities", () => {
  it("declares every standard action implemented by ChromeProvider", () => {
    expect(ChromeProviderCapabilities.standard).toEqual([
      "browser.link.open_adjacent",
      "browser.tab.activate_previous",
      "browser.tab.activate_next",
      "browser.tab.close_current",
      "browser.history.back",
      "browser.history.forward",
      "browser.page.reload",
      "browser.tab.open_new",
      "browser.tab.pin",
      "browser.tab.unpin",
      "browser.tab.toggle_mute",
      "browser.tab.close_others",
      "browser.tab.restore",
      "browser.link.copy",
      "browser.page.copy_url",
      "browser.page.scroll_top_bottom"
    ]);
    expect(new Set(ChromeProviderCapabilities.standard).size).toBe(16);
  });
});
