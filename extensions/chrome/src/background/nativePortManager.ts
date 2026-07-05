import type { ActionExecutionResult } from "./actionExecutor";
import type { LinkResolveResult } from "../content/linkResolver";
import type { ActionResultMessage, GestureEventMessage } from "../protocol/messages";

type ResolveLastPointerResponse = LinkResolveResult | { status: "no_recent_pointer" };
type PortLike = { postMessage(message: unknown): void };

type GestureIntent =
  | { action: "open_link_background"; url: string }
  | { action: "activate_left_tab" }
  | { action: "activate_right_tab" };

type Dependencies = {
  port: PortLike;
  resolveLastPointer(): Promise<ResolveLastPointerResponse>;
  executeAction(intent: GestureIntent): Promise<ActionExecutionResult>;
};

export function createNativePortManager(deps: Dependencies) {
  return {
    async handleNativeMessage(message: GestureEventMessage) {
      if (message.version !== 1 || message.type !== "gesture_event") {
        return;
      }

      if (message.payload.gesture === "three_finger_tap") {
        const resolved = await deps.resolveLastPointer();
        if (resolved.status !== "success") {
          deps.port.postMessage(actionResult(message.id, "open_link_background", resolved.status));
          return;
        }
        deps.port.postMessage(actionResultFromExecution(message.id, await deps.executeAction({ action: "open_link_background", url: resolved.url })));
        return;
      }

      const intent = intentFromGesture(message.payload.gesture);
      deps.port.postMessage(actionResultFromExecution(message.id, await deps.executeAction(intent)));
    }
  };
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
