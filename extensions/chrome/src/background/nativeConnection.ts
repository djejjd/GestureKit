type Event<T> = { addListener(listener: T): void; removeListener(listener: T): void };
export type NativeConnectionPort = {
  postMessage(message: unknown): void;
  disconnect(): void;
  onMessage: Event<(message: unknown) => void>;
  onDisconnect: Event<() => void>;
};

/** Owns one Native port and one retry timer. Never buffers or replays messages. */
export function createNativeConnection<P extends NativeConnectionPort>(options: {
  connect(): P;
  opened(port: P): void;
  message(port: P, message: unknown): void;
  closed(): void;
}) {
  let port: P | null = null;
  let cleanup: (() => void) | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let stopped = true;
  let attempts = 0;

  function retry() {
    if (stopped || timer) return;
    const delay = Math.min(30_000, 1_000 * 2 ** Math.min(attempts++, 5));
    timer = setTimeout(() => { timer = null; ensureConnected(); }, delay);
  }

  function closeCurrent() {
    const old = port;
    port = null;
    cleanup?.(); cleanup = null;
    try { old?.disconnect(); } catch { /* already disconnected */ }
  }

  function ensureConnected() {
    if (stopped || port) return;
    if (timer) { clearTimeout(timer); timer = null; }
    try {
      const current = options.connect();
      port = current;
      const message = (value: unknown) => { if (port === current) options.message(current, value); };
      const disconnected = () => {
        if (port !== current) return;
        closeCurrent();
        options.closed();
        retry();
      };
      cleanup = () => {
        current.onMessage.removeListener(message);
        current.onDisconnect.removeListener(disconnected);
      };
      current.onMessage.addListener(message);
      current.onDisconnect.addListener(disconnected);
      options.opened(current);
    } catch {
      closeCurrent();
      options.closed();
      retry();
    }
  }

  return {
    start() { if (!stopped) return; stopped = false; ensureConnected(); },
    stop() {
      if (stopped) return;
      stopped = true;
      if (timer) clearTimeout(timer);
      timer = null; closeCurrent(); options.closed();
    },
    ensureConnected,
    isCurrent: (candidate: P) => !stopped && port === candidate,
    ready(candidate: P) { if (port === candidate) attempts = 0; },
    current: () => port
  };
}
