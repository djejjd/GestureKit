export type GestureSettingsMode = "safe" | "efficient";
export type SwipeSensitivity = "robust" | "standard" | "sensitive";

export type SwipeRecognitionOverride = {
  source: "preset" | "recommended";
  recommendedMinDistance: number | null;
};

export type GestureSettings = {
  mode: GestureSettingsMode;
  swipeSensitivity: SwipeSensitivity;
  edgeTapEnabled: boolean;
  doubleTapCloseEnabled: boolean;
  flickSwitchEnabled: boolean;
  linkClickProtectionEnabled: boolean;
  leftEdgeMax: number;
  rightEdgeMin: number;
  doubleTapMinMs: number;
  doubleTapMaxMs: number;
  cooldownMs: number;
  tapDurationMinMs: number;
  tapDurationMaxMs: number;
  swipeRecognitionOverride: SwipeRecognitionOverride | null;
};

export type GestureSettingsInput = Partial<GestureSettings> & {
  mode?: GestureSettingsMode;
};

export type GestureSettingsStorage = {
  get(key: string): Promise<Record<string, unknown>>;
  set(items: Record<string, unknown>): Promise<void>;
};

export const GESTURE_SETTINGS_STORAGE_KEY = "gesturekitGestureSettings";

export const GESTURE_SETTINGS_PRESETS: Record<GestureSettingsMode, GestureSettings> = {
  safe: {
    mode: "safe",
    swipeSensitivity: "robust",
    edgeTapEnabled: true,
    doubleTapCloseEnabled: true,
    flickSwitchEnabled: true,
    linkClickProtectionEnabled: false,
    leftEdgeMax: 0.3,
    rightEdgeMin: 0.7,
    doubleTapMinMs: 160,
    doubleTapMaxMs: 330,
    cooldownMs: 260,
    tapDurationMinMs: 45,
    tapDurationMaxMs: 200,
    swipeRecognitionOverride: null
  },
  efficient: {
    mode: "efficient",
    swipeSensitivity: "sensitive",
    edgeTapEnabled: true,
    doubleTapCloseEnabled: true,
    flickSwitchEnabled: true,
    linkClickProtectionEnabled: false,
    leftEdgeMax: 0.38,
    rightEdgeMin: 0.62,
    doubleTapMinMs: 120,
    doubleTapMaxMs: 380,
    cooldownMs: 160,
    tapDurationMinMs: 35,
    tapDurationMaxMs: 240,
    swipeRecognitionOverride: null
  }
};

export function normalizeGestureSettings(input: GestureSettingsInput | unknown): GestureSettings {
  const raw = isRecord(input) ? input : {};
  const mode = raw.mode === "efficient" ? "efficient" : "safe";
  const preset = GESTURE_SETTINGS_PRESETS[mode];
  const merged = {
    ...preset,
    ...raw,
    mode
  };

  let leftEdgeMax = clampNumber(merged.leftEdgeMax, preset.leftEdgeMax, 0.2, 0.4);
  let rightEdgeMin = clampNumber(merged.rightEdgeMin, preset.rightEdgeMin, 0.6, 0.8);
  const rawEdgesCross =
    typeof merged.leftEdgeMax === "number" &&
    typeof merged.rightEdgeMin === "number" &&
    merged.leftEdgeMax >= merged.rightEdgeMin - 0.1;
  if (rawEdgesCross || leftEdgeMax >= rightEdgeMin - 0.1) {
    leftEdgeMax = preset.leftEdgeMax;
    rightEdgeMin = preset.rightEdgeMin;
  }

  let doubleTapMinMs = clampNumber(merged.doubleTapMinMs, preset.doubleTapMinMs, 80, 220);
  let doubleTapMaxMs = clampNumber(merged.doubleTapMaxMs, preset.doubleTapMaxMs, 240, 500);
  if (doubleTapMinMs >= doubleTapMaxMs - 80) {
    doubleTapMinMs = preset.doubleTapMinMs;
    doubleTapMaxMs = preset.doubleTapMaxMs;
  }

  let tapDurationMinMs = clampNumber(merged.tapDurationMinMs, preset.tapDurationMinMs, 20, 100);
  let tapDurationMaxMs = clampNumber(merged.tapDurationMaxMs, preset.tapDurationMaxMs, 120, 320);
  if (tapDurationMinMs >= tapDurationMaxMs - 80) {
    tapDurationMinMs = preset.tapDurationMinMs;
    tapDurationMaxMs = preset.tapDurationMaxMs;
  }

  return {
    mode,
    swipeSensitivity: isSwipeSensitivity(merged.swipeSensitivity) ? merged.swipeSensitivity : preset.swipeSensitivity,
    edgeTapEnabled: typeof merged.edgeTapEnabled === "boolean" ? merged.edgeTapEnabled : preset.edgeTapEnabled,
    doubleTapCloseEnabled: typeof merged.doubleTapCloseEnabled === "boolean"
      ? merged.doubleTapCloseEnabled
      : preset.doubleTapCloseEnabled,
    flickSwitchEnabled: typeof merged.flickSwitchEnabled === "boolean"
      ? merged.flickSwitchEnabled
      : preset.flickSwitchEnabled,
    linkClickProtectionEnabled: typeof merged.linkClickProtectionEnabled === "boolean"
      ? merged.linkClickProtectionEnabled
      : preset.linkClickProtectionEnabled,
    leftEdgeMax,
    rightEdgeMin,
    doubleTapMinMs,
    doubleTapMaxMs,
    cooldownMs: clampNumber(merged.cooldownMs, preset.cooldownMs, 80, 500),
    tapDurationMinMs,
    tapDurationMaxMs,
    swipeRecognitionOverride: normalizeSwipeRecognitionOverride(merged.swipeRecognitionOverride)
  };
}

export async function loadGestureSettings(storage: GestureSettingsStorage): Promise<GestureSettings> {
  const result = await storage.get(GESTURE_SETTINGS_STORAGE_KEY);
  return normalizeGestureSettings(result[GESTURE_SETTINGS_STORAGE_KEY]);
}

export async function saveGestureSettings(
  storage: GestureSettingsStorage,
  input: GestureSettingsInput
): Promise<GestureSettings> {
  const settings = normalizeGestureSettings(input);
  await storage.set({ [GESTURE_SETTINGS_STORAGE_KEY]: settings });
  return settings;
}

function clampNumber(value: unknown, fallback: number, min: number, max: number): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.min(max, Math.max(min, value))
    : fallback;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isSwipeSensitivity(value: unknown): value is SwipeSensitivity {
  return value === "robust" || value === "standard" || value === "sensitive";
}

function normalizeSwipeRecognitionOverride(value: unknown): SwipeRecognitionOverride | null {
  if (!isRecord(value)) {
    return null;
  }
  const source = value.source === "preset" || value.source === "recommended"
    ? value.source
    : null;
  if (source === null) {
    return null;
  }
  const recommendedMinDistance = typeof value.recommendedMinDistance === "number" &&
    Number.isFinite(value.recommendedMinDistance) &&
    value.recommendedMinDistance >= 0.05 &&
    value.recommendedMinDistance <= 0.20
    ? value.recommendedMinDistance
    : (source === "recommended" ? null : null);
  if (source === "recommended" && recommendedMinDistance === null) {
    return null;
  }
  return { source, recommendedMinDistance };
}
