import type { ActionResultOutcome, ProviderEvent } from "./protocol";

/** Provider 本地账本的操作状态。 */
export type LedgerState = "accepted" | "success" | "failed" | "result_unknown";

/** 已持久化的幂等操作记录。 */
export type LedgerRecord = {
  operationId: string;
  state: LedgerState;
  updatedAt: number;
  terminalAt: number | null;
  compactedAt: number | null;
  eventIds: string[];
};

/** 单次 acceptance 事务的结果，明确区分本次新建与读取既有操作。 */
export type AcceptanceResult = {
  state: LedgerState;
  created: boolean;
};

/** IndexedDB ledger/outbox 的最小访问接口。 */
export interface OperationLedgerStore {
  accept(operationId: string, event: ProviderEvent): Promise<LedgerState>;
  acceptWithDisposition(operationId: string, event: ProviderEvent): Promise<AcceptanceResult>;
  finalize(operationId: string, outcome: ActionResultOutcome, event: ProviderEvent): Promise<void>;
  status(operationId: string): Promise<LedgerRecord | null>;
  events(operationId: string): Promise<ProviderEvent[]>;
  pending(limit: number): Promise<ProviderEvent[]>;
  append(event: ProviderEvent): Promise<void>;
  acknowledge(eventIds: string[]): Promise<void>;
  compact(now: number): Promise<void>;
  nextProducerSequence(): Promise<number>;
}

/** Provider 无法安全保存关键事件时必须拒绝继续执行。 */
export class ProviderStorageFullError extends Error {
  constructor() {
    super("provider_storage_full");
  }
}

export type OperationLedgerOptions = {
  maxOutboxBytes?: number;
  criticalReserveBytes?: number;
};

const LEDGER_STORE = "ledger";
const OUTBOX_STORE = "outbox";
const METADATA_STORE = "metadata";
const EVENTS_STORE = "events";
const OUTBOX_BYTES_KEY = "outbox_bytes";
const PRODUCER_SEQUENCE_KEY = "producer_sequence";

/** 打开 Provider 单一数据库，确保 ledger 和 outbox 能参加同一个事务。 */
export async function createOperationLedgerStore(name = "gesturekit-provider-v2", options: OperationLedgerOptions = {}): Promise<OperationLedgerStore> {
  const db = await openDatabase(name);
  return new IndexedDBOperationLedgerStore(db, options.maxOutboxBytes ?? 5 * 1024 * 1024, options.criticalReserveBytes ?? 1024 * 1024);
}

class IndexedDBOperationLedgerStore implements OperationLedgerStore {
  constructor(private readonly db: IDBDatabase, private readonly maxOutboxBytes: number, private readonly criticalReserveBytes: number) {}

  async accept(operationId: string, event: ProviderEvent): Promise<LedgerState> {
    return (await this.acceptWithDisposition(operationId, event)).state;
  }

  async acceptWithDisposition(operationId: string, event: ProviderEvent): Promise<AcceptanceResult> {
    const transaction = this.db.transaction([LEDGER_STORE, OUTBOX_STORE, EVENTS_STORE, METADATA_STORE], "readwrite");
    const ledger = transaction.objectStore(LEDGER_STORE);
    const existing = await request<LedgerRecord | undefined>(ledger.get(operationId));
    if (existing) {
      await transactionDone(transaction);
      return { state: existing.state, created: false };
    }
    await this.putEvent(transaction, event);
    transaction.objectStore(EVENTS_STORE).put(event);
    ledger.put({ operationId, state: "accepted", updatedAt: event.wallClockMs, terminalAt: null, compactedAt: null, eventIds: [event.eventId] } satisfies LedgerRecord);
    await transactionDone(transaction);
    return { state: "accepted", created: true };
  }

  async finalize(operationId: string, outcome: ActionResultOutcome, event: ProviderEvent): Promise<void> {
    const transaction = this.db.transaction([LEDGER_STORE, OUTBOX_STORE, EVENTS_STORE, METADATA_STORE], "readwrite");
    const state = outcomeToLedgerState(outcome);
    const ledger = transaction.objectStore(LEDGER_STORE);
    const existing = await request<LedgerRecord | undefined>(ledger.get(operationId));
    ledger.put({ operationId, state, updatedAt: event.wallClockMs, terminalAt: event.wallClockMs, compactedAt: null, eventIds: [...(existing?.eventIds ?? []), event.eventId] } satisfies LedgerRecord);
    await this.putEvent(transaction, event);
    transaction.objectStore(EVENTS_STORE).put(event);
    await transactionDone(transaction);
  }

  async status(operationId: string): Promise<LedgerRecord | null> {
    const transaction = this.db.transaction(LEDGER_STORE, "readonly");
    const record = await request<LedgerRecord | undefined>(transaction.objectStore(LEDGER_STORE).get(operationId));
    await transactionDone(transaction);
    return record ?? null;
  }

  async events(operationId: string): Promise<ProviderEvent[]> {
    const record = await this.status(operationId);
    if (!record) return [];
    const transaction = this.db.transaction(EVENTS_STORE, "readonly");
    const events = transaction.objectStore(EVENTS_STORE);
    const values = await Promise.all((record.eventIds ?? []).map((eventId) => request<ProviderEvent | undefined>(events.get(eventId))));
    await transactionDone(transaction);
    return values.filter((event): event is ProviderEvent => event !== undefined);
  }

  async pending(limit: number): Promise<ProviderEvent[]> {
    const transaction = this.db.transaction(OUTBOX_STORE, "readonly");
    const all = await request<ProviderEvent[]>(transaction.objectStore(OUTBOX_STORE).getAll());
    await transactionDone(transaction);
    return all.sort((left, right) => left.producerSequence - right.producerSequence).slice(0, limit);
  }

  async acknowledge(eventIds: string[]): Promise<void> {
    const transaction = this.db.transaction([OUTBOX_STORE, METADATA_STORE], "readwrite");
    const outbox = transaction.objectStore(OUTBOX_STORE);
    const existing = await Promise.all([...new Set(eventIds)].map((eventId) => request<ProviderEvent | undefined>(outbox.get(eventId))));
    const metadata = transaction.objectStore(METADATA_STORE);
    const currentBytes = await this.outboxBytes(transaction);
    const reclaimed = existing.reduce((sum, event) => sum + (event ? encodedSize(event) : 0), 0);
    for (const eventId of new Set(eventIds)) outbox.delete(eventId);
    metadata.put({ key: OUTBOX_BYTES_KEY, value: Math.max(0, currentBytes - reclaimed) });
    await transactionDone(transaction);
  }

  async append(event: ProviderEvent): Promise<void> {
    const transaction = this.db.transaction([OUTBOX_STORE, METADATA_STORE], "readwrite");
    await this.putEvent(transaction, event);
    await transactionDone(transaction);
  }

  async compact(now: number): Promise<void> {
    const transaction = this.db.transaction([LEDGER_STORE, EVENTS_STORE], "readwrite");
    const ledger = transaction.objectStore(LEDGER_STORE);
    const events = transaction.objectStore(EVENTS_STORE);
    const records = await request<LedgerRecord[]>(ledger.getAll());
    for (const record of records) {
      if (record.terminalAt === null) continue;
      if (record.compactedAt !== null && now - record.terminalAt >= 7 * 24 * 60 * 60 * 1000) {
        ledger.delete(record.operationId);
      } else if (record.compactedAt === null && now - record.terminalAt >= 10 * 60 * 1000) {
        for (const eventId of record.eventIds ?? []) events.delete(eventId);
        ledger.put({ ...record, compactedAt: now });
      }
    }
    await transactionDone(transaction);
  }

  async nextProducerSequence(): Promise<number> {
    const transaction = this.db.transaction(METADATA_STORE, "readwrite");
    const metadata = transaction.objectStore(METADATA_STORE);
    const current = await request<{ key: string; value: number } | undefined>(metadata.get(PRODUCER_SEQUENCE_KEY));
    const next = (current?.value ?? 0) + 1;
    metadata.put({ key: PRODUCER_SEQUENCE_KEY, value: next });
    await transactionDone(transaction);
    return next;
  }

  private async putEvent(transaction: IDBTransaction, event: ProviderEvent): Promise<void> {
    const outbox = transaction.objectStore(OUTBOX_STORE);
    const existing = await request<ProviderEvent | undefined>(outbox.get(event.eventId));
    const totalBytes = await this.outboxBytes(transaction) - (existing ? encodedSize(existing) : 0) + encodedSize(event);
    const limit = isCriticalEvent(event) ? this.maxOutboxBytes : this.maxOutboxBytes - this.criticalReserveBytes;
    if (totalBytes > limit) {
      transaction.abort();
      throw new ProviderStorageFullError();
    }
    outbox.put(event);
    transaction.objectStore(METADATA_STORE).put({ key: OUTBOX_BYTES_KEY, value: totalBytes });
  }

  /** 旧数据库首次使用时只扫描一次，之后完全依赖事务内 metadata 计数。 */
  private async outboxBytes(transaction: IDBTransaction): Promise<number> {
    const metadata = transaction.objectStore(METADATA_STORE);
    const cached = await request<{ key: string; value: number } | undefined>(metadata.get(OUTBOX_BYTES_KEY));
    if (cached) return cached.value;
    const events = await request<ProviderEvent[]>(transaction.objectStore(OUTBOX_STORE).getAll());
    const value = events.reduce((sum, event) => sum + encodedSize(event), 0);
    metadata.put({ key: OUTBOX_BYTES_KEY, value });
    return value;
  }
}

function openDatabase(name: string): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(name, 2);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(LEDGER_STORE)) db.createObjectStore(LEDGER_STORE, { keyPath: "operationId" });
      if (!db.objectStoreNames.contains(OUTBOX_STORE)) db.createObjectStore(OUTBOX_STORE, { keyPath: "eventId" });
      if (!db.objectStoreNames.contains(METADATA_STORE)) db.createObjectStore(METADATA_STORE, { keyPath: "key" });
      if (!db.objectStoreNames.contains(EVENTS_STORE)) db.createObjectStore(EVENTS_STORE, { keyPath: "eventId" });
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

function isCriticalEvent(event: ProviderEvent): boolean {
  return event.type === "action_accepted" || event.type === "action_result";
}

function encodedSize(event: ProviderEvent): number {
  return new TextEncoder().encode(JSON.stringify(event)).byteLength;
}
