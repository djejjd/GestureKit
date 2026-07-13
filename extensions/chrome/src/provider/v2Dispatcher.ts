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
      // 链接副作用必须先证明候选 guard 与 opaque target 都有效，才允许写 acceptance。
      if (action.actionId === "browser.link.open_adjacent" && action.parameters.guardState !== "guard_armed") {
        this.sendActionResult(envelope, "failed", action.parameters.guardState === "guard_expired" ? "guard_expired" : "guard_unavailable");
        return;
      }
      const preflight = this.actions.preflight(action);
      if (preflight.outcome === "failed") {
        this.sendActionResult(envelope, "failed", preflight.reason);
        return;
      }
      const acceptedAt = Date.now();
      let acceptedEvent: ProviderEvent;
      let acceptance: { state: LedgerState; created: boolean };
      try {
        acceptedEvent = await this.event(envelope, "action_accepted", {
          operationId,
          acceptedAt
        });
        acceptance = await this.ledger.acceptWithDisposition(operationId, acceptedEvent);
      } catch {
        // 接受证据无法持久化时禁止触发 Chrome 副作用；连接仍要收到可识别的失败结果。
        this.sendActionResult(envelope, "failed", "storage_full");
        return;
      }
      if (!acceptance.created) {
        const duplicate = await duplicateResult(this.ledger, operationId, acceptance.state);
        this.sendActionResult(envelope, duplicate.outcome, duplicate.reason);
        return;
      }
      try {
        const result = await this.actions.execute(action);
        const outcome: ActionResultOutcome = result.outcome === "succeeded" ? "succeeded" : "failed";
        const reason: ActionResultReason = result.outcome === "failed" ? result.reason : "completed";
        await this.finalizeAndSend(envelope, operationId, outcome, reason, acceptedEvent.eventId);
      } catch {
        await this.finalizeAndSend(envelope, operationId, "failed", "chrome_api_error", acceptedEvent.eventId);
      }
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

  private async finalizeAndSend(
    envelope: ProviderEnvelope,
    operationId: string,
    outcome: ActionResultOutcome,
    reason: ActionResultReason,
    acceptedEventId: string
  ): Promise<void> {
    const completedAt = Date.now();
    try {
      await this.ledger.finalize(operationId, outcome, await this.event(envelope, "action_result", {
        operationId,
        outcome,
        reason,
        completedAt
      }, acceptedEventId));
      this.sendActionResult(envelope, outcome, reason, completedAt);
    } catch {
      // 副作用已发生但终态证据未能落库，不能向 App 虚报持久化终态。
      this.sendActionResult(envelope, "result_unknown", "recovery_timeout");
    }
  }
}

async function duplicateResult(
  ledger: OperationLedgerStore,
  operationId: string,
  state: LedgerState
): Promise<{ outcome: ActionResultOutcome; reason: ActionResultReason }> {
  if (state === "accepted") return { outcome: "result_unknown", reason: "recovery_timeout" };
  const record = await ledger.status(operationId);
  const terminalResult = record?.terminalResult;
  if (terminalResult && terminalResult.reason !== null) {
    return terminalResult;
  }
  const event = (await ledger.events(operationId)).findLast((candidate) => candidate.type === "action_result");
  if (event?.type === "action_result") {
    const payload = event.payload as { outcome: ActionResultOutcome; reason: ActionResultReason | null };
    if (payload.reason !== null) return { outcome: payload.outcome, reason: payload.reason };
  }
  return { outcome: "result_unknown", reason: "recovery_timeout" };
}
