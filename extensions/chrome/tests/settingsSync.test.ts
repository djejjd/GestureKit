import { describe, expect, it } from "vitest";
import { createSettingsUpdateMessage, settingsSyncStatusFromAck } from "../src/background/settingsSync";
import { GESTURE_SETTINGS_PRESETS } from "../src/settings/gestureSettings";

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

  it("creates popup sync status from settings_ack", () => {
    const status = settingsSyncStatusFromAck({
      version: 1,
      id: "settings-1",
      type: "settings_ack",
      timestamp: 456,
      payload: {
        applied: true,
        swipeSensitivity: "standard"
      },
      error: null
    });

    expect(status).toEqual({
      applied: true,
      swipeSensitivity: "standard",
      lastSyncedAt: 456,
      message: undefined
    });
  });
});
