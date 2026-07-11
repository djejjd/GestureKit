import type { ProviderEvent } from "./protocol";
import { createOperationLedgerStore, type OperationLedgerOptions, type OperationLedgerStore } from "./operationLedger";

/** Provider 可补交 telemetry 的只关注队列接口。 */
export interface TelemetryOutbox {
  append(event: ProviderEvent): Promise<void>;
  acknowledge(eventIds: string[]): Promise<void>;
  pending(limit: number): Promise<ProviderEvent[]>;
}

/** 与 ledger 共享数据库，避免关键事件跨库丢失。 */
export async function createTelemetryOutbox(databaseName?: string, options?: OperationLedgerOptions): Promise<TelemetryOutbox> {
  const store = await createOperationLedgerStore(databaseName, options);
  return new IndexedDBTelemetryOutbox(store);
}

class IndexedDBTelemetryOutbox implements TelemetryOutbox {
  constructor(private readonly store: OperationLedgerStore) {}

  append(event: ProviderEvent): Promise<void> { return this.store.append(event); }
  acknowledge(eventIds: string[]): Promise<void> { return this.store.acknowledge(eventIds); }
  pending(limit: number): Promise<ProviderEvent[]> { return this.store.pending(limit); }
}
