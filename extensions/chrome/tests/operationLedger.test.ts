import { describe, expect, it } from "vitest";
import { createOperationLedgerStore } from "../src/provider/operationLedger";
import type { ProviderEvent } from "../src/provider/protocol";

function event(eventId: string, type: "action_accepted" | "action_result"): ProviderEvent {
  return {
    eventId,
    producerSessionId: "provider-session",
    producerSequence: type === "action_accepted" ? 1 : 2,
    causedByEventId: null,
    monotonicClockMs: 1,
    wallClockMs: 1,
    gestureSessionId: "gesture-session",
    operationId: "operation-1",
    type,
    payload: type === "action_accepted"
      ? { operationId: "operation-1", acceptedAt: 1 }
      : { operationId: "operation-1", outcome: "succeeded", reason: "completed", completedAt: 2 }
  };
}

describe("OperationLedger", () => {
  it("persists accepted ledger state and action_accepted event atomically", async () => {
    const store = await createOperationLedgerStore(`ledger-${crypto.randomUUID()}`);
    const accepted = event("event-accepted", "action_accepted");

    await expect(store.accept("operation-1", accepted)).resolves.toBe("accepted");
    await expect(store.status("operation-1")).resolves.toMatchObject({ state: "accepted" });
    await expect(store.pending(10)).resolves.toContainEqual(accepted);
  });

  it("returns existing state without duplicating an accepted operation", async () => {
    const store = await createOperationLedgerStore(`ledger-${crypto.randomUUID()}`);
    const accepted = event("event-accepted", "action_accepted");

    await store.accept("operation-1", accepted);
    await expect(store.accept("operation-1", accepted)).resolves.toBe("accepted");
    await expect(store.pending(10)).resolves.toHaveLength(1);
  });

  it("persists final state and keeps it after outbox acknowledgement", async () => {
    const store = await createOperationLedgerStore(`ledger-${crypto.randomUUID()}`);
    await store.accept("operation-1", event("event-accepted", "action_accepted"));
    const result = event("event-result", "action_result");

    await store.finalize("operation-1", "succeeded", result);
    await store.acknowledge(["event-accepted", "event-result"]);

    await expect(store.status("operation-1")).resolves.toMatchObject({ state: "success" });
    await expect(store.pending(10)).resolves.toEqual([]);
  });

  it("compacts terminal records after ten minutes but keeps accepted operations", async () => {
    const store = await createOperationLedgerStore(`ledger-${crypto.randomUUID()}`);
    await store.accept("operation-1", event("event-accepted", "action_accepted"));
    await store.finalize("operation-1", "succeeded", event("event-result", "action_result"));
    await store.accept("operation-2", { ...event("event-accepted-2", "action_accepted"), operationId: "operation-2", payload: { operationId: "operation-2", acceptedAt: 1 } });

    await store.compact(10 * 60 * 1000 + 2);

    await expect(store.status("operation-1")).resolves.toMatchObject({ state: "success", compactedAt: 600002 });
    await expect(store.status("operation-2")).resolves.toMatchObject({ state: "accepted", compactedAt: null });
  });

  it("keeps complete events after ACK until terminal compaction", async () => {
    const store = await createOperationLedgerStore(`ledger-${crypto.randomUUID()}`);
    await store.accept("operation-1", event("event-accepted", "action_accepted"));
    await store.finalize("operation-1", "succeeded", event("event-result", "action_result"));
    await store.acknowledge(["event-accepted", "event-result"]);

    await expect(store.events("operation-1")).resolves.toHaveLength(2);
    await store.compact(10 * 60 * 1000 + 2);
    await expect(store.events("operation-1")).resolves.toEqual([]);
  });

  it("recovers accepted and final transactions after a worker restart", async () => {
    const databaseName = `ledger-${crypto.randomUUID()}`;
    const firstWorker = await createOperationLedgerStore(databaseName);
    await firstWorker.accept("operation-1", event("event-accepted", "action_accepted"));

    const afterAcceptedRestart = await createOperationLedgerStore(databaseName);
    await expect(afterAcceptedRestart.status("operation-1")).resolves.toMatchObject({ state: "accepted" });
    await expect(afterAcceptedRestart.pending(10)).resolves.toMatchObject([{ eventId: "event-accepted" }]);

    await afterAcceptedRestart.finalize("operation-1", "succeeded", event("event-result", "action_result"));
    const afterFinalRestart = await createOperationLedgerStore(databaseName);
    await expect(afterFinalRestart.status("operation-1")).resolves.toMatchObject({ state: "success" });
    await expect(afterFinalRestart.pending(10)).resolves.toMatchObject([{ eventId: "event-accepted" }, { eventId: "event-result" }]);
  });

  it("continues producer sequence after a worker restart", async () => {
    const databaseName = `ledger-${crypto.randomUUID()}`;
    const firstWorker = await createOperationLedgerStore(databaseName);
    await expect(firstWorker.nextProducerSequence()).resolves.toBe(1);
    await expect(firstWorker.nextProducerSequence()).resolves.toBe(2);

    const restartedWorker = await createOperationLedgerStore(databaseName);
    await expect(restartedWorker.nextProducerSequence()).resolves.toBe(3);
  });
});
