import { describe, expect, it, vi } from "vitest";
import { createInteractionGuardRouter } from "../src/background/interactionGuardRouter";
const arm = (id = "session") => ({ type: "interaction_guard_arm", payload: { gestureSessionId: id, features: ["drag_selection"], deadline: Date.now() + 750 } });
const release = (id = "session") => ({ type: "interaction_guard_release", payload: { gestureSessionId: id, disposition: "discard" } });
describe("interaction guard source routing", () => {
  it("releases original document after tab switch without querying active tab again", async () => {
    const query = vi.fn().mockResolvedValue([{ id: 1 }]);
    const send = vi.fn().mockResolvedValue({ status: "guard_armed", documentToken: "page-1" });
    const route = createInteractionGuardRouter({ query, send, trace: vi.fn() });
    await route(arm());
    query.mockResolvedValue([{ id: 2 }]);
    await route(release());
    expect(query).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[1][0]).toBe(1);
    expect(send.mock.calls[1][1]).toMatchObject({ type: "gesturekit.linkGuardDiscard", documentToken: "page-1" });
  });
  it("does not arm a candidate already released while query was pending", async () => {
    let resolve!: (tabs: { id: number }[]) => void;
    const query = vi.fn().mockImplementation(() => new Promise(r => { resolve = r; }));
    const send = vi.fn().mockResolvedValue({ status: "guard_armed", documentToken: "page-1" });
    const route = createInteractionGuardRouter({ query, send, trace: vi.fn() });
    const arming = route(arm());
    const releasing = route(release());
    resolve([{ id: 1 }]);
    await Promise.all([arming, releasing]);
    expect(send).not.toHaveBeenCalled();
  });
  it("does not resurrect a session when release arrived before arm", async () => {
    const send = vi.fn();
    const route = createInteractionGuardRouter({ query: vi.fn().mockResolvedValue([{ id: 1 }]), send, trace: vi.fn() });
    await route(release());
    await route(arm());
    expect(send).not.toHaveBeenCalled();
  });
  it("skips expired arm", async () => {
    const send = vi.fn();
    const route = createInteractionGuardRouter({ query: vi.fn().mockResolvedValue([{ id: 1 }]), send, trace: vi.fn() });
    const message = arm(); message.payload.deadline = Date.now() - 1;
    await route(message);
    expect(send).not.toHaveBeenCalled();
  });  it("does not let an older query overwrite a newer candidate", async () => {
    const queries: ((tabs: {id: number}[]) => void)[] = [];
    const query = vi.fn().mockImplementation(() => new Promise(resolve => { queries.push(resolve); }));
    let active: string | null = null;
    const send = vi.fn(async (_tab: number, message: Record<string, unknown>) => {
      if (message.type === "gesturekit.linkGuardArm") active = message.gestureSessionId as string;
      if (message.type === "gesturekit.linkGuardDiscard" && active === message.gestureSessionId) active = null;
      return { status: "guard_armed", documentToken: "page" };
    });
    const route = createInteractionGuardRouter({ query, send, trace: vi.fn() });
    const oldArm = route(arm("old"));
    const oldRelease = route(release("old"));
    const newArm = route(arm("new"));
    queries[1]([{ id: 1 }]); await newArm;
    queries[0]([{ id: 1 }]); await Promise.all([oldArm, oldRelease]);
    expect(active).toBe("new");
    expect(send.mock.calls.map(call => call[1].gestureSessionId)).toEqual(["new"]);
  });

});
