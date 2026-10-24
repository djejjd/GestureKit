import type { ProviderEnvelope } from "../provider/protocol";

type NativePort = {
  postMessage(message: unknown): void;
  onMessage: { addListener(listener: (message: unknown) => void): void; removeListener?(listener: (message: unknown) => void): void };
};

export type ControlCenterOpenResult = { status: "opened" | "unavailable" };

/** 将 popup 意图绑定到 host 已认证的 v2 session；未认证时拒绝发送。 */
export function createControlCenterRequestForwarder(
  port: () => NativePort,
  authenticatedSessionId: () => string | null
) {
  const pending = new Map<string, (result: ControlCenterOpenResult) => void>();
  const timers = new Map<string, ReturnType<typeof setTimeout>>();
  let listenerAttached = false;
  let disposed = false;
  const listener = (message: unknown) => {
    const envelope = message as Partial<ProviderEnvelope>;
    if (envelope.type !== "control_center_open_response" || typeof envelope.messageId !== "string") return;
    finish(envelope.messageId, (envelope.payload as { opened?: boolean }).opened ? { status: "opened" } : { status: "unavailable" });
  };
  function finish(id: string, result: ControlCenterOpenResult) {
    const resolve = pending.get(id);
    if (!resolve) return;
    pending.delete(id); clearTimeout(timers.get(id)); timers.delete(id); resolve(result);
  }

  function attach(): void {
    if (listenerAttached) return;
    listenerAttached = true;
    port().onMessage.addListener(listener);
  }

  return {
    open(): Promise<ControlCenterOpenResult> {
      const providerSessionId = authenticatedSessionId();
      if (disposed || !providerSessionId) return Promise.resolve({ status: "unavailable" });
      attach();
      const messageId = crypto.randomUUID();
      return new Promise((resolve) => {
        pending.set(messageId, resolve);
        timers.set(messageId, setTimeout(() => finish(messageId, { status: "unavailable" }), 1500));
        try { port().postMessage({
          protocolVersion: 2,
          messageId,
          providerSessionId,
          gestureSessionId: null,
          operationId: null,
          type: "control_center_open_request",
          timestamp: Date.now(),
          payload: {},
          error: null
        } satisfies ProviderEnvelope); } catch { finish(messageId, { status: "unavailable" }); }
      });
    },
    handle(envelope: ProviderEnvelope): boolean {
      if (envelope.type !== "control_center_open_response") return false;
      const resolve = pending.get(envelope.messageId);
      if (!resolve) return false;
      finish(envelope.messageId, (envelope.payload as { opened: boolean }).opened ? { status: "opened" } : { status: "unavailable" });
      return true;
    },
    dispose() {
      disposed = true;
      if (listenerAttached) port().onMessage.removeListener?.(listener);
      listenerAttached = false;
      for (const id of pending.keys()) finish(id, { status: "unavailable" });
    }
  };
}
