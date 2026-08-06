import { describe, expect, it, vi } from "vitest";
import { createE2EControl, type E2EPageCommand } from "../src/background/e2eControl";

function fixtureCommand(overrides: Partial<E2EPageCommand> = {}): E2EPageCommand {
  return {
    token: "e2e-test-token-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    gestureSessionId: "g-test-1",
    operationId: "op-test-1",
    scenario: "success",
    ...overrides
  };
}

describe("createE2EControl", () => {
  it("rejects a production build and does not dispatch", async () => {
    const dispatch = vi.fn();
    const control = createE2EControl({ token: null, allowedOrigin: null, dispatch });
    await expect(control.handle("http://127.0.0.1:4567", fixtureCommand())).resolves.toEqual({ status: "e2e_unavailable" });
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("rejects an origin mismatch before forwarding the command", async () => {
    const dispatch = vi.fn();
    const control = createE2EControl({ token: "token", allowedOrigin: "http://127.0.0.1:4567", dispatch });
    await expect(control.handle("https://example.test", fixtureCommand())).resolves.toEqual({ status: "e2e_origin_rejected" });
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("rejects a token mismatch", async () => {
    const dispatch = vi.fn();
    const control = createE2EControl({ token: "correct-token", allowedOrigin: "http://127.0.0.1:4567", dispatch });
    await expect(control.handle("http://127.0.0.1:4567", fixtureCommand({ token: "wrong-token" }))).resolves.toEqual({ status: "e2e_token_rejected" });
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("dispatches when origin and token both match", async () => {
    const dispatch = vi.fn().mockResolvedValue({ status: "e2e_dispatched" });
    const token = "shared-secret";
    const control = createE2EControl({ token, allowedOrigin: "http://127.0.0.1:4567", dispatch });
    const cmd = fixtureCommand({ token });
    await expect(control.handle("http://127.0.0.1:4567", cmd)).resolves.toEqual({ status: "e2e_dispatched" });
    expect(dispatch).toHaveBeenCalledWith(cmd);
  });

  it("rejects when allowedOrigin is null even with a valid token", async () => {
    const dispatch = vi.fn();
    const control = createE2EControl({ token: "valid-token", allowedOrigin: null, dispatch });
    await expect(control.handle("http://127.0.0.1:4567", fixtureCommand({ token: "valid-token" }))).resolves.toEqual({ status: "e2e_unavailable" });
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("rejects when token is null even with a valid allowedOrigin", async () => {
    const dispatch = vi.fn();
    const control = createE2EControl({ token: null, allowedOrigin: "http://127.0.0.1:4567", dispatch });
    await expect(control.handle("http://127.0.0.1:4567", fixtureCommand())).resolves.toEqual({ status: "e2e_unavailable" });
    expect(dispatch).not.toHaveBeenCalled();
  });
});
