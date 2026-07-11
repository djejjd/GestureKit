import type { ActionDescriptor } from "./protocol";
import { ContextProvider } from "./contextProvider";

export type AdapterResult = { outcome: "succeeded" } | { outcome: "failed"; reason: "context_expired" | "target_not_found" | "capability_unavailable" };

/** 执行标准动作的 Chrome adapter；副作用前重新校验短时效 targetRef。 */
export class ChromeActionAdapter {
  constructor(private readonly contexts: ContextProvider, private readonly openAdjacent: (url: string) => Promise<void>) {}

  async execute(action: ActionDescriptor, now = Date.now()): Promise<AdapterResult> {
    if (action.actionId !== "browser.link.open_adjacent") return { outcome: "failed", reason: "capability_unavailable" };
    if (!action.targetRef) return { outcome: "failed", reason: "target_not_found" };
    const url = this.contexts.resolveTarget(action.targetRef, now);
    if (!url) return { outcome: "failed", reason: "context_expired" };
    await this.openAdjacent(url);
    return { outcome: "succeeded" };
  }
}
