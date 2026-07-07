import {
  GESTURE_SETTINGS_PRESETS,
  loadGestureSettings,
  saveGestureSettings,
  type GestureSettings,
  type GestureSettingsMode,
  type GestureSettingsStorage
} from "../settings/gestureSettings";
import { SETTINGS_SYNC_STATUS_STORAGE_KEY, type SettingsSyncStatus } from "../background/settingsSync";
import "./popup.css";

type PopupStorage = GestureSettingsStorage & {
  get(key: string | string[]): Promise<Record<string, unknown>>;
};

type PopupStatus = {
  nativeConnected?: boolean;
  appConnected?: boolean;
  lastResult?: string;
  settingsSync?: SettingsSyncStatus;
};

const STATUS_STORAGE_KEY = "gesturekitStatus";

export async function initializeGestureSettingsPopup(doc: Document, storage: PopupStorage): Promise<void> {
  const [settings, statusResult] = await Promise.all([
    loadGestureSettings(storage),
    storage.get([STATUS_STORAGE_KEY, SETTINGS_SYNC_STATUS_STORAGE_KEY])
  ]);
  renderSettings(doc, settings);
  renderStatus(doc, statusResult[STATUS_STORAGE_KEY], statusResult[SETTINGS_SYNC_STATUS_STORAGE_KEY]);
  bindEvents(doc, storage);
}

function bindEvents(doc: Document, storage: PopupStorage) {
  select(doc, "#mode").addEventListener("change", () => {
    const mode = select(doc, "#mode").value === "efficient" ? "efficient" : "safe";
    void saveAndRender(doc, storage, GESTURE_SETTINGS_PRESETS[mode]);
  });

  for (const selector of [
    "#edgeTapEnabled",
    "#doubleTapCloseEnabled",
    "#flickSwitchEnabled",
    "#swipeSensitivity",
    "#edgeWidth",
    "#doubleTapSpeed",
    "#cooldownMs"
  ]) {
    element(doc, selector).addEventListener("change", () => {
      void saveAndRender(doc, storage, readSettings(doc));
    });
  }

  for (const selector of ["#edgeWidth", "#doubleTapSpeed", "#cooldownMs"]) {
    element(doc, selector).addEventListener("input", () => {
      renderSettings(doc, readSettings(doc));
    });
  }

  element(doc, "#resetDefaults").addEventListener("click", () => {
    void saveAndRender(doc, storage, GESTURE_SETTINGS_PRESETS.safe);
  });
}

async function saveAndRender(doc: Document, storage: PopupStorage, settings: GestureSettings) {
  const saved = await saveGestureSettings(storage, settings);
  renderSettings(doc, saved);
}

function renderSettings(doc: Document, settings: GestureSettings) {
  select(doc, "#mode").value = settings.mode;
  select(doc, "#swipeSensitivity").value = settings.swipeSensitivity;
  checkbox(doc, "#edgeTapEnabled").checked = settings.edgeTapEnabled;
  checkbox(doc, "#doubleTapCloseEnabled").checked = settings.doubleTapCloseEnabled;
  checkbox(doc, "#flickSwitchEnabled").checked = settings.flickSwitchEnabled;

  const edgeWidth = Math.round(settings.leftEdgeMax * 100);
  input(doc, "#edgeWidth").value = String(edgeWidth);
  output(doc, "#edgeWidthValue").textContent = `${edgeWidth}%`;

  input(doc, "#doubleTapSpeed").value = String(settings.doubleTapMaxMs);
  output(doc, "#doubleTapSpeedValue").textContent = `${settings.doubleTapMinMs}-${settings.doubleTapMaxMs}ms`;

  input(doc, "#cooldownMs").value = String(settings.cooldownMs);
  output(doc, "#cooldownMsValue").textContent = `${settings.cooldownMs}ms`;
}

function renderStatus(doc: Document, value: unknown, syncValue: unknown) {
  const status = isPopupStatus(value) ? value : {};
  const settingsSync = isSettingsSyncStatus(syncValue)
    ? syncValue
    : isSettingsSyncStatus(status.settingsSync)
      ? status.settingsSync
      : null;
  element(doc, "#nativeStatus").textContent = status.nativeConnected ? "已连接" : "未连接";
  element(doc, "#appStatus").textContent = status.appConnected ? "在线" : "未连接";
  element(doc, "#settingsSyncStatus").textContent = settingsSync
    ? `${settingsSync.applied ? "已应用" : "未应用"} ${settingsSync.swipeSensitivity}`
    : "待同步";
  element(doc, "#lastResult").textContent = status.lastResult ?? "暂无";
}

function readSettings(doc: Document): GestureSettings {
  const mode: GestureSettingsMode = select(doc, "#mode").value === "efficient" ? "efficient" : "safe";
  const preset = GESTURE_SETTINGS_PRESETS[mode];
  const edgeWidth = Number(input(doc, "#edgeWidth").value) / 100;
  const doubleTapMaxMs = Number(input(doc, "#doubleTapSpeed").value);
  const cooldownMs = Number(input(doc, "#cooldownMs").value);
  return {
    ...preset,
    swipeSensitivity: readSwipeSensitivity(doc),
    edgeTapEnabled: checkbox(doc, "#edgeTapEnabled").checked,
    doubleTapCloseEnabled: checkbox(doc, "#doubleTapCloseEnabled").checked,
    flickSwitchEnabled: checkbox(doc, "#flickSwitchEnabled").checked,
    leftEdgeMax: edgeWidth,
    rightEdgeMin: 1 - edgeWidth,
    doubleTapMaxMs,
    cooldownMs
  };
}

function readSwipeSensitivity(doc: Document) {
  const value = select(doc, "#swipeSensitivity").value;
  if (value === "standard" || value === "sensitive") {
    return value;
  }
  return "robust";
}

function select(doc: Document, selector: string): HTMLSelectElement {
  return element(doc, selector) as HTMLSelectElement;
}

function input(doc: Document, selector: string): HTMLInputElement {
  return element(doc, selector) as HTMLInputElement;
}

function checkbox(doc: Document, selector: string): HTMLInputElement {
  return input(doc, selector);
}

function output(doc: Document, selector: string): HTMLOutputElement {
  return element(doc, selector) as HTMLOutputElement;
}

function element(doc: Document, selector: string): HTMLElement {
  const found = doc.querySelector(selector);
  if (!(found instanceof HTMLElement)) {
    throw new Error(`Missing popup element: ${selector}`);
  }
  return found;
}

function isPopupStatus(value: unknown): value is PopupStatus {
  return typeof value === "object" && value !== null;
}

function isSettingsSyncStatus(value: unknown): value is SettingsSyncStatus {
  return typeof value === "object" && value !== null &&
    "applied" in value &&
    "swipeSensitivity" in value;
}

declare const chrome: { storage?: { local?: PopupStorage } } | undefined;

if (typeof chrome !== "undefined" && chrome.storage?.local && typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", () => {
    void initializeGestureSettingsPopup(document, chrome.storage!.local!);
  });
}
