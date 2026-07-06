import { resolveLinkAtPoint } from "./linkResolver";

export type PointerSnapshot = {
  x: number;
  y: number;
  timestamp: number;
};

const MAX_POINTER_AGE_MS = 1500;
const CONSUME_CLICK_WINDOW_MS = 1000;
let lastPointer: PointerSnapshot | null = null;
let pendingConsumedClick: { url: string; expiresAt: number } | null = null;

type ResolveOptions = {
  consumeNextClick?: boolean;
};

window.addEventListener(
  "pointermove",
  (event) => {
    lastPointer = {
      x: event.clientX,
      y: event.clientY,
      timestamp: Date.now()
    };
  },
  { passive: true }
);

window.addEventListener(
  "click",
  (event) => {
    if (!pendingConsumedClick || Date.now() > pendingConsumedClick.expiresAt) {
      pendingConsumedClick = null;
      return;
    }

    const target = event.target instanceof Element ? event.target : null;
    const anchor = target?.closest("a[href]") as HTMLAnchorElement | null;
    if (!anchor || anchor.href !== pendingConsumedClick.url) {
      return;
    }

    pendingConsumedClick = null;
    event.preventDefault();
    event.stopImmediatePropagation();
  },
  { capture: true }
);

export function resolveLinkAtLastPointer(now: number = Date.now(), options: ResolveOptions = {}) {
  if (!lastPointer || now - lastPointer.timestamp > MAX_POINTER_AGE_MS) {
    return { status: "no_recent_pointer" as const };
  }

  const result = resolveLinkAtPoint(lastPointer.x, lastPointer.y);
  if (options.consumeNextClick && result.status === "success") {
    pendingConsumedClick = {
      url: result.url,
      expiresAt: now + CONSUME_CLICK_WINDOW_MS
    };
  }
  return result;
}

if (typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message.type !== "gesturekit.resolveLastPointer") {
      return false;
    }

    sendResponse(resolveLinkAtLastPointer(Date.now(), { consumeNextClick: Boolean(message.consumeNextClick) }));
    return false;
  });
}
