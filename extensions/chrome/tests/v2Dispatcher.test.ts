import { describe, expect, it } from "vitest";
import { ContextProvider } from "../src/provider/contextProvider";
import { ChromeActionAdapter } from "../src/provider/actionAdapter";
import { V2Dispatcher } from "../src/provider/v2Dispatcher";
import type { ProviderEnvelope } from "../src/provider/protocol";

describe("V2Dispatcher", () => {
  it("responds to context_request then executes the matching action_request", async () => {
    const contexts = new ContextProvider();
    const sent: ProviderEnvelope[] = [];
    const adapter = new ChromeActionAdapter(contexts, async () => {});
    const dispatcher = new V2Dispatcher(
      contexts,
      adapter,
      async () => "https://example.com/a?secret=raw",
      (message) => sent.push(message)
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
});
