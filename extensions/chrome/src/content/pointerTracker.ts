import { resolveLinkAtPoint } from "./linkResolver";
import { GESTURE_SETTINGS_STORAGE_KEY, normalizeGestureSettings } from "../settings/gestureSettings";

export type PointerSnapshot = {
  x: number;
  y: number;
  timestamp: number;
};

const MAX_POINTER_AGE_MS = 1500;
const CONSUME_CLICK_WINDOW_MS = 1000;
const LINK_CLICK_PROTECTION_WINDOW_MS = 180;

type PointerTrackerState = {
  lastPointer: PointerSnapshot | null;
  pendingConsumedClick: { url: string; expiresAt: number } | null;
  lastLinkClick: { url: string; timestamp: number } | null;
  protectedLinkClick: { url: string; timestamp: number; timeout: ReturnType<typeof setTimeout> } | null;
  expiredProtectedClick: { url: string; timestamp: number } | null;
  linkClickProtectionEnabled: boolean;
};

const state = sharedState();

type ResolveOptions = {
  consumeNextClick?: boolean;
};

window.addEventListener(
  "pointermove",
  (event) => {
    state.lastPointer = {
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
    const target = event.target instanceof Element ? event.target : null;
    const anchor = target?.closest("a[href]") as HTMLAnchorElement | null;

    if (!state.pendingConsumedClick || Date.now() > state.pendingConsumedClick.expiresAt) {
      state.pendingConsumedClick = null;
    } else if (anchor?.href === state.pendingConsumedClick.url) {
      state.pendingConsumedClick = null;
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    if (!anchor?.href) {
      return;
    }

    if (shouldProtectLinkClick(event, anchor)) {
      protectLinkClick(event, anchor.href);
      return;
    }

    state.lastLinkClick = {
      url: anchor.href,
      timestamp: Date.now()
    };
  },
  { capture: true }
);

export function resolveLinkAtLastPointer(now: number = Date.now(), options: ResolveOptions = {}) {
  if (options.consumeNextClick) {
    const protectedResult = consumeProtectedLinkClick(now);
    if (protectedResult) {
      return protectedResult;
    }
    const expiredProtectedResult = consumeExpiredProtectedLinkClick(now);
    if (expiredProtectedResult) {
      return expiredProtectedResult;
    }
  }

  if (!state.lastPointer) {
    return { status: "no_recent_pointer", detail: "暂无指针位置（页面加载后鼠标未移动）" };
  }
  if (now - state.lastPointer.timestamp > MAX_POINTER_AGE_MS) {
    const age = now - state.lastPointer.timestamp;
    return {
      status: "no_recent_pointer",
      detail: `指针已过期 ${age}ms（阈值 ${MAX_POINTER_AGE_MS}ms），最后位置 (${state.lastPointer.x.toFixed(0)},${state.lastPointer.y.toFixed(0)})`
    };
  }

  const result = resolveLinkAtPoint(state.lastPointer.x, state.lastPointer.y);
  if (options.consumeNextClick && result.status === "success") {
    const lastClickAge = state.lastLinkClick ? now - state.lastLinkClick.timestamp : -1;
    const urlMatch = state.lastLinkClick?.url === result.url;
    const clickAlreadyFired = urlMatch && lastClickAge >= 0 && lastClickAge <= CONSUME_CLICK_WINDOW_MS;
    state.pendingConsumedClick = {
      url: result.url,
      expiresAt: now + CONSUME_CLICK_WINDOW_MS
    };
    if (clickAlreadyFired) {
      const detail = [
        `点击已先触发：protection=${state.linkClickProtectionEnabled ? "ON" : "OFF"}`,
        `clickAge=${lastClickAge}ms`,
        `url=${result.url.slice(0, 60)}`
      ].join(" ");
      return { ...result, clickAlreadyFired: true, detail };
    }
  }
  return result;
}

function consumeProtectedLinkClick(now: number) {
  if (!state.protectedLinkClick || now - state.protectedLinkClick.timestamp > LINK_CLICK_PROTECTION_WINDOW_MS) {
    return null;
  }
  const url = state.protectedLinkClick.url;
  clearTimeout(state.protectedLinkClick.timeout);
  state.protectedLinkClick = null;
  return { status: "success" as const, url, clickProtected: true };
}

function consumeExpiredProtectedLinkClick(now: number) {
  if (!state.expiredProtectedClick || now - state.expiredProtectedClick.timestamp > CONSUME_CLICK_WINDOW_MS) {
    return null;
  }
  const url = state.expiredProtectedClick.url;
  state.expiredProtectedClick = null;
  return { status: "success" as const, url, clickAlreadyFired: true };
}

export function setLinkClickProtectionEnabled(enabled: boolean) {
  resetTransientClickState();
  state.linkClickProtectionEnabled = enabled;
}

function shouldProtectLinkClick(event: MouseEvent, anchor: HTMLAnchorElement): boolean {
  return state.linkClickProtectionEnabled &&
    event.cancelable &&
    !event.defaultPrevented &&
    event.button === 0 &&
    !event.metaKey &&
    !event.ctrlKey &&
    !event.shiftKey &&
    !event.altKey &&
    isHttpLink(anchor.href) &&
    !anchor.download &&
    (!anchor.target || anchor.target === "_self");
}

function isHttpLink(urlValue: string): boolean {
  try {
    const url = new URL(urlValue);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

function protectLinkClick(event: MouseEvent, url: string) {
  if (state.protectedLinkClick) {
    clearTimeout(state.protectedLinkClick.timeout);
  }

  event.preventDefault();
  event.stopImmediatePropagation();
  state.protectedLinkClick = {
    url,
    timestamp: Date.now(),
    timeout: setTimeout(() => {
      state.expiredProtectedClick = {
        url,
        timestamp: Date.now()
      };
      state.protectedLinkClick = null;
      window.location.assign(url);
    }, LINK_CLICK_PROTECTION_WINDOW_MS)
  };
}

function resetTransientClickState() {
  if (state.protectedLinkClick) {
    clearTimeout(state.protectedLinkClick.timeout);
  }
  state.pendingConsumedClick = null;
  state.lastLinkClick = null;
  state.protectedLinkClick = null;
  state.expiredProtectedClick = null;
}

export function cancelProtectedClick() {
  if (state.protectedLinkClick) {
    clearTimeout(state.protectedLinkClick.timeout);
    state.protectedLinkClick = null;
  }
}

function sharedState(): PointerTrackerState {
  const key = "__gestureKitPointerTrackerState";
  const target = window as unknown as Record<string, PointerTrackerState | undefined>;
  target[key] ??= {
    lastPointer: null,
    pendingConsumedClick: null,
    lastLinkClick: null,
    protectedLinkClick: null,
    expiredProtectedClick: null,
    linkClickProtectionEnabled: true
  };
  return target[key]!;
}

function syncLinkClickProtectionFromStorage() {
  if (typeof chrome === "undefined" || !chrome.storage?.local) {
    return;
  }
  chrome.storage.onChanged?.addListener((changes, areaName) => {
    if (areaName !== "local" || !changes[GESTURE_SETTINGS_STORAGE_KEY]) {
      return;
    }
    setLinkClickProtectionEnabled(
      normalizeGestureSettings(changes[GESTURE_SETTINGS_STORAGE_KEY].newValue).linkClickProtectionEnabled
    );
  });
}

if (typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
  syncLinkClickProtectionFromStorage();
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message.type === "gesturekit.cancelTap") {
      cancelProtectedClick();
      return false;
    }
    if (message.type !== "gesturekit.resolveLastPointer") {
      return false;
    }

    sendResponse(resolveLinkAtLastPointer(Date.now(), { consumeNextClick: Boolean(message.consumeNextClick) }));
    return false;
  });
}
