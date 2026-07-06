import { afterEach, describe, expect, it, vi } from "vitest";
import { createNativePortManager } from "../src/background/nativePortManager";
import type { GestureEventMessage } from "../src/protocol/messages";

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

  it("dispatches swipe left to action executor and posts action_result", async () => {
    const postMessage = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(),
      executeAction: vi.fn(async () => ({ action: "activate_left_tab", status: "success" }))
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_swipe_left"));

    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      version: 1,
      type: "action_result",
      payload: { action: "activate_left_tab", status: "success" },
      error: null
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

    await manager.handleNativeMessage(gestureMessage("three_finger_tap"));

    expect(executeAction).toHaveBeenCalledWith({ action: "open_link_background", url: "https://example.com" });
  });

  it("returns no_target without opening a tab", async () => {
    const postMessage = vi.fn();
    const executeAction = vi.fn();
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap"));

    expect(executeAction).not.toHaveBeenCalled();
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "open_link_background", status: "no_target" }
    }));
  });

  it("uses left-half three-finger tap as activate_left_tab when no second tap follows", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "activate_left_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.25 }));

    expect(executeAction).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(300);

    expect(executeAction).toHaveBeenCalledWith({ action: "activate_left_tab" });
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "activate_left_tab", status: "success" }
    }));
  });

  it("uses right-half three-finger tap as activate_right_tab when no second tap follows", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "activate_right_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.75 }));

    expect(executeAction).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(300);

    expect(executeAction).toHaveBeenCalledWith({ action: "activate_right_tab" });
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "activate_right_tab", status: "success" }
    }));
  });

  it("uses no-link three-finger double tap as close_tab", async () => {
    vi.useFakeTimers();
    const postMessage = vi.fn();
    const executeAction = vi.fn(async () => ({ action: "close_tab", status: "success" }));
    const manager = createNativePortManager({
      port: { postMessage },
      resolveLastPointer: vi.fn(async () => ({ status: "no_target" })),
      executeAction
    });

    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.25 }));
    await manager.handleNativeMessage(gestureMessage("three_finger_tap", { touchX: 0.75 }));
    await vi.advanceTimersByTimeAsync(300);

    expect(executeAction).toHaveBeenCalledTimes(1);
    expect(executeAction).toHaveBeenCalledWith({ action: "close_tab" });
    expect(postMessage).toHaveBeenCalledWith(expect.objectContaining({
      payload: { action: "close_tab", status: "success" }
    }));
  });
});
