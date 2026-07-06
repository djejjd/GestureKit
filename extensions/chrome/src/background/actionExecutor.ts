import type { ActionStatus, ActionType } from "../protocol/messages";
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

  await api.tabs.create({
    url: url.toString(),
    active: true,
    index: activeTab.index + 1,
    windowId: activeTab.windowId
  });
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
  if (!activeTab?.id) {
    return { action: "close_tab", status: "page_unavailable" };
  }

  await api.tabs.remove(activeTab.id);
  return { action: "close_tab", status: "success" };
}

function parseAllowedURL(value: string): URL | null {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:" ? url : null;
  } catch {
    return null;
  }
}
