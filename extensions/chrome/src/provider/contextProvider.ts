import type { ContextSnapshotPayload, ContextTargetKind } from "./protocol";

/** Chrome 页面上下文的最小 v2 Provider；只输出动作决策所需的白名单事实。 */
export class ContextProvider {
  private readonly targets = new Map<string, { contextId: string; url: string; expiresAt: number }>();

  snapshot(resolvedURL: string | null, now = Date.now(), ttlMs = 1_500): ContextSnapshotPayload {
    if (!resolvedURL) return this.unavailable("no_target", now, ttlMs);
    let url: URL;
    try { url = new URL(resolvedURL); } catch { return this.unavailable("page_unavailable", now, ttlMs); }
    if (url.protocol !== "http:" && url.protocol !== "https:") return this.unavailable("page_unavailable", now, ttlMs);
    url.search = "";
    url.hash = "";
    const contextId = crypto.randomUUID();
    const targetRef = crypto.randomUUID();
    const expiresAt = now + ttlMs;
    this.targets.set(targetRef, { contextId, url: resolvedURL, expiresAt });
    return { contextId, pageIdentity: url.toString(), expiresAt, targetKind: "standard_link", targetRef };
  }

  resolveTarget(contextId: string, targetRef: string, now = Date.now()): string | null {
    const target = this.targets.get(targetRef);
    if (!target || target.contextId !== contextId || target.expiresAt < now) { this.targets.delete(targetRef); return null; }
    return target.url;
  }

  private unavailable(targetKind: ContextTargetKind, now: number, ttlMs: number): ContextSnapshotPayload {
    return { contextId: crypto.randomUUID(), pageIdentity: "", expiresAt: now + ttlMs, targetKind, targetRef: null };
  }
}
