import { describe, expect, it, vi } from "vitest";
import { ChromeProvider } from "../src/provider/chromeProvider";
import type { ChromeApi } from "../src/background/chromeApi";
import { ContextProvider } from "../src/provider/contextProvider";
import { ChromeActionAdapter } from "../src/provider/actionAdapter";
import { V2Dispatcher } from "../src/provider/v2Dispatcher";
import { createOperationLedgerStore } from "../src/provider/operationLedger";
import type { ProviderEnvelope } from "../src/provider/protocol";

describe("disconnect during accepted browser execution", () => {
  it("does not reload after an executing tab query completes on a dead session", async () => {
    let active = true;
    let queries = 0;
    const effects: number[] = [];
    const tab = { id: 10, index: 1, windowId: 1, url: "https://example.test" } as chrome.tabs.Tab;
    const api = { tabs: {
      query: async () => { if (++queries === 3) { await Promise.resolve(); active = false; } return [tab]; },
      reload: async (id: number) => { effects.push(id); }
    } } as unknown as ChromeApi;
    const provider = new ChromeProvider(api, async () => null);
    const deadline = Date.now() + 10_000;
    const snapshot = await provider.context({ gestureSessionId: "gesture", requiresTargetRef: false, deadline });
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    const ledger = await createOperationLedgerStore(`interrupted-${crypto.randomUUID()}`);
    const dispatcher = new V2Dispatcher(contexts, new ChromeActionAdapter(contexts, async () => {}), async () => null,
      message => sent.push(message), ledger, "producer", provider, () => active);
    await dispatcher.handle({
      protocolVersion: 2, messageId: "action", providerSessionId: "session", gestureSessionId: "gesture", operationId: "operation",
      type: "action_request", timestamp: Date.now(), payload: { actionId: "browser.page.reload", contextId: snapshot.contextId, deadline, parameters: {} }, error: null
    });
    expect(effects).toEqual([]);
    await expect(ledger.status("operation")).resolves.toMatchObject({ state: "failed" });
    expect(sent[0].payload).toMatchObject({ outcome: "failed", reason: "provider_disconnected" });
  });
  it("records unknown if interrupted between the two effects of close-current", async () => {
    let active = true;
    const tab = { id: 10, index: 1, windowId: 1, url: "https://example.test" } as chrome.tabs.Tab;
    const remove = vi.fn(async () => {});
    const api = { tabs: {
      query: async (query: chrome.tabs.QueryInfo) => query.active ? [tab] : [{ ...tab, id: 9, index: 0 }, tab],
      update: async () => { active = false; return tab; }, remove
    } } as unknown as ChromeApi;
    const provider = new ChromeProvider(api, async () => null);
    const deadline = Date.now() + 10_000;
    const snapshot = await provider.context({ gestureSessionId: "gesture", requiresTargetRef: false, deadline });
    await expect(provider.executeAccepted({ operationId: "operation", actionId: "browser.tab.close_current", contextId: snapshot.contextId, gestureSessionId: "gesture", deadline }, undefined, () => active)).resolves.toMatchObject({ status: "result_unknown" });
    expect(remove).not.toHaveBeenCalled();
  });
});
