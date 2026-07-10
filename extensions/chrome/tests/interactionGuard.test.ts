import { describe, expect, it } from "vitest";
import { createInteractionGuard } from "../src/content/interactionGuard";

describe("interactionGuard", () => {
  it("does not consume a DOM event without a matching armed session", () => {
    const guard = createInteractionGuard();

    expect(guard.consume({ gestureSessionId: "g-1", nowMonotonicMs: 10 })).toEqual({
      status: "guard_unavailable"
    });
  });

  it("records armed_before_dom when the guard arrives before the DOM event", () => {
    const guard = createInteractionGuard();
    guard.arm({
      gestureSessionId: "g-1",
      issuedAtMonotonicMs: 1,
      leaseMs: 800
    }, 2);

    expect(guard.observeDOMEvent({
      gestureSessionId: "g-1",
      eventType: "click",
      domEventMonotonicMs: 3
    })).toMatchObject({ status: "armed_before_dom", armedAtMonotonicMs: 2 });
  });

  it("reports late when the guard becomes active after the DOM event", () => {
    const guard = createInteractionGuard();
    guard.arm({
      gestureSessionId: "g-1",
      issuedAtMonotonicMs: 1,
      leaseMs: 800
    }, 4);

    expect(guard.observeDOMEvent({
      gestureSessionId: "g-1",
      eventType: "selectstart",
      domEventMonotonicMs: 3
    })).toMatchObject({ status: "late", armedAtMonotonicMs: 4 });
  });
});
