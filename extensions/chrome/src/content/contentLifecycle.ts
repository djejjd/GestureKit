type Lifecycle = ReturnType<typeof createLifecycle>;
const KEY = "__gestureKitContentLifecycle";

export function beginContentLifecycle(onDispose: () => void) {
  const owner = window as unknown as Record<string, Lifecycle | undefined>;
  owner[KEY]?.dispose();
  const lifecycle = createLifecycle(onDispose);
  owner[KEY] = lifecycle;
  return lifecycle;
}

function createLifecycle(onDispose: () => void) {
  const runtime = typeof chrome !== "undefined" ? chrome.runtime : undefined;
  const runtimeID = runtime?.id;
  const cleanups: (() => void)[] = [];
  let disposed = false;
  function dispose() {
    if (disposed) return;
    disposed = true;
    for (const cleanup of cleanups.splice(0)) cleanup();
    onDispose();
  }
  function valid() {
    if (disposed) return false;
    try { if (runtimeID && runtime?.id !== runtimeID) { dispose(); return false; } }
    catch { dispose(); return false; }
    return true;
  }
  if (runtimeID) {
    const timer = setInterval(valid, 1_000);
    cleanups.push(() => clearInterval(timer));
  }
  return {
    dispose, valid,
    on(type: string, handler: (event: any) => void, options?: AddEventListenerOptions) {
      const listener = (event: Event) => { if (valid()) handler(event); };
      window.addEventListener(type, listener, options);
      cleanups.push(() => window.removeEventListener(type, listener, options));
    },
    onMessage(handler: Parameters<typeof chrome.runtime.onMessage.addListener>[0]) {
      if (!runtime?.onMessage) return;
      const listener: typeof handler = (message, sender, respond) => valid() ? handler(message, sender, respond) : false;
      runtime.onMessage.addListener(listener);
      cleanups.push(() => { try { runtime.onMessage.removeListener?.(listener); } catch { /* old extension context */ } });
    }
  };
}
