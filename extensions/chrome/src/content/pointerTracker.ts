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
  }

  if (!state.lastPointer || now - state.lastPointer.timestamp > MAX_POINTER_AGE_MS) {
    return { status: "no_recent_pointer" as const };
  }

  const result = resolveLinkAtPoint(state.lastPointer.x, state.lastPointer.y);
  if (options.consumeNextClick && result.status === "success") {
    const clickAlreadyFired = state.lastLinkClick?.url === result.url && now - state.lastLinkClick.timestamp <= CONSUME_CLICK_WINDOW_MS;
    state.pendingConsumedClick = {
      url: result.url,
      expiresAt: now + CONSUME_CLICK_WINDOW_MS
    };
    if (clickAlreadyFired) {
      return { ...result, clickAlreadyFired: true };
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
    !anchor.download &&
    (!anchor.target || anchor.target === "_self");
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
}

function sharedState(): PointerTrackerState {
  const key = "__gestureKitPointerTrackerState";
  const target = window as unknown as Record<string, PointerTrackerState | undefined>;
  target[key] ??= {
    lastPointer: null,
    pendingConsumedClick: null,
    lastLinkClick: null,
    protectedLinkClick: null,
    linkClickProtectionEnabled: false
  };
  return target[key]!;
}

function syncLinkClickProtectionFromStorage() {
  if (typeof chrome === "undefined" || !chrome.storage?.local) {
    return;
  }
  void chrome.storage.local.get(GESTURE_SETTINGS_STORAGE_KEY).then((result) => {
    setLinkClickProtectionEnabled(
      normalizeGestureSettings(result[GESTURE_SETTINGS_STORAGE_KEY]).linkClickProtectionEnabled
    );
  });
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
    if (message.type !== "gesturekit.resolveLastPointer") {
      return false;
    }

    sendResponse(resolveLinkAtLastPointer(Date.now(), { consumeNextClick: Boolean(message.consumeNextClick) }));
    return false;
  });
}
