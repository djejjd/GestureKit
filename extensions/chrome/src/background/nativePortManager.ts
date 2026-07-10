import type { ActionExecutionResult } from "./actionExecutor";
import type { LinkResolveResult } from "../content/linkResolver";
import type { ActionResultMessage, GestureEventMessage } from "../protocol/messages";
import { GESTURE_SETTINGS_PRESETS, type GestureSettings } from "../settings/gestureSettings";

type ResolveLastPointerResponse = LinkResolveResult | { status: "no_recent_pointer" };
type PortLike = { postMessage(message: unknown): void };

type GestureIntent =
  | { action: "open_link_background"; url: string }
  | { action: "activate_left_tab" }
  | { action: "activate_right_tab" }
  | { action: "close_tab" };

type Dependencies = {
  port: PortLike;
  resolveLastPointer(): Promise<ResolveLastPointerResponse>;
  executeAction(intent: GestureIntent): Promise<ActionExecutionResult>;
  getSettings?(): Promise<GestureSettings>;
  onActionResult?(message: ActionResultMessage): void;
  cancelPendingTap?(): void;
};

const DOUBLE_TAP_WINDOW_MS = 300;

export function createNativePortManager(deps: Dependencies) {
  let pendingTap: { id: string; timer: ReturnType<typeof setTimeout>; startedAt: number; zone: TapZone; pendingAction: string } | null = null;
  let cooldownUntil = 0;

  async function currentSettings() {
    return deps.getSettings ? deps.getSettings() : GESTURE_SETTINGS_PRESETS.safe;
  }

  async function executeAndPost(id: string, intent: GestureIntent) {
    postActionResult(actionResultFromExecution(id, await deps.executeAction(intent)));
    cooldownUntil = Date.now() + (await currentSettings()).cooldownMs;
  }

  function postActionResult(message: ActionResultMessage) {
    deps.port.postMessage(message);
    deps.onActionResult?.(message);
  }

  function clearPendingTap(reason?: string) {
    if (pendingTap) {
      clearTimeout(pendingTap.timer);
      if (reason) {
        postActionResult(actionResult(pendingTap.id, pendingTap.pendingAction, "gesture_unstable", { reason }));
      }
      pendingTap = null;
    }
  }

  function scheduleSingleTapFallback(
    id: string,
    zone: TapZone,
    intent: GestureIntent | null,
    settings: GestureSettings,
    resolveDetail?: string
  ) {
    clearPendingTap("superseded_by_tap");
    pendingTap = {
      id,
      startedAt: Date.now(),
      zone,
      pendingAction: intent ? intent.action : "open_link_background",
      timer: setTimeout(() => {
        pendingTap = null;
        if (intent) {
          void executeAndPost(id, intent);
          return;
        }
        postActionResult(actionResult(
          id,
          "open_link_background",
          "no_target",
          resolveDetail ? { resolveDetail } : undefined
        ));
      }, zone === "center" ? settings.doubleTapMaxMs : DOUBLE_TAP_WINDOW_MS)
    };
  }

  return {
    async handleNativeMessage(message: GestureEventMessage) {
      if (message.version !== 1 || message.type !== "gesture_event") {
        return;
      }

      const settings = await currentSettings();

      if (message.payload.gesture === "three_finger_tap") {
        if (Date.now() < cooldownUntil) {
          clearPendingTap("cooldown");
          deps.cancelPendingTap?.();
          postActionResult(actionResult(message.id, "open_link_background", "gesture_unstable", { reason: "cooldown" }));
          return;
        }

        if (!isStableTapDuration(message.payload.durationMs, settings)) {
          clearPendingTap("tap_duration_unstable");
          deps.cancelPendingTap?.();
          postActionResult(actionResult(message.id, "open_link_background", "gesture_unstable", { reason: "tap_duration_unstable" }));
          return;
        }

        const resolved = await deps.resolveLastPointer();
        if (resolved.status !== "success") {
          const tapZone = tapZoneFromTouchX(message.payload.touchX, resolved.status, settings);
          if (tapZone) {
            if (pendingTap?.zone === "center" && tapZone === "center" && settings.doubleTapCloseEnabled) {
              const interval = Date.now() - pendingTap.startedAt;
              if (interval >= settings.doubleTapMinMs && interval <= settings.doubleTapMaxMs) {
                clearPendingTap("converted_to_double_tap_close");
                await executeAndPost(message.id, { action: "close_tab" });
                return;
              }
              clearPendingTap("tap_duration_unstable");
              postActionResult(actionResult(message.id, "open_link_background", "gesture_unstable", { reason: "tap_duration_unstable" }));
              return;
            }
            const fallbackIntent = intentFromTapZone(tapZone);
            const resolveDetail = "detail" in resolved && typeof resolved.detail === "string"
              ? resolved.detail
              : undefined;
            scheduleSingleTapFallback(message.id, tapZone, fallbackIntent, settings, resolveDetail);
            return;
          }
          clearPendingTap();
          const failureDetail: Record<string, unknown> = {};
          if ("detail" in resolved && typeof resolved.detail === "string") {
            failureDetail.resolveDetail = resolved.detail;
          }
          const resolvedReason = diagnosticReasonFromResolvedFailure(resolved);
          if (resolvedReason) {
            failureDetail.reason = resolvedReason;
          }
          if (!settings.edgeTapEnabled && tapZoneFromTouchXIgnoringSetting(message.payload.touchX, resolved.status, settings) !== null) {
            failureDetail.reason = "edge_tap_disabled";
          }
          postActionResult(actionResult(
            message.id,
            "open_link_background",
            actionStatusFromResolvedFailure(resolved),
            Object.keys(failureDetail).length > 0 ? failureDetail : undefined
          ));
          return;
        }
        clearPendingTap();
        if (resolved.clickAlreadyFired) {
          const detail: Record<string, unknown> = {
            reason: typeof resolved.reason === "string" ? resolved.reason : "click_already_fired"
          };
          if ("detail" in resolved && typeof resolved.detail === "string") {
            detail.resolveDetail = resolved.detail;
          }
          postActionResult(actionResult(message.id, "open_link_background", "gesture_unstable", detail));
          return;
        }
        await executeAndPost(message.id, { action: "open_link_background", url: resolved.url });
        return;
      }

      clearPendingTap();
      const intent = intentFromGesture(message.payload.gesture);
      if (!settings.flickSwitchEnabled) {
        postActionResult(actionResult(message.id, intent.action, "gesture_unstable", { reason: "flick_switch_disabled" }));
        return;
      }
      await executeAndPost(message.id, intent);
    }
  };
}

function tapZoneFromTouchXIgnoringSetting(
  touchX: number | undefined,
  status: ResolveLastPointerResponse["status"],
  settings: GestureSettings
): TapZone | null {
  if (touchX === undefined || touchX < 0 || touchX > 1) {
    return null;
  }
  if (status !== "no_target" && status !== "no_recent_pointer" && status !== "page_unavailable") {
    return null;
  }
  if (touchX <= settings.leftEdgeMax) {
    return "left";
  }
  if (touchX >= settings.rightEdgeMin) {
    return "right";
  }
  return null;
}

type TapZone = "left" | "center" | "right";

function isStableTapDuration(durationMs: number | undefined, settings: GestureSettings): boolean {
  return durationMs !== undefined &&
    durationMs >= settings.tapDurationMinMs &&
    durationMs <= settings.tapDurationMaxMs;
}

function tapZoneFromTouchX(
  touchX: number | undefined,
  status: ResolveLastPointerResponse["status"],
  settings: GestureSettings
): TapZone | null {
  if (touchX === undefined || touchX < 0 || touchX > 1) {
    return null;
  }
  if (status !== "no_target" && status !== "no_recent_pointer" && status !== "page_unavailable") {
    return null;
  }
  if (touchX <= settings.leftEdgeMax) {
    return settings.edgeTapEnabled ? "left" : null;
  }
  if (touchX >= settings.rightEdgeMin) {
    return settings.edgeTapEnabled ? "right" : null;
  }
  return "center";
}

function intentFromTapZone(zone: TapZone): GestureIntent | null {
  if (zone === "left") {
    return { action: "activate_left_tab" };
  }
  if (zone === "right") {
    return { action: "activate_right_tab" };
  }
  return null;
}

function intentFromGesture(gesture: GestureEventMessage["payload"]["gesture"]): GestureIntent {
  if (gesture === "three_finger_swipe_left") {
    return { action: "activate_right_tab" };
  }
  return { action: "activate_left_tab" };
}

function actionResultFromExecution(id: string, result: ActionExecutionResult): ActionResultMessage {
  return actionResult(id, result.action, result.status, result.details);
}

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
    timestamp: Date.now(),
    payload: { action, status, ...(details ? { details } : {}) },
    error: null
  };
}

function actionStatusFromResolvedFailure(
  resolved: Exclude<ResolveLastPointerResponse, { status: "success" }>
): ActionResultMessage["payload"]["status"] {
  if (resolved.status === "non_anchor_navigation") {
    return "gesture_unstable";
  }
  return resolved.status;
}

function diagnosticReasonFromResolvedFailure(
  resolved: Exclude<ResolveLastPointerResponse, { status: "success" }>
): string | null {
  if ("reason" in resolved && typeof resolved.reason === "string") {
    return resolved.reason;
  }
  if (resolved.status === "non_anchor_navigation") {
    return "non_anchor_navigation";
  }
  return null;
}
