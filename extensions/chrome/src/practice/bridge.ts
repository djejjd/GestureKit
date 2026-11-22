/** 按练习标签路由消息，页面离开时释放端口的所有待处理请求。 */
export function practiceBridge(pageURL: string, invalidate: (tabId: number) => void) {
  const pages = new Map<number, { send: (message: Record<string, unknown>) => Promise<any> }>();
  function attach(port: chrome.runtime.Port) {
    const id = port.sender?.tab?.id;
    if (port.name !== "gesturekit-practice" || port.sender?.url !== pageURL || id === undefined) return;
    const pending = new Map<string, (value: unknown) => void>();
    const page = { send(message: Record<string, unknown>) {
      return new Promise(resolve => {
        const key = crypto.randomUUID();
        const finish = (value: unknown) => { clearTimeout(timer); pending.delete(key); resolve(value); };
        const timer = setTimeout(() => finish(null), 250);
        pending.set(key, finish);
        try { port.postMessage({ key, message }); } catch { finish(null); }
      });
    } };
    invalidate(id);
    pages.set(id, page);
    port.onMessage.addListener(({ key, result }) => pending.get(key)?.(result));
    port.onDisconnect.addListener(() => {
      if (pages.get(id) === page) {
        pages.delete(id);
        invalidate(id);
      }
      for (const finish of pending.values()) finish(null);
    });
  }
  return { attach, pages };
}
