import { presentPopupState, renderPopup, type PopupPageState } from "./popupPageState";
import "./popup.css";

const STATUS_STORAGE_KEY = "gesturekitStatus";

type PopupStorage = {
  get(key: string | string[]): Promise<Record<string, unknown>>;
};

/** 初始化只读 popup；配置写入和诊断历史均迁移到 macOS 控制中心。 */
export async function initializePopup(doc: Document, storage: PopupStorage): Promise<void> {
  let rawStatus = (await storage.get(STATUS_STORAGE_KEY))[STATUS_STORAGE_KEY];

  const render = (): void => renderPopup(doc, presentPopupState(rawStatus));
  render();

  chrome.storage?.onChanged?.addListener?.((changes, areaName) => {
    if (areaName !== "local" || !changes[STATUS_STORAGE_KEY]) return;
    rawStatus = changes[STATUS_STORAGE_KEY].newValue;
    render();
  });

  doc.querySelector<HTMLButtonElement>("#openControlCenter")?.addEventListener("click", async () => {
    const feedback = doc.querySelector<HTMLElement>("#controlCenterFeedback");
    try {
      const result = await chrome.runtime?.sendMessage?.({ type: "gesturekit.openControlCenter" }) as { status?: string } | undefined;
      if (feedback) {
        feedback.textContent = result?.status === "opened"
          ? "已打开 GestureKit 控制中心"
          : "无法打开控制中心，请确认 GestureKit 已连接";
      }
    } catch {
      if (feedback) {
        feedback.textContent = "无法打开控制中心，请确认 GestureKit 已连接";
      }
    }
  });

  try {
    await chrome.runtime?.sendMessage?.({ type: "gesturekit.runConnectionProbe" });
  } catch {
    // popup 在测试或后台不可用时仍显示最后一次可读取的状态。
  }
}

/** 导出供测试使用的纯状态转换结果。 */
export function popupStateForTesting(rawStatus: unknown): PopupPageState {
  return presentPopupState(rawStatus);
}

if (typeof document !== "undefined" && typeof chrome !== "undefined" && chrome.storage?.local) {
  void initializePopup(document, chrome.storage.local);
}
