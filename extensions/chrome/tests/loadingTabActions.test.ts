import { afterEach, describe, expect, it, vi } from "vitest";
import type { ChromeApi } from "../src/background/chromeApi";
import { ChromeProvider } from "../src/provider/chromeProvider";
import { ContextProvider } from "../src/provider/contextProvider";
import { ChromeActionAdapter } from "../src/provider/actionAdapter";
import { V2Dispatcher } from "../src/provider/v2Dispatcher";
import { createOperationLedgerStore } from "../src/provider/operationLedger";
import type { ProviderEnvelope, StandardActionID } from "../src/provider/protocol";

// Chrome is the external boundary: keep the real Provider, action executor,
// dispatcher and ledger, and simulate only Chrome's tab state / side effects.
function loadingBrowser(url?: string, pendingUrl?: string) {
  const active: chrome.tabs.Tab = {
    id: 10, index: 1, windowId: 4, active: true, highlighted: true,
    pinned: false, incognito: false, selected: true, discarded: false,
    autoDiscardable: true, groupId: -1, status: "loading", url, pendingUrl
  };
  const state = { active: active as chrome.tabs.Tab | undefined };
  const api: ChromeApi = {
    tabs: {
      query: vi.fn(async (query) => query.active
        ? state.active ? [state.active] : []
        : [{ ...active, id: 9, index: 0 }, active, { ...active, id: 11, index: 2 }]),
      create: vi.fn(async () => ({ ...active, id: 12 })),
      update: vi.fn(async (id) => ({ ...active, id })),
      remove: vi.fn(async () => {}),
      goBack: vi.fn(async () => {}),
      goForward: vi.fn(async () => {}),
      reload: vi.fn(async () => {}),
      sendMessage: vi.fn(async () => { throw new Error("content script not ready"); })
    },
    sessions: { restore: vi.fn(async () => ({ lastModified: 0 })) }
  };
  const content = vi.fn(async () => { throw new Error("content script not ready"); });
  return { api, state, content, provider: new ChromeProvider(api, content) };
}

const loadingStates = [
  { name: "pending URL only", url: "", pendingUrl: "https://example.test/pending?token=secret" },
  { name: "no URL", url: undefined, pendingUrl: undefined }
];

const browserActions: { actionId: StandardActionID; effect: keyof ChromeApi["tabs"] | "restore"; args: unknown[] }[] = [
  { actionId: "browser.tab.activate_previous", effect: "update", args: [9, { active: true }] },
  { actionId: "browser.tab.activate_next", effect: "update", args: [11, { active: true }] },
  { actionId: "browser.tab.close_current", effect: "remove", args: [10] },
  { actionId: "browser.tab.open_new", effect: "create", args: [{ active: true, windowId: 4 }] },
  { actionId: "browser.tab.pin", effect: "update", args: [10, { pinned: true }] },
  { actionId: "browser.tab.unpin", effect: "update", args: [10, { pinned: false }] },
  { actionId: "browser.tab.toggle_mute", effect: "update", args: [10, { muted: true }] },
  { actionId: "browser.tab.close_others", effect: "remove", args: [[9, 11]] },
  { actionId: "browser.tab.restore", effect: "restore", args: [] },
  { actionId: "browser.page.reload", effect: "reload", args: [10] },
  { actionId: "browser.history.back", effect: "goBack", args: [10] },
  { actionId: "browser.history.forward", effect: "goForward", args: [10] }
];

afterEach(() => vi.useRealTimers());

describe.each(loadingStates)("loading tab: $name", ({ url, pendingUrl }) => {
  describe.each([false, true])("requiresTargetRef=%s", (requiresTargetRef) => {
    it.each(browserActions)("executes $actionId without a committed URL or content script", async ({ actionId, effect, args }) => {
      const { api, provider, content } = loadingBrowser(url, pendingUrl);
      const deadline = Date.now() + 10_000;
      const snapshot = await provider.context({ gestureSessionId: "loading", requiresTargetRef, deadline });

      await expect(provider.execute({
        operationId: "loading-op", actionId, contextId: snapshot.contextId,
        gestureSessionId: "loading", deadline
      })).resolves.toEqual({ status: "success" });

      expect(effect === "restore" ? api.sessions.restore : api.tabs[effect]).toHaveBeenCalledWith(...args);
      expect(content).not.toHaveBeenCalled();
      expect(api.tabs.sendMessage).not.toHaveBeenCalled();
      expect(snapshot.pageIdentity).toBe("");
      expect(snapshot.targetRef).toBeUndefined();
      expect(snapshot.expiresAt).toBe(deadline);
    });

    it.each(["browser.link.open_adjacent", "browser.link.copy"] as const)("does not invent a link target for %s", async (actionId) => {
      const { api, provider } = loadingBrowser(url, pendingUrl);
      const deadline = Date.now() + 10_000;
      const snapshot = await provider.context({ gestureSessionId: "loading", requiresTargetRef, deadline });

      await expect(provider.execute({
        operationId: "link-op", actionId, contextId: snapshot.contextId,
        gestureSessionId: "loading", deadline
      })).resolves.toEqual({ status: "context_expired" });
      expect(api.tabs.create).not.toHaveBeenCalled();
      expect(api.tabs.sendMessage).not.toHaveBeenCalled();
    });

    it.each(["browser.page.copy_url", "browser.page.scroll_top_bottom"] as const)("still requires page readiness for %s", async (actionId) => {
      const { api, provider } = loadingBrowser(url, pendingUrl);
      const deadline = Date.now() + 10_000;
      const snapshot = await provider.context({ gestureSessionId: "loading", requiresTargetRef, deadline });

      await expect(provider.execute({
        operationId: "page-op", actionId, contextId: snapshot.contextId,
        gestureSessionId: "loading", deadline
      })).resolves.toEqual({ status: "page_unavailable" });
      expect(api.tabs.update).not.toHaveBeenCalled();
      expect(api.tabs.create).not.toHaveBeenCalled();
    });
  });
});

describe("loading context identity and expiry", () => {
  it.each(["expired request", "expired context", "wrong session", "different tab", "closed tab"])("rejects %s and permits the next independent operation", async (failure) => {
    vi.useFakeTimers();
    const { api, state, provider } = loadingBrowser();
    const original = state.active!;
    const deadline = Date.now() + 1_000;
    const snapshot = await provider.context({ gestureSessionId: "old", requiresTargetRef: false, deadline });
    if (failure === "expired context") vi.advanceTimersByTime(1_001);
    if (failure === "different tab") state.active = { ...original, id: 11 };
    if (failure === "closed tab") state.active = undefined;

    await expect(provider.execute({
      operationId: "old-op", actionId: "browser.page.reload", contextId: snapshot.contextId,
      gestureSessionId: failure === "wrong session" ? "other" : "old",
      deadline: failure === "expired request" ? Date.now() - 1 : Date.now() + 10_000
    })).resolves.toEqual({ status: "context_expired" });
    expect(api.tabs.reload).not.toHaveBeenCalled();

    state.active = { ...original, url: "https://example.test/ready", status: "complete" };
    const freshDeadline = Date.now() + 1_000;
    const fresh = await provider.context({ gestureSessionId: "new", requiresTargetRef: false, deadline: freshDeadline });
    await expect(provider.execute({
      operationId: "new-op", actionId: "browser.page.reload", contextId: fresh.contextId,
      gestureSessionId: "new", deadline: freshDeadline
    })).resolves.toEqual({ status: "success" });
    expect(api.tabs.reload).toHaveBeenCalledTimes(1);
    expect(api.tabs.reload).toHaveBeenCalledWith(10);
  });

  it("keeps a tab context usable when its first navigation commits", async () => {
    const { provider, state, api } = loadingBrowser();
    const deadline = Date.now() + 1_000;
    const snapshot = await provider.context({ gestureSessionId: "loading", requiresTargetRef: false, deadline });
    state.active = { ...state.active!, url: "https://example.test/ready", status: "complete" };

    await expect(provider.execute({
      operationId: "commit-op", actionId: "browser.tab.activate_next", contextId: snapshot.contextId,
      gestureSessionId: "loading", deadline
    })).resolves.toEqual({ status: "success" });
    expect(api.tabs.update).toHaveBeenCalledWith(11, { active: true });
  });
});

describe.each(loadingStates)("loading Provider protocol: $name", ({ url, pendingUrl }) => {
  it.each([false, true])("persists acceptance and a terminal result without replay (requiresTargetRef=%s)", async (requiresTargetRef) => {
    const { api, provider } = loadingBrowser(url, pendingUrl);
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    const ledger = await createOperationLedgerStore(`loading-${crypto.randomUUID()}`);
    const dispatcher = new V2Dispatcher(contexts, new ChromeActionAdapter(contexts, async () => {}),
      async () => null, message => sent.push(message), ledger, "loading-producer", provider);
    const deadline = Date.now() + 10_000;
    const envelope: ProviderEnvelope = {
      protocolVersion: 2, messageId: "loading-context", providerSessionId: "provider",
      gestureSessionId: "loading", operationId: null, type: "context_request", timestamp: Date.now(),
      payload: { gestureSessionId: "loading", requiresTargetRef, deadline }, error: null
    };
    await dispatcher.handle(envelope);
    const snapshot = sent[0].payload as { contextId: string };
    let acceptedBeforeEffect = false;
    api.tabs.reload = vi.fn(async () => {
      acceptedBeforeEffect = (await ledger.status("loading-op"))?.state === "accepted";
    });
    const action: ProviderEnvelope = {
      ...envelope, messageId: "loading-action", type: "action_request", operationId: "loading-op",
      payload: { actionId: "browser.page.reload", contextId: snapshot.contextId, deadline, parameters: {} }
    };
    await dispatcher.handle(action);
    await dispatcher.handle({ ...action, messageId: "duplicate" });

    expect(acceptedBeforeEffect).toBe(true);
    expect(api.tabs.reload).toHaveBeenCalledTimes(1);
    expect(api.tabs.reload).toHaveBeenCalledWith(10);
    await expect(ledger.status("loading-op")).resolves.toMatchObject({ state: "success" });
    const events = await ledger.events("loading-op");
    expect(events.map(event => event.type)).toEqual(["action_accepted", "action_result"]);
    expect(events.every(event => event.gestureSessionId === "loading" && event.operationId === "loading-op")).toBe(true);
    expect(sent.slice(1).map(message => message.payload)).toEqual([
      expect.objectContaining({ operationId: "loading-op", outcome: "succeeded", reason: "completed" }),
      expect.objectContaining({ operationId: "loading-op", outcome: "succeeded", reason: "completed" })
    ]);
    expect(JSON.stringify([sent, events])).not.toContain("token=secret");
  });
});
