type DisconnectListener = (port: PortLike) => void;

export type PortLike = {
  postMessage(message: unknown): void;
  onMessage: {
    addListener(listener: (message: unknown) => void): void;
  };
  onDisconnect: {
    addListener(listener: () => void): void;
  };
};

type Dependencies = {
  connect(): PortLike;
  attach(port: PortLike): void;
  onDisconnect?(port: PortLike): void;
};

export function createReconnectableNativePort(deps: Dependencies) {
  let currentPort = connectAndAttach();
  let disconnected = false;

  function connectAndAttach() {
    const port = deps.connect();
    port.onDisconnect.addListener(() => {
      if (port !== currentPort) {
        return;
      }
      disconnected = true;
      deps.onDisconnect?.(port);
    });
    deps.attach(port);
    return port;
  }

  return {
    currentPort() {
      return currentPort;
    },
    isDisconnected() {
      return disconnected;
    },
    ensureConnected() {
      if (!disconnected) {
        return currentPort;
      }
      disconnected = false;
      currentPort = connectAndAttach();
      return currentPort;
    }
  };
}
