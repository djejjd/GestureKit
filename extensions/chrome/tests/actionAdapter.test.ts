import { describe, expect, it } from "vitest";
import { ChromeActionAdapter } from "../src/provider/actionAdapter";
import { ContextProvider } from "../src/provider/contextProvider";

describe("ChromeActionAdapter", () => {
  it("rejects an expired targetRef without opening a page", async () => {
    const contexts = new ContextProvider();
    const snapshot = contexts.snapshot("https://example.com/a", 100, 10);
    let opened = false;
    const adapter = new ChromeActionAdapter(contexts, async () => { opened = true; });
    const result = await adapter.execute({ actionId: "browser.link.open_adjacent", contextId: snapshot.contextId, targetRef: snapshot.targetRef, parameters: {}, deadline: 200 }, 111);
    expect(result).toMatchObject({ outcome: "failed", reason: "context_expired" });
    expect(opened).toBe(false);
  });

  it("rejects a targetRef paired with a different contextId", async () => {
    const contexts = new ContextProvider();
    const snapshot = contexts.snapshot("https://example.com/a", 100, 50);
    const adapter = new ChromeActionAdapter(contexts, async () => { throw new Error("must not open"); });
    const result = await adapter.execute({ actionId: "browser.link.open_adjacent", contextId: "other-context", targetRef: snapshot.targetRef, parameters: {}, deadline: 200 }, 110);
    expect(result).toMatchObject({ outcome: "failed", reason: "context_expired" });
  });
});
