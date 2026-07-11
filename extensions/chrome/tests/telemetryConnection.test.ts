import { describe, expect, it } from "vitest";
import { createOperationLedgerStore } from "../src/provider/operationLedger";
import { TelemetryConnection } from "../src/provider/telemetryConnection";
import type { ProviderEnvelope, ProviderEvent } from "../src/provider/protocol";

function accepted(): ProviderEvent { return { eventId: "event", producerSessionId: "producer", producerSequence: 1, causedByEventId: null, monotonicClockMs: 1, wallClockMs: 1, gestureSessionId: null, operationId: "operation", type: "action_accepted", payload: { operationId: "operation", acceptedAt: 1 } }; }
function envelope(type: ProviderEnvelope["type"], payload: ProviderEnvelope["payload"]): ProviderEnvelope { return { protocolVersion: 2, messageId: crypto.randomUUID(), providerSessionId: "provider", gestureSessionId: null, operationId: null, type, timestamp: 1, payload, error: null }; }

describe("TelemetryConnection", () => {
  it("starts synchronization only after capability snapshot and consumes telemetry ACK", async () => {
    const store = await createOperationLedgerStore(`connection-${crypto.randomUUID()}`);
    await store.accept("operation", accepted());
    const sent: ProviderEnvelope[] = [];
    const connection = new TelemetryConnection(store, "producer", (message) => sent.push(message));

    await connection.handle(envelope("capability_snapshot", { capabilities: [], capabilityVersion: 1 }));
    expect(sent.map((message) => message.type)).toEqual(["operation_status_request", "telemetry_batch"]);
    await connection.handle(envelope("telemetry_ack", { acknowledgedEventIds: ["event"] }));
    await expect(store.pending(10)).resolves.toEqual([]);
  });
});
