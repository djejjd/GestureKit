import type {
  ActionStatus,
  DiagnosticEventKind,
  DiagnosticEventMessage,
  DiagnosticReason,
  DiagnosticSource,
  GestureRecognitionThresholds,
  GestureType,
  ActionType,
  SwipeSensitivity
} from "../protocol/messages";

export const DIAGNOSTICS_STORAGE_KEY = "gesturekitDiagnostics";

export type DiagnosticsStorage = {
  get(key: string): Promise<Record<string, unknown>>;
  set(items: Record<string, unknown>): Promise<void>;
};

export type GestureDiagnosticEntry = {
  id: string;
  timestamp: number;
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
};

export type DiagnosticsSummary = {
  swipeSuccessText: string;
  mainFailureReason: string;
  suggestion: string;
};

export async function appendDiagnostic(
  storage: DiagnosticsStorage,
  entry: GestureDiagnosticEntry,
  limit = 100
): Promise<GestureDiagnosticEntry[]> {
  const result = await storage.get(DIAGNOSTICS_STORAGE_KEY);
  const existing = normalizeDiagnostics(result[DIAGNOSTICS_STORAGE_KEY]);
  const next = [...existing, entry].slice(-limit);
  await storage.set({ [DIAGNOSTICS_STORAGE_KEY]: next });
  return next;
}

export async function clearDiagnostics(storage: DiagnosticsStorage): Promise<void> {
  await storage.set({ [DIAGNOSTICS_STORAGE_KEY]: [] });
}

export function diagnosticEntryFromMessage(message: DiagnosticEventMessage): GestureDiagnosticEntry {
  return {
    id: message.id,
    timestamp: message.timestamp,
    ...message.payload
  };
}

export function normalizeDiagnostics(value: unknown): GestureDiagnosticEntry[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter(isDiagnosticEntry).slice(-100);
}

export function summarizeDiagnostics(events: GestureDiagnosticEntry[]): DiagnosticsSummary {
  const swipes = events
    .filter((event) => event.gesture === "three_finger_swipe_left" || event.gesture === "three_finger_swipe_right")
    .slice(-10);
  if (swipes.length === 0) {
    return {
      swipeSuccessText: "暂无",
      mainFailureReason: "暂无",
      suggestion: "继续使用，等待更多数据"
    };
  }

  const successes = swipes.filter((event) => event.status === "success" || event.reason === "success").length;
  const failures = swipes.filter((event) => event.reason !== "success");
  const mainReason = mostCommonReason(failures);
  return {
    swipeSuccessText: `${successes} / ${swipes.length}`,
    mainFailureReason: mainReason ? reasonLabel(mainReason) : "暂无",
    suggestion: suggestionFor(mainReason)
  };
}

export function formatDiagnosticsForClipboard(events: GestureDiagnosticEntry[]): string {
  const lines = [
    "GestureKit Diagnostics",
    `count=${events.length}`,
    ...events.slice(-20).map((event) => {
      const parts = [
        `time=${event.timestamp}`,
        `source=${event.source}`,
        `kind=${event.kind}`,
        event.gesture ? `gesture=${event.gesture}` : null,
        event.action ? `action=${event.action}` : null,
        event.status ? `status=${event.status}` : null,
        `reason=${event.reason}`,
        event.swipeSensitivity ? `sensitivity=${event.swipeSensitivity}` : null,
        typeof event.dx === "number" ? `dx=${event.dx.toFixed(3)}` : null,
        typeof event.dy === "number" ? `dy=${event.dy.toFixed(3)}` : null,
        typeof event.durationMs === "number" ? `durationMs=${event.durationMs}` : null,
        event.thresholds ? `minDistance=${event.thresholds.swipeMinDistance}` : null
      ].filter(Boolean);
      return parts.join(" ");
    })
  ];
  return lines.join("\n");
}

export function isDiagnosticEventMessage(message: unknown): message is DiagnosticEventMessage {
  return isRecord(message) &&
    message.version === 1 &&
    message.type === "diagnostic_event" &&
    typeof message.id === "string" &&
    typeof message.timestamp === "number" &&
    isRecord(message.payload) &&
    isDiagnosticSource(message.payload.source) &&
    isDiagnosticEventKind(message.payload.kind) &&
    isDiagnosticReason(message.payload.reason);
}

export function diagnosticFromActionResult(
  id: string,
  timestamp: number,
  action: ActionType,
  status: ActionStatus
): GestureDiagnosticEntry {
  return {
    id: `action-${id}-${timestamp}`,
    timestamp,
    source: "extension",
    kind: "action",
    action,
    status,
    reason: status === "success" ? "success" : reasonFromStatus(status)
  };
}

function mostCommonReason(events: GestureDiagnosticEntry[]): DiagnosticReason | null {
  const counts = new Map<DiagnosticReason, number>();
  for (const event of events) {
    counts.set(event.reason, (counts.get(event.reason) ?? 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
}

export function reasonLabel(reason: DiagnosticReason): string {
  const labels: Record<DiagnosticReason, string> = {
    success: "成功",
    distance_too_short: "横向距离不足",
    too_slow: "滑动偏慢",
    too_fast: "滑动过快",
    horizontal_ratio_too_low: "手势偏斜",
    cooldown: "动作冷却中",
    not_chrome: "非 Chrome 前台",
    native_host_disconnected: "Native host 已断开",
    page_unavailable: "当前页面不可用",
    no_target: "未命中目标",
    unknown: "未知"
  };
  return labels[reason];
}

function suggestionFor(reason: DiagnosticReason | null): string {
  if (reason === "distance_too_short") {
    return "可以尝试“灵敏”";
  }
  if (reason === "horizontal_ratio_too_low") {
    return "手势偏斜，先保持当前灵敏度";
  }
  if (reason === "too_slow") {
    return "动作需要更短促";
  }
  if (reason === "native_host_disconnected" || reason === "page_unavailable") {
    return "先排查连接或页面状态";
  }
  return "继续观察，暂不调整";
}

function reasonFromStatus(status: ActionStatus): DiagnosticReason {
  if (status === "native_host_disconnected") {
    return "native_host_disconnected";
  }
  if (status === "page_unavailable") {
    return "page_unavailable";
  }
  if (status === "no_target") {
    return "no_target";
  }
  if (status === "gesture_unstable") {
    return "unknown";
  }
  return status === "success" ? "success" : "unknown";
}

function isDiagnosticEntry(value: unknown): value is GestureDiagnosticEntry {
  return isRecord(value) &&
    typeof value.id === "string" &&
    typeof value.timestamp === "number" &&
    isDiagnosticSource(value.source) &&
    isDiagnosticEventKind(value.kind) &&
    isDiagnosticReason(value.reason);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isDiagnosticSource(value: unknown): value is DiagnosticSource {
  return value === "app" || value === "host" || value === "extension";
}

function isDiagnosticEventKind(value: unknown): value is DiagnosticEventKind {
  return value === "gesture" || value === "action" || value === "connection" || value === "settings";
}

function isDiagnosticReason(value: unknown): value is DiagnosticReason {
  return value === "success" ||
    value === "distance_too_short" ||
    value === "too_slow" ||
    value === "too_fast" ||
    value === "horizontal_ratio_too_low" ||
    value === "cooldown" ||
    value === "not_chrome" ||
    value === "native_host_disconnected" ||
    value === "page_unavailable" ||
    value === "no_target" ||
    value === "unknown";
}
