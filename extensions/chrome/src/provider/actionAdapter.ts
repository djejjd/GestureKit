import type { ActionDescriptor } from "./protocol";
import { ContextProvider } from "./contextProvider";

export type AdapterResult = { outcome: "succeeded" } | { outcome: "failed"; reason: "context_expired" | "target_not_found" | "capability_unavailable" };
type PreflightResult = { outcome: "failed"; reason: "context_expired" | "target_not_found" | "capability_unavailable" } | { outcome: "ready"; url?: string };

/** 执行标准动作的 Chrome adapter；副作用前重新校验短时效 targetRef。 */
export class ChromeActionAdapter {
  constructor(
    private readonly contexts: ContextProvider,
    private readonly openAdjacent: (url: string) => Promise<void>,
    private readonly executeStandard?: (action: ActionDescriptor) => Promise<void>
  ) {}

  async execute(action: ActionDescriptor, now = Date.now()): Promise<AdapterResult> {
    const preflight = this.preflight(action, now);
    if (preflight.outcome === "failed") return preflight;
    if (action.actionId === "browser.link.open_adjacent") await this.openAdjacent(preflight.url!);
    else if (this.executeStandard) await this.executeStandard(action);
    else return { outcome: "failed", reason: "capability_unavailable" };
    return { outcome: "succeeded" };
  }

  /** 副作用前的同步上下文校验，供分发器在写入 acceptance 前 fail-closed。 */
  preflight(action: ActionDescriptor, now = Date.now()): PreflightResult {
    if (action.actionId !== "browser.link.open_adjacent") {
      return this.executeStandard ? { outcome: "ready" } : { outcome: "failed", reason: "capability_unavailable" };
    }
    if (!action.targetRef) return { outcome: "failed", reason: "target_not_found" };
    const url = this.contexts.resolveTarget(action.contextId, action.targetRef, now);
    return url ? { outcome: "ready", url } : { outcome: "failed", reason: "context_expired" };
  }
}
