---
date: 2026-06-16
topic: context-inherited-context-probe
---

# Inherited context in /holacracy:context — probe findings & design direction

## Summary

A live probe against the GlassFrog v5 MCP settles how `/holacracy:context` should load inherited Holacratic context: it is a **single-call problem, not a hierarchy walk**. `glassfrog_get_role_context(role_id)` returns the role plus its full ancestor chain to the Anchor Circle, the parent role's policies, and the org's Constitution sections in one compact call. This doc records the empirical findings, the corrections they force on the repo's stale API-constraints reference, and the design direction the findings unblock for [ideation ideas 2–6](../ideation/2026-06-16-context-inherited-context-ideation.html). It does **not** change `/holacracy:context` — that stays the cheap default per [ADR-0003](../adr/0003-glassfrog-tension-api-adoption.md) / [issue #17](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/17).

## Problem Frame

`/holacracy:context` loads only positional context (identity + flat role roster). The ideation that preceded this probe could not choose an architecture because the repo's own `glassfrog-api-constraints.md` contradicted the live MCP tool surface: the doc claimed policies are unreadable and there is no hierarchy endpoint, while the connected server exposed `glassfrog_get_role_context`, `glassfrog_list_role_policies`, `glassfrog_get_org_tree`, and `glassfrog_get_role_tree`. Every downstream design — argument-gated load, payload filter, caching, fallback — had a different shape depending on whether inherited context costs one call or N. The probe resolves that fork against ground truth so design stops guessing.

## Findings

Probed against org `Integral Productivity` (75 roles, multi-circle), focal role **Product Architecture** (nested: Anchor Circle → Market Applied Innovation → Enterprise Architecture → Product Architecture).

- **F1. `glassfrog_get_role_context(role_id)` is the inherited-context bundle.** One call returns the role (purpose, accountabilities, domains, skills, notes, projects, actions) **plus** a `governance` block containing: `ancestor_roles` (the full chain to the Anchor Circle, each with name + purpose + parent), `parent_role` with its `policies` inline (excerpts), `sibling_roles`, and `org_rules` (Constitution v5 sections with summaries + content URLs). It is described as "lighter weight than `glassfrog_get_role` with all includes."
- **F2. Inherited strategy is resolved server-side.** `glassfrog_get_role_strategy(role_id)` returns the strategy body with `"inherited": true` and `"inherited_from_role_id"` when the role's strategy comes from an enclosing circle. The caller does not walk the chain to resolve it.
- **F3. Policies are fully readable.** `glassfrog_list_role_policies(role_id)` returns each policy's full `title`, `body`, and `domain_id`. `get_role_context` additionally surfaces the parent role's policies as excerpts. (Writing policies remains impossible via API — that boundary is unchanged.)
- **F4. Tree tools go down, not up.** `glassfrog_get_role_tree` / `glassfrog_get_org_tree` return **descendants** (children). Ancestors come from `get_role_context.ancestor_roles`, not from a tree call.
- **F5. Cost shape favors focused-role loading.** `glassfrog_get_me(include_roles: true)` returned ~114k characters (75 embedded roles) — too large to load eagerly. A single focused-role `get_role_context` is compact. Inherited-context loading must be scoped to a resolved role/circle, never the whole roster.
- **F6. IDs and naming are v5.** IDs are prefixed (`role_<32hex>`, `per_…`, `org_…`, `pol_…`, `dom_…`); roles relate by `parent_role_id`. The repo's `parent_circle_id` / `sub_circle_id` / `is_circle` language is v3-era.

## Key Decisions

- **The "single-call bundle" branch is confirmed; the "N-call walk" and "user-asserted fallback" branches drop in priority.** Per F1–F2, inherited purpose, the ancestor chain, parent policies, and inherited strategy are reachable in 1–2 calls for a focused role. The ideation's per-level `get_circle` traversal and its disconnect-only user-assertion path are no longer the primary design — they survive only as the GlassFrog-absent degradation case.
- **Inherited-context loading stays opt-in and focused.** F5 plus ADR-0003 mean the default `/holacracy:context` keeps its current cheap path; inherited context loads only for a resolved role/circle, behind an explicit trigger.

## Requirements

**Constraints-doc correction (this session)**

- R1. `skills/holacratic-ai-governance/references/glassfrog-api-constraints.md` "What Cannot Be Read" must stop claiming policies are unreadable. Policies are readable via `glassfrog_list_role_policies` (full body) and surfaced as parent-policy excerpts in `get_role_context`. The *write* boundary ("cannot create/modify/delete policies via API") stays.
- R2. The same file's "no dedicated hierarchy endpoint" note must be corrected: `get_role_context` returns the upward `ancestor_roles` chain to the Anchor Circle in one call, and `get_role_tree` / `get_org_tree` provide the downward view.
- R3. The tool inventory and field language must be updated to v5: prefixed IDs, `parent_role_id`, and the read tools that exist today (`get_role_context`, `get_role_strategy` with inheritance metadata, `list_role_policies`, `list_subrole_policies`, `get_role_tree`, `get_org_tree`).
- R4. Corrections must be grounded in observed payloads (this doc's Findings), not the v5 announcement alone, so the reference stays honest about what the *connected* server returns.

**Design direction the findings hand to ideas 2–6 (downstream, not this session)**

- R5. When inherited context is requested for a focused role, the load is `get_role_context(role_id)` plus, when strategy matters, `get_role_strategy(role_id)` — a 1–2 call ceiling, not a per-level walk.
- R6. The default `/holacracy:context` path is unchanged; inherited loading is opt-in (argument-gated) and scoped to a resolved role/circle, never the full roster.
- R7. The `actor-and-role-resolution.md:73` "Strategy on file says…" narration is reconciled by routing inherited loading through the shared reference so the narration matches behavior (ideation idea 4) — now feasible because `get_role_strategy` returns inherited strategy directly.

## Scope Boundaries

- In scope this session: the probe (done), the `glassfrog-api-constraints.md` correction (R1–R4), and filing the downstream follow-ups.
- Deferred (downstream issues): the actual `/holacracy:context` change, the payload filter, caching, and the shared-reference relocation — ideation ideas 2–6.
- Outside scope: changing the default behavior of `/holacracy:context`; any policy/governance *write* path.

## Dependencies / Assumptions

- A1. Findings reflect a populated multi-circle org. A solo-operator flat org would still return `get_role_context`, but `ancestor_roles` would be shorter — the shape holds; the depth varies.
- A2. The MCP server (`ipllc-glassfrog-mcp-server.vercel.app`) tracks GlassFrog API v5. If it is ever repointed to a v3-only endpoint, F1–F4 must be re-probed.
- A3. `get_role_context` returns parent policies as *excerpts*; full inherited policy bodies still need `list_role_policies` against the relevant role. The payload filter (idea 3) decides whether excerpts suffice for the command surface.

## Outstanding Questions

**Deferred to planning (ideas 2–6)**

- Q1. Does `get_role_context`'s `ancestor_roles` (name + purpose only) plus `parent_role.policies` excerpts satisfy the binding-constraints payload (idea 3), or does the command also need `get_role_strategy` and a `list_role_policies` per ancestor?
- Q2. What is the opt-in trigger surface — a `--inherited` flag on the command, or lazy load inside the role skills when a governance-interpretive turn arises?

## Sources

- Live probe payloads (this session): `glassfrog_get_role_context`, `glassfrog_get_role_strategy`, `glassfrog_list_role_policies`, `glassfrog_get_role_tree`, `glassfrog_get_me` against org `Integral Productivity`.
- `skills/holacratic-ai-governance/references/glassfrog-api-constraints.md` (lines 112, 118, 27–29 — the stale claims).
- `docs/adr/0003-glassfrog-tension-api-adoption.md` and [issue #17](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/17) (the "keep it cheap" stance).
- [Ideation artifact](../ideation/2026-06-16-context-inherited-context-ideation.html) (ideas 1–6).
