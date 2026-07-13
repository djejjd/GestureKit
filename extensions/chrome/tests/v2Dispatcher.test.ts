import { describe, expect, it } from "vitest";
import { ContextProvider } from "../src/provider/contextProvider";
import { ChromeActionAdapter } from "../src/provider/actionAdapter";
import { V2Dispatcher } from "../src/provider/v2Dispatcher";
import type { ProviderEnvelope } from "../src/provider/protocol";
import { createOperationLedgerStore } from "../src/provider/operationLedger";

describe("V2Dispatcher", () => {
  it("responds to context_request then executes the matching action_request", async () => {
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    const adapter = new ChromeActionAdapter(contexts, async () => {});
    const store = await createOperationLedgerStore(`dispatcher-${crypto.randomUUID()}`);
    const dispatcher = new V2Dispatcher(
      contexts,
      adapter,
      async () => "https://example.com/a?secret=raw",
      (message) => sent.push(message),
      store,
      "producer-session"
    );
    const deadline = Date.now() + 2_000;
    await dispatcher.handle({
      protocolVersion: 2, messageId: "m1", providerSessionId: "s1", gestureSessionId: "g1", operationId: null,
      type: "context_request", timestamp: Date.now(), payload: { gestureSessionId: "g1", deadline }, error: null
    });
    expect(sent[0]?.type).toBe("context_snapshot");
    const snapshot = sent[0]?.payload as { contextId: string; targetRef: string };
    await dispatcher.handle({
      protocolVersion: 2, messageId: "m2", providerSessionId: "s1", gestureSessionId: "g1", operationId: "op1",
      type: "action_request", timestamp: Date.now(), payload: { actionId: "browser.link.open_adjacent", contextId: snapshot.contextId, targetRef: snapshot.targetRef, parameters: {}, deadline }, error: null
    });
    expect(sent[1]?.type).toBe("action_result");
    expect((sent[1]?.payload as { outcome: string }).outcome).toBe("succeeded");
  });

  it("does not execute Chrome actions when accepted evidence cannot be persisted", async () => {
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    let executions = 0;
    const adapter = new ChromeActionAdapter(contexts, async () => { executions += 1; });
    const store = await createOperationLedgerStore(`dispatcher-full-${crypto.randomUUID()}`, { maxOutboxBytes: 0, criticalReserveBytes: 0 });
    const dispatcher = new V2Dispatcher(contexts, adapter, async () => "https://example.com/a", (message) => sent.push(message), store, "producer-session");
    const snapshot = contexts.snapshot("https://example.com/a", Date.now(), 2_000);

    await dispatcher.handle(actionRequest(snapshot.contextId, snapshot.targetRef!, "op-storage-full"));

    expect(executions).toBe(0);
    expect(sent).toHaveLength(1);
    expect(sent[0]?.payload).toMatchObject({ operationId: "op-storage-full", outcome: "failed", reason: "storage_full" });
    await expect(store.status("op-storage-full")).resolves.toBeNull();
  });

  it("fails closed when accepted event sequence allocation throws", async () => {
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    let executions = 0;
    const store = await createOperationLedgerStore(`dispatcher-sequence-${crypto.randomUUID()}`);
    store.nextProducerSequence = async () => { throw new Error("sequence unavailable"); };
    const adapter = new ChromeActionAdapter(contexts, async () => { executions += 1; });
    const dispatcher = new V2Dispatcher(contexts, adapter, async () => "https://example.com/a", (message) => sent.push(message), store, "producer-session");
    const snapshot = contexts.snapshot("https://example.com/a", Date.now(), 2_000);

    await expect(dispatcher.handle(actionRequest(snapshot.contextId, snapshot.targetRef!, "op-sequence-failure"))).resolves.toBeUndefined();

    expect(executions).toBe(0);
    expect(sent[0]?.payload).toMatchObject({ operationId: "op-sequence-failure", outcome: "failed", reason: "storage_full" });
  });

  it("persists and sends chrome_api_error when the Chrome adapter throws", async () => {
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    const store = await createOperationLedgerStore(`dispatcher-adapter-error-${crypto.randomUUID()}`);
    const adapter = new ChromeActionAdapter(contexts, async () => { throw new Error("Chrome tabs failed"); });
    const dispatcher = new V2Dispatcher(contexts, adapter, async () => "https://example.com/a", (message) => sent.push(message), store, "producer-session");
    const snapshot = contexts.snapshot("https://example.com/a", Date.now(), 2_000);

    await expect(dispatcher.handle(actionRequest(snapshot.contextId, snapshot.targetRef!, "op-adapter-error"))).resolves.toBeUndefined();

    expect(sent[0]?.payload).toMatchObject({ operationId: "op-adapter-error", outcome: "failed", reason: "chrome_api_error" });
    await expect(store.status("op-adapter-error")).resolves.toMatchObject({ state: "failed" });
  });

  it("returns result_unknown when terminal evidence cannot be persisted", async () => {
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    let executions = 0;
    const store = await createOperationLedgerStore(`dispatcher-finalize-${crypto.randomUUID()}`);
    store.finalize = async () => { throw new Error("finalize unavailable"); };
    const adapter = new ChromeActionAdapter(contexts, async () => { executions += 1; });
    const dispatcher = new V2Dispatcher(contexts, adapter, async () => "https://example.com/a", (message) => sent.push(message), store, "producer-session");
    const snapshot = contexts.snapshot("https://example.com/a", Date.now(), 2_000);

    await expect(dispatcher.handle(actionRequest(snapshot.contextId, snapshot.targetRef!, "op-finalize-failure"))).resolves.toBeUndefined();

    expect(executions).toBe(1);
    expect(sent[0]?.payload).toMatchObject({ operationId: "op-finalize-failure", outcome: "result_unknown", reason: "recovery_timeout" });
    await expect(store.status("op-finalize-failure")).resolves.toMatchObject({ state: "accepted" });
  });

  it("does not execute a duplicate action request after it was accepted", async () => {
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    let executions = 0;
    const store = await createOperationLedgerStore(`dispatcher-duplicate-${crypto.randomUUID()}`);
    let acceptedBeforeExecution = false;
    const adapter = new ChromeActionAdapter(contexts, async () => {
      acceptedBeforeExecution = (await store.status("op-duplicate"))?.state === "accepted";
      executions += 1;
    });
    const dispatcher = new V2Dispatcher(contexts, adapter, async () => "https://example.com/a", (message) => sent.push(message), store, "producer-session");
    const snapshot = contexts.snapshot("https://example.com/a", Date.now(), 2_000);
    const request = actionRequest(snapshot.contextId, snapshot.targetRef!, "op-duplicate");

    await dispatcher.handle(request);
    await dispatcher.handle(request);

    expect(executions).toBe(1);
    expect(acceptedBeforeExecution).toBe(true);
    await expect(store.status("op-duplicate")).resolves.toMatchObject({ state: "success" });
  });

  it("executes only the invocation that created an in-flight acceptance record", async () => {
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    const store = await createOperationLedgerStore(`dispatcher-race-${crypto.randomUUID()}`);
    let executions = 0;
    let releaseAction!: () => void;
    const actionBlocked = new Promise<void>((resolve) => { releaseAction = resolve; });
    let firstStarted!: () => void;
    const firstActionStarted = new Promise<void>((resolve) => { firstStarted = resolve; });
    const adapter = new ChromeActionAdapter(contexts, async () => {
      executions += 1;
      firstStarted();
      await actionBlocked;
    });
    const dispatcher = new V2Dispatcher(contexts, adapter, async () => "https://example.com/a", (message) => sent.push(message), store, "producer-session");
    const snapshot = contexts.snapshot("https://example.com/a", Date.now(), 2_000);
    const request = actionRequest(snapshot.contextId, snapshot.targetRef!, "op-race");

    const first = dispatcher.handle(request);
    await firstActionStarted;
    const duplicate = dispatcher.handle({ ...request, messageId: crypto.randomUUID() });
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(executions).toBe(1);
    releaseAction();
    await Promise.all([first, duplicate]);
  });

  it("returns the persisted failed terminal result to a duplicate request", async () => {
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    const store = await createOperationLedgerStore(`dispatcher-terminal-duplicate-${crypto.randomUUID()}`);
    const adapter = new ChromeActionAdapter(contexts, async () => { throw new Error("Chrome tabs failed"); });
    const dispatcher = new V2Dispatcher(contexts, adapter, async () => "https://example.com/a", (message) => sent.push(message), store, "producer-session");
    const snapshot = contexts.snapshot("https://example.com/a", Date.now(), 2_000);
    const request = actionRequest(snapshot.contextId, snapshot.targetRef!, "op-terminal-duplicate");

    await dispatcher.handle(request);
    await dispatcher.handle({ ...request, messageId: crypto.randomUUID() });

    expect(sent[1]?.payload).toMatchObject({ operationId: "op-terminal-duplicate", outcome: "failed", reason: "chrome_api_error" });
  });
});

function actionRequest(contextId: string, targetRef: string, operationId: string): ProviderEnvelope {
  return {
    protocolVersion: 2,
    messageId: crypto.randomUUID(),
    providerSessionId: "provider-session",
    gestureSessionId: "gesture-session",
    operationId,
    type: "action_request",
    timestamp: Date.now(),
    payload: { actionId: "browser.link.open_adjacent", contextId, targetRef, parameters: {}, deadline: Date.now() + 2_000 },
    error: null
  };
}
