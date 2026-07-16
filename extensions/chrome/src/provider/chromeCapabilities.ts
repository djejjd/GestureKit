import type { StandardActionID } from "./protocol";

/** Chrome Provider 当前实际实现的标准动作集合。 */
export const ChromeProviderCapabilities = {
  standard: [
    "browser.link.open_adjacent",
    "browser.tab.activate_previous",
    "browser.tab.activate_next",
    "browser.tab.close_current",
    "browser.history.back",
    "browser.history.forward",
    "browser.page.reload"
  ] as const satisfies readonly StandardActionID[]
};
