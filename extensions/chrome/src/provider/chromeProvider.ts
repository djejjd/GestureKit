import { executeStandardAction } from "../background/actionExecutor";
import type { ChromeApi } from "../background/chromeApi";
import type { StandardActionID } from "./protocol";

export type ContextRequest = { gestureSessionId: string; deadline: number };
export type ContextSnapshot = {
  contextId: string;
  expiresAt: number;
  targetKind: "standard_link" | "no_target" | "page_unavailable";
  targetRef?: string;
  pageIdentity: string;
};
export type ActionRequest = {
  operationId: string;
  actionId: StandardActionID;
  contextId: string;
  targetRef?: string | null;
  guardState?: "guard_armed" | "guard_unavailable" | "guard_expired" | "guard_late";
  deadline: number;
};
export type ActionResult = { status: "success" | "guard_unavailable" | "guard_expired" | "context_expired" | "target_not_found" | "page_unavailable" | "edge_reached" | "chrome_api_error" };
export type OperationStatusResponse = { operationId: string; status: "accepted" | "success" | "failed" | "result_unknown" | "not_found" };

type PointerResolution =
  | { status: "success"; url: string; frameId?: number }
  | { status: "no_target" }
  | { status: "page_unavailable" };
type StoredTarget = { contextId: string; tabId: number; frameId: number; url: string; expiresAt: number };

/**
 * Chrome Provider v2 boundary. URLs stay in this process behind session-bound
 * opaque refs; callers only receive page identity and target classification.
 */
export class ChromeProvider {
  private readonly targets = new Map<string, StoredTarget>();
  private readonly statuses = new Map<string, OperationStatusResponse>();

  constructor(
    private readonly api: ChromeApi,
    private readonly resolvePointer: (tabId: number) => Promise<PointerResolution>,
    private readonly accept?: (request: ActionRequest) => Promise<boolean>
  ) {}

  async context(request: ContextRequest): Promise<ContextSnapshot> {
    const now = Date.now();
    if (request.deadline <= now) return unavailable("page_unavailable", now);
    const tab = await activeTab(this.api);
    if (!tab?.id) return unavailable("page_unavailable", now);
    let resolved: PointerResolution;
    try { resolved = await this.resolvePointer(tab.id); } catch { return unavailable("page_unavailable", now); }
    if (resolved.status !== "success") return unavailable(resolved.status, now);
    const pageIdentity = safePageIdentity(tab.url);
    if (!pageIdentity) return unavailable("page_unavailable", now);
    const contextId = crypto.randomUUID();
    const targetRef = crypto.randomUUID();
    const expiresAt = request.deadline;
    this.targets.set(targetRef, { contextId, tabId: tab.id, frameId: resolved.frameId ?? 0, url: resolved.url, expiresAt });
    return { contextId, expiresAt, targetKind: "standard_link", targetRef, pageIdentity };
  }

  async execute(request: ActionRequest): Promise<ActionResult> {
    const now = Date.now();
    if (request.deadline <= now) return { status: "context_expired" };
    let url: string | undefined;
    if (request.actionId === "browser.link.open_adjacent") {
      if (request.guardState !== "guard_armed") return { status: request.guardState === "guard_expired" ? "guard_expired" : "guard_unavailable" };
      const target = request.targetRef ? this.targets.get(request.targetRef) : undefined;
      if (!target || target.contextId !== request.contextId || target.expiresAt < now) return { status: "context_expired" };
      const tab = await activeTab(this.api);
      if (!tab?.id || tab.id !== target.tabId) return { status: "context_expired" };
      let current: PointerResolution;
      try { current = await this.resolvePointer(tab.id); } catch { return { status: "context_expired" }; }
      if (current.status !== "success" || (current.frameId ?? 0) !== target.frameId) return { status: "context_expired" };
      url = target.url;
    }
    // All fail-closed checks complete before acceptance. No Chrome API action may precede it.
    if (this.accept && !(await this.accept(request))) return { status: "chrome_api_error" };
    this.statuses.set(request.operationId, { operationId: request.operationId, status: "accepted" });
    try {
      const result = await executeStandardAction(this.api, request.actionId, url);
      const status = result.status === "success" ? "success" : result.status;
      this.statuses.set(request.operationId, { operationId: request.operationId, status: status === "success" ? "success" : "failed" });
      return { status };
    } catch {
      this.statuses.set(request.operationId, { operationId: request.operationId, status: "failed" });
      return { status: "chrome_api_error" };
    }
  }

  async reconcile(operationId: string): Promise<OperationStatusResponse> {
    return this.statuses.get(operationId) ?? { operationId, status: "not_found" };
  }
}

async function activeTab(api: ChromeApi): Promise<chrome.tabs.Tab | undefined> {
  return (await api.tabs.query({ active: true, lastFocusedWindow: true }))[0];
}

function unavailable(targetKind: "no_target" | "page_unavailable", now: number): ContextSnapshot {
  return { contextId: crypto.randomUUID(), expiresAt: now, targetKind, pageIdentity: "" };
}

function safePageIdentity(value: string | undefined): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch { return null; }
}
