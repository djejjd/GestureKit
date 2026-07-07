import { beforeEach, describe, expect, it, vi } from "vitest";
import { GESTURE_SETTINGS_PRESETS, GESTURE_SETTINGS_STORAGE_KEY } from "../src/settings/gestureSettings";
import { initializeGestureSettingsPopup } from "../src/popup/popup";

function setupDom() {
  document.body.innerHTML = `
    <select id="mode">
      <option value="safe">安全模式</option>
      <option value="efficient">高效模式</option>
    </select>
    <input id="edgeTapEnabled" type="checkbox" />
    <input id="doubleTapCloseEnabled" type="checkbox" />
    <input id="flickSwitchEnabled" type="checkbox" />
    <input id="edgeWidth" type="range" min="20" max="40" />
    <output id="edgeWidthValue"></output>
    <input id="doubleTapSpeed" type="range" min="240" max="500" />
    <output id="doubleTapSpeedValue"></output>
    <input id="cooldownMs" type="range" min="80" max="500" />
    <output id="cooldownMsValue"></output>
    <div id="nativeStatus"></div>
    <div id="appStatus"></div>
    <div id="lastResult"></div>
    <button id="resetDefaults"></button>
  `;
}

function storageWith(value: unknown = GESTURE_SETTINGS_PRESETS.safe, status: unknown = undefined) {
  const state: Record<string, unknown> = { [GESTURE_SETTINGS_STORAGE_KEY]: value };
  if (status !== undefined) {
    state.gesturekitStatus = status;
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
  });

  it("renders stored settings and status", async () => {
    const storage = storageWith(
      { ...GESTURE_SETTINGS_PRESETS.efficient, doubleTapCloseEnabled: false },
      {
        nativeConnected: true,
        appConnected: false,
        lastResult: "gesture_unstable"
      }
    );

    await initializeGestureSettingsPopup(document, storage);

    expect((document.querySelector("#mode") as HTMLSelectElement).value).toBe("efficient");
    expect((document.querySelector("#doubleTapCloseEnabled") as HTMLInputElement).checked).toBe(false);
    expect(document.querySelector("#nativeStatus")?.textContent).toBe("已连接");
    expect(document.querySelector("#appStatus")?.textContent).toBe("未连接");
    expect(document.querySelector("#lastResult")?.textContent).toBe("gesture_unstable");
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
        leftEdgeMax: 0.38,
        rightEdgeMin: 0.62
      })
    });
  });

  it("saves toggle and slider changes", async () => {
    const storage = storageWith(GESTURE_SETTINGS_PRESETS.safe);
    await initializeGestureSettingsPopup(document, storage);

    const edgeTapEnabled = document.querySelector("#edgeTapEnabled") as HTMLInputElement;
    const cooldown = document.querySelector("#cooldownMs") as HTMLInputElement;
    edgeTapEnabled.checked = false;
    cooldown.value = "180";
    edgeTapEnabled.dispatchEvent(new Event("change"));
    cooldown.dispatchEvent(new Event("input"));
    cooldown.dispatchEvent(new Event("change"));
    await flushPromises();

    expect(storage.set).toHaveBeenLastCalledWith({
      [GESTURE_SETTINGS_STORAGE_KEY]: expect.objectContaining({
        edgeTapEnabled: false,
        cooldownMs: 180
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
});
