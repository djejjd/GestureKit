import { describe, expect, it, vi } from "vitest";
import { createControlCenterRequestForwarder } from "../src/background/controlCenterRequest";

describe("control center open request", () => {
  it("forwards through the authenticated Provider v2 session and resolves the App response", async () => {
    let inbound: ((message: unknown) => void) | undefined;
    const port = {
      postMessage: vi.fn(),
      onMessage: { addListener: vi.fn((listener) => { inbound = listener; }) }
    };
    const forward = createControlCenterRequestForwarder(() => port, () => "authenticated-session");

    const result = forward.open();
    expect(port.postMessage).toHaveBeenCalledWith(expect.objectContaining({
      protocolVersion: 2,
      providerSessionId: "authenticated-session",
      type: "control_center_open_request"
    }));
    const request = port.postMessage.mock.calls[0][0];
    inbound?.({ ...request, type: "control_center_open_response", payload: { opened: true }, error: null });

    await expect(result).resolves.toEqual({ status: "opened" });
  });

  it("fails visibly rather than sending without an authenticated Provider session", async () => {
    const port = { postMessage: vi.fn(), onMessage: { addListener: vi.fn() } };
    const forward = createControlCenterRequestForwarder(() => port, () => null);

    await expect(forward.open()).resolves.toEqual({ status: "unavailable" });
    expect(port.postMessage).not.toHaveBeenCalled();
  });
});
