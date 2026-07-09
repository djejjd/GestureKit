import { describe, expect, it, vi } from "vitest";
import { createReconnectableNativePort, type PortLike } from "../src/background/reconnectableNativePort";

function createPort() {
  const disconnectListeners: Array<() => void> = [];
  const port: PortLike & { triggerDisconnect(): void } = {
    postMessage: vi.fn(),
    onMessage: {
      addListener: vi.fn()
    },
    onDisconnect: {
      addListener: vi.fn((listener: () => void) => {
        disconnectListeners.push(listener);
      })
    },
    triggerDisconnect() {
      for (const listener of disconnectListeners) {
        listener();
      }
    }
  };
  return port;
}

describe("reconnectableNativePort", () => {
  it("reuses the same port while still connected", () => {
    const port = createPort();
    const connect = vi.fn(() => port);
    const attach = vi.fn();

    const reconnectable = createReconnectableNativePort({ connect, attach });

    expect(reconnectable.currentPort()).toBe(port);
    expect(reconnectable.ensureConnected()).toBe(port);
    expect(connect).toHaveBeenCalledTimes(1);
    expect(attach).toHaveBeenCalledTimes(1);
  });

  it("reconnects after the current port disconnects", () => {
    const firstPort = createPort();
    const secondPort = createPort();
    const connect = vi.fn()
      .mockReturnValueOnce(firstPort)
      .mockReturnValueOnce(secondPort);
    const attach = vi.fn();
    const onDisconnect = vi.fn();

    const reconnectable = createReconnectableNativePort({ connect, attach, onDisconnect });
    firstPort.triggerDisconnect();

    expect(reconnectable.isDisconnected()).toBe(true);
    expect(onDisconnect).toHaveBeenCalledWith(firstPort);

    const reconnected = reconnectable.ensureConnected();
    expect(reconnected).toBe(secondPort);
    expect(reconnectable.currentPort()).toBe(secondPort);
    expect(reconnectable.isDisconnected()).toBe(false);
    expect(connect).toHaveBeenCalledTimes(2);
    expect(attach).toHaveBeenCalledTimes(2);
  });
});
