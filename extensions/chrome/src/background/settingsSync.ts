import type { SettingsAckMessage, SettingsUpdateMessage } from "../protocol/messages";
import type { GestureSettings, SwipeSensitivity } from "../settings/gestureSettings";

export const SETTINGS_SYNC_STATUS_STORAGE_KEY = "gesturekitSettingsSync";

type SwipeRecognitionPreset = SettingsUpdateMessage["payload"];

const SWIPE_RECOGNITION_PRESETS: Record<SwipeSensitivity, SwipeRecognitionPreset> = {
  robust: {
    swipeSensitivity: "robust",
    swipeMinDistance: 0.11,
    swipeHorizontalRatio: 1.8,
    swipeMinDurationMs: 60,
    swipeMaxDurationMs: 350
  },
  standard: {
    swipeSensitivity: "standard",
    swipeMinDistance: 0.09,
    swipeHorizontalRatio: 1.5,
    swipeMinDurationMs: 60,
    swipeMaxDurationMs: 420
  },
  sensitive: {
    swipeSensitivity: "sensitive",
    swipeMinDistance: 0.075,
    swipeHorizontalRatio: 1.25,
    swipeMinDurationMs: 50,
    swipeMaxDurationMs: 480
  }
};

export type SettingsSyncStatus = {
  applied: boolean;
  swipeSensitivity: SwipeSensitivity;
  lastSyncedAt: number;
  message?: string;
};

export function createSettingsUpdateMessage(settings: GestureSettings, timestamp = Date.now()): SettingsUpdateMessage {
  return {
    version: 1,
    id: `settings-${timestamp}`,
    type: "settings_update",
    timestamp,
    payload: SWIPE_RECOGNITION_PRESETS[settings.swipeSensitivity],
    error: null
  };
}

export function settingsSyncStatusFromAck(message: SettingsAckMessage): SettingsSyncStatus {
  return {
    applied: message.payload.applied,
    swipeSensitivity: message.payload.swipeSensitivity,
    lastSyncedAt: message.timestamp,
    message: message.payload.message
  };
}

export function isSettingsAckMessage(message: unknown): message is SettingsAckMessage {
  return isRecord(message) &&
    message.version === 1 &&
    message.type === "settings_ack" &&
    isRecord(message.payload) &&
    typeof message.payload.applied === "boolean" &&
    isSwipeSensitivity(message.payload.swipeSensitivity);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isSwipeSensitivity(value: unknown): value is SwipeSensitivity {
  return value === "robust" || value === "standard" || value === "sensitive";
}
