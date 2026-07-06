import type { ActionExecutionResult } from "./actionExecutor";
import type { LinkResolveResult } from "../content/linkResolver";
import type { ActionResultMessage, GestureEventMessage } from "../protocol/messages";

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
};

const DOUBLE_TAP_WINDOW_MS = 300;

export function createNativePortManager(deps: Dependencies) {
  let pendingTap: { timer: ReturnType<typeof setTimeout> } | null = null;

  async function executeAndPost(id: string, intent: GestureIntent) {
    deps.port.postMessage(actionResultFromExecution(id, await deps.executeAction(intent)));
  }

  function clearPendingTap() {
    if (pendingTap) {
      clearTimeout(pendingTap.timer);
      pendingTap = null;
    }
  }

  function scheduleSingleTapFallback(id: string, intent: GestureIntent) {
    clearPendingTap();
    pendingTap = {
      timer: setTimeout(() => {
        pendingTap = null;
        void executeAndPost(id, intent);
      }, DOUBLE_TAP_WINDOW_MS)
    };
  }

  return {
    async handleNativeMessage(message: GestureEventMessage) {
      if (message.version !== 1 || message.type !== "gesture_event") {
        return;
      }

      if (message.payload.gesture === "three_finger_tap") {
        const resolved = await deps.resolveLastPointer();
        if (resolved.status !== "success") {
          const fallbackIntent = tapZoneIntent(message.payload.touchX, resolved.status);
          if (fallbackIntent) {
            if (pendingTap) {
              clearPendingTap();
              await executeAndPost(message.id, { action: "close_tab" });
              return;
            }
            scheduleSingleTapFallback(message.id, fallbackIntent);
            return;
          }
          clearPendingTap();
          deps.port.postMessage(actionResult(message.id, "open_link_background", resolved.status));
          return;
        }
        clearPendingTap();
        await executeAndPost(message.id, { action: "open_link_background", url: resolved.url });
        return;
      }

      clearPendingTap();
      const intent = intentFromGesture(message.payload.gesture);
      await executeAndPost(message.id, intent);
    }
  };
}

function tapZoneIntent(touchX: number | undefined, status: ResolveLastPointerResponse["status"]): GestureIntent | null {
  if (touchX === undefined || touchX < 0 || touchX > 1) {
    return null;
  }
  if (status !== "no_target" && status !== "no_recent_pointer" && status !== "page_unavailable") {
    return null;
  }
  return touchX < 0.5 ? { action: "activate_left_tab" } : { action: "activate_right_tab" };
}

function intentFromGesture(gesture: GestureEventMessage["payload"]["gesture"]): GestureIntent {
  if (gesture === "three_finger_swipe_left") {
    return { action: "activate_left_tab" };
  }
  return { action: "activate_right_tab" };
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
