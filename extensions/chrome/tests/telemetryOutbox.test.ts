import { describe, expect, it } from "vitest";
import { createTelemetryOutbox } from "../src/provider/telemetryOutbox";
import type { ProviderEvent } from "../src/provider/protocol";

function telemetry(eventId: string, sequence: number): ProviderEvent {
  return {
    eventId,
    producerSessionId: "provider-session",
    producerSequence: sequence,
    causedByEventId: null,
    monotonicClockMs: sequence,
    wallClockMs: sequence,
    gestureSessionId: null,
    operationId: "operation-1",
    type: "action_accepted",
    payload: { operationId: "operation-1", acceptedAt: sequence }
  };
}

describe("TelemetryOutbox", () => {
  it("returns queued events in producer sequence order and removes only acknowledged events", async () => {
    const outbox = await createTelemetryOutbox(`outbox-${crypto.randomUUID()}`);
    await outbox.append(telemetry("event-2", 2));
    await outbox.append(telemetry("event-1", 1));

    await expect(outbox.pending(10)).resolves.toMatchObject([{ eventId: "event-1" }, { eventId: "event-2" }]);
    await outbox.acknowledge(["event-1"]);
    await expect(outbox.pending(10)).resolves.toMatchObject([{ eventId: "event-2" }]);
  });
});
