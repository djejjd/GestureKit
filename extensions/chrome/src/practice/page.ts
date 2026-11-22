/** 练习页从同一内容脚本取得选区证据，仅向页面写入绑定动作预览。 */
import { handlePageMessage, endPracticeGesture } from "../content/pointerTracker";
import "./page.css";
const output = document.querySelector("output")!;
const names: Record<string,string> = {
  "browser.tab.activate_previous":"切换到左侧标签", "browser.tab.activate_next":"切换到右侧标签",
  "browser.tab.close_current":"关闭当前标签", "browser.link.open_adjacent":"在相邻标签打开链接",
  "browser.link.open_background":"在后台打开链接", "browser.tab.restore":"恢复关闭的标签",
  "browser.page.reload":"刷新页面", "browser.tab.open_new":"新建标签", "browser.tab.pin":"固定标签",
  "browser.tab.unpin":"取消固定标签", "browser.tab.toggle_mute":"切换静音", "browser.tab.close_others":"关闭其他标签",
  "browser.link.copy":"复制链接", "browser.page.copy_url":"复制页面地址", "browser.history.back":"后退",
  "browser.history.forward":"前进", "browser.page.scroll_top_bottom":"滚动页面"
};
// 示例链接用于目标识别，原生点击也留在练习页。
document.addEventListener("click", event => { if ((event.target as Element)?.closest("a")) event.preventDefault(); }, true);
let port: chrome.runtime.Port | undefined;
function connect() {
  if (document.hidden || port) return;
  const current = chrome.runtime.connect({ name: "gesturekit-practice" });
  port = current;
  current.onMessage.addListener(({ key, message }) => {
    if (document.hidden || current !== port) return;
    if (message.type === "gesturekit.practiceReset") {
      endPracticeGesture();
      output.textContent = "连接已重置，等待下一次手势";
      current.postMessage({ key, result: { status: "reset" } });
      return;
    }
    if (message.type === "gesturekit.practicePreview") {
      handlePageMessage({ ...message, type: "gesturekit.dragEvidence" }, evidence => {
        output.textContent = evidence.dragging ? "保留文字选区" : `预览 · ${names[message.actionId] ?? message.actionId}`;
      });
      handlePageMessage({ ...message, type: "gesturekit.linkGuardDiscard" }, () => {});
      current.postMessage({ key, result: { status: "previewed" } });
    } else {
      handlePageMessage(message, result => current.postMessage({ key, result }));
      if (message.type === "gesturekit.linkGuardRelease" && !window.getSelection()?.isCollapsed) output.textContent = "保留文字选区";
    }
  });
  current.onDisconnect.addListener(() => { if (port === current) { port = undefined; endPracticeGesture(); output.textContent = "连接已中断，请重新打开练习页"; } });
}
function disconnect() { endPracticeGesture(); const old = port; port = undefined; old?.disconnect(); }
document.addEventListener("visibilitychange", () => { if (document.hidden) disconnect(); else connect(); });
window.addEventListener("pagehide", disconnect);
connect();
