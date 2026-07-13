import type { SettingsAckMessage, SettingsUpdateMessage } from "../protocol/messages";
import type { GestureSettings, SwipeSensitivity } from "../settings/gestureSettings";
import {
  resolveEffectiveSwipeRecognition,
  describeRecognitionDelta
} from "../settings/swipeRecognition";

export const SETTINGS_SYNC_STATUS_STORAGE_KEY = "gesturekitSettingsSync";

export type SettingsSyncPhase = "saved_only" | "pending" | "applied" | "failed" | "stale";

export type SettingsSyncStatus = {
  phase: SettingsSyncPhase;
  savedSwipeSensitivity: SwipeSensitivity;
  runtimeSwipeSensitivity: SwipeSensitivity | null;
  currentAppSessionId: string | null;
  requestedAt: number | null;
  appliedAt: number | null;
  messageId: string | null;
  deltaSummary: string[];
  message?: string;
};

export function createSettingsUpdateMessage(
  settings: GestureSettings,
  timestamp = Date.now()
): SettingsUpdateMessage {
  const recognition = resolveEffectiveSwipeRecognition(settings);
  return {
    version: 1,
    id: `settings-${timestamp}`,
    type: "settings_update",
    timestamp,
    payload: {
      swipeSensitivity: recognition.swipeSensitivity,
      swipeMinDistance: recognition.swipeMinDistance,
      swipeHorizontalRatio: recognition.swipeHorizontalRatio,
      swipeMinDurationMs: recognition.swipeMinDurationMs,
      swipeMaxDurationMs: recognition.swipeMaxDurationMs
    },
    error: null
  };
}

export function createPendingSettingsSyncStatus(
  settings: GestureSettings,
  messageId: string,
  previous: SettingsSyncStatus | null,
  timestamp: number
): SettingsSyncStatus {
  return {
    phase: "pending",
    savedSwipeSensitivity: settings.swipeSensitivity,
    runtimeSwipeSensitivity: previous?.runtimeSwipeSensitivity ?? null,
    currentAppSessionId: previous?.currentAppSessionId ?? null,
    requestedAt: timestamp,
    appliedAt: null,
    messageId,
    deltaSummary: previous?.deltaSummary ?? []
  };
}

export function createSavedOnlySettingsSyncStatus(
  settings: GestureSettings,
  previous: SettingsSyncStatus | null
): SettingsSyncStatus {
  return {
    phase: "saved_only",
    savedSwipeSensitivity: settings.swipeSensitivity,
    runtimeSwipeSensitivity: previous?.runtimeSwipeSensitivity ?? null,
    currentAppSessionId: previous?.currentAppSessionId ?? null,
    requestedAt: null,
    appliedAt: previous?.appliedAt ?? null,
    messageId: null,
    deltaSummary: previous?.deltaSummary ?? []
  };
}

export function settingsSyncStatusFromAck(
  message: SettingsAckMessage,
  settings: GestureSettings,
  currentStatus: SettingsSyncStatus | null
): SettingsSyncStatus {
  if (currentStatus) {
    if (currentStatus.phase !== "pending") {
      return currentStatus;
    }
    if (currentStatus.messageId !== message.id) {
      return currentStatus;
    }
  }

  const effective = resolveEffectiveSwipeRecognition(settings);
  const recommended: Parameters<typeof describeRecognitionDelta>[1] = {
    ...message.payload.recognitionSettings,
    swipeSensitivity: message.payload.swipeSensitivity,
    source: "recommended" as const
  };

  return {
    phase: message.payload.applied ? "applied" : "failed",
    savedSwipeSensitivity: settings.swipeSensitivity,
    runtimeSwipeSensitivity: message.payload.swipeSensitivity,
    currentAppSessionId: message.payload.appSessionId,
    requestedAt: null,
    appliedAt: message.timestamp,
    messageId: message.id,
    deltaSummary: describeRecognitionDelta(effective, recommended),
    message: message.payload.message
  };
}

export function markSettingsSyncFailed(
  previous: SettingsSyncStatus | null,
  reason: string,
  timestamp: number
): SettingsSyncStatus {
  return {
    phase: "failed",
    savedSwipeSensitivity: previous?.savedSwipeSensitivity ?? "standard",
    runtimeSwipeSensitivity: previous?.runtimeSwipeSensitivity ?? null,
    currentAppSessionId: previous?.currentAppSessionId ?? null,
    requestedAt: previous?.requestedAt ?? null,
    appliedAt: null,
    messageId: null,
    deltaSummary: previous?.deltaSummary ?? [],
    message: reason
  };
}

export function markSettingsSyncStale(
  previous: SettingsSyncStatus | null,
  appSessionId: string | null,
  timestamp: number
): SettingsSyncStatus {
  if (!previous) {
    return {
      phase: "saved_only",
      savedSwipeSensitivity: "standard",
      runtimeSwipeSensitivity: null,
      currentAppSessionId: appSessionId,
      requestedAt: null,
      appliedAt: null,
      messageId: null,
      deltaSummary: [],
      message: undefined
    };
  }

  const isStale = previous.phase === "applied" &&
    previous.currentAppSessionId !== null &&
    appSessionId !== null &&
    previous.currentAppSessionId !== appSessionId;

  return {
    ...previous,
    phase: isStale ? "stale" : previous.phase,
    currentAppSessionId: appSessionId ?? previous.currentAppSessionId,
    message: isStale ? "App 已重启，需要重新应用或等待自动重同步" : previous.message
  };
}

export function isSettingsSyncStatus(value: unknown): value is SettingsSyncStatus {
  return isRecord(value) &&
    typeof value.phase === "string" &&
    ["saved_only", "pending", "applied", "failed", "stale"].includes(value.phase) &&
    isSwipeSensitivity(value.savedSwipeSensitivity);
}

export function isSettingsAckMessage(message: unknown): message is SettingsAckMessage {
  return isRecord(message) &&
    message.version === 1 &&
    message.type === "settings_ack" &&
    isRecord(message.payload) &&
    typeof message.payload.applied === "boolean" &&
    typeof message.payload.appSessionId === "string" &&
    isSwipeSensitivity(message.payload.swipeSensitivity) &&
    isRecord(message.payload.recognitionSettings) &&
    isSwipeSensitivity(message.payload.recognitionSettings.swipeSensitivity);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isSwipeSensitivity(value: unknown): value is SwipeSensitivity {
  return value === "robust" || value === "standard" || value === "sensitive";
}
