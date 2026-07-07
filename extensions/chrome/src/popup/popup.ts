import {
  GESTURE_SETTINGS_PRESETS,
  loadGestureSettings,
  saveGestureSettings,
  type GestureSettings,
  type GestureSettingsMode,
  type GestureSettingsStorage
} from "../settings/gestureSettings";
import { SETTINGS_SYNC_STATUS_STORAGE_KEY, type SettingsSyncStatus } from "../background/settingsSync";
import {
  clearDiagnostics,
  DIAGNOSTICS_STORAGE_KEY,
  formatDiagnosticsForClipboard,
  normalizeDiagnostics,
  reasonLabel,
  summarizeDiagnostics,
  type GestureDiagnosticEntry
} from "../diagnostics/diagnostics";
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
    storage.get([STATUS_STORAGE_KEY, SETTINGS_SYNC_STATUS_STORAGE_KEY, DIAGNOSTICS_STORAGE_KEY])
  ]);
  let diagnostics = normalizeDiagnostics(statusResult[DIAGNOSTICS_STORAGE_KEY]);
  renderSettings(doc, settings);
  renderStatus(doc, statusResult[STATUS_STORAGE_KEY], statusResult[SETTINGS_SYNC_STATUS_STORAGE_KEY]);
  renderDiagnostics(doc, diagnostics);
  bindEvents(doc, storage, () => diagnostics, (next) => {
    diagnostics = next;
    renderDiagnostics(doc, diagnostics);
  });
}

function bindEvents(
  doc: Document,
  storage: PopupStorage,
  getDiagnostics: () => GestureDiagnosticEntry[],
  setDiagnostics: (diagnostics: GestureDiagnosticEntry[]) => void
) {
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

  element(doc, "#diagnosticsToggle").addEventListener("click", () => {
    const panel = element(doc, "#diagnosticsPanel");
    const toggle = element(doc, "#diagnosticsToggle");
    const expanded = toggle.getAttribute("aria-expanded") === "true";
    toggle.setAttribute("aria-expanded", String(!expanded));
    panel.hidden = expanded;
  });

  element(doc, "#copyDiagnostics").addEventListener("click", () => {
    void navigator.clipboard?.writeText(formatDiagnosticsForClipboard(getDiagnostics()));
  });

  element(doc, "#clearDiagnostics").addEventListener("click", () => {
    void clearDiagnostics(storage).then(() => setDiagnostics([]));
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

function renderDiagnostics(doc: Document, diagnostics: GestureDiagnosticEntry[]) {
  const summary = summarizeDiagnostics(diagnostics);
  element(doc, "#swipeSuccessRate").textContent = summary.swipeSuccessText;
  element(doc, "#mainFailureReason").textContent = summary.mainFailureReason;
  element(doc, "#diagnosticsSuggestion").textContent = summary.suggestion;
  element(doc, "#diagnosticsList").replaceChildren(...diagnostics.slice(-10).reverse().map((entry) => diagnosticRow(doc, entry)));
}

function diagnosticRow(doc: Document, entry: GestureDiagnosticEntry): HTMLElement {
  const row = doc.createElement("div");
  row.className = `diagnostic diagnostic-${entry.reason === "success" ? "success" : "warning"}`;

  const title = doc.createElement("div");
  title.className = "diagnostic-title";
  title.textContent = `${formatTime(entry.timestamp)}  ${gestureLabel(entry.gesture)}  ${entry.reason === "success" ? "成功" : "失败"}`;

  const reason = doc.createElement("div");
  reason.className = "diagnostic-reason";
  reason.textContent = entry.reason === "success" ? actionLabel(entry.action) : reasonLabel(entry.reason);

  const metrics = doc.createElement("div");
  metrics.className = "diagnostic-metrics";
  metrics.textContent = [
    typeof entry.dx === "number" ? `dx ${entry.dx.toFixed(3)}` : null,
    typeof entry.dy === "number" ? `dy ${entry.dy.toFixed(3)}` : null,
    typeof entry.durationMs === "number" ? `${entry.durationMs}ms` : null,
    entry.swipeSensitivity ?? null,
    entry.thresholds ? `阈值 ${entry.thresholds.swipeMinDistance.toFixed(3)}` : null
  ].filter(Boolean).join("  ");

  row.append(title, reason, metrics);
  return row;
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

function gestureLabel(gesture: GestureDiagnosticEntry["gesture"]): string {
  if (gesture === "three_finger_swipe_left") {
    return "左轻扫";
  }
  if (gesture === "three_finger_swipe_right") {
    return "右轻扫";
  }
  if (gesture === "three_finger_tap") {
    return "点按";
  }
  return "事件";
}

function actionLabel(action: GestureDiagnosticEntry["action"]): string {
  if (action === "open_link_background") {
    return "打开链接并切换到新标签页";
  }
  if (action === "activate_left_tab") {
    return "切换到左侧标签页";
  }
  if (action === "activate_right_tab") {
    return "切换到右侧标签页";
  }
  if (action === "close_tab") {
    return "关闭当前标签页";
  }
  return "已记录";
}

function formatTime(timestamp: number): string {
  return new Date(timestamp).toLocaleTimeString("zh-CN", {
    hour12: false,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  });
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
