import { beforeEach, describe, expect, it, vi } from "vitest";
import { initializePopup, popupStateForTesting } from "../src/popup/popup";

const listeners: Array<(changes: Record<string, { newValue?: unknown }>, areaName: string) => void> = [];

function setupDom(): void {
  document.body.innerHTML = `
    <p id="pageSupport"></p><strong id="appConnection"></strong><strong id="providerConnection"></strong>
    <strong id="presetName"></strong><strong id="latestResult"></strong><p id="latestResultDetail"></p>
    <button id="openControlCenter" type="button"></button>
  `;
}

function storageWith(status: unknown) {
  return { get: vi.fn(async () => ({ gesturekitStatus: status })) };
}

describe("minimal popup", () => {
  beforeEach(() => {
    setupDom();
    listeners.length = 0;
    Object.defineProperty(globalThis, "chrome", {
      configurable: true,
      value: {
        runtime: { sendMessage: vi.fn(async () => undefined) },
        storage: { onChanged: { addListener: vi.fn((listener) => listeners.push(listener)) } }
      }
    });
  });

  it("renders only page context and a control-center entry", async () => {
    await initializePopup(document, storageWith({ nativeConnected: true, appConnected: true, pageSupported: true, presetName: "标准浏览", lastResult: "activate_next success" }));
    expect(document.querySelector("#pageSupport")?.textContent).toBe("当前页面支持手势");
    expect(document.querySelector("#presetName")?.textContent).toBe("标准浏览");
    expect(document.querySelector("#openControlCenter")).toBeInstanceOf(HTMLButtonElement);
    expect(document.querySelector("#mode")).toBeNull();
    expect(document.querySelector("#diagnosticsList")).toBeNull();
  });

  it("maps guard failure without leaking internal status", () => {
    const state = popupStateForTesting({ lastResult: "guard_unavailable" });
    expect(state.latestResult).toMatchObject({ title: "为避免误触，本次操作未执行" });
    expect(state.latestResult?.title).not.toContain("guard_unavailable");
  });

  it("requests opening the control center", async () => {
    await initializePopup(document, storageWith({}));
    (document.querySelector("#openControlCenter") as HTMLButtonElement).click();
    expect(chrome.runtime.sendMessage).toHaveBeenCalledWith({ type: "gesturekit.openControlCenter" });
  });
});
