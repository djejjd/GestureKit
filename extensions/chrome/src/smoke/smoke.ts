type ConnectionProbeResult = {
  hostConnected: boolean;
  appConnected: boolean;
  status: string;
  message: string;
};

const statusElement = document.querySelector("#status") as HTMLParagraphElement | null;
const detailsElement = document.querySelector("#details") as HTMLPreElement | null;

if (!statusElement || !detailsElement) {
  throw new Error("Smoke page elements not found");
}

function render(result: ConnectionProbeResult) {
  statusElement.textContent = result.status === "connected" ? "通过" : "失败";
  detailsElement.textContent = JSON.stringify(result, null, 2);
}

chrome.runtime.sendMessage({ type: "gesturekit.runConnectionProbe" }, (result?: ConnectionProbeResult) => {
  if (chrome.runtime.lastError) {
    render({
      hostConnected: false,
      appConnected: false,
      status: "error",
      message: chrome.runtime.lastError.message
    });
    return;
  }

  render(result ?? {
    hostConnected: false,
    appConnected: false,
    status: "error",
    message: "missing_probe_result"
  });
});
