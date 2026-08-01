declare const __GESTUREKIT_E2E_TOKEN__: string | undefined;

// 普通 build 的 token === null 时不注册 listener
if (typeof __GESTUREKIT_E2E_TOKEN__ !== "undefined" && __GESTUREKIT_E2E_TOKEN__) {
  window.addEventListener("message", (event: MessageEvent) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.type !== "gesturekit.e2eLinkOperation") return;

    const command = data as {
      token?: string;
      gestureSessionId?: string;
      operationId?: string;
      scenario?: string;
    };

    // 使用编译期 token、location.origin 和完整 command 字段校验
    if (!command.token || command.token !== __GESTUREKIT_E2E_TOKEN__) return;
    if (!command.gestureSessionId || !command.operationId || !command.scenario) return;

    chrome.runtime.sendMessage({
      type: "gesturekit.e2eLinkOperation",
      origin: location.origin,
      command: {
        token: command.token,
        gestureSessionId: command.gestureSessionId,
        operationId: command.operationId,
        scenario: command.scenario
      }
    }).then((response: { status?: string } | undefined) => {
      window.postMessage({
        type: "gesturekit.e2eLinkResult",
        status: response?.status ?? "e2e_unavailable",
        gestureSessionId: command.gestureSessionId,
        operationId: command.operationId
      }, location.origin);
    }).catch(() => {
      window.postMessage({
        type: "gesturekit.e2eLinkResult",
        status: "e2e_unavailable",
        gestureSessionId: command.gestureSessionId,
        operationId: command.operationId
      }, location.origin);
    });
  });
}
