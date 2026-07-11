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
});
