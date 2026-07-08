import { describe, expect, it } from "vitest";
import {
  buildRecommendedSettings,
  describeRecognitionDelta,
  resolveEffectiveSwipeRecognition
} from "../src/settings/swipeRecognition";
import { GESTURE_SETTINGS_PRESETS } from "../src/settings/gestureSettings";
import type { DiagnosticsSummary } from "../src/diagnostics/diagnostics";

const summaryFixture: DiagnosticsSummary = {
  swipeSuccessText: "3 / 5",
  mainFailureReason: "横向距离不足",
  suggestion: "可以尝试「灵敏」",
  recommendedSensitivity: "sensitive",
  recommendedMinDistance: 0.084,
  recommendationText: "推荐档位 灵敏，推荐最小距离 0.084"
};

describe("swipe recognition", () => {
  describe("resolveEffectiveSwipeRecognition", () => {
    it("returns preset values when no override", () => {
      const effective = resolveEffectiveSwipeRecognition(GESTURE_SETTINGS_PRESETS.safe);

      expect(effective.swipeSensitivity).toBe("robust");
      expect(effective.swipeMinDistance).toBe(0.11);
      expect(effective.source).toBe("preset");
    });

    it("returns preset values when override source is not recommended", () => {
      const settings = {
        ...GESTURE_SETTINGS_PRESETS.safe,
        swipeRecognitionOverride: {
          source: "preset" as const,
          recommendedMinDistance: 0.09
        }
      };

      const effective = resolveEffectiveSwipeRecognition(settings);

      expect(effective.source).toBe("preset");
      expect(effective.swipeMinDistance).toBe(0.11);
    });

    it("returns recommended override when present and valid", () => {
      const settings = {
        ...GESTURE_SETTINGS_PRESETS.safe,
        swipeSensitivity: "standard",
        swipeRecognitionOverride: {
          source: "recommended" as const,
          recommendedMinDistance: 0.084
        }
      };

      const effective = resolveEffectiveSwipeRecognition(settings);

      expect(effective.swipeSensitivity).toBe("standard");
      expect(effective.swipeMinDistance).toBe(0.084);
      expect(effective.swipeHorizontalRatio).toBe(1.5);
      expect(effective.source).toBe("recommended");
    });

    it("falls back to preset when recommendedMinDistance is null", () => {
      const settings = {
        ...GESTURE_SETTINGS_PRESETS.safe,
        swipeRecognitionOverride: {
          source: "recommended" as const,
          recommendedMinDistance: null
        }
      };

      const effective = resolveEffectiveSwipeRecognition(settings);

      expect(effective.source).toBe("preset");
      expect(effective.swipeMinDistance).toBe(0.11);
    });
  });

  describe("buildRecommendedSettings", () => {
    it("builds recommended settings from diagnostics summary", () => {
      const next = buildRecommendedSettings(GESTURE_SETTINGS_PRESETS.safe, {
        ...summaryFixture,
        recommendedSensitivity: "sensitive",
        recommendedMinDistance: 0.084
      });

      expect(next).toMatchObject({
        swipeSensitivity: "sensitive",
        swipeRecognitionOverride: {
          source: "recommended",
          recommendedMinDistance: 0.084
        }
      });
    });

    it("returns null when diagnostics has no recommendation", () => {
      const next = buildRecommendedSettings(GESTURE_SETTINGS_PRESETS.safe, {
        ...summaryFixture,
        recommendedSensitivity: "standard",
        recommendedMinDistance: null
      });

      expect(next).toBeNull();
    });

    it("preserves non-swipe settings when building recommendation", () => {
      const settings = {
        ...GESTURE_SETTINGS_PRESETS.safe,
        edgeTapEnabled: false,
        cooldownMs: 200
      };

      const next = buildRecommendedSettings(settings, {
        ...summaryFixture,
        recommendedSensitivity: "sensitive",
        recommendedMinDistance: 0.084
      });

      expect(next).toMatchObject({
        edgeTapEnabled: false,
        cooldownMs: 200,
        swipeSensitivity: "sensitive"
      });
    });
  });

  describe("describeRecognitionDelta", () => {
    it("describes sensitivity difference", () => {
      const current = { ...resolveEffectiveSwipeRecognition(GESTURE_SETTINGS_PRESETS.safe) };
      const recommended = { ...current, swipeSensitivity: "sensitive" as const, swipeMinDistance: 0.084 };

      const lines = describeRecognitionDelta(current, recommended);

      expect(lines.some((l) => l.includes("robust") && l.includes("sensitive"))).toBe(true);
    });

    it("describes min distance difference", () => {
      const current = resolveEffectiveSwipeRecognition({
        ...GESTURE_SETTINGS_PRESETS.safe,
        swipeSensitivity: "standard"
      });
      const recommended = { ...current, swipeMinDistance: 0.075 };

      const lines = describeRecognitionDelta(current, recommended);

      expect(lines.some((l) => l.includes("0.090") && l.includes("0.075"))).toBe(true);
    });

    it("reports consistency when values match", () => {
      const current = resolveEffectiveSwipeRecognition({
        ...GESTURE_SETTINGS_PRESETS.safe,
        swipeSensitivity: "standard"
      });

      const lines = describeRecognitionDelta(current, { ...current });

      expect(lines.some((l) => l.includes("一致"))).toBe(true);
    });
  });
});
