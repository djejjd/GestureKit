/** 候选手势在 content script 中建立 guard 所需的命令。 */
export type GuardCommand = {
  gestureSessionId: string;
  issuedAtMonotonicMs: number;
  leaseMs: number;
};

/** 会被 guard 观测的 DOM 默认行为入口。 */
export type GuardedDOMEventType = "click" | "selectstart" | "dragstart";

/** 单个 DOM 事件相对 guard 的时序证据。 */
export type GuardObservation = {
  gestureSessionId: string;
  eventType: GuardedDOMEventType;
  domEventMonotonicMs: number;
  armedAtMonotonicMs: number | null;
  status: "armed_before_dom" | "late" | "unavailable";
};

type ActiveGuard = GuardCommand & {
  armedAtMonotonicMs: number;
};

/**
 * 创建页面级候选 guard 状态机。
 *
 * 状态机只保存当前页面的一次性 session；调用方负责将它绑定到正确的
 * tab、frame 和页面身份，避免跨页面复用 guard。
 */
export function createInteractionGuard() {
  let activeGuard: ActiveGuard | null = null;

  /** 在 content script 收到来自后台的命令时启动一次性 lease。 */
  function arm(command: GuardCommand, receivedAtMonotonicMs: number): void {
    activeGuard = {
      ...command,
      armedAtMonotonicMs: receivedAtMonotonicMs
    };
  }

  /**
   * 为真实 DOM 副作用记录时序。
   *
   * `late` 表示命令抵达晚于 DOM 事件；此时调用方必须 fail-closed，
   * 不能将链接动作标记为已安全保护。
   */
  function observeDOMEvent(input: {
    gestureSessionId: string;
    eventType: GuardedDOMEventType;
    domEventMonotonicMs: number;
  }): GuardObservation {
    const guard = matchingActiveGuard(input.gestureSessionId, input.domEventMonotonicMs);
    if (!guard) {
      return {
        ...input,
        armedAtMonotonicMs: null,
        status: "unavailable"
      };
    }

    return {
      ...input,
      armedAtMonotonicMs: guard.armedAtMonotonicMs,
      status: guard.armedAtMonotonicMs <= input.domEventMonotonicMs ? "armed_before_dom" : "late"
    };
  }

  /**
   * 消费一次成功的 guard，确保同一 session 不会保护第二个副作用。
   */
  function consume(input: { gestureSessionId: string; nowMonotonicMs: number }): { status: "guard_consumed" | "guard_unavailable" } {
    const guard = matchingActiveGuard(input.gestureSessionId, input.nowMonotonicMs);
    if (!guard) {
      return { status: "guard_unavailable" };
    }

    activeGuard = null;
    return { status: "guard_consumed" };
  }

  /** 在 lease 到期或 session 不匹配时主动清理页面级状态。 */
  function matchingActiveGuard(gestureSessionId: string, nowMonotonicMs: number): ActiveGuard | null {
    if (!activeGuard) return null;
    if (nowMonotonicMs > activeGuard.armedAtMonotonicMs + activeGuard.leaseMs) {
      activeGuard = null;
      return null;
    }
    return activeGuard.gestureSessionId === gestureSessionId ? activeGuard : null;
  }

  return { arm, consume, observeDOMEvent };
}
