import type { GestureSettings, SwipeRecognitionOverride, SwipeSensitivity } from "./gestureSettings";
import type { DiagnosticsSummary } from "../diagnostics/diagnostics";

export type EffectiveSwipeRecognition = {
  swipeSensitivity: SwipeSensitivity;
  swipeMinDistance: number;
  swipeHorizontalRatio: number;
  swipeMinDurationMs: number;
  swipeMaxDurationMs: number;
  source: "preset" | "recommended";
};

const SWIPE_RECOGNITION_PRESETS: Record<SwipeSensitivity, Omit<EffectiveSwipeRecognition, "source">> = {
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

export function resolveEffectiveSwipeRecognition(settings: GestureSettings): EffectiveSwipeRecognition {
  const preset = SWIPE_RECOGNITION_PRESETS[settings.swipeSensitivity];
  if (
    settings.swipeRecognitionOverride?.source !== "recommended" ||
    settings.swipeRecognitionOverride.recommendedMinDistance === null
  ) {
    return { ...preset, source: "preset" };
  }
  return {
    ...preset,
    swipeMinDistance: settings.swipeRecognitionOverride.recommendedMinDistance,
    source: "recommended"
  };
}

export function buildRecommendedSettings(
  settings: GestureSettings,
  summary: DiagnosticsSummary
): GestureSettings | null {
  if (summary.recommendedMinDistance === null) {
    return null;
  }

  const override: SwipeRecognitionOverride = {
    source: "recommended",
    recommendedMinDistance: summary.recommendedMinDistance
  };

  return {
    ...settings,
    swipeSensitivity: summary.recommendedSensitivity,
    swipeRecognitionOverride: override
  };
}

export function describeRecognitionDelta(
  current: EffectiveSwipeRecognition,
  recommended: EffectiveSwipeRecognition
): string[] {
  const lines: string[] = [];
  lines.push(
    current.swipeSensitivity === recommended.swipeSensitivity
      ? "推荐档位与当前一致"
      : `灵敏度 ${current.swipeSensitivity} -> ${recommended.swipeSensitivity}`
  );
  lines.push(
    current.swipeMinDistance === recommended.swipeMinDistance
      ? "推荐最小距离与当前一致"
      : `最小距离 ${current.swipeMinDistance.toFixed(3)} -> ${recommended.swipeMinDistance.toFixed(3)}`
  );
  return lines;
}
