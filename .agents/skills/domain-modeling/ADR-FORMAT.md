# ADR Format

ADRs live in `docs/adr/` and use sequential numbering: `0001-slug.md`, `0002-slug.md`, etc.

The `docs/adr/` directory already exists in GestureKit (0001-0003). Follow its established format.

> **本仓库适配（GestureKit）**：必须使用仓库既有的**中文结构化格式**，不要使用通用单段模板。
> 参见 [0001-use-native-host-shim.md](../../docs/adr/0001-use-native-host-shim.md) 为范例。

## Template（仓库既有格式）

```md
# ADR NNNN：{决策标题，中文}

日期：{YYYY-MM-DD}

## 状态

{已接受 | 提议 | 已废弃 | 被 ADR-NNNN 取代}

## 背景

{1-3 句：为什么需要这个决策。}

## 决策

{做了什么，怎么做的。}

## 后果

收益：{...}

代价：{...}

## 不采用的方案

{被否决的替代方案，以及否决原因（非显然时才有价值）。}
```

各小节（状态/背景/决策/后果/不采用的方案）按需保留；若某节无实质内容可省略，但不要用
占位符。标题行保留 `ADR NNNN：` 前缀。

## Numbering

Scan `docs/adr/` for the highest existing number and increment by one.

## When to offer an ADR

All three of these must be true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will look at the code and wonder "why on earth did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If a decision is easy to reverse, skip it — you'll just reverse it. If it's not surprising, nobody will wonder why. If there was no real alternative, there's nothing to record beyond "we did the obvious thing."

### What qualifies

- **Architectural shape.** "We're using a monorepo." "The write model is event-sourced, the read model is projected into Postgres."
- **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
- **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target. Not every library — just the ones that would take a quarter to swap out.
- **Boundary and scope decisions.** "Customer data is owned by the Customer context; other contexts reference it by ID only." The explicit no-s are as valuable as the yes-s.
- **Deliberate deviations from the obvious path.** "We're using manual SQL instead of an ORM because X." Anything where a reasonable reader would assume the opposite. These stop the next engineer from "fixing" something that was deliberate.
- **Constraints not visible in the code.** "We can't use AWS because of compliance requirements." "Response times must be under 200ms because of the partner API contract."
- **Rejected alternatives when the rejection is non-obvious.** If you considered GraphQL and picked REST for subtle reasons, record it — otherwise someone will suggest GraphQL again in six months.
