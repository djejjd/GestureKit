import type { ProviderEvent } from "./protocol";
import type { OperationLedgerStore } from "./operationLedger";

/** 重连时先补交的本地事件，以及需要向 App 查询的未终态操作。 */
export type ReconciliationPlan = {
  pendingEvents: ProviderEvent[];
  pendingOperationIds: string[];
};

/** 生成不产生副作用的对账计划；调用方必须先完成认证再发送该计划。 */
export async function buildReconciliationPlan(store: OperationLedgerStore, limit: number): Promise<ReconciliationPlan> {
  const pendingEvents = await store.pending(limit);
  const operationIds = [...new Set(pendingEvents.map((event) => event.operationId).filter((id): id is string => id !== null))];
  const pendingOperationIds: string[] = [];

  for (const operationId of operationIds) {
    const record = await store.status(operationId);
    if (record?.state === "accepted") pendingOperationIds.push(operationId);
  }

  return { pendingEvents, pendingOperationIds };
}
