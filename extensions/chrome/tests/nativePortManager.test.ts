import { afterEach, describe, expect, it, vi } from "vitest";
import { createNativePortManager } from "../src/background/nativePortManager";
import type { GestureEventMessage } from "../src/protocol/messages";
import { GESTURE_SETTINGS_PRESETS, type GestureSettings } from "../src/settings/gestureSettings";

function gestureMessage(
  gesture: GestureEventMessage["payload"]["gesture"],
  payload: Partial<GestureEventMessage["payload"]> = {}
): GestureEventMessage {
  return {
    version: 1,
    id: "gesture-1",
    type: "gesture_event",
    timestamp: 10,
    payload: { gesture, appBundleId: "com.google.Chrome", confidence: 0.9, ...payload },
    error: null
  };
}

describe("createNativePortManager", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("maps swipe left to the right tab like macOS content movement", async () => {
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "activate_right_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_swipe_left"));

    expect(executeAction).toHaveBeenCalledWith({ action: "activate_right_tab" });
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      version: 1,
      type: "action_result",
      payload: { action: "activate_right_tab", status: "success" },
      error: null
    }));
  });

  it("maps swipe right to the left tab like macOS content movement", async () => {
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "activate_left_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_swipe_right"));

    expect(executeAction).toHaveBeenCalledWith({ action: "activate_left_tab" });
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "activate_left_tab", status: "success" }
    }));
  });

  it("does not dispatch swipe gestures when flick switching is disabled", async () => {
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(),
      executeAction,
      getSettings: vi.fn(async () => ({ ...GESTURE_SETTINGS_PRESETS.safe, flickSwitchEnabled: false }))
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_swipe_left"));

    expect(executeAction).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: {
        action: "activate_right_tab",
        status: "gesture_unstable",
        details: { reason: "flick_switch_disabled" }
      }
    }));
  });

  it("resolves link before open_link_background", async () => {
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "open_link_background", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "success", url: "https://example.com" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { durationMs: 96 }));

    expect(executeAction).toHaveBeenCalledWith({ action: "open_link_background", url: "https://example.com" });
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "open_link_background", status: "success" }
    }));
  });

  it("does not open a duplicate tab when the page click already fired", async () => {
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({
        status: "success",
        url: "https://example.com",
        clickAlreadyFired: true
      })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { durationMs: 96 }));

    expect(executeAction).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: {
        action: "open_link_background",
        status: "gesture_unstable",
        details: { reason: "click_already_fired" }
      }
    }));
  });

  it("preserves protected_click_expired instead of downgrading it to click_already_fired", async () => {
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({
        status: "success",
        url: "https://example.com",
        clickAlreadyFired: true,
        reason: "protected_click_expired",
        detail: "点击保护窗口已过期，页面已继续当前页跳转"
      })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { durationMs: 96 }));

    expect(executeAction).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: {
        action: "open_link_background",
        status: "gesture_unstable",
        details: {
          reason: "protected_click_expired",
          resolveDetail: "点击保护窗口已过期，页面已继续当前页跳转"
        }
      }
    }));
  });

  it("opens a link when the page click was protected by the content script", async () => {
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "open_link_background", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({
        status: "success",
        url: "https://example.com",
        clickProtected: true
      })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { durationMs: 96 }));

    expect(executeAction).toHaveBeenCalledWith({ action: "open_link_background", url: "https://example.com" });
  });

  it("ignores short no-link tap without opening a tab or switching tabs", async () => {
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.25, durationMs: 16 }));

    expect(executeAction).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: {
        action: "open_link_background",
        status: "gesture_unstable",
        details: { reason: "tap_duration_unstable" }
      }
    }));
  });

  it("encodes non_anchor_navigation as gesture_unstable with diagnostic reason", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({
        status: "non_anchor_navigation",
        detail: "命中 <div>，但不是标准 <a href>"
      })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.5, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(360);

    expect(executeAction).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: {
        action: "open_link_background",
        status: "gesture_unstable",
        details: {
          reason: "non_anchor_navigation",
          resolveDetail: "命中 <div>，但不是标准 <a href>"
        }
      }
    }));
  });

  it("uses left-edge three-finger tap as activate_left_tab when no second tap follows", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "activate_left_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.25, durationMs: 96 }));

    expect(executeAction).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(300);

    expect(executeAction).toHaveBeenCalledWith({ action: "activate_left_tab" });
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "activate_left_tab", status: "success" }
    }));
  });

  it("does not switch tabs from edge taps when edge tap switching is disabled", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction,
      getSettings: vi.fn(async () => ({ ...GESTURE_SETTINGS_PRESETS.safe, edgeTapEnabled: false }))
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.25, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(300);

    expect(executeAction).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: {
        action: "open_link_background",
        status: "no_target",
        details: { reason: "edge_tap_disabled" }
      }
    }));
  });

  it("uses custom edge width from settings", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "activate_left_tab", status: "success" }));
    const settings: GestureSettings = { ...GESTURE_SETTINGS_PRESETS.safe, leftEdgeMax: 0.28 };
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction,
      getSettings: vi.fn(async () => settings)
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.3, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(360);

    expect(executeAction).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "open_link_background", status: "no_target" }
    }));
  });

  it("uses right-edge three-finger tap as activate_right_tab when no second tap follows", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "activate_right_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.75, durationMs: 96 }));

    expect(executeAction).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(300);

    expect(executeAction).toHaveBeenCalledWith({ action: "activate_right_tab" });
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "activate_right_tab", status: "success" }
    }));
  });

  it("does not switch tabs for a center single tap", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.5, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(360);

    expect(executeAction).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "open_link_background", status: "no_target" }
    }));
  });

  it("uses center no-link three-finger double tap as close_tab", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "close_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.5, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(180);
    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.52, durationMs: 104 }));
    await vi.advanceTimersByTimeAsync(300);

    expect(executeAction).toHaveBeenCalledTimes(1);
    expect(executeAction).toHaveBeenCalledWith({ action: "close_tab" });
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "close_tab", status: "success" }
    }));
  });

  it("keeps the center double-tap window open through efficient-mode max interval", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "close_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction,
      getSettings: vi.fn(async () => GESTURE_SETTINGS_PRESETS.efficient)
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.5, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(340);
    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.52, durationMs: 104 }));

    expect(executeAction).toHaveBeenCalledWith({ action: "close_tab" });
  });

  it("does not close a tab when double-tap close is disabled", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction,
      getSettings: vi.fn(async () => ({ ...GESTURE_SETTINGS_PRESETS.safe, doubleTapCloseEnabled: false }))
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.5, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(180);
    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.52, durationMs: 104 }));
    await vi.advanceTimersByTimeAsync(360);

    expect(executeAction).not.toHaveBeenCalled();
  });

  it("reports cooldown as a diagnostic reason", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "activate_left_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.25, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(300);
    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.75, durationMs: 96 }));

    expect(postMessage).toHaveBeenLastCalledWith(expect.objectContaining({
      payload: {
        action: "open_link_background",
        status: "gesture_unstable",
        details: { reason: "cooldown" }
      }
    }));
  });

  it("does not close a tab when the second center tap is too fast", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.5, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(80);
    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.52, durationMs: 104 }));
    await vi.advanceTimersByTimeAsync(360);

    expect(executeAction).not.toHaveBeenCalled();
  });

  it("ignores no-link taps during the post-action cooldown", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "activate_left_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.25, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(300);
    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.75, durationMs: 96 }));
    await vi.advanceTimersByTimeAsync(300);

    expect(executeAction).toHaveBeenCalledTimes(1);
    expect(executeAction).toHaveBeenCalledWith({ action: "activate_left_tab" });
  });

  it("cancels edge-tap pending action with original action on supersede", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    // First tap: left edge, pending action = activate_left_tab
    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.2, durationMs: 96 }));
    // Second tap comes before the 300ms window expires, cancels the first
    await vi.advanceTimersByTimeAsync(50);
    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.75, durationMs: 96 }));

    // The first pending tap was cancelled with its original action
    const cancelMessages = postMessage.mock.calls
      .map((call: unknown[]) => (call[0] as { payload: { action: string; status: string; details?: Record<string, unknown> } }).payload)
      .filter((p: { action: string; status: string }) => p.status === "gesture_unstable" && p.action === "activate_left_tab");

    expect(cancelMessages.length).toBe(1);
    expect(cancelMessages[0]).toMatchObject({
      action: "activate_left_tab",
      status: "gesture_unstable",
      details: { reason: "superseded_by_tap" }
    });
  });
});
