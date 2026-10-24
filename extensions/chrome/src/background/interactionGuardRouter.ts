type GuardMessage = {
  type: string;
  payload: { gestureSessionId: string; features?: string[]; deadline?: number; disposition?: string };
};
type Response = { status?: string; documentToken?: string } | null;
type Dependencies = {
  query: () => Promise<{ id?: number }[]>;
  send: (tabID: number, message: Record<string, unknown>) => Promise<Response>;
  trace: (sessionID: string, stage: string, detail: string) => void;
};

/** 在 arm 到达时固定来源。异步 release 等待同一次 arm，不查询切换后的活动页。 */
export function createInteractionGuardRouter({ query, send, trace }: Dependencies) {
  type Source = { tabID: number; documentToken?: string };
  const entries = new Map<string, { deadline: number; ready: Promise<Source | null>; released: boolean }>();
  // 有界墓碑防止 release 先到时迟到 arm 复活旧候选；每次消息顺便过期清理。
  const closed = new Map<string, number>();
  let latestArmSequence = 0;
  let disposed = false;
  const close = (id: string) => {
    closed.set(id, Date.now() + 1600);
    if (closed.size > 256) closed.delete(closed.keys().next().value!);
  };
  const route = async (message: GuardMessage): Promise<void> => {
    if (disposed) return;
    const now = Date.now();
    for (const [id, entry] of entries) if (entry.deadline <= now) { entries.delete(id); close(id); }
    for (const [id, deadline] of closed) if (deadline <= now) closed.delete(id);
    const payload = message.payload;
    const id = payload.gestureSessionId;
    if (message.type === "interaction_guard_arm") {
      if (closed.has(id) || entries.has(id)) return;
      const features = payload.features?.filter(value => value === "link_click" || value === "drag_selection") ?? [];
      const maxLeaseMs = features.includes("link_click") ? 1200 : 800;
      const deadline = Math.min(payload.deadline ?? 0, now + maxLeaseMs);
      if (!features.length || deadline <= now || entries.size >= 128) {
        trace(id, "forward_failed", "invalid_or_expired_guard"); return;
      }
      const sequence = ++latestArmSequence;
      const ready = (async (): Promise<Source | null> => {
        const [tab] = await query();
        if (disposed || closed.has(id) || sequence !== latestArmSequence) {
          trace(id, "guard_discarded", "superseded_before_arm"); return null;
        }
        if (tab?.id === undefined || Date.now() >= deadline) {
          trace(id, "forward_failed", tab?.id === undefined ? "active_tab_unavailable" : "guard_expired");
          return null;
        }
        trace(id, "forwarding", "content_script");
        const response = await send(tab.id, {
          type: "gesturekit.linkGuardArm", gestureSessionId: id,
          features, leaseMs: Math.max(0, deadline - Date.now())
        });
        trace(id, response?.status === "guard_armed" ? "forwarded" : "forward_failed", response?.status ?? "content_script_unavailable");
        return response?.status === "guard_armed" ? { tabID: tab.id, documentToken: response.documentToken } : null;
      })().catch(() => { trace(id, "forward_failed", "content_script_unavailable"); return null; });
      entries.set(id, { deadline, ready, released: false });
      await ready;
      return;
    }
    const entry = entries.get(id);
    if (!entry || entry.released) { close(id); return; }
    entry.released = true;
    close(id);
    try {
      const source = await entry.ready;
      if (!source) return;
      const discarding = disposed || payload.disposition === "discard";
      const response = await send(source.tabID, {
        type: discarding ? "gesturekit.linkGuardDiscard" : "gesturekit.linkGuardRelease",
        gestureSessionId: id, documentToken: source.documentToken
      });
      trace(id, !response?.status || response.status === "guard_unavailable" ? "forward_failed" : discarding ? "guard_discarded" : "guard_released", response?.status ?? "release_unavailable");
    } catch { trace(id, "forward_failed", "release_unavailable"); }
    finally { entries.delete(id); }
  };
  return Object.assign(route, {
    async dispose() {
      if (disposed) return;
      disposed = true;
      const pending = [...entries.entries()];
      entries.clear(); closed.clear();
      await Promise.all(pending.map(async ([id, entry]) => {
        if (entry.released) return; // The existing release continuation owns cleanup.
        entry.released = true;
        const source = await entry.ready;
        if (!source) return;
        try {
          await send(source.tabID, { type: "gesturekit.linkGuardDiscard", gestureSessionId: id, documentToken: source.documentToken });
          trace(id, "guard_discarded", "provider_session_closed");
        } catch { trace(id, "forward_failed", "dispose_unavailable"); }
      }));
    }
  });
}
