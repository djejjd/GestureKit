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

/** 执行 v2 标准动作；链接 URL 仅由调用方从本地 opaque targetRef 解析。 */
export async function executeStandardAction(
  api: ChromeApi,
  actionId: StandardActionID,
  targetURL?: string
): Promise<StandardActionExecutionResult> {
  if (actionId === "browser.link.open_adjacent") {
    if (!targetURL) return { status: "page_unavailable" };
    return standardResult(await openLinkBackground(api, targetURL));
  }
  if (actionId === "browser.tab.activate_previous") return standardResult(await activateAdjacentTab(api, "left"));
  if (actionId === "browser.tab.activate_next") return standardResult(await activateAdjacentTab(api, "right"));
  if (actionId === "browser.tab.close_current") return standardResult(await closeActiveTab(api));
  const activeTab = await getActiveTab(api);
  if (!activeTab?.id) return { status: "page_unavailable" };
  if (actionId === "browser.history.back") await api.tabs.goBack(activeTab.id);
  else if (actionId === "browser.history.forward") await api.tabs.goForward(activeTab.id);
  else await api.tabs.reload(activeTab.id);
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
    active: false,
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
