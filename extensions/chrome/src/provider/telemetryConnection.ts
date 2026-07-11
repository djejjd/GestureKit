import type { ProviderEnvelope } from "./protocol";
import type { OperationLedgerStore } from "./operationLedger";
import { acknowledgeTelemetry, synchronizeTelemetry } from "./telemetrySync";

/** 将 telemetry 同步限定在已认证会话的 capability snapshot 之后。 */
export class TelemetryConnection {
  constructor(
    private readonly store: OperationLedgerStore,
    private readonly producerSessionId: string,
    private readonly send: (message: ProviderEnvelope) => void
  ) {}

  async handle(envelope: ProviderEnvelope): Promise<void> {
    if (envelope.type === "capability_snapshot") {
      await synchronizeTelemetry(this.store, { providerSessionId: envelope.providerSessionId, producerSessionId: this.producerSessionId }, this.send);
    }
    if (envelope.type === "telemetry_ack") {
      const payload = envelope.payload as { acknowledgedEventIds: string[] };
      await acknowledgeTelemetry(this.store, payload.acknowledgedEventIds);
    }
  }
}
