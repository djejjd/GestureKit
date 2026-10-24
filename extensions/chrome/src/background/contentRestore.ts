type Dependencies = {
  query(): Promise<{ id?: number; url?: string }[]>;
  sendMessage(tabId: number, message: unknown): Promise<unknown>;
  executeScript(injection: { target: { tabId: number }; files: string[]; injectImmediately: boolean }): Promise<unknown>;
};

/** Probe first: worker restarts must not repeatedly replace healthy page scripts. */
export async function restoreContentScripts(api: Dependencies, buildId: string) {
  const summary = { checked: 0, restored: 0, failed: 0 };
  const tabs = (await api.query()).filter(tab => tab.id !== undefined && /^https?:\/\//.test(tab.url ?? ""));
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(4, tabs.length) }, async () => {
    while (next < tabs.length) {
      const tab = tabs[next++];
      summary.checked += 1;
      try {
        let installed: { buildId?: string } | null = null;
        try { installed = await api.sendMessage(tab.id!, { type: "gesturekit.contentVersion" }) as { buildId?: string } | null; } catch { /* not injected */ }
        if (installed?.buildId === buildId) continue;
        await api.executeScript({ target: { tabId: tab.id! }, files: ["dist/content/pointerTracker.js"], injectImmediately: true });
        summary.restored += 1;
      } catch { summary.failed += 1; }
    }
  }));
  return summary;
}
