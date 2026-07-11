/** popup 只呈现当前页面上下文，避免承担设置和历史诊断职责。 */
export type PopupPageState = {
  pageSupport: "supported" | "unsupported" | "checking";
  appConnection: "connected" | "disconnected" | "checking";
  providerConnection: "connected" | "disconnected" | "checking";
  presetName: string | null;
  latestResult: PopupResult | null;
};

export type PopupResult = {
  title: string;
  detail: string;
  severity: "informational" | "warning" | "critical";
};

type StoredStatus = {
  nativeConnected?: boolean;
  appConnected?: boolean;
  pageSupported?: boolean;
  presetName?: string;
  lastResult?: string;
};

/** 将扩展内部状态转换成用户可理解的 popup 数据。 */
export function presentPopupState(raw: unknown): PopupPageState {
  const status = isStoredStatus(raw) ? raw : {};
  return {
    pageSupport: status.pageSupported === true ? "supported" : status.pageSupported === false ? "unsupported" : "checking",
    appConnection: connectionState(status.appConnected),
    providerConnection: connectionState(status.nativeConnected),
    presetName: typeof status.presetName === "string" ? status.presetName : null,
    latestResult: presentLatestResult(status.lastResult)
  };
}

/** 渲染最小 popup；所有字段均为已映射的用户文案。 */
export function renderPopup(doc: Document, state: PopupPageState): void {
  text(doc, "#pageSupport", pageSupportText(state.pageSupport));
  text(doc, "#appConnection", connectionText(state.appConnection, "GestureKit App"));
  text(doc, "#providerConnection", connectionText(state.providerConnection, "Chrome Provider"));
  text(doc, "#presetName", state.presetName ?? "正在获取当前预设");
  text(doc, "#latestResult", state.latestResult?.title ?? "暂无本页操作记录");
  text(doc, "#latestResultDetail", state.latestResult?.detail ?? "操作结果会显示在这里");
}

function isStoredStatus(value: unknown): value is StoredStatus {
  return typeof value === "object" && value !== null;
}

function connectionState(value: unknown): PopupPageState["appConnection"] {
  return value === true ? "connected" : value === false ? "disconnected" : "checking";
}

function pageSupportText(state: PopupPageState["pageSupport"]): string {
  switch (state) {
    case "supported": return "当前页面支持手势";
    case "unsupported": return "当前页面暂不支持手势";
    case "checking": return "正在检查当前页面";
  }
}

function connectionText(state: PopupPageState["appConnection"], name: string): string {
  switch (state) {
    case "connected": return `${name} 已连接`;
    case "disconnected": return `${name} 未连接`;
    case "checking": return `${name} 正在连接`;
  }
}

function presentLatestResult(value: unknown): PopupResult | null {
  if (typeof value !== "string" || value.length === 0 || value === "connected") return null;
  if (value === "guard_unavailable") {
    return { title: "为避免误触，本次操作未执行", detail: "当前页面无法安全执行此操作", severity: "warning" };
  }
  if (value === "native_host_disconnected") {
    return { title: "Chrome 连接已中断", detail: "未确认操作会保留诊断信息", severity: "warning" };
  }
  if (value.includes("success")) {
    return { title: "操作已完成", detail: "本页最近一次动作已收到明确结果", severity: "informational" };
  }
  return { title: "操作结果暂时无法确认", detail: "系统已保存诊断信息", severity: "warning" };
}

function text(doc: Document, selector: string, value: string): void {
  const element = doc.querySelector(selector);
  if (element) element.textContent = value;
}
