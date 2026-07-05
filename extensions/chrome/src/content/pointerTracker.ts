import { resolveLinkAtPoint } from "./linkResolver";

export type PointerSnapshot = {
  x: number;
  y: number;
  timestamp: number;
};

const MAX_POINTER_AGE_MS = 1500;
let lastPointer: PointerSnapshot | null = null;

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

export function resolveLinkAtLastPointer(now: number = Date.now()) {
  if (!lastPointer || now - lastPointer.timestamp > MAX_POINTER_AGE_MS) {
    return { status: "no_recent_pointer" as const };
  }

  return resolveLinkAtPoint(lastPointer.x, lastPointer.y);
}

if (typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message.type !== "gesturekit.resolveLastPointer") {
      return false;
    }

    sendResponse(resolveLinkAtLastPointer());
    return false;
  });
}
