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

  it("retains 24-hour offline events and sends them in producer sequence order", async () => {
    const outbox = await createTelemetryOutbox(`outbox-offline-${crypto.randomUUID()}`);
    const dayMs = 24 * 60 * 60 * 1000;
    const older = { ...telemetry("event-older", 1), wallClockMs: 1 };
    const newer = { ...telemetry("event-newer", 2), wallClockMs: dayMs + 1 };

    await outbox.append(newer);
    await outbox.append(older);

    await expect(outbox.pending(10)).resolves.toEqual([older, newer]);
  });

  it("reserves capacity for critical action evidence", async () => {
    const outbox = await createTelemetryOutbox(`outbox-${crypto.randomUUID()}`, { maxOutboxBytes: 500, criticalReserveBytes: 200 });
    const nonCritical = { ...telemetry("event-health", 1), type: "health_response" as const, payload: { probeSequence: 1, healthy: true }, eventId: "x".repeat(180) };

    await expect(outbox.append(nonCritical)).rejects.toThrow("provider_storage_full");
  });

  it("rejects while saturated, then reclaims capacity only after ACK", async () => {
    const first = { ...telemetry("event-first", 1), eventId: "f".repeat(120) };
    const second = { ...telemetry("event-second", 2), eventId: "s".repeat(120) };
    const bytesForOneEvent = new TextEncoder().encode(JSON.stringify(first)).byteLength;
    const outbox = await createTelemetryOutbox(`outbox-${crypto.randomUUID()}`, { maxOutboxBytes: bytesForOneEvent, criticalReserveBytes: 0 });

    await outbox.append(first);
    await expect(outbox.append(second)).rejects.toThrow("provider_storage_full");
    await expect(outbox.pending(10)).resolves.toEqual([first]);

    await outbox.acknowledge([first.eventId]);
    await expect(outbox.append(second)).resolves.toBeUndefined();
    await expect(outbox.pending(10)).resolves.toEqual([second]);
  });
});
