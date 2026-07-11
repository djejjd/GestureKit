import { describe, expect, it } from "vitest";
import { createOperationLedgerStore } from "../src/provider/operationLedger";
import { buildReconciliationPlan } from "../src/provider/reconciliation";
import type { ProviderEvent } from "../src/provider/protocol";

function acceptedEvent(operationId: string, eventId: string, sequence: number): ProviderEvent {
  return {
    eventId,
    producerSessionId: "provider-session",
    producerSequence: sequence,
    causedByEventId: null,
    monotonicClockMs: sequence,
    wallClockMs: sequence,
    gestureSessionId: "gesture-session",
    operationId,
    type: "action_accepted",
    payload: { operationId, acceptedAt: sequence }
  };
}

describe("reconciliation", () => {
  it("requests status only for accepted operations and keeps events ordered", async () => {
    const store = await createOperationLedgerStore(`reconcile-${crypto.randomUUID()}`);
    await store.accept("operation-2", acceptedEvent("operation-2", "event-2", 2));
    await store.accept("operation-1", acceptedEvent("operation-1", "event-1", 1));

    await expect(buildReconciliationPlan(store, 10)).resolves.toEqual({
      pendingEvents: [acceptedEvent("operation-1", "event-1", 1), acceptedEvent("operation-2", "event-2", 2)],
      pendingOperationIds: ["operation-1", "operation-2"]
    });
  });
});
