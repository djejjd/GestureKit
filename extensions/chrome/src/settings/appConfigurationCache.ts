import type { ConfigurationSnapshotPayload } from "../provider/protocol";

/** App 下发的只读配置快照；此模块从不生成或修改用户配置。 */
export type AppConfigurationSnapshot = ConfigurationSnapshotPayload;

export type AppConfigurationCacheStorage = {
  get(key: string): Promise<Record<string, unknown>>;
  set(items: Record<string, unknown>): Promise<void>;
};

export const APP_CONFIGURATION_CACHE_STORAGE_KEY = "gesturekitAppConfigurationCache";

export function applySnapshot(
  cached: AppConfigurationSnapshot | null,
  incoming: AppConfigurationSnapshot
): AppConfigurationSnapshot {
  if (cached?.storeEpoch !== incoming.storeEpoch) {
    return incoming;
  }
  return cached.configurationVersion > incoming.configurationVersion ? cached : incoming;
}

export async function loadAppConfigurationCache(
  storage: AppConfigurationCacheStorage
): Promise<AppConfigurationSnapshot | null> {
  const value = (await storage.get(APP_CONFIGURATION_CACHE_STORAGE_KEY))[APP_CONFIGURATION_CACHE_STORAGE_KEY];
  return isSnapshot(value) ? value : null;
}

/** 仅保存已经由 App 接收的快照，绝不接受 popup 或 settings 写入。 */
export async function cacheAppConfigurationSnapshot(
  storage: AppConfigurationCacheStorage,
  snapshot: AppConfigurationSnapshot
): Promise<AppConfigurationSnapshot> {
  const cached = await loadAppConfigurationCache(storage);
  const applied = applySnapshot(cached, snapshot);
  await storage.set({ [APP_CONFIGURATION_CACHE_STORAGE_KEY]: applied });
  return applied;
}

function isSnapshot(value: unknown): value is AppConfigurationSnapshot {
  if (typeof value !== "object" || value === null) return false;
  const snapshot = value as Record<string, unknown>;
  return typeof snapshot.storeEpoch === "string" && snapshot.storeEpoch.length > 0 &&
    Number.isInteger(snapshot.schemaVersion) &&
    Number.isInteger(snapshot.configurationVersion) &&
    typeof snapshot.configJSON === "string";
}
