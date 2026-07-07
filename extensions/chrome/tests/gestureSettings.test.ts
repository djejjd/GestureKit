import { describe, expect, it, vi } from "vitest";
import {
  GESTURE_SETTINGS_PRESETS,
  GESTURE_SETTINGS_STORAGE_KEY,
  loadGestureSettings,
  normalizeGestureSettings,
  saveGestureSettings
} from "../src/settings/gestureSettings";

function storageWith(value: unknown = undefined) {
  const state: Record<string, unknown> = {};
  if (value !== undefined) {
    state[GESTURE_SETTINGS_STORAGE_KEY] = value;
  }
  return {
    get: vi.fn(async (key: string) => ({ [key]: state[key] })),
    set: vi.fn(async (items: Record<string, unknown>) => {
      Object.assign(state, items);
    }),
    state
  };
}

describe("gesture settings", () => {
  it("uses safe mode as the default", () => {
    expect(GESTURE_SETTINGS_PRESETS.safe).toMatchObject({
      mode: "safe",
      swipeSensitivity: "robust",
      edgeTapEnabled: true,
      doubleTapCloseEnabled: true,
      flickSwitchEnabled: true,
      leftEdgeMax: 0.3,
      rightEdgeMin: 0.7,
      doubleTapMinMs: 160,
      doubleTapMaxMs: 330,
      cooldownMs: 260,
      tapDurationMinMs: 45,
      tapDurationMaxMs: 200
    });
  });

  it("normalizes partial custom settings against the selected preset", () => {
    const normalized = normalizeGestureSettings({
      mode: "efficient",
      doubleTapCloseEnabled: false,
      leftEdgeMax: 0.5,
      rightEdgeMin: 0.4,
      cooldownMs: 10
    });

    expect(normalized).toMatchObject({
      mode: "efficient",
      swipeSensitivity: "sensitive",
      doubleTapCloseEnabled: false,
      leftEdgeMax: 0.38,
      rightEdgeMin: 0.62,
      cooldownMs: 80
    });
  });

  it("keeps an explicit swipe sensitivity when valid", () => {
    const normalized = normalizeGestureSettings({
      mode: "safe",
      swipeSensitivity: "standard"
    });

    expect(normalized.swipeSensitivity).toBe("standard");
  });

  it("falls back to safe settings when storage is empty", async () => {
    const storage = storageWith();

    await expect(loadGestureSettings(storage)).resolves.toEqual(GESTURE_SETTINGS_PRESETS.safe);
  });

  it("saves normalized settings to storage", async () => {
    const storage = storageWith();

    await saveGestureSettings(storage, { mode: "efficient", edgeTapEnabled: false });

    expect(storage.set).toHaveBeenCalledWith({
      [GESTURE_SETTINGS_STORAGE_KEY]: expect.objectContaining({
        mode: "efficient",
        edgeTapEnabled: false,
        leftEdgeMax: 0.38
      })
    });
  });
});
