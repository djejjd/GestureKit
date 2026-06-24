import type { LinkResolveResult } from "../content/linkResolver";

type ResolveLastPointerResponse =
  | LinkResolveResult
  | { status: "no_recent_pointer" };

type SimulatedGestureMessage = {
  type: "gesturekit.simulateTap";
};

async function resolveActiveTabLink(): Promise<ResolveLastPointerResponse> {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab?.id) {
    return { status: "page_unavailable" };
  }

  const response = await chrome.tabs.sendMessage(tab.id, {
    type: "gesturekit.resolveLastPointer"
  });
  return response as ResolveLastPointerResponse;
}

chrome.runtime.onMessage.addListener(
  (
    message: SimulatedGestureMessage,
    _sender,
    sendResponse: (response: ResolveLastPointerResponse) => void
  ) => {
    if (message.type !== "gesturekit.simulateTap") {
      return false;
    }

    resolveActiveTabLink()
      .then(sendResponse)
      .catch(() => sendResponse({ status: "page_unavailable" }));
    return true;
  }
);
