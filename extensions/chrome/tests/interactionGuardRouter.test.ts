import { describe, expect, it, vi } from "vitest";
import { createInteractionGuardRouter } from "../src/background/interactionGuardRouter";

it("does not arm after a pending tab query is disposed", async () => {
  let finish!: (tabs: { id: number }[]) => void;
  const query = () => new Promise<{ id: number }[]>(resolve => { finish = resolve; });
  const send = vi.fn(async () => ({ status: "guard_armed" }));
  const route = createInteractionGuardRouter({ query, send, trace: () => {} });
  const pending = route({ type: "interaction_guard_arm", payload: { gestureSessionId: "old", features: ["drag_selection"], deadline: Date.now() + 800 } });
  route.dispose(); finish([{ id: 10 }]); await pending;
  expect(send).not.toHaveBeenCalled();
});

it("discards an armed guard exactly once on dispose", async () => {
  const send = vi.fn(async () => ({ status: "guard_armed", documentToken: "page" }));
  const route = createInteractionGuardRouter({ query: async () => [{ id: 10 }], send, trace: () => {} });
  await route({ type: "interaction_guard_arm", payload: { gestureSessionId: "old", features: ["drag_selection"], deadline: Date.now() + 800 } });
  await route.dispose(); await route.dispose();
  expect(send.mock.calls).toHaveLength(2);
  expect(send).toHaveBeenLastCalledWith(10, { type: "gesturekit.linkGuardDiscard", gestureSessionId: "old", documentToken: "page" });
});

it("discards a late arm acknowledgement on its original page after dispose", async () => {
  let acknowledge!: (response: { status: string; documentToken: string }) => void;
  const send = vi.fn().mockImplementationOnce(() => new Promise(resolve => { acknowledge = resolve; }))
    .mockResolvedValue({ status: "guard_discarded" });
  const route = createInteractionGuardRouter({ query: async () => [{ id: 10 }], send, trace: () => {} });
  const arming = route({ type: "interaction_guard_arm", payload: { gestureSessionId: "old", features: ["drag_selection"], deadline: Date.now() + 800 } });
  await Promise.resolve();
  const cleanup = route.dispose();
  acknowledge({ status: "guard_armed", documentToken: "original-page" });
  await Promise.all([arming, cleanup]);
  expect(send).toHaveBeenLastCalledWith(10, { type: "gesturekit.linkGuardDiscard", gestureSessionId: "old", documentToken: "original-page" });
});
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
  it("preserves the bounded link arbitration budget without extending drag-only leases", async () => {
    const now = vi.spyOn(Date, "now").mockReturnValue(1000);
    const send = vi.fn().mockResolvedValue({ status: "guard_armed", documentToken: "page" });
    const route = createInteractionGuardRouter({ query: vi.fn().mockResolvedValue([{ id: 1 }]), send, trace: vi.fn() });
    await route({ type: "interaction_guard_arm", payload: { gestureSessionId: "link", features: ["link_click"], deadline: 2200 } });
    expect(send.mock.calls[0][1].leaseMs).toBe(1200);
    await route({ type: "interaction_guard_arm", payload: { gestureSessionId: "drag", features: ["drag_selection"], deadline: 2200 } });
    expect(send.mock.calls[1][1].leaseMs).toBe(800);
    now.mockRestore();
  });

});
