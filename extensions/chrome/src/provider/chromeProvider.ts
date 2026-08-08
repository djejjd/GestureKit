import { executeStandardAction } from "../background/actionExecutor";
import type { ChromeApi } from "../background/chromeApi";
import type { StandardActionID } from "./protocol";

export type ContextRequest = { gestureSessionId: string; requiresTargetRef: boolean; deadline: number };
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
  gestureSessionId: string;
  deadline: number;
  parameters?: Record<string, string>;
};
export type ActionResult = { status: "success" | "guard_unavailable" | "guard_expired" | "context_expired" | "target_not_found" | "page_unavailable" | "edge_reached" | "chrome_api_error" };
export type OperationStatusResponse = { operationId: string; status: "accepted" | "success" | "failed" | "result_unknown" | "not_found" };

type PointerResolution =
  | { status: "success"; url: string; frameId?: number }
  | { status: "no_target" }
  | { status: "page_unavailable" };
type StoredTarget = { contextId: string; gestureSessionId: string; tabId: number; frameId: number; url: string; expiresAt: number };
type StoredContext = { gestureSessionId: string; tabId: number; expiresAt: number; allowedActionIds?: readonly StandardActionID[] };
type ContentBridge = (tabId: number, message: Record<string, unknown>) => Promise<unknown>;

/**
 * 无需链接目标的动作集合（swipe 上下文允许的动作）。
 * 保持 V2.4 的既有限制：close_current / history / reload / link.open_adjacent
 * 仍仅在带目标的（tap）上下文执行；V2.5 新增的非链接动作加入此集合。
 */
const NON_TARGET_ACTION_IDS = [
  "browser.tab.activate_previous",
  "browser.tab.activate_next",
  "browser.tab.open_new",
  "browser.tab.pin",
  "browser.tab.unpin",
  "browser.tab.toggle_mute",
  "browser.tab.close_others",
  "browser.tab.restore",
  // 非链接动作：任意手势（含非三指点按）都应可触发；缺此列表会导致
  // requiresTargetRef=false 的 context 在 preflight 被 allowedActionIds 拒绝。
  "browser.tab.close_current",
  "browser.page.reload",
  "browser.history.back",
  "browser.history.forward",
  "browser.page.copy_url",
  "browser.page.scroll_top_bottom"
] as const satisfies readonly StandardActionID[];

/**
 * Chrome Provider v2 boundary. URLs stay in this process behind session-bound
 * opaque refs; callers only receive page identity and target classification.
 */
export class ChromeProvider {
  private readonly targets = new Map<string, StoredTarget>();
  private readonly contexts = new Map<string, StoredContext>();
  private readonly statuses = new Map<string, OperationStatusResponse>();

  constructor(
    private readonly api: ChromeApi,
    private readonly content: ContentBridge,
    private readonly accept?: (request: ActionRequest) => Promise<boolean>
  ) {}

  async context(request: ContextRequest): Promise<ContextSnapshot> {
    const now = Date.now();
    if (request.deadline <= now) return unavailable("page_unavailable", request.deadline);
    const tab = await activeTab(this.api);
    if (!tab?.id) return unavailable("page_unavailable", request.deadline);
    const pageIdentityInfo = pageIdentityFromTabURL(tab.url);
    if (!pageIdentityInfo) return unavailable("page_unavailable", request.deadline);
    const pageIdentity = request.requiresTargetRef && (pageIdentityInfo.protocol !== "http:" && pageIdentityInfo.protocol !== "https:") ? "" : pageIdentityInfo.identity;
    const contextId = crypto.randomUUID();
    const expiresAt = request.deadline;
    // 尽早存储 context 使 preflight 能找到它，不受 unavailable 返回路径影响
    this.contexts.set(contextId, {
      gestureSessionId: request.gestureSessionId,
      tabId: tab.id,
      expiresAt,
      allowedActionIds: request.requiresTargetRef ? undefined : NON_TARGET_ACTION_IDS
    });
    if (request.requiresTargetRef && pageIdentityInfo.protocol !== "http:" && pageIdentityInfo.protocol !== "https:") {
      return { contextId, expiresAt, targetKind: "page_unavailable", pageIdentity };
    }
    if (!request.requiresTargetRef) {
      return { contextId, expiresAt, targetKind: "no_target", pageIdentity };
    }
    let resolved: PointerResolution;
    try {
      resolved = await this.content(tab.id, { type: "gesturekit.resolveLastPointer" }) as PointerResolution;
    } catch {
      await this.releaseGuard(tab.id, request.gestureSessionId);
      return { contextId, expiresAt, targetKind: "page_unavailable", pageIdentity };
    }
    if (resolved.status !== "success") {
      await this.releaseGuard(tab.id, request.gestureSessionId);
      return { contextId, expiresAt, targetKind: resolved.status === "no_target" ? "no_target" : "page_unavailable", pageIdentity };
    }
    const targetRef = crypto.randomUUID();
    this.targets.set(targetRef, { contextId, gestureSessionId: request.gestureSessionId, tabId: tab.id, frameId: resolved.frameId ?? 0, url: resolved.url, expiresAt });
    return { contextId, expiresAt, targetKind: "standard_link", targetRef, pageIdentity };
  }

  async execute(request: ActionRequest): Promise<ActionResult> {
    const preflight = await this.preflight(request);
    if (preflight.status !== "ready") return { status: preflight.status };
    if (this.accept && !(await this.accept(request))) {
      await this.releaseCurrentGuard(request.gestureSessionId);
      return { status: "chrome_api_error" };
    }
    return this.executeAccepted(request, preflight.url);
  }

  async preflight(request: ActionRequest): Promise<{ status: "ready"; url?: string } | { status: "guard_unavailable" | "guard_expired" | "context_expired" | "target_not_found" }> {
    const now = Date.now();
    if (request.deadline <= now) {
      await this.releaseCurrentGuard(request.gestureSessionId);
      return { status: "context_expired" };
    }
    const context = this.contexts.get(request.contextId);
    if (!context || context.expiresAt < now) {
      return { status: "context_expired" };
    }
    if (context.gestureSessionId !== request.gestureSessionId) {
      return { status: request.actionId === "browser.link.open_adjacent" ? "guard_unavailable" : "context_expired" };
    }
    if (context.allowedActionIds && !context.allowedActionIds.includes(request.actionId)) {
      return { status: "context_expired" };
    }
    const active = await activeTab(this.api);
    if (!active?.id || active.id !== context.tabId) return { status: "context_expired" };
    let url: string | undefined;
    if (request.actionId === "browser.link.open_adjacent") {
      const target = request.targetRef ? this.targets.get(request.targetRef) : undefined;
      if (!target || target.contextId !== request.contextId || target.expiresAt < now) {
        await this.releaseCurrentGuard(request.gestureSessionId);
        return { status: "context_expired" };
      }
      if (target.gestureSessionId !== request.gestureSessionId) {
        await this.releaseGuard(target.tabId, request.gestureSessionId);
        return { status: "guard_unavailable" };
      }
      if (active.id !== target.tabId) {
        await this.releaseGuard(target.tabId, request.gestureSessionId);
        return { status: "context_expired" };
      }
      let current: PointerResolution;
      try { current = await this.content(active.id, { type: "gesturekit.resolveLastPointer" }) as PointerResolution; } catch {
        await this.releaseGuard(active.id, request.gestureSessionId);
        return { status: "context_expired" };
      }
      if (current.status !== "success" || (current.frameId ?? 0) !== target.frameId) {
        await this.releaseGuard(active.id, request.gestureSessionId);
        return { status: "context_expired" };
      }
      let guard: { status?: string };
      try { guard = await this.content(active.id, { type: "gesturekit.guardConsume", gestureSessionId: request.gestureSessionId, url: target.url }) as { status?: string }; } catch {
        await this.releaseGuard(active.id, request.gestureSessionId);
        return { status: "guard_unavailable" };
      }
      if (guard.status !== "guard_consumed") return { status: guard.status === "guard_expired" ? "guard_expired" : "guard_unavailable" };
      url = target.url;
    } else if (request.actionId === "browser.link.copy") {
      // 复制链接：解析 opaque targetRef 到 URL，但不消费交互保护（无导航副作用）。
      const target = request.targetRef ? this.targets.get(request.targetRef) : undefined;
      if (!target || target.contextId !== request.contextId || target.expiresAt < now) {
        return { status: "context_expired" };
      }
      if (target.gestureSessionId !== request.gestureSessionId) {
        return { status: "guard_unavailable" };
      }
      if (active.id !== target.tabId) {
        return { status: "context_expired" };
      }
      url = target.url;
    }
    return { status: "ready", url };
  }

  async executeAccepted(request: ActionRequest, url?: string): Promise<ActionResult> {
    this.statuses.set(request.operationId, { operationId: request.operationId, status: "accepted" });
    try {
      const result = await executeStandardAction(this.api, request.actionId, url, request.parameters);
      const status = result.status === "success" ? "success" : result.status;
      this.statuses.set(request.operationId, { operationId: request.operationId, status: status === "success" ? "success" : "failed" });
      if (status !== "success") await this.releaseCurrentGuard(request.gestureSessionId);
      return { status };
    } catch {
      this.statuses.set(request.operationId, { operationId: request.operationId, status: "failed" });
      await this.releaseCurrentGuard(request.gestureSessionId);
      return { status: "chrome_api_error" };
    }
  }

  async reconcile(operationId: string): Promise<OperationStatusResponse> {
    return this.statuses.get(operationId) ?? { operationId, status: "not_found" };
  }

  private async releaseCurrentGuard(gestureSessionId: string): Promise<void> {
    const tab = await activeTab(this.api);
    if (tab?.id) await this.releaseGuard(tab.id, gestureSessionId);
  }

  private async releaseGuard(tabId: number, gestureSessionId: string): Promise<void> {
    try { await this.content(tabId, { type: "gesturekit.guardRelease", gestureSessionId }); } catch { /* best-effort cleanup */ }
  }
}

async function activeTab(api: ChromeApi): Promise<chrome.tabs.Tab | undefined> {
  return (await api.tabs.query({ active: true, lastFocusedWindow: true }))[0];
}

function unavailable(targetKind: "no_target" | "page_unavailable", expiresAt: number): ContextSnapshot {
  return { contextId: crypto.randomUUID(), expiresAt, targetKind, pageIdentity: "" };
}

function pageIdentityFromTabURL(value: string | undefined): { protocol: string; identity: string } | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    url.search = "";
    url.hash = "";
    return { protocol: url.protocol, identity: url.toString() };
  } catch {
    return null;
  }
}
