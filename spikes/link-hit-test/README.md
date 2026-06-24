# 链接命中验证 Spike

目标：验证 Chrome 扩展侧记录最近 pointer 位置的策略，确认它能识别普通网页链接。

手动验证步骤：

1. 在 Chrome 中打开 `pages/basic-links.html`。
2. 把指针移动到每个链接上。
3. 在 `extensions/chrome` 中运行 `npm run build`。
4. 从 `extensions/chrome` 加载 unpacked extension。
5. 从 background script 触发一次模拟手势事件：

   ```js
   chrome.runtime.sendMessage({ type: "gesturekit.simulateTap" }, console.log)
   ```

   这段代码从扩展 service worker console 中运行。

6. 确认 `http:` 和 `https:` 链接会被接受。
7. 确认 `javascript:` 链接会被拒绝。
8. 打开 `pages/no-link.html`，确认不会执行链接动作。
