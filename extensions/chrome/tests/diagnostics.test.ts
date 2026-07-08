import { describe, expect, it, vi } from "vitest";
import {
  appendDiagnostic,
  DIAGNOSTICS_STORAGE_KEY,
  diagnosticFromActionResult,
  formatDiagnosticsForClipboard,
  summarizeDiagnostics,
  type GestureDiagnosticEntry
} from "../src/diagnostics/diagnostics";
import type { ActionResultMessage } from "../src/protocol/messages";

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
    expect(summary.recommendedSensitivity).toBe("sensitive");
    expect(summary.recommendedMinDistance).toBe(0.11);
  });

  it("recommends a personal minimum distance from successful swipe samples", () => {
    const events = [0.080, 0.084, 0.090, 0.100, 0.120].map((dx, index) => ({
      ...swipeEntry(index, "success"),
      dx
    }));

    const summary = summarizeDiagnostics(events);

    expect(summary.recommendedSensitivity).toBe("standard");
    expect(summary.recommendedMinDistance).toBe(0.084);
    expect(summary.recommendationText).toContain("推荐最小距离 0.084");
  });

  it("uses action_result details reason for extension-side failures", () => {
    const entry = diagnosticFromActionResult(actionResult("gesture-1", "activate_left_tab", "gesture_unstable", {
      reason: "cooldown"
    }));

    expect(entry.reason).toBe("cooldown");
  });

  it("labels click race failures in Chinese", () => {
    const entry = diagnosticFromActionResult(actionResult("gesture-1", "open_link_background", "gesture_unstable", {
      reason: "click_already_fired"
    }));

    expect(entry.reason).toBe("click_already_fired");
    expect(summarizeDiagnostics([entry]).mainFailureReason).toBe("点击已先触发");
  });

  it("labels missing link targets with a specific Chinese hint", () => {
    const entry = diagnosticFromActionResult(actionResult("gesture-1", "open_link_background", "no_target"));

    expect(entry.reason).toBe("no_target");
    const summary = summarizeDiagnostics([entry]);
    expect(summary.mainFailureReason).toBe("未命中可打开链接");
    expect(summary.suggestion).toBe("把鼠标停在普通 http/https 链接上");
  });

  it("formats diagnostics for clipboard without page content or URLs", () => {
    const text = formatDiagnosticsForClipboard([swipeEntry(1, "gesture_unstable")]);

    expect(text).toContain("GestureKit Diagnostics");
    expect(text).toContain("recommendation=");
    expect(text).toContain("distance_too_short");
    expect(text).toContain("dx=0.073");
    expect(text).not.toContain("http");
  });

  it("includes current vs recommended delta in clipboard", () => {
    const text = formatDiagnosticsForClipboard(
      [swipeEntry(1, "success")],
      {
        swipeSensitivity: "robust",
        swipeMinDistance: 0.11,
        swipeHorizontalRatio: 1.8,
        swipeMinDurationMs: 60,
        swipeMaxDurationMs: 350,
        source: "preset" as const
      },
      {
        swipeSensitivity: "sensitive",
        swipeMinDistance: 0.084,
        swipeHorizontalRatio: 1.25,
        swipeMinDurationMs: 50,
        swipeMaxDurationMs: 480,
        source: "recommended" as const
      }
    );

    expect(text).toContain("currentRecognition=");
    expect(text).toContain("recommendedRecognition=");
    expect(text).toContain("robust");
    expect(text).toContain("sensitive");
  });

  it("includes applyPhase in clipboard when sync status provided", () => {
    const text = formatDiagnosticsForClipboard(
      [swipeEntry(1, "success")],
      undefined,
      undefined,
      {
        phase: "applied",
        savedSwipeSensitivity: "sensitive",
        runtimeSwipeSensitivity: "sensitive",
        currentAppSessionId: "sess-1",
        requestedAt: null,
        appliedAt: 200,
        messageId: "ack-1",
        deltaSummary: [],
        message: undefined
      }
    );

    expect(text).toContain("applyPhase=applied");
  });
});

function actionResult(
  id: string,
  action: ActionResultMessage["payload"]["action"],
  status: ActionResultMessage["payload"]["status"],
  details?: Record<string, unknown>
): ActionResultMessage {
  return {
    version: 1,
    id,
    type: "action_result",
    timestamp: 123,
    payload: {
      action,
      status,
      ...(details ? { details } : {})
    },
    error: null
  };
}
