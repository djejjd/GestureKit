import { beforeEach, describe, expect, it, vi } from "vitest";
import { GESTURE_SETTINGS_PRESETS, GESTURE_SETTINGS_STORAGE_KEY } from "../src/settings/gestureSettings";
import { initializeGestureSettingsPopup } from "../src/popup/popup";
import { SETTINGS_SYNC_STATUS_STORAGE_KEY } from "../src/background/settingsSync";
import { DIAGNOSTICS_STORAGE_KEY, type GestureDiagnosticEntry } from "../src/diagnostics/diagnostics";

const storageListeners: Array<(changes: Record<string, { oldValue?: unknown; newValue?: unknown }>, areaName: string) => void> = [];

function setupDom() {
  document.body.innerHTML = `
    <select id="mode">
      <option value="safe">安全模式</option>
      <option value="efficient">高效模式</option>
    </select>
    <select id="swipeSensitivity">
      <option value="robust">稳健</option>
      <option value="standard">标准</option>
      <option value="sensitive">灵敏</option>
    </select>
    <input id="edgeTapEnabled" type="checkbox" />
    <input id="doubleTapCloseEnabled" type="checkbox" />
    <input id="flickSwitchEnabled" type="checkbox" />
    <input id="linkClickProtectionEnabled" type="checkbox" />
    <input id="edgeWidth" type="range" min="20" max="40" />
    <output id="edgeWidthValue"></output>
    <input id="doubleTapSpeed" type="range" min="240" max="500" />
    <output id="doubleTapSpeedValue"></output>
    <input id="cooldownMs" type="range" min="80" max="500" />
    <output id="cooldownMsValue"></output>
    <div id="nativeStatus"></div>
    <div id="appStatus"></div>
    <div id="settingsSyncStatus"></div>
    <div id="lastResult"></div>
    <div id="swipeSuccessRate"></div>
    <div id="mainFailureReason"></div>
    <div id="diagnosticsSuggestion"></div>
    <div id="recommendedSensitivity"></div>
    <div id="recommendedMinDistance"></div>
    <button id="diagnosticsToggle" aria-expanded="false"></button>
    <div id="diagnosticsPanel" hidden>
      <div id="diagnosticsList"></div>
    </div>
    <button id="copyDiagnostics"></button>
    <button id="clearDiagnostics"></button>
    <section class="recommendation">
      <div id="recommendationDelta"></div>
      <strong id="recommendationSavedStatus"></strong>
      <strong id="recommendationRuntimeStatus"></strong>
      <strong id="recommendationFailureReason"></strong>
      <button id="applyRecommendedSettings" type="button">应用推荐设置</button>
    </section>
    <button id="resetDefaults"></button>
  `;
}

function storageWith(
  value: unknown = GESTURE_SETTINGS_PRESETS.safe,
  status: unknown = undefined,
  diagnostics: GestureDiagnosticEntry[] = [],
  syncStatus: unknown = undefined
) {
  const state: Record<string, unknown> = {
    [GESTURE_SETTINGS_STORAGE_KEY]: value,
    [DIAGNOSTICS_STORAGE_KEY]: diagnostics
  };
  if (status !== undefined) {
    state.gesturekitStatus = status;
  }
  if (syncStatus !== undefined) {
    state[SETTINGS_SYNC_STATUS_STORAGE_KEY] = syncStatus;
  }
  return {
    get: vi.fn(async (key: string | string[]) => {
      const keys = Array.isArray(key) ? key : [key];
      return Object.fromEntries(keys.map((item) => [item, state[item]]));
    }),
    set: vi.fn(async (items: Record<string, unknown>) => {
      Object.assign(state, items);
    }),
    state
  };
}

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
}

describe("gesture settings popup", () => {
  beforeEach(() => {
    setupDom();
    storageListeners.length = 0;
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {
        writeText: vi.fn(async () => {})
      }
    });
    Object.defineProperty(globalThis, "chrome", {
      configurable: true,
      value: {
        runtime: {
          sendMessage: vi.fn(async () => ({ status: "connected" }))
        },
        storage: {
          onChanged: {
            addListener: vi.fn((listener: (changes: Record<string, { oldValue?: unknown; newValue?: unknown }>, areaName: string) => void) => {
              storageListeners.push(listener);
            }),
            removeListener: vi.fn()
          }
        }
      }
    });
  });

  it("renders stored settings and status", async () => {
    const storage = storageWith(
      { ...GESTURE_SETTINGS_PRESETS.efficient, doubleTapCloseEnabled: false },
      {
        nativeConnected: true,
        appConnected: false,
        lastResult: "open_link_background success"
      },
      [],
      {
        phase: "applied",
        savedSwipeSensitivity: "sensitive",
        runtimeSwipeSensitivity: "sensitive",
        currentAppSessionId: "sess-1",
        requestedAt: null,
        appliedAt: 200,
        messageId: "ack-1",
        deltaSummary: [],
        message: undefined
      }
    );

    await initializeGestureSettingsPopup(document, storage);

    expect((document.querySelector("#mode") as HTMLSelectElement).value).toBe("efficient");
    expect((document.querySelector("#swipeSensitivity") as HTMLSelectElement).value).toBe("sensitive");
    expect((document.querySelector("#doubleTapCloseEnabled") as HTMLInputElement).checked).toBe(false);
    expect((document.querySelector("#linkClickProtectionEnabled") as HTMLInputElement).checked).toBe(false);
    expect(document.querySelector("#nativeStatus")?.textContent).toBe("已连接");
    expect(document.querySelector("#appStatus")?.textContent).toBe("未连接");
    expect(document.querySelector("#settingsSyncStatus")?.textContent).toBe("已应用 sensitive");
    expect(document.querySelector("#lastResult")?.textContent).toBe("打开链接成功");
  });

  it("renders diagnostics summary while keeping settings controls", async () => {
    const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe, undefined, [
      swipeDiagnostic("diag-1", "success"),
      swipeDiagnostic("diag-2", "gesture_unstable"),
      swipeDiagnostic("diag-3", "gesture_unstable")
    ]);

    await initializeGestureSettingsPopup(document, storage);

    expect(document.querySelector("#mode")).toBeInstanceOf(HTMLSelectElement);
    expect(document.querySelector("#swipeSensitivity")).toBeInstanceOf(HTMLSelectElement);
    expect(document.querySelector("#swipeSuccessRate")?.textContent).toBe("1 / 3");
    expect(document.querySelector("#mainFailureReason")?.textContent).toBe("横向距离不足");
    expect(document.querySelector("#diagnosticsSuggestion")?.textContent).toBe("可以尝试“灵敏”");
    expect(document.querySelector("#recommendedSensitivity")?.textContent).toBe("灵敏");
    expect(document.querySelector("#recommendedMinDistance")?.textContent).toBe("0.110");
  });

  it("expands recent diagnostics", async () => {
    const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe, undefined, [
      swipeDiagnostic("diag-1", "gesture_unstable")
    ]);
    await initializeGestureSettingsPopup(document, storage);

    (document.querySelector("#diagnosticsToggle") as HTMLButtonElement).click();

    expect((document.querySelector("#diagnosticsToggle") as HTMLButtonElement).getAttribute("aria-expanded")).toBe("true");
    expect((document.querySelector("#diagnosticsPanel") as HTMLElement).hidden).toBe(false);
    expect(document.querySelector("#diagnosticsList")?.textContent).toContain("右轻扫");
    expect(document.querySelector("#diagnosticsList")?.textContent).toContain("横向距离不足");
  });

  it("copies diagnostics text", async () => {
    const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe, undefined, [
      swipeDiagnostic("diag-1", "gesture_unstable")
    ]);
    await initializeGestureSettingsPopup(document, storage);

    (document.querySelector("#copyDiagnostics") as HTMLButtonElement).click();
    await flushPromises();

    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(expect.stringContaining("GestureKit Diagnostics"));
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(expect.stringContaining("mode=safe"));
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(expect.stringContaining("swipeSensitivity=robust"));
  });

  it("clears diagnostics", async () => {
    const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe, undefined, [
      swipeDiagnostic("diag-1", "gesture_unstable")
    ]);
    await initializeGestureSettingsPopup(document, storage);

    (document.querySelector("#clearDiagnostics") as HTMLButtonElement).click();
    await flushPromises();

    expect(storage.set).toHaveBeenLastCalledWith({ [DIAGNOSTICS_STORAGE_KEY]: [] });
    expect(document.querySelector("#swipeSuccessRate")?.textContent).toBe("暂无");
  });

  it("applies a preset when mode changes", async () => {
    const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe);
    await initializeGestureSettingsPopup(document, storage);

    const mode = document.querySelector("#mode") as HTMLSelectElement;
    mode.value = "efficient";
    mode.dispatchEvent(new Event("change"));
    await flushPromises();

    expect((document.querySelector("#edgeWidth") as HTMLInputElement).value).toBe("38");
    expect(storage.set).toHaveBeenCalledWith({
      [GESTURE_SETTINGS_STORAGE_KEY]: expect.objectContaining({
        mode: "efficient",
        swipeSensitivity: "sensitive",
        leftEdgeMax: 0.38,
        rightEdgeMin: 0.62
      })
    });
  });

  it("saves toggle and slider changes", async () => {
    const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe);
    await initializeGestureSettingsPopup(document, storage);

    const edgeTapEnabled = document.querySelector("#edgeTapEnabled") as HTMLInputElement;
    const linkClickProtectionEnabled = document.querySelector("#linkClickProtectionEnabled") as HTMLInputElement;
    const cooldown = document.querySelector("#cooldownMs") as HTMLInputElement;
    edgeTapEnabled.checked = false;
    linkClickProtectionEnabled.checked = false;
    cooldown.value = "180";
    edgeTapEnabled.dispatchEvent(new Event("change"));
    linkClickProtectionEnabled.dispatchEvent(new Event("change"));
    cooldown.dispatchEvent(new Event("input"));
    cooldown.dispatchEvent(new Event("change"));
    await flushPromises();

    expect(storage.set).toHaveBeenLastCalledWith({
      [GESTURE_SETTINGS_STORAGE_KEY]: expect.objectContaining({
        edgeTapEnabled: false,
        linkClickProtectionEnabled: false,
        cooldownMs: 180
      })
    });
  });

  it("saves swipe sensitivity changes", async () => {
    const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe);
    await initializeGestureSettingsPopup(document, storage);

    const sensitivity = document.querySelector("#swipeSensitivity") as HTMLSelectElement;
    sensitivity.value = "standard";
    sensitivity.dispatchEvent(new Event("change"));
    await flushPromises();

    expect(storage.set).toHaveBeenLastCalledWith({
      [GESTURE_SETTINGS_STORAGE_KEY]: expect.objectContaining({
        mode: "safe",
        swipeSensitivity: "standard"
      })
    });
  });

  it("resets to safe defaults", async () => {
    const storage = storageWith(GESTURE_SETTINGS_PRESETS.efficient);
    await initializeGestureSettingsPopup(document, storage);

    (document.querySelector("#resetDefaults") as HTMLButtonElement).click();
    await flushPromises();

    expect((document.querySelector("#mode") as HTMLSelectElement).value).toBe("safe");
    expect(storage.set).toHaveBeenLastCalledWith({
      [GESTURE_SETTINGS_STORAGE_KEY]: GESTURE_SETTINGS_PRESETS.safe
    });
  });

  it("renders saved and runtime status separately", async () => {
    const storage = storageWith(
      GESTURE_SETTINGS_PRESETS.safe,
      undefined,
      [swipeDiagnostic("diag-1", "success"), swipeDiagnostic("diag-2", "success")],
      {
        phase: "saved_only",
        savedSwipeSensitivity: "sensitive",
        runtimeSwipeSensitivity: null,
        currentAppSessionId: null,
        requestedAt: null,
        appliedAt: null,
        messageId: null,
        deltaSummary: ["推荐档位与当前一致", "推荐最小距离与当前一致"],
        message: undefined
      }
    );

    await initializeGestureSettingsPopup(document, storage);

    expect(document.querySelector("#recommendationSavedStatus")?.textContent).toContain("已保存");
    expect(document.querySelector("#recommendationRuntimeStatus")?.textContent).toContain("等待确认");
  });

  it("applies recommended settings after confirmation", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true);
    const storage = storageWith(
      GESTURE_SETTINGS_PRESETS.safe,
      undefined,
      [swipeDiagnostic("diag-1", "success"), swipeDiagnostic("diag-2", "gesture_unstable")],
      {
        phase: "saved_only",
        savedSwipeSensitivity: "robust",
        runtimeSwipeSensitivity: null,
        currentAppSessionId: null,
        requestedAt: null,
        appliedAt: null,
        messageId: null,
        deltaSummary: [],
        message: undefined
      }
    );

    await initializeGestureSettingsPopup(document, storage);
    (document.querySelector("#applyRecommendedSettings") as HTMLButtonElement).click();
    await flushPromises();

    expect(storage.set).toHaveBeenCalledWith({
      [GESTURE_SETTINGS_STORAGE_KEY]: expect.objectContaining({
        swipeSensitivity: "sensitive",
        swipeRecognitionOverride: expect.objectContaining({
          source: "recommended"
        })
      })
    });
    expect(document.querySelector("#recommendationSavedStatus")?.textContent).toContain("已保存");
  });

  it("does not apply recommendation when confirm is cancelled", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(false);
    const storage = storageWith(
      GESTURE_SETTINGS_PRESETS.safe,
      undefined,
      [swipeDiagnostic("diag-1", "success")]
    );

    await initializeGestureSettingsPopup(document, storage);
    const setCallCount = (storage.set as ReturnType<typeof vi.fn>).mock.calls.length;
    (document.querySelector("#applyRecommendedSettings") as HTMLButtonElement).click();
    await flushPromises();

    expect(storage.set).toHaveBeenCalledTimes(setCallCount);
  });

  it("shows failure reason when sync failed", async () => {
    const storage = storageWith(
      GESTURE_SETTINGS_PRESETS.safe,
      undefined,
      [swipeDiagnostic("diag-1", "success")],
      {
        phase: "failed",
        savedSwipeSensitivity: "sensitive",
        runtimeSwipeSensitivity: null,
        currentAppSessionId: null,
        requestedAt: 100,
        appliedAt: null,
        messageId: null,
        deltaSummary: [],
        message: "native_host_disconnected"
      }
    );

    await initializeGestureSettingsPopup(document, storage);

    expect(document.querySelector("#recommendationFailureReason")?.textContent).toContain("native_host_disconnected");
  });

  it("refreshes recommendation status when storage sync state changes", async () => {
    const storage = storageWith(
      GESTURE_SETTINGS_PRESETS.safe,
      undefined,
      [swipeDiagnostic("diag-1", "success"), swipeDiagnostic("diag-2", "gesture_unstable")]
    );

    await initializeGestureSettingsPopup(document, storage);

    storageListeners[0]?.({
      [SETTINGS_SYNC_STATUS_STORAGE_KEY]: {
        oldValue: undefined,
        newValue: {
          phase: "applied",
          savedSwipeSensitivity: "sensitive",
          runtimeSwipeSensitivity: "sensitive",
          currentAppSessionId: "session-1",
          requestedAt: 100,
          appliedAt: 150,
          messageId: "settings-1",
          deltaSummary: [],
          message: undefined
        }
      }
    }, "local");

    expect(document.querySelector("#recommendationSavedStatus")?.textContent).toContain("已应用");
    expect(document.querySelector("#recommendationRuntimeStatus")?.textContent).toContain("sensitive");
  });
});

function swipeDiagnostic(id: string, status: "success" | "gesture_unstable"): GestureDiagnosticEntry {
  return {
    id,
    timestamp: 1_782_200_000_000,
    source: "app",
    kind: "gesture",
    gesture: "three_finger_swipe_right",
    action: "activate_right_tab",
    status,
    reason: status === "success" ? "success" : "distance_too_short",
    swipeSensitivity: "standard",
    dx: status === "success" ? 0.126 : 0.073,
    dy: 0.012,
    distance: status === "success" ? 0.127 : 0.074,
    durationMs: 164,
    horizontalRatio: 6.08,
    thresholds: {
      swipeSensitivity: "standard",
      swipeMinDistance: 0.09,
      swipeHorizontalRatio: 1.5,
      swipeMinDurationMs: 60,
      swipeMaxDurationMs: 420
    }
  };
}
