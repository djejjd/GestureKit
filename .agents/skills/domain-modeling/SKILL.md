---
name: domain-modeling
description: Build and sharpen a project's domain model. Use when the user wants to pin down domain terminology or a ubiquitous language, record an architectural decision, or when another skill needs to maintain the domain model.
---

# Domain Modeling

> **本仓库适配（GestureKit）**：本项目没有 `CONTEXT.md`。权威术语源按以下顺序读取，
> 缺失时再由本 skill 补建 `CONTEXT.md` 词表：
>
> 1. `docs/product/` 下对应版本的**产品契约**（如 `gesturekit-v2.3-installation-contract.md`、`gesturekit-v2.2-configuration-contract.md`）
> 2. `docs/architecture/` 架构文档与 `docs/adr/`（已有 0001-0003，沿用其编号与格式）
> 3. `CLAUDE.md` 的 Architecture 章节与 Key Conventions
> 4. `AGENTS.md` 的权威资料清单
>
> 项目约定：用户可见文字与代码注释用中文；协议字段、路径、API 名保留英文。
> 术语定义要同时给中文释义和英文术语，`_Avoid_` 列出易混的同义/近义说法。
> 新增 ADR 必须遵循 [ADR-FORMAT.md](./ADR-FORMAT.md) 中**仓库既有格式**（中文结构化，
> 含状态/背景/决策/后果/不采用的方案），不要使用通用单段模板。

Actively build and sharpen the project's domain model as you design. This is the *active* discipline — challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* the glossary for vocabulary is not this skill — that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

## File structure

GestureKit 使用"契约驱动"的多上下文结构：术语散落在 `docs/product/`（产品契约）、
`docs/architecture/`（架构）与 `docs/adr/`（决策记录）中，根目录无 `CONTEXT.md`。

```
/
├── CLAUDE.md                     ← 架构与约定，术语速览
├── AGENTS.md                     ← 工作流与权威资料清单
├── docs/
│   ├── product/                  ← 产品契约（各版本）
│   │   └── gesturekit-v2*.md
│   ├── architecture/             ← 架构文档
│   ├── adr/                      ← 决策记录 0001-0003
│   └── operations/               ← 操作说明
├── Sources/GestureKitCore/       ← 共享核心（协议、规则、模型）
├── apps/macos/GestureKitApp/     ← App 层
└── extensions/chrome/            ← Chrome 扩展
```

当术语在既有文档中无法确认、需要建立统一词表时，再于根目录补建 `CONTEXT.md`
（格式见 [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md)）。ADR 目录已存在，直接沿用。

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in the authoritative sources (`docs/product/` 契约、`docs/architecture/`、`docs/adr/`、`CLAUDE.md`，以及补建后的 `CONTEXT.md`), call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update the glossary inline

When a term is resolved, record it right there. Don't batch these up — capture them as they happen. If the repo's authoritative source is missing a definition, add it to the appropriate contract/architecture doc; if a unified `CONTEXT.md` exists, update it. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat it as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).
