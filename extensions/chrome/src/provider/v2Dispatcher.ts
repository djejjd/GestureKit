import type { ActionDescriptor, ActionResultOutcome, ActionResultReason, ProviderEnvelope, ProviderEvent } from "./protocol";
import { ContextProvider } from "./contextProvider";
import { ChromeActionAdapter } from "./actionAdapter";
import type { LedgerState, OperationLedgerStore } from "./operationLedger";

type Send = (message: ProviderEnvelope) => void;

/** v2 Provider 分发器：只处理 context_request 与 action_request，其他消息由会话层处理。 */
export class V2Dispatcher {
  constructor(
    private readonly contexts: ContextProvider,
    private readonly actions: ChromeActionAdapter,
    private readonly resolveURL: () => Promise<string | null>,
    private readonly send: Send,
    private readonly ledger: OperationLedgerStore,
    private readonly producerSessionId: string
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
      const operationId = envelope.operationId!;
      const acceptedAt = Date.now();
      const acceptedEvent = await this.event(envelope, "action_accepted", {
        operationId,
        acceptedAt
      });
      let state: LedgerState;
      try {
        state = await this.ledger.accept(operationId, acceptedEvent);
      } catch {
        // 接受证据无法持久化时禁止触发 Chrome 副作用；连接仍要收到可识别的失败结果。
        this.sendActionResult(envelope, "failed", "storage_full");
        return;
      }
      if (state !== "accepted") {
        const duplicate = duplicateResult(state);
        this.sendActionResult(envelope, duplicate.outcome, duplicate.reason);
        return;
      }
      const result = await this.actions.execute(action);
      const completedAt = Date.now();
      const outcome: ActionResultOutcome = result.outcome === "succeeded" ? "succeeded" : "failed";
      const reason: ActionResultReason = result.outcome === "failed" ? result.reason : "completed";
      await this.ledger.finalize(operationId, outcome, await this.event(envelope, "action_result", {
        operationId,
        outcome,
        reason,
        completedAt
      }, acceptedEvent.eventId));
      this.sendActionResult(envelope, outcome, reason, completedAt);
    }
  }

  private async event(
    envelope: ProviderEnvelope,
    type: "action_accepted" | "action_result",
    payload: ProviderEvent["payload"],
    causedByEventId = envelope.messageId
  ): Promise<ProviderEvent> {
    const now = Date.now();
    return {
      eventId: crypto.randomUUID(),
      producerSessionId: this.producerSessionId,
      producerSequence: await this.ledger.nextProducerSequence(),
      causedByEventId,
      monotonicClockMs: now,
      wallClockMs: now,
      gestureSessionId: envelope.gestureSessionId,
      operationId: envelope.operationId,
      type,
      payload
    };
  }

  private sendActionResult(envelope: ProviderEnvelope, outcome: ActionResultOutcome, reason: ActionResultReason, completedAt = Date.now()): void {
    this.send({ ...envelope, messageId: crypto.randomUUID(), type: "action_result", timestamp: Date.now(), payload: { operationId: envelope.operationId!, outcome, reason, completedAt }, error: null });
  }
}

function duplicateResult(state: Exclude<LedgerState, "accepted"> | "accepted"): { outcome: ActionResultOutcome; reason: ActionResultReason } {
  switch (state) {
    case "success": return { outcome: "succeeded", reason: "completed" };
    case "failed": return { outcome: "failed", reason: "provider_disconnected" };
    case "accepted":
    case "result_unknown": return { outcome: "result_unknown", reason: "recovery_timeout" };
  }
}
