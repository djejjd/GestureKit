import {
  GESTURE_SETTINGS_PRESETS,
  loadGestureSettings,
  saveGestureSettings,
  type GestureSettings,
  type GestureSettingsMode,
  type GestureSettingsStorage
} from "../settings/gestureSettings";
import {
  buildRecommendedSettings,
  describeRecognitionDelta,
  resolveEffectiveSwipeRecognition,
  type EffectiveSwipeRecognition
} from "../settings/swipeRecognition";
import { SETTINGS_SYNC_STATUS_STORAGE_KEY, type SettingsSyncStatus, isSettingsSyncStatus } from "../background/settingsSync";
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
  const summary = summarizeDiagnostics(diagnostics);
  const syncStatus = extractSyncStatus(statusResult[SETTINGS_SYNC_STATUS_STORAGE_KEY], statusResult[STATUS_STORAGE_KEY]);
  renderSettings(doc, settings);
  renderStatus(doc, statusResult[STATUS_STORAGE_KEY], syncStatus);
  renderDiagnostics(doc, diagnostics);
  renderRecommendationCard(doc, settings, summary, syncStatus);
  bindEvents(doc, storage, () => diagnostics, (next) => {
    diagnostics = next;
    const newSummary = summarizeDiagnostics(diagnostics);
    renderDiagnostics(doc, diagnostics);
    renderRecommendationCard(doc, settings, newSummary, syncStatus);
  });

  try {
    chrome.runtime?.sendMessage?.({ type: "gesturekit.runConnectionProbe" });
  } catch {
    // probe not available (e.g. in tests)
  }
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
    "#linkClickProtectionEnabled",
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
    const nextExpanded = !expanded;
    toggle.setAttribute("aria-expanded", String(nextExpanded));
    toggle.textContent = nextExpanded ? "收起" : "展开";
    panel.hidden = expanded;
  });

  element(doc, "#copyDiagnostics").addEventListener("click", () => {
    void (async () => {
      const settings = await loadGestureSettings(storage);
      const statusResult = await storage.get([SETTINGS_SYNC_STATUS_STORAGE_KEY]);
      const syncStatus = extractSyncStatus(statusResult[SETTINGS_SYNC_STATUS_STORAGE_KEY], null);
      await navigator.clipboard?.writeText(formatPopupDiagnostics(settings, getDiagnostics(), syncStatus));
    })();
  });

  element(doc, "#clearDiagnostics").addEventListener("click", () => {
    void clearDiagnostics(storage).then(() => {
      setDiagnostics([]);
      const toggle = element(doc, "#diagnosticsToggle");
      toggle.setAttribute("aria-expanded", "false");
      toggle.textContent = "展开";
      element(doc, "#diagnosticsPanel").hidden = true;
    });
  });

  element(doc, "#applyRecommendedSettings").addEventListener("click", () => {
    void applyRecommendedSettings(doc, storage);
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
  checkbox(doc, "#linkClickProtectionEnabled").checked = settings.linkClickProtectionEnabled;

  const edgeWidth = Math.round(settings.leftEdgeMax * 100);
  input(doc, "#edgeWidth").value = String(edgeWidth);
  output(doc, "#edgeWidthValue").textContent = `${edgeWidth}%`;

  input(doc, "#doubleTapSpeed").value = String(settings.doubleTapMaxMs);
  output(doc, "#doubleTapSpeedValue").textContent = `${settings.doubleTapMinMs}-${settings.doubleTapMaxMs}ms`;

  input(doc, "#cooldownMs").value = String(settings.cooldownMs);
  output(doc, "#cooldownMsValue").textContent = `${settings.cooldownMs}ms`;
}

function extractSyncStatus(syncValue: unknown, statusValue: unknown): SettingsSyncStatus | null {
  if (isSettingsSyncStatus(syncValue)) {
    return syncValue;
  }
  if (isPopupStatus(statusValue) && isSettingsSyncStatus(statusValue.settingsSync)) {
    return statusValue.settingsSync;
  }
  return null;
}

function renderStatus(doc: Document, value: unknown, settingsSync: SettingsSyncStatus | null) {
  const status = isPopupStatus(value) ? value : {};

  const nativeEl = element(doc, "#nativeStatus");
  const appEl = element(doc, "#appStatus");
  const syncEl = element(doc, "#settingsSyncStatus");
  const lastEl = element(doc, "#lastResult");

  nativeEl.textContent = status.nativeConnected ? "已连接" : "未连接";
  nativeEl.className = status.nativeConnected ? "dot-online" : "dot-offline";

  appEl.textContent = status.appConnected ? "在线" : "未连接";
  appEl.className = status.appConnected ? "dot-online" : "dot-offline";

  if (settingsSync) {
    syncEl.textContent = `${phaseLabel(settingsSync.phase)} ${settingsSync.savedSwipeSensitivity}`;
    if (settingsSync.phase === "applied") {
      syncEl.className = "dot-online";
    } else if (settingsSync.phase === "failed" || settingsSync.phase === "stale") {
      syncEl.className = "dot-offline";
    } else {
      syncEl.className = "dot-sync";
    }
  } else {
    syncEl.textContent = "待同步";
    syncEl.className = "dot-offline";
  }

  lastEl.textContent = status.lastResult ? resultLabel(status.lastResult) : "暂无";
  lastEl.className = "";
}

function renderDiagnostics(doc: Document, diagnostics: GestureDiagnosticEntry[]) {
  const summary = summarizeDiagnostics(diagnostics);
  element(doc, "#swipeSuccessRate").textContent = summary.swipeSuccessText;
  element(doc, "#mainFailureReason").textContent = summary.mainFailureReason;
  element(doc, "#diagnosticsSuggestion").textContent = summary.suggestion;
  element(doc, "#recommendedSensitivity").textContent = sensitivityLabel(summary.recommendedSensitivity);
  element(doc, "#recommendedMinDistance").textContent = summary.recommendedMinDistance === null
    ? "暂无"
    : summary.recommendedMinDistance.toFixed(3);
  element(doc, "#diagnosticsList").replaceChildren(...diagnostics.slice(-10).reverse().map((entry) => diagnosticRow(doc, entry)));
}

function renderRecommendationCard(
  doc: Document,
  settings: GestureSettings,
  summary: ReturnType<typeof summarizeDiagnostics>,
  syncStatus: SettingsSyncStatus | null
) {
  const current = resolveEffectiveSwipeRecognition(settings);
  const showCard = summary.recommendedMinDistance !== null;
  const section = doc.querySelector("#recommendationSection");
  if (section instanceof HTMLElement) {
    section.hidden = !showCard;
  }
  if (!showCard) {
    return;
  }

  const recommended: EffectiveSwipeRecognition = {
    swipeSensitivity: summary.recommendedSensitivity,
    swipeMinDistance: summary.recommendedMinDistance!,
    swipeHorizontalRatio: current.swipeHorizontalRatio,
    swipeMinDurationMs: current.swipeMinDurationMs,
    swipeMaxDurationMs: current.swipeMaxDurationMs,
    source: "recommended"
  };

  const deltaLines = describeRecognitionDelta(current, recommended);
  element(doc, "#recommendationDelta").textContent = deltaLines.join("；");

  const savedEl = element(doc, "#recommendationSavedStatus");
  const runtimeEl = element(doc, "#recommendationRuntimeStatus");
  const failureEl = element(doc, "#recommendationFailureReason");
  const button = element(doc, "#applyRecommendedSettings") as HTMLButtonElement;

  if (syncStatus) {
    savedEl.textContent = `推荐保存状态：${phaseLabel(syncStatus.phase)}`;
    runtimeEl.textContent = syncStatus.runtimeSwipeSensitivity
      ? `App 运行时：${syncStatus.runtimeSwipeSensitivity}`
      : "App 运行时：等待确认";
  } else {
    savedEl.textContent = "推荐保存状态：未保存";
    runtimeEl.textContent = "App 运行时：未知";
  }

  if (syncStatus?.phase === "failed" || syncStatus?.phase === "stale") {
    failureEl.textContent = syncStatus.message ?? syncStatus.phase;
    failureEl.hidden = false;
  } else {
    failureEl.textContent = "";
    failureEl.hidden = true;
  }

  button.disabled = false;
  button.textContent = syncStatus?.phase === "applied" ? "重新应用推荐设置" : "应用推荐设置";
}

async function applyRecommendedSettings(doc: Document, storage: PopupStorage) {
  const settings = await loadGestureSettings(storage);
  const statusResult = await storage.get([DIAGNOSTICS_STORAGE_KEY]);
  const diagnostics = normalizeDiagnostics(statusResult[DIAGNOSTICS_STORAGE_KEY]);
  const summary = summarizeDiagnostics(diagnostics);

  const next = buildRecommendedSettings(settings, summary);
  if (!next) {
    const failureEl = element(doc, "#recommendationFailureReason");
    failureEl.textContent = "当前推荐数据不足，暂不应用";
    failureEl.hidden = false;
    return;
  }

  if (!window.confirm("将把推荐档位和推荐最小距离写入扩展设置，并等待 App 运行时确认。继续吗？")) {
    return;
  }

  const saved = await saveGestureSettings(storage, next);
  renderSettings(doc, saved);
  renderRecommendationCard(doc, saved, summary, null);

  try {
    chrome.runtime?.sendMessage?.({ type: "gesturekit.runConnectionProbe" });
  } catch {
    // probe not available
  }
}

function formatPopupDiagnostics(
  settings: GestureSettings,
  diagnostics: GestureDiagnosticEntry[],
  syncStatus: SettingsSyncStatus | null
): string {
  const summary = summarizeDiagnostics(diagnostics);
  const current = resolveEffectiveSwipeRecognition(settings);
  const recommended: EffectiveSwipeRecognition | null = summary.recommendedMinDistance !== null
    ? {
        swipeSensitivity: summary.recommendedSensitivity,
        swipeMinDistance: summary.recommendedMinDistance,
        swipeHorizontalRatio: current.swipeHorizontalRatio,
        swipeMinDurationMs: current.swipeMinDurationMs,
        swipeMaxDurationMs: current.swipeMaxDurationMs,
        source: "recommended"
      }
    : null;

  return [
    "GestureKit Settings",
    `mode=${settings.mode}`,
    `swipeSensitivity=${settings.swipeSensitivity}`,
    `edgeTapEnabled=${settings.edgeTapEnabled}`,
    `doubleTapCloseEnabled=${settings.doubleTapCloseEnabled}`,
    `flickSwitchEnabled=${settings.flickSwitchEnabled}`,
    `linkClickProtectionEnabled=${settings.linkClickProtectionEnabled}`,
    `cooldownMs=${settings.cooldownMs}`,
    `edgeWidth=${settings.leftEdgeMax.toFixed(2)}`,
    formatDiagnosticsForClipboard(diagnostics, current, recommended, syncStatus)
  ].join("\n");
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

  if (entry.message) {
    const detail = doc.createElement("div");
    detail.className = "diagnostic-metrics";
    detail.textContent = entry.message;
    row.append(detail);
  }

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
    linkClickProtectionEnabled: checkbox(doc, "#linkClickProtectionEnabled").checked,
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

function resultLabel(value: string): string {
  const labels: Record<string, string> = {
    "connected": "已连接",
    "native_host_disconnected": "Native host 已断开",
    "open_link_background success": "打开链接成功",
    "open_link_background gesture_unstable": "打开链接未执行",
    "open_link_background no_recent_pointer": "没有最近鼠标位置",
    "open_link_background no_target": "未命中链接",
    "open_link_background page_unavailable": "当前页面不可用",
    "open_link_background unsupported_url_scheme": "链接类型不支持",
    "activate_left_tab success": "已切换到左侧标签页",
    "activate_left_tab gesture_unstable": "左切未执行",
    "activate_left_tab page_unavailable": "左切失败：页面不可用",
    "activate_right_tab success": "已切换到右侧标签页",
    "activate_right_tab gesture_unstable": "右切未执行",
    "activate_right_tab page_unavailable": "右切失败：页面不可用",
    "close_tab success": "已关闭当前标签页",
    "close_tab gesture_unstable": "关闭标签页未执行",
    "close_tab page_unavailable": "关闭失败：页面不可用"
  };
  return labels[value] ?? value;
}

function sensitivityLabel(sensitivity: GestureSettings["swipeSensitivity"]): string {
  if (sensitivity === "sensitive") {
    return "灵敏";
  }
  if (sensitivity === "robust") {
    return "稳健";
  }
  return "标准";
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

function phaseLabel(phase: string): string {
  const labels: Record<string, string> = {
    saved_only: "已保存",
    pending: "等待确认",
    applied: "已应用",
    failed: "失败",
    stale: "已失效"
  };
  return labels[phase] ?? phase;
}

declare const chrome: { storage?: { local?: PopupStorage } } | undefined;

if (typeof chrome !== "undefined" && chrome.storage?.local && typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", () => {
    void initializeGestureSettingsPopup(document, chrome.storage!.local!);
  });
}
