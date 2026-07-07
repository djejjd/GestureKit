import { describe, expect, it, vi } from "vitest";
import {
  appendDiagnostic,
  DIAGNOSTICS_STORAGE_KEY,
  formatDiagnosticsForClipboard,
  summarizeDiagnostics,
  type GestureDiagnosticEntry
} from "../src/diagnostics/diagnostics";

function storageWith(initial: GestureDiagnosticEntry[] = []) {
  const state: Record<string, unknown> = {
    [DIAGNOSTICS_STORAGE_KEY]: initial
  };
  return {
    get: vi.fn(async (key: string) => ({ [key]: state[key] })),
    set: vi.fn(async (items: Record<string, unknown>) => {
      Object.assign(state, items);
    }),
    state
  };
}

function swipeEntry(index: number, status: "success" | "gesture_unstable" = "success"): GestureDiagnosticEntry {
  return {
    id: `diag-${index}`,
    timestamp: index,
    source: "app",
    kind: "gesture",
    gesture: "three_finger_swipe_right",
    action: "activate_right_tab",
    status,
    reason: status === "success" ? "success" : "distance_too_short",
    swipeSensitivity: "standard",
    dx: status === "success" ? 0.126 : 0.073,
    dy: 0.012,
    distance: status === "success" ? 0.127 : 0.074,
    durationMs: 164,
    horizontalRatio: 6.08,
    thresholds: {
      swipeSensitivity: "standard",
      swipeMinDistance: 0.09,
      swipeHorizontalRatio: 1.5,
      swipeMinDurationMs: 60,
      swipeMaxDurationMs: 420
    }
  };
}

describe("diagnostics", () => {
  it("keeps only the newest diagnostics when appending", async () => {
    const storage = storageWith(Array.from({ length: 100 }, (_, index) => swipeEntry(index)));

    await appendDiagnostic(storage, swipeEntry(100), 100);

    const saved = storage.state[DIAGNOSTICS_STORAGE_KEY] as GestureDiagnosticEntry[];
    expect(saved).toHaveLength(100);
    expect(saved[0].id).toBe("diag-1");
    expect(saved[99].id).toBe("diag-100");
  });

  it("summarizes recent swipe success rate and main failure reason", () => {
    const events = [
      ...Array.from({ length: 7 }, (_, index) => swipeEntry(index, "success")),
      ...Array.from({ length: 3 }, (_, index) => swipeEntry(index + 7, "gesture_unstable"))
    ];

    const summary = summarizeDiagnostics(events);

    expect(summary.swipeSuccessText).toBe("7 / 10");
    expect(summary.mainFailureReason).toBe("横向距离不足");
    expect(summary.suggestion).toBe("可以尝试“灵敏”");
  });

  it("formats diagnostics for clipboard without page content or URLs", () => {
    const text = formatDiagnosticsForClipboard([swipeEntry(1, "gesture_unstable")]);

    expect(text).toContain("GestureKit Diagnostics");
    expect(text).toContain("distance_too_short");
    expect(text).toContain("dx=0.073");
    expect(text).not.toContain("http");
  });
});
