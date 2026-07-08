import { describe, expect, it } from "vitest";
import {
  createSettingsUpdateMessage,
  createPendingSettingsSyncStatus,
  settingsSyncStatusFromAck,
  markSettingsSyncFailed,
  markSettingsSyncStale,
  isSettingsAckMessage
} from "../src/background/settingsSync";
import { GESTURE_SETTINGS_PRESETS } from "../src/settings/gestureSettings";
import type { GestureSettings } from "../src/settings/gestureSettings";

const recommendedSettings: GestureSettings = {
  ...GESTURE_SETTINGS_PRESETS.safe,
  swipeSensitivity: "sensitive",
  swipeRecognitionOverride: {
    source: "recommended",
    recommendedMinDistance: 0.084
  }
};

describe("settings sync", () => {
  it("creates a settings_update message from gesture settings", () => {
    const message = createSettingsUpdateMessage({
      ...GESTURE_SETTINGS_PRESETS.efficient,
      swipeSensitivity: "sensitive"
    }, 123);

    expect(message).toMatchObject({
      version: 1,
      type: "settings_update",
      timestamp: 123,
      payload: {
        swipeSensitivity: "sensitive",
        swipeMinDistance: 0.075,
        swipeHorizontalRatio: 1.25,
        swipeMinDurationMs: 50,
        swipeMaxDurationMs: 480
      },
      error: null
    });
    expect(message.id).toMatch(/^settings-/);
  });

  it("creates settings_update with recommended override min distance", () => {
    const message = createSettingsUpdateMessage(recommendedSettings, 200);

    expect(message.payload.swipeMinDistance).toBe(0.084);
    expect(message.payload.swipeSensitivity).toBe("sensitive");
  });

  it("marks settings as pending when storage changes before ack", () => {
    const status = createPendingSettingsSyncStatus(recommendedSettings, 100);

    expect(status.phase).toBe("pending");
    expect(status.runtimeSwipeSensitivity).toBeNull();
    expect(status.savedSwipeSensitivity).toBe("sensitive");
  });

  it("creates applied status from settings_ack", () => {
    const status = settingsSyncStatusFromAck({
      version: 1,
      id: "settings-1",
      type: "settings_ack",
      timestamp: 456,
      payload: {
        applied: true,
        swipeSensitivity: "sensitive",
        appSessionId: "session-abc",
        recognitionSettings: {
          swipeSensitivity: "sensitive",
          swipeMinDistance: 0.084,
          swipeHorizontalRatio: 1.25,
          swipeMinDurationMs: 50,
          swipeMaxDurationMs: 480
        }
      },
      error: null
    }, recommendedSettings);

    expect(status.phase).toBe("applied");
    expect(status.runtimeSwipeSensitivity).toBe("sensitive");
    expect(status.currentAppSessionId).toBe("session-abc");
    expect(status.appliedAt).toBe(456);
  });

  it("creates failed status from settings_ack with applied:false", () => {
    const status = settingsSyncStatusFromAck({
      version: 1,
      id: "settings-fail",
      type: "settings_ack",
      timestamp: 500,
      payload: {
        applied: false,
        swipeSensitivity: "standard",
        appSessionId: "session-xyz",
        recognitionSettings: {
          swipeSensitivity: "standard",
          swipeMinDistance: 0.09,
          swipeHorizontalRatio: 1.5,
          swipeMinDurationMs: 60,
          swipeMaxDurationMs: 420
        },
        message: "thresholds out of range"
      },
      error: null
    }, recommendedSettings);

    expect(status.phase).toBe("failed");
    expect(status.message).toBe("thresholds out of range");
  });

  it("marks settings sync as failed on disconnect", () => {
    const failed = markSettingsSyncFailed(
      { phase: "pending", savedSwipeSensitivity: "sensitive", runtimeSwipeSensitivity: null, currentAppSessionId: null, requestedAt: 100, appliedAt: null, messageId: null, deltaSummary: [], message: undefined },
      "native_host_disconnected",
      200
    );

    expect(failed.phase).toBe("failed");
    expect(failed.message).toBe("native_host_disconnected");
  });

  it("marks settings as stale when probe sees a new app session", () => {
    const stale = markSettingsSyncStale(
      {
        phase: "applied",
        savedSwipeSensitivity: "sensitive",
        runtimeSwipeSensitivity: "sensitive",
        currentAppSessionId: "session-old",
        requestedAt: 100,
        appliedAt: 150,
        messageId: "ack-1",
        deltaSummary: [],
        message: undefined
      },
      "session-new",
      200
    );

    expect(stale.phase).toBe("stale");
    expect(stale.currentAppSessionId).toBe("session-new");
  });

  it("does not mark as stale when session matches", () => {
    const result = markSettingsSyncStale(
      {
        phase: "applied",
        savedSwipeSensitivity: "sensitive",
        runtimeSwipeSensitivity: "sensitive",
        currentAppSessionId: "session-same",
        requestedAt: 100,
        appliedAt: 150,
        messageId: "ack-1",
        deltaSummary: [],
        message: undefined
      },
      "session-same",
      200
    );

    expect(result.phase).toBe("applied");
  });

  it("returns saved_only when marking stale with no previous status", () => {
    const result = markSettingsSyncStale(null, null, 200);

    expect(result.phase).toBe("saved_only");
  });

  it("isSettingsAckMessage validates new payload shape", () => {
    expect(isSettingsAckMessage({
      version: 1,
      id: "ack-1",
      type: "settings_ack",
      timestamp: 100,
      payload: {
        applied: true,
        swipeSensitivity: "standard",
        appSessionId: "sess-1",
        recognitionSettings: {
          swipeSensitivity: "standard",
          swipeMinDistance: 0.09,
          swipeHorizontalRatio: 1.5,
          swipeMinDurationMs: 60,
          swipeMaxDurationMs: 420
        }
      },
      error: null
    })).toBe(true);
  });
});
