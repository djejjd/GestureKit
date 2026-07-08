export type GestureType =
  | "three_finger_tap"
  | "three_finger_swipe_left"
  | "three_finger_swipe_right";

export type ActionType =
  | "open_link_background"
  | "activate_left_tab"
  | "activate_right_tab"
  | "close_tab";

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
    touchX?: number;
    durationMs?: number;
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

export type ProbeRequestMessage = GestureKitMessage<
  "probe_request",
  {
    source: "extension_smoke_page";
  }
>;

export type ProbeResponseMessage = GestureKitMessage<
  "probe_response",
  {
    hostConnected: boolean;
    appConnected: boolean;
    appSessionId?: string;
    message?: string;
  }
>;

export type SwipeSensitivity = "robust" | "standard" | "sensitive";

export type SettingsUpdateMessage = GestureKitMessage<
  "settings_update",
  {
    swipeSensitivity: SwipeSensitivity;
    swipeMinDistance: number;
    swipeHorizontalRatio: number;
    swipeMinDurationMs: number;
    swipeMaxDurationMs: number;
  }
>;

export type SettingsAckMessage = GestureKitMessage<
  "settings_ack",
  {
    applied: boolean;
    swipeSensitivity: SwipeSensitivity;
    appSessionId: string;
    recognitionSettings: GestureRecognitionThresholds;
    message?: string;
  }
>;

export type DiagnosticSource = "app" | "host" | "extension";
export type DiagnosticEventKind = "gesture" | "action" | "connection" | "settings";
export type DiagnosticReason =
  | "success"
  | "distance_too_short"
  | "too_slow"
  | "too_fast"
  | "horizontal_ratio_too_low"
  | "cooldown"
  | "flick_switch_disabled"
  | "edge_tap_disabled"
  | "double_tap_disabled"
  | "tap_duration_unstable"
  | "chrome_action_failed"
  | "click_already_fired"
  | "not_chrome"
  | "native_host_disconnected"
  | "page_unavailable"
  | "no_target"
  | "unknown";

export type GestureRecognitionThresholds = {
  swipeSensitivity: SwipeSensitivity;
  swipeMinDistance: number;
  swipeHorizontalRatio: number;
  swipeMinDurationMs: number;
  swipeMaxDurationMs: number;
};

export type DiagnosticEventMessage = GestureKitMessage<
  "diagnostic_event",
  {
    source: DiagnosticSource;
    kind: DiagnosticEventKind;
    gesture?: GestureType;
    action?: ActionType;
    status?: ActionStatus;
    reason: DiagnosticReason;
    swipeSensitivity?: SwipeSensitivity;
    dx?: number;
    dy?: number;
    distance?: number;
    durationMs?: number;
    horizontalRatio?: number;
    thresholds?: GestureRecognitionThresholds;
    message?: string;
  }
>;
