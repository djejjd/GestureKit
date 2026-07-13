import { describe, expect, it } from "vitest";
import { applySnapshot, type AppConfigurationSnapshot } from "../src/settings/appConfigurationCache";

function snapshotWithEpoch(storeEpoch: string): AppConfigurationSnapshot {
  return {
    storeEpoch,
    schemaVersion: 2,
    configurationVersion: 1,
    diagnosticLoggingEnabled: false,
    configJSON: '{"recognition":{"swipeSensitivity":"standard"}}'
  };
}

describe("app configuration cache", () => {
  it("drops a cache with a different store epoch", () => {
    expect(applySnapshot(snapshotWithEpoch("old"), snapshotWithEpoch("new")))
      .toEqual(snapshotWithEpoch("new"));
  });

  it("keeps the newest cache entry within an epoch", () => {
    expect(applySnapshot(
      { ...snapshotWithEpoch("stable"), configurationVersion: 3 },
      { ...snapshotWithEpoch("stable"), configurationVersion: 2 }
    )).toEqual({ ...snapshotWithEpoch("stable"), configurationVersion: 3 });
  });
});
