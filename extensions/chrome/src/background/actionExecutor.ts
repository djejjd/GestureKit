import type { ActionStatus, ActionType } from "../protocol/messages";
import type { StandardActionID } from "../provider/protocol";
import type { ChromeApi } from "./chromeApi";

type ActionIntent =
  | { action: "open_link_background"; url: string }
  | { action: "activate_left_tab" }
  | { action: "activate_right_tab" }
  | { action: "close_tab" };

export type ActionExecutionResult = {
  action: ActionType;
  status: ActionStatus;
  details?: Record<string, unknown>;
};

export type StandardActionExecutionResult = { status: "success" | "page_unavailable" | "edge_reached" };

/**
 * 执行 v2 标准动作；链接 URL 仅由调用方从本地 opaque targetRef 解析。
 * @param parameters 动作参数（如 scroll_to_top_bottom 的 position: top|bottom）
 */
export async function executeStandardAction(
  api: ChromeApi,
  actionId: StandardActionID,
  targetURL?: string,
  parameters?: Record<string, string>
): Promise<StandardActionExecutionResult> {
  if (actionId === "browser.link.open_adjacent") {
    if (!targetURL) return { status: "page_unavailable" };
    return standardResult(await openLinkBackground(api, targetURL));
  }
  if (actionId === "browser.tab.activate_previous") return standardResult(await activateAdjacentTab(api, "left"));
  if (actionId === "browser.tab.activate_next") return standardResult(await activateAdjacentTab(api, "right"));
  if (actionId === "browser.tab.close_current") return standardResult(await closeActiveTab(api));
  if (actionId === "browser.link.copy") {
    if (!targetURL) return { status: "page_unavailable" };
    return copyToActiveTab(api, targetURL);
  }

  const activeTab = await getActiveTab(api);
  if (!activeTab?.id) return { status: "page_unavailable" };

  if (actionId === "browser.history.back") await api.tabs.goBack(activeTab.id);
  else if (actionId === "browser.history.forward") await api.tabs.goForward(activeTab.id);
  else if (actionId === "browser.page.reload") await api.tabs.reload(activeTab.id);
  else if (actionId === "browser.tab.open_new") return openNewTab(api, activeTab.windowId);
  else if (actionId === "browser.tab.pin") return setTabPinned(api, activeTab.id, true);
  else if (actionId === "browser.tab.unpin") return setTabPinned(api, activeTab.id, false);
  else if (actionId === "browser.tab.toggle_mute") return toggleTabMute(api, activeTab);
  else if (actionId === "browser.tab.close_others") return closeOtherTabs(api, activeTab);
  else if (actionId === "browser.tab.restore") return restoreLastClosedTab(api);
  else if (actionId === "browser.page.copy_url") {
    if (!activeTab.url) return { status: "page_unavailable" };
    return copyToActiveTab(api, activeTab.url);
  } else if (actionId === "browser.page.scroll_top_bottom") {
    return scrollActiveTab(api, activeTab.id, parameters?.position);
  }
  return { status: "success" };
}

function standardResult(result: ActionExecutionResult): StandardActionExecutionResult {
  return result.status === "success" ? { status: "success" } : { status: result.status === "edge_reached" ? "edge_reached" : "page_unavailable" };
}

const openerTabByOpenedTab = new Map<number, number>();

export async function executeGestureAction(api: ChromeApi, intent: ActionIntent): Promise<ActionExecutionResult> {
  if (intent.action === "open_link_background") {
    return openLinkBackground(api, intent.url);
  }
  if (intent.action === "activate_left_tab") {
    return activateAdjacentTab(api, "left");
  }
  if (intent.action === "activate_right_tab") {
    return activateAdjacentTab(api, "right");
  }
  return closeActiveTab(api);
}

async function openLinkBackground(api: ChromeApi, urlValue: string): Promise<ActionExecutionResult> {
  const url = parseAllowedURL(urlValue);
  if (!url) {
    return { action: "open_link_background", status: "unsupported_url_scheme" };
  }

  const activeTab = await getActiveTab(api);
  if (!activeTab?.id || activeTab.index === undefined || activeTab.windowId === undefined) {
    return { action: "open_link_background", status: "page_unavailable" };
  }

  const created = await api.tabs.create({
    url: url.toString(),
    active: true,
    index: activeTab.index + 1,
    windowId: activeTab.windowId
  });
  if (created.id !== undefined && activeTab.id !== undefined) {
    openerTabByOpenedTab.set(created.id, activeTab.id);
  }
  return { action: "open_link_background", status: "success" };
}

async function activateAdjacentTab(api: ChromeApi, direction: "left" | "right"): Promise<ActionExecutionResult> {
  const activeTab = await getActiveTab(api);
  const action: ActionType = direction === "left" ? "activate_left_tab" : "activate_right_tab";
  if (!activeTab?.id || activeTab.index === undefined || activeTab.windowId === undefined) {
    return { action, status: "page_unavailable" };
  }

  const tabs = (await api.tabs.query({ currentWindow: true }))
    .filter((tab) => tab.windowId === activeTab.windowId && tab.id !== undefined && tab.index !== undefined)
    .sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
  if (tabs.length === 0) {
    return { action, status: "edge_reached" };
  }

  const currentPosition = tabs.findIndex((tab) => tab.id === activeTab.id);
  if (currentPosition < 0) {
    return { action, status: "page_unavailable" };
  }

  const offset = direction === "left" ? -1 : 1;
  const targetPosition = (currentPosition + offset + tabs.length) % tabs.length;
  const target = tabs[targetPosition];
  if (!target?.id) {
    return { action, status: "edge_reached" };
  }

  await api.tabs.update(target.id, { active: true });
  return { action, status: "success", details: { targetIndex: target.index } };
}

async function getActiveTab(api: ChromeApi): Promise<chrome.tabs.Tab | undefined> {
  const [tab] = await api.tabs.query({ active: true, lastFocusedWindow: true });
  return tab;
}

async function closeActiveTab(api: ChromeApi): Promise<ActionExecutionResult> {
  const activeTab = await getActiveTab(api);
  if (!activeTab?.id || activeTab.index === undefined || activeTab.windowId === undefined) {
    return { action: "close_tab", status: "page_unavailable" };
  }

  const target = await preferredTabAfterClose(api, activeTab);
  if (target?.id !== undefined) {
    await api.tabs.update(target.id, { active: true });
  }
  await api.tabs.remove(activeTab.id);
  openerTabByOpenedTab.delete(activeTab.id);
  return { action: "close_tab", status: "success" };
}

async function preferredTabAfterClose(api: ChromeApi, activeTab: chrome.tabs.Tab): Promise<chrome.tabs.Tab | null> {
  const tabs = (await api.tabs.query({ currentWindow: true }))
    .filter((tab) => tab.windowId === activeTab.windowId && tab.id !== undefined && tab.index !== undefined && tab.id !== activeTab.id)
    .sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
  if (tabs.length === 0) {
    return null;
  }

  const openerId = openerTabByOpenedTab.get(activeTab.id!);
  const opener = openerId === undefined ? null : tabs.find((tab) => tab.id === openerId) ?? null;
  if (opener) {
    return opener;
  }

  const left = [...tabs].reverse().find((tab) => (tab.index ?? 0) < (activeTab.index ?? 0));
  if (left) {
    return left;
  }
  return tabs.find((tab) => (tab.index ?? 0) > (activeTab.index ?? 0)) ?? null;
}

function parseAllowedURL(value: string): URL | null {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:" ? url : null;
  } catch {
    return null;
  }
}

// ---------- V2.5 新增标准动作实现 ----------

/** 在当前窗口打开一个新标签页（激活）。 */
async function openNewTab(api: ChromeApi, windowId?: number): Promise<StandardActionExecutionResult> {
  try {
    await api.tabs.create({ active: true, ...(windowId !== undefined ? { windowId } : {}) });
    return { status: "success" };
  } catch {
    return { status: "page_unavailable" };
  }
}

/** 固定/取消固定指定标签页。 */
async function setTabPinned(api: ChromeApi, tabId: number, pinned: boolean): Promise<StandardActionExecutionResult> {
  try {
    await api.tabs.update(tabId, { pinned });
    return { status: "success" };
  } catch {
    return { status: "page_unavailable" };
  }
}

/** 静音/取消静音当前标签页。 */
async function toggleTabMute(api: ChromeApi, tab: chrome.tabs.Tab): Promise<StandardActionExecutionResult> {
  const currentlyMuted = Boolean(tab.mutedInfo?.muted);
  try {
    await api.tabs.update(tab.id!, { muted: !currentlyMuted });
    return { status: "success" };
  } catch {
    return { status: "page_unavailable" };
  }
}

/** 关闭当前窗口内除活动标签（及固定标签）外的其他标签。 */
async function closeOtherTabs(api: ChromeApi, activeTab: chrome.tabs.Tab): Promise<StandardActionExecutionResult> {
  const tabs = await api.tabs.query({ currentWindow: true });
  const toClose = tabs
    .filter((tab) => tab.windowId === activeTab.windowId && tab.id !== undefined && tab.id !== activeTab.id && !tab.pinned)
    .map((tab) => tab.id!);
  if (toClose.length === 0) return { status: "success" };
  try {
    await api.tabs.remove(toClose);
    return { status: "success" };
  } catch {
    return { status: "page_unavailable" };
  }
}

/** 恢复最近关闭的标签页（chrome.sessions.restore，需要 "sessions" 权限）。 */
async function restoreLastClosedTab(api: ChromeApi): Promise<StandardActionExecutionResult> {
  try {
    await api.sessions.restore();
    return { status: "success" };
  } catch {
    return { status: "page_unavailable" };
  }
}

/** 通过活动标签页的 content script 将文本写入剪贴板。 */
async function copyToActiveTab(api: ChromeApi, text: string): Promise<StandardActionExecutionResult> {
  const activeTab = await getActiveTab(api);
  if (!activeTab?.id) return { status: "page_unavailable" };
  try {
    const response = await api.tabs.sendMessage(activeTab.id, {
      type: "gesturekit.copyText",
      text
    }) as { status?: string };
    return response?.status === "success" ? { status: "success" } : { status: "page_unavailable" };
  } catch {
    return { status: "page_unavailable" };
  }
}

/** 通过活动标签页的 content script 滚动到顶部/底部。 */
async function scrollActiveTab(api: ChromeApi, tabId: number, position?: string): Promise<StandardActionExecutionResult> {
  try {
    const response = await api.tabs.sendMessage(tabId, {
      type: "gesturekit.scroll",
      position: position === "bottom" ? "bottom" : "top"
    }) as { status?: string };
    return response?.status === "success" ? { status: "success" } : { status: "page_unavailable" };
  } catch {
    return { status: "page_unavailable" };
  }
}
