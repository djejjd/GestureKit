import type { ActionResultOutcome, ProviderEvent } from "./protocol";

/** Provider 本地账本的操作状态。 */
export type LedgerState = "accepted" | "success" | "failed" | "result_unknown";

/** 已持久化的幂等操作记录。 */
export type LedgerRecord = {
  operationId: string;
  state: LedgerState;
  updatedAt: number;
};

/** IndexedDB ledger/outbox 的最小访问接口。 */
export interface OperationLedgerStore {
  accept(operationId: string, event: ProviderEvent): Promise<LedgerState>;
  finalize(operationId: string, outcome: ActionResultOutcome, event: ProviderEvent): Promise<void>;
  status(operationId: string): Promise<LedgerRecord | null>;
  pending(limit: number): Promise<ProviderEvent[]>;
  append(event: ProviderEvent): Promise<void>;
  acknowledge(eventIds: string[]): Promise<void>;
}

const LEDGER_STORE = "ledger";
const OUTBOX_STORE = "outbox";
const METADATA_STORE = "metadata";

/** 打开 Provider 单一数据库，确保 ledger 和 outbox 能参加同一个事务。 */
export async function createOperationLedgerStore(name = "gesturekit-provider-v2"): Promise<OperationLedgerStore> {
  const db = await openDatabase(name);
  return new IndexedDBOperationLedgerStore(db);
}

class IndexedDBOperationLedgerStore implements OperationLedgerStore {
  constructor(private readonly db: IDBDatabase) {}

  async accept(operationId: string, event: ProviderEvent): Promise<LedgerState> {
    const transaction = this.db.transaction([LEDGER_STORE, OUTBOX_STORE], "readwrite");
    const ledger = transaction.objectStore(LEDGER_STORE);
    const existing = await request<LedgerRecord | undefined>(ledger.get(operationId));
    if (existing) {
      await transactionDone(transaction);
      return existing.state;
    }
    ledger.put({ operationId, state: "accepted", updatedAt: event.wallClockMs } satisfies LedgerRecord);
    transaction.objectStore(OUTBOX_STORE).put(event);
    await transactionDone(transaction);
    return "accepted";
  }

  async finalize(operationId: string, outcome: ActionResultOutcome, event: ProviderEvent): Promise<void> {
    const transaction = this.db.transaction([LEDGER_STORE, OUTBOX_STORE], "readwrite");
    const state = outcomeToLedgerState(outcome);
    transaction.objectStore(LEDGER_STORE).put({ operationId, state, updatedAt: event.wallClockMs } satisfies LedgerRecord);
    transaction.objectStore(OUTBOX_STORE).put(event);
    await transactionDone(transaction);
  }

  async status(operationId: string): Promise<LedgerRecord | null> {
    const transaction = this.db.transaction(LEDGER_STORE, "readonly");
    const record = await request<LedgerRecord | undefined>(transaction.objectStore(LEDGER_STORE).get(operationId));
    await transactionDone(transaction);
    return record ?? null;
  }

  async pending(limit: number): Promise<ProviderEvent[]> {
    const transaction = this.db.transaction(OUTBOX_STORE, "readonly");
    const all = await request<ProviderEvent[]>(transaction.objectStore(OUTBOX_STORE).getAll());
    await transactionDone(transaction);
    return all.sort((left, right) => left.producerSequence - right.producerSequence).slice(0, limit);
  }

  async acknowledge(eventIds: string[]): Promise<void> {
    const transaction = this.db.transaction(OUTBOX_STORE, "readwrite");
    const outbox = transaction.objectStore(OUTBOX_STORE);
    for (const eventId of eventIds) outbox.delete(eventId);
    await transactionDone(transaction);
  }

  async append(event: ProviderEvent): Promise<void> {
    const transaction = this.db.transaction(OUTBOX_STORE, "readwrite");
    transaction.objectStore(OUTBOX_STORE).put(event);
    await transactionDone(transaction);
  }
}

function openDatabase(name: string): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(name, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      db.createObjectStore(LEDGER_STORE, { keyPath: "operationId" });
      db.createObjectStore(OUTBOX_STORE, { keyPath: "eventId" });
      db.createObjectStore(METADATA_STORE, { keyPath: "key" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("无法打开 Provider IndexedDB"));
  });
}

function request<T>(idbRequest: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    idbRequest.onsuccess = () => resolve(idbRequest.result);
    idbRequest.onerror = () => reject(idbRequest.error ?? new Error("IndexedDB 请求失败"));
  });
}

function transactionDone(transaction: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onabort = () => reject(transaction.error ?? new Error("IndexedDB 事务被中止"));
    transaction.onerror = () => reject(transaction.error ?? new Error("IndexedDB 事务失败"));
  });
}

function outcomeToLedgerState(outcome: ActionResultOutcome): LedgerState {
  switch (outcome) {
    case "succeeded": return "success";
    case "failed": return "failed";
    case "result_unknown": return "result_unknown";
  }
}
