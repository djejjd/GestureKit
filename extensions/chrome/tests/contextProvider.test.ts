import { describe, expect, it } from "vitest";
import { ContextProvider } from "../src/provider/contextProvider";

describe("ContextProvider", () => {
  it("strips query/hash and keeps the original URL behind an expiring opaque targetRef", () => {
    const provider = new ContextProvider();
    const snapshot = provider.snapshot("https://example.com/a?token=secret#frag", 100, 50);
    expect(snapshot.pageIdentity).toBe("https://example.com/a");
    expect(snapshot.targetRef).not.toBeNull();
    expect(provider.resolveTarget(snapshot.targetRef!, 149)).toContain("token=secret");
    expect(provider.resolveTarget(snapshot.targetRef!, 151)).toBeNull();
  });
});
