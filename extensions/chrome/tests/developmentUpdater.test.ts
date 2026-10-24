import { afterEach, describe, expect, it, vi } from "vitest";
import { createDevelopmentUpdater } from "../src/background/developmentUpdater";

function updater(overrides: Record<string, unknown> = {}) {
  let saved: any = null;
  const options = {
    buildId: "a".repeat(64), installType: async () => "development",
    readBuild: vi.fn(async () => ({ schemaVersion: 1, buildId: "b".repeat(64) })),
    busy: () => false, load: async () => saved,
    save: vi.fn(async (value: unknown) => { saved = value; }),
    reload: vi.fn(), now: () => Date.now(), ...overrides
  };
  return { instance: createDevelopmentUpdater(options), options, saved: () => saved };
}
afterEach(() => vi.useRealTimers());

describe("development extension updates", () => {
  it("persists one correlated attempt before reloading, and does not loop on the same build", async () => {
    const { instance, options, saved } = updater();
    options.reload = vi.fn(); // the callback itself is still invoked from the supplied object
    await instance.check(); await instance.check();
    expect(saved()).toMatchObject({ stage: "reloading", buildId: "b".repeat(64), previousBuildId: "a".repeat(64) });
    expect(saved().operationId).toEqual(expect.any(String));
    expect(options.reload).toHaveBeenCalledTimes(1);
  });
  it("waits for an active gesture/action and retries once idle", async () => {
    let busy = true;
    const { instance, options } = updater({ busy: () => busy });
    await instance.check(); expect(options.reload).not.toHaveBeenCalled();
    busy = false; await instance.check(); expect(options.reload).toHaveBeenCalledTimes(1);
  });
  it.each(["normal", "admin", "sideload"])("never checks disk or reloads a %s install", async (installType) => {
    const { instance, options } = updater({ installType: async () => installType });
    await instance.check(); expect(options.readBuild).not.toHaveBeenCalled(); expect(options.reload).not.toHaveBeenCalled();
  });
  it("does not reload identical, malformed or unreadable builds", async () => {
    const readBuild = vi.fn().mockResolvedValueOnce({ schemaVersion: 1, buildId: "a".repeat(64) })
      .mockResolvedValueOnce({ schemaVersion: 1, buildId: "invalid" }).mockRejectedValueOnce(Error("missing"));
    const { instance, options } = updater({ readBuild });
    await instance.check(); await instance.check(); await instance.check();
    expect(options.reload).not.toHaveBeenCalled();
  });
  it("confirms the new running build with the original update operation ID", async () => {
    const prior = { operationId: "update-1", stage: "reloading", buildId: "a".repeat(64), startedAt: 950 };
    const { instance, saved } = updater({ now: () => 1_000, load: async () => prior, readBuild: async () => ({ schemaVersion: 1, buildId: "a".repeat(64) }) });
    await instance.check(); expect(saved()).toMatchObject({ operationId: "update-1", stage: "applied", durationMs: 50 });
  });
  it("records a reload failure, then allows a different build to be attempted", async () => {
    const { instance, options, saved } = updater({ reload: vi.fn(() => { throw Error("reload failed"); }) });
    await instance.check(); expect(saved()).toMatchObject({ stage: "failed", failureStage: "reload" });
    await instance.check(); expect(options.reload).toHaveBeenCalledTimes(1);
    options.readBuild.mockResolvedValue({ schemaVersion: 1, buildId: "c".repeat(64) });
    await instance.check(); expect(options.reload).toHaveBeenCalledTimes(2);
  });
  it("serializes concurrent checks instead of issuing duplicate reloads", async () => {
    const { instance, options } = updater();
    await Promise.all([instance.check(), instance.check(), instance.check()]);
    expect(options.reload).toHaveBeenCalledTimes(1);
  });
  it("keeps a confirmed applied update terminal when a subsequent marker read fails", async () => {
    let status: any = { operationId: "applied-update", stage: "reloading", buildId: "a".repeat(64), startedAt: Date.now() };
    const readBuild = vi.fn().mockRejectedValueOnce(Error("temporary read failure"))
      .mockResolvedValue({ schemaVersion: 1, buildId: "a".repeat(64) });
    const { instance } = updater({ readBuild, load: async () => status, save: async (value: unknown) => { status = value; } });
    await instance.check();
    expect(status).toMatchObject({ operationId: "applied-update", stage: "applied" });
    await instance.check();
    expect(status.stage).toBe("applied");
  });
});
