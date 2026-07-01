export type GestureType =
  | "three_finger_tap"
  | "three_finger_swipe_left"
  | "three_finger_swipe_right";

export type ActionType =
  | "open_link_background"
  | "activate_left_tab"
  | "activate_right_tab";

export type ActionStatus =
  | "success"
  | "edge_reached"
  | "no_recent_pointer"
  | "no_target"
  | "page_unavailable"
  | "unsupported_url_scheme"
  | "unsupported_app"
  | "native_host_disconnected"
  | "app_unavailable"
  | "extension_unavailable"
  | "gesture_unstable"
  | "error";

export type GestureKitMessage<TType extends string, TPayload extends object> = {
  version: 1;
  id: string;
  type: TType;
  timestamp: number;
  payload: TPayload;
  error: null | {
    code: string;
    message: string;
  };
};

export type GestureEventMessage = GestureKitMessage<
  "gesture_event",
  {
    gesture: GestureType;
    appBundleId: string;
    confidence?: number;
  }
>;

export type ActionResultMessage = GestureKitMessage<
  "action_result",
  {
    action: ActionType;
    status: ActionStatus;
    details?: Record<string, unknown>;
  }
>;
