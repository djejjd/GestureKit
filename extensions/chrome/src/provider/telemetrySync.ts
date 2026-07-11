import type { ProviderEnvelope } from "./protocol";
import type { OperationLedgerStore } from "./operationLedger";
import { buildReconciliationPlan } from "./reconciliation";

/** 已认证 Provider 会话的最小发送信息。 */
export type ProviderSessionContext = {
  providerSessionId: string;
  producerSessionId: string;
};

/** 认证完成后的对账顺序：未终态状态查询在前，telemetry batch 在后。 */
export async function synchronizeTelemetry(
  store: OperationLedgerStore,
  session: ProviderSessionContext,
  send: (envelope: ProviderEnvelope) => void,
  now = Date.now()
): Promise<void> {
  const plan = await buildReconciliationPlan(store, 100);
  let sequence = 0;
  for (const operationId of plan.pendingOperationIds) {
    send(envelope(session, `status-${++sequence}`, "operation_status_request", operationId, { operationId }, now));
  }
  if (plan.pendingEvents.length > 0) {
    send(envelope(session, `telemetry-${++sequence}`, "telemetry_batch", null, { events: plan.pendingEvents }, now));
  }
}

/** ACK 只清理 outbox，不修改 ledger。 */
export function acknowledgeTelemetry(store: OperationLedgerStore, acknowledgedEventIds: string[]): Promise<void> {
  return store.acknowledge(acknowledgedEventIds);
}

function envelope(
  session: ProviderSessionContext,
  messageId: string,
  type: ProviderEnvelope["type"],
  operationId: string | null,
  payload: ProviderEnvelope["payload"],
  timestamp: number
): ProviderEnvelope {
  return {
    protocolVersion: 2,
    messageId,
    providerSessionId: session.providerSessionId,
    gestureSessionId: null,
    operationId,
    type,
    timestamp,
    payload,
    error: null
  };
}
