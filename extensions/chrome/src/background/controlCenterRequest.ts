import type { ProviderEnvelope } from "../provider/protocol";

type NativePort = {
  postMessage(message: unknown): void;
  onMessage: { addListener(listener: (message: unknown) => void): void };
};

export type ControlCenterOpenResult = { status: "opened" | "unavailable" };

/** 将 popup 意图绑定到 host 已认证的 v2 session；未认证时拒绝发送。 */
export function createControlCenterRequestForwarder(
  port: () => NativePort,
  authenticatedSessionId: () => string | null
) {
  const pending = new Map<string, (result: ControlCenterOpenResult) => void>();
  let listenerAttached = false;

  function attach(): void {
    if (listenerAttached) return;
    listenerAttached = true;
    port().onMessage.addListener((message) => {
      const envelope = message as Partial<ProviderEnvelope>;
      if (envelope.type !== "control_center_open_response" || typeof envelope.messageId !== "string") return;
      const resolve = pending.get(envelope.messageId);
      if (!resolve) return;
      pending.delete(envelope.messageId);
      resolve((envelope.payload as { opened?: boolean }).opened ? { status: "opened" } : { status: "unavailable" });
    });
  }

  return {
    open(): Promise<ControlCenterOpenResult> {
      const providerSessionId = authenticatedSessionId();
      if (!providerSessionId) return Promise.resolve({ status: "unavailable" });
      attach();
      const messageId = crypto.randomUUID();
      return new Promise((resolve) => {
        pending.set(messageId, resolve);
        setTimeout(() => {
          const pendingResolve = pending.get(messageId);
          if (!pendingResolve) return;
          pending.delete(messageId);
          pendingResolve({ status: "unavailable" });
        }, 1500);
        port().postMessage({
          protocolVersion: 2,
          messageId,
          providerSessionId,
          gestureSessionId: null,
          operationId: null,
          type: "control_center_open_request",
          timestamp: Date.now(),
          payload: {},
          error: null
        } satisfies ProviderEnvelope);
      });
    },
    handle(envelope: ProviderEnvelope): boolean {
      if (envelope.type !== "control_center_open_response") return false;
      const resolve = pending.get(envelope.messageId);
      if (!resolve) return false;
      pending.delete(envelope.messageId);
      resolve((envelope.payload as { opened: boolean }).opened ? { status: "opened" } : { status: "unavailable" });
      return true;
    }
  };
}
