import { describe, expect, it } from "vitest";
import { createOperationLedgerStore } from "../src/provider/operationLedger";
import { synchronizeTelemetry } from "../src/provider/telemetrySync";
import type { ProviderEvent, ProviderEnvelope } from "../src/provider/protocol";

function acceptedEvent(): ProviderEvent {
  return {
    eventId: "event-accepted", producerSessionId: "producer", producerSequence: 1, causedByEventId: null,
    monotonicClockMs: 1, wallClockMs: 1, gestureSessionId: "gesture", operationId: "operation-1",
    type: "action_accepted", payload: { operationId: "operation-1", acceptedAt: 1 }
  };
}

describe("telemetry synchronization", () => {
  it("sends status request before telemetry batch after authentication", async () => {
    const store = await createOperationLedgerStore(`sync-${crypto.randomUUID()}`);
    await store.accept("operation-1", acceptedEvent());
    const sent: ProviderEnvelope[] = [];

    await synchronizeTelemetry(store, { providerSessionId: "provider", producerSessionId: "producer" }, (message) => sent.push(message), 10);

    expect(sent.map((message) => message.type)).toEqual(["operation_status_request", "telemetry_batch"]);
    expect(sent[1].payload).toMatchObject({ events: [acceptedEvent()] });
  });

  it("uses new message IDs for every reconnect synchronization", async () => {
    const store = await createOperationLedgerStore(`sync-${crypto.randomUUID()}`);
    await store.accept("operation-1", acceptedEvent());
    const first: ProviderEnvelope[] = [];
    const second: ProviderEnvelope[] = [];

    await synchronizeTelemetry(store, { providerSessionId: "provider", producerSessionId: "producer" }, (message) => first.push(message));
    await synchronizeTelemetry(store, { providerSessionId: "provider", producerSessionId: "producer" }, (message) => second.push(message));

    expect(new Set([...first, ...second].map((message) => message.messageId)).size).toBe(first.length + second.length);
  });
});
