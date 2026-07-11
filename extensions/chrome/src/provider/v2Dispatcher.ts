import type { ActionDescriptor, ProviderEnvelope } from "./protocol";
import { ContextProvider } from "./contextProvider";
import { ChromeActionAdapter } from "./actionAdapter";

type Send = (message: ProviderEnvelope) => void;

/** v2 Provider 分发器：只处理 context_request 与 action_request，其他消息由会话层处理。 */
export class V2Dispatcher {
  constructor(
    private readonly contexts: ContextProvider,
    private readonly actions: ChromeActionAdapter,
    private readonly resolveURL: () => Promise<string | null>,
    private readonly send: Send
  ) {}

  async handle(envelope: ProviderEnvelope): Promise<void> {
    if (envelope.type === "context_request") {
      const payload = envelope.payload as { deadline: number };
      const now = Date.now();
      if (payload.deadline <= now) {
        this.send({ ...envelope, messageId: crypto.randomUUID(), type: "context_snapshot", timestamp: now, payload: { contextId: crypto.randomUUID(), pageIdentity: "", expiresAt: now, targetKind: "page_unavailable", targetRef: null }, error: { code: "context_expired", message: "context_request 已超过 deadline" } });
        return;
      }
      const snapshot = this.contexts.snapshot(await this.resolveURL(), now, payload.deadline - now);
      this.send({ ...envelope, messageId: crypto.randomUUID(), type: "context_snapshot", timestamp: Date.now(), payload: snapshot, error: null });
      return;
    }
    if (envelope.type === "action_request") {
      const action = envelope.payload as ActionDescriptor;
      const result = await this.actions.execute(action);
      this.send({ ...envelope, messageId: crypto.randomUUID(), type: "action_result", timestamp: Date.now(), payload: { operationId: envelope.operationId!, outcome: result.outcome, reason: result.outcome === "failed" ? result.reason : "completed", completedAt: Date.now() }, error: null });
    }
  }
}
