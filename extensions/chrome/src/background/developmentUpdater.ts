export type DevelopmentUpdateStatus = {
  operationId: string;
  buildId: string;
  previousBuildId?: string;
  lastAttemptBuildId?: string;
  stage: "deferred" | "reloading" | "applied" | "failed";
  failureStage?: "read" | "reload";
  startedAt: number;
  durationMs?: number;
  lastCheckFailure?: "read";
};

/** Local unpacked resources only; no remote downloads and no page-supplied commands. */
export function createDevelopmentUpdater(options: {
  buildId: string;
  installType(): Promise<string>;
  readBuild(): Promise<unknown>;
  busy(): boolean;
  load(): Promise<DevelopmentUpdateStatus | null>;
  save(status: DevelopmentUpdateStatus): Promise<void>;
  reload(): void;
  now(): number;
}) {
  let checking = false;
  let installation: Promise<string> | null = null;
  let attempted: string | undefined;
  return {
    async check(): Promise<void> {
      if (checking || !validBuildId(options.buildId)) return;
      checking = true;
      let previous: DevelopmentUpdateStatus | null = null;
      try {
        installation ??= options.installType();
        if (await installation !== "development") return;
        previous = await options.load();
        if (previous?.stage === "reloading" && previous.buildId === options.buildId) {
          previous = { ...previous, stage: "applied", durationMs: Math.max(0, options.now() - previous.startedAt) };
          await options.save(previous);
        }
        const marker = await options.readBuild() as { schemaVersion?: number; buildId?: unknown } | null;
        if (marker?.schemaVersion !== 1 || !validBuildId(marker.buildId)) throw Error("invalid build marker");
        if (marker.buildId === options.buildId) {
          if (previous?.lastCheckFailure) await options.save({ ...previous, lastCheckFailure: undefined });
          return;
        }
        if (attempted === marker.buildId || previous?.lastAttemptBuildId === marker.buildId) return;
        const status: DevelopmentUpdateStatus = {
          operationId: previous?.stage === "deferred" && previous.buildId === marker.buildId ? previous.operationId : crypto.randomUUID(),
          buildId: marker.buildId, previousBuildId: options.buildId,
          startedAt: previous?.stage === "deferred" && previous.buildId === marker.buildId ? previous.startedAt : options.now(),
          stage: "deferred", lastAttemptBuildId: previous?.lastAttemptBuildId
        };
        if (options.busy()) { await options.save(status); return; }
        attempted = marker.buildId;
        status.lastAttemptBuildId = marker.buildId;
        status.stage = "reloading";
        await options.save(status); // Must be durable before terminating this worker.
        // A gesture may have arrived while storage was committing the request.
        if (options.busy()) {
          attempted = undefined;
          await options.save({ ...status, stage: "deferred", lastAttemptBuildId: previous?.lastAttemptBuildId });
          return;
        }
        try { options.reload(); }
        catch { await options.save({ ...status, stage: "failed", failureStage: "reload" }); }
      } catch {
        if (previous?.stage === "applied" && previous.buildId === options.buildId) {
          try { await options.save({ ...previous, lastCheckFailure: "read" }); } catch { /* retain confirmed terminal */ }
          return;
        }
        // One bounded status object; never persist arbitrary browser errors or URLs.
        try {
          await options.save({
            operationId: previous?.operationId ?? crypto.randomUUID(), buildId: previous?.buildId ?? options.buildId,
            lastAttemptBuildId: attempted ?? previous?.lastAttemptBuildId,
            stage: "failed", failureStage: "read", startedAt: previous?.startedAt ?? options.now()
          });
        } catch { /* Storage failure cannot authorize a reload. */ }
      } finally { checking = false; }
    }
  };
}

function validBuildId(value: unknown): value is string {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}
