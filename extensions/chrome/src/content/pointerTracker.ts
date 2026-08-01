import { resolveLinkAtPoint } from "./linkResolver";
import { createInteractionGuard, type GuardCommand } from "./interactionGuard";

export type PointerSnapshot = {
  x: number;
  y: number;
  timestamp: number;
};

const MAX_POINTER_AGE_MS = 1500;
const CONSUME_CLICK_WINDOW_MS = 2000;
// 保护窗口必须覆盖 guard deadline（App 侧 candidate guard 为 750ms）。
// 若窗口短于 deadline，手势在 500~750ms 之间到达时会被 content script 抢先
// 原地导航（window.location.href），导致"原地打开"。取值与 guard deadline 对齐。
const LINK_CLICK_PROTECTION_WINDOW_MS = 750;

type PointerTrackerState = {
  lastPointer: PointerSnapshot | null;
  pendingConsumedClick: { url: string; expiresAt: number } | null;
  lastLinkClick: { url: string; timestamp: number } | null;
  protectedLinkClick: { url: string; gestureSessionId: string | null; timestamp: number; timeout: ReturnType<typeof setTimeout> } | null;
  consumedProtectedClick: { url: string; gestureSessionId: string } | null;
  expiredProtectedClick: { url: string; timestamp: number } | null;
  linkClickProtectionEnabled: boolean;
  timedOutAndNavigated: boolean;
};

const state = sharedState();
const interactionGuard = createInteractionGuard();

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
    const anchor = linkAnchorForEvent(event);
    const activeGuard = interactionGuard.active(performance.now());
    traceGuard(activeGuard?.gestureSessionId, "click_observed", anchor ? "anchor_resolved" : "anchor_missing");

    if (!state.pendingConsumedClick || Date.now() > state.pendingConsumedClick.expiresAt) {
      state.pendingConsumedClick = null;
    } else if (anchor?.href === state.pendingConsumedClick.url) {
      state.pendingConsumedClick = null;
      event.preventDefault();
      event.stopImmediatePropagation();
      traceGuard(activeGuard?.gestureSessionId, "click_blocked", "pending_consumed_click");
      return;
    }

    if (!anchor?.href) {
      return;
    }

    if (shouldProtectLinkClick(event, anchor) && (state.linkClickProtectionEnabled || activeGuard)) {
      protectLinkClick(event, anchor.href, activeGuard?.gestureSessionId ?? null);
      traceGuard(activeGuard?.gestureSessionId, "click_blocked", "active_guard");
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
    // 保护窗口已超时并已导航，不返回链接避免重复打开新标签页
    if (state.timedOutAndNavigated) {
      return { status: "no_target" as const };
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
  return {
    status: "success" as const,
    url,
    clickAlreadyFired: true,
    reason: "protected_click_expired" as const,
    detail: "点击保护窗口已过期，未在窗口内消费"
  };
}

export function setLinkClickProtectionEnabled(enabled: boolean) {
  resetTransientClickState();
  state.linkClickProtectionEnabled = enabled;
}

function shouldProtectLinkClick(event: MouseEvent, anchor: HTMLAnchorElement): boolean {
  return event.cancelable &&
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

/**
 * 触控板产生的合成 click 有时以 document 或链接内的非 Element 节点为 target。
 * 守卫绑定的是用户最后指向的链接，因此在事件路径不含 anchor 时回退到该位置。
 */
function linkAnchorForEvent(event: MouseEvent): HTMLAnchorElement | null {
  for (const target of event.composedPath()) {
    if (target instanceof Element) {
      const anchor = target.closest("a[href]") as HTMLAnchorElement | null;
      if (anchor?.href) return anchor;
    }
  }
  if (!state.lastPointer || Date.now() - state.lastPointer.timestamp > MAX_POINTER_AGE_MS) return null;
  const pointed = document.elementFromPoint(state.lastPointer.x, state.lastPointer.y);
  return pointed?.closest("a[href]") as HTMLAnchorElement | null;
}

function isHttpLink(urlValue: string): boolean {
  try {
    const url = new URL(urlValue);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

function protectLinkClick(event: MouseEvent, url: string, gestureSessionId: string | null) {
  if (state.protectedLinkClick) {
    clearTimeout(state.protectedLinkClick.timeout);
  }

  event.preventDefault();
  event.stopImmediatePropagation();
  state.protectedLinkClick = {
    url,
    gestureSessionId,
    timestamp: Date.now(),
    timeout: setTimeout(() => {
      // 保护到期：若 GestureKit 已消费（consumeProtectedLinkClick 会
      // clearTimeout 此定时器），回调不会执行。未消费时直接导航，
      // 标记 timedOutAndNavigated，让晚到的手势跳过重复打开。
      state.protectedLinkClick = null;
      state.timedOutAndNavigated = true;
      traceGuard(gestureSessionId, "lease_expired", "original_navigation_restored");
      window.location.href = url;
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
  state.consumedProtectedClick = null;
  state.expiredProtectedClick = null;
}

export function cancelProtectedClick() {
  if (state.protectedLinkClick) {
    clearTimeout(state.protectedLinkClick.timeout);
    state.protectedLinkClick = null;
  }
}

function releaseProtectedClick(gestureSessionId: string): { status: "guard_released" | "guard_unavailable" } {
  const protectedClick = state.protectedLinkClick;
  if (protectedClick?.gestureSessionId === gestureSessionId) {
    clearTimeout(protectedClick.timeout);
    state.protectedLinkClick = null;
    traceGuard(gestureSessionId, "released", "protected_click_restored");
    // 被暂存的原生导航在候选被拒绝或 Provider 放弃时必须恢复。
    window.location.href = protectedClick.url;
    return { status: "guard_released" };
  }
  const consumed = state.consumedProtectedClick;
  if (consumed?.gestureSessionId !== gestureSessionId) return { status: "guard_unavailable" };
  state.consumedProtectedClick = null;
  traceGuard(gestureSessionId, "released", "consumed_click_restored");
  window.location.href = consumed.url;
  return { status: "guard_released" };
}

export function setPointerSnapshotForTesting(snapshot: PointerSnapshot | null) {
  state.lastPointer = snapshot;
}

function sharedState(): PointerTrackerState {
  const key = "__gestureKitPointerTrackerState";
  const target = window as unknown as Record<string, PointerTrackerState | undefined>;
  target[key] ??= {
    lastPointer: null,
    pendingConsumedClick: null,
    lastLinkClick: null,
    protectedLinkClick: null,
    consumedProtectedClick: null,
    expiredProtectedClick: null,
    linkClickProtectionEnabled: false,
    timedOutAndNavigated: false
  };
  return target[key]!;
}

if (typeof chrome !== "undefined" && chrome.runtime?.onMessage) {
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message.type === "gesturekit.linkGuardArm") {
      const command: GuardCommand = {
        gestureSessionId: message.gestureSessionId,
        issuedAtMonotonicMs: performance.now(),
        leaseMs: message.leaseMs
      };
      interactionGuard.arm(command, performance.now());
      traceGuard(command.gestureSessionId, "armed", "content_script_ack");
      sendResponse({ status: "guard_armed", gestureSessionId: command.gestureSessionId });
      return false;
    }
    if (message.type === "gesturekit.linkGuardRelease") {
      const released = releaseProtectedClick(message.gestureSessionId);
      const guard = interactionGuard.release({ gestureSessionId: message.gestureSessionId, nowMonotonicMs: performance.now() });
      sendResponse(released.status === "guard_released" ? released : guard);
      return false;
    }
    if (message.type === "gesturekit.guardArm") {
      const command = message as GuardCommand & { type: "gesturekit.guardArm" };
      interactionGuard.arm(command, performance.now());
      sendResponse({ status: "guard_armed", gestureSessionId: command.gestureSessionId });
      return false;
    }
    if (message.type === "gesturekit.guardRelease") {
      const released = releaseProtectedClick(message.gestureSessionId);
      const guard = interactionGuard.release({ gestureSessionId: message.gestureSessionId, nowMonotonicMs: performance.now() });
      sendResponse(released.status === "guard_released" ? released : guard);
      return false;
    }
    if (message.type === "gesturekit.guardConsume") {
      const protectedClick = state.protectedLinkClick;
      if (protectedClick?.gestureSessionId === message.gestureSessionId) {
        clearTimeout(protectedClick.timeout);
        state.protectedLinkClick = null;
        state.consumedProtectedClick = {
          url: protectedClick.url,
          gestureSessionId: message.gestureSessionId
        };
        traceGuard(message.gestureSessionId, "consumed", "protected_click");
      } else if (typeof message.url === "string") {
        // 动作可能先于浏览器默认 click 到达。预登记目标 URL，确保这个稍晚
        // 到达的原始 click 仍会被一次性吞掉。
        state.pendingConsumedClick = { url: message.url, expiresAt: Date.now() + CONSUME_CLICK_WINDOW_MS };
        traceGuard(message.gestureSessionId, "consumed", "pending_click");
      }
      const result = interactionGuard.consume({ gestureSessionId: message.gestureSessionId, nowMonotonicMs: performance.now() });
      traceGuard(message.gestureSessionId, result.status === "guard_consumed" ? "consume_acknowledged" : "consume_rejected", result.status);
      sendResponse(result);
      return false;
    }
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

function traceGuard(gestureSessionId: string | undefined | null, stage: string, detail: string) {
  if (!gestureSessionId || typeof chrome === "undefined" || !chrome.runtime?.sendMessage) return;
  void chrome.runtime.sendMessage({
    type: "gesturekit.guardTrace",
    gestureSessionId,
    stage,
    detail,
    timestamp: Date.now()
  }).catch(() => {});
}
