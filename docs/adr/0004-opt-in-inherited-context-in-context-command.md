# 4. Load inherited governance context opt-in, not by default, in /holacracy:context

Date: 2026-06-16

## Status

Accepted

## Context

`/holacracy:context` resolves **positional** context only: actor identity (`glassfrog_get_me`), a flat role roster grouped by each role's immediate circle (`glassfrog_list_my_roles`), and registered scheduled routines. It performs no hierarchy traversal and never loads the **inherited** governance that flows down from the enclosing circles — purpose, strategy, policies, domains. In Holacracy this inherited context is load-bearing: Constitution v5 requires interpreting governance in the context of the enclosing Circle and any Super-Circle (Art 4.2) and treats super-circle Strategies as mandatory prioritization inputs (Art 2.3.3). A shared reference even narrated "Strategy on file says…" as if inherited strategy were loaded, when it was not.

[ADR-0003](0003-glassfrog-tension-api-adoption.md) and its tracking issue ([#17](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/17)) established a deliberate stance: **keep `/holacracy:context` cheap**, deferring command-surface expansion. That stance was set when the cost of loading more was unknown.

A live GlassFrog **API v5** probe (2026-06-16, captured in `docs/brainstorms/2026-06-16-context-inherited-context-probe-requirements.md`) settled the cost question and refuted the repo's then-current API-constraints reference:

- `glassfrog_get_role_context(role_id)` returns, in **one call**, the role plus a `governance` block: the `ancestor_roles` chain to the Anchor Circle (purpose per level), the `parent_role` with policy excerpts, sibling roles, and the org's Constitution sections.
- `glassfrog_get_role_strategy(role_id)` returns the inherited strategy with `inherited: true` and `inherited_from_role_id` — the cascade is resolved server-side.
- `glassfrog_list_role_policies` returns full policy bodies; policies are readable (the constraints doc's "not exposed" claim was stale).
- `get_role_tree` / `get_org_tree` return descendants only — ancestors come from `get_role_context`.
- `glassfrog_get_me(include_roles: true)` is ~114k characters in a 75-role org — eager, all-roles loading is not viable.

So inherited context is a **1–2 call, single-role** load, not the N-call hierarchy walk it appeared to be.

## Decision

Load inherited governance context **opt-in, scoped to a single resolved role** — never by default and never across the whole roster.

1. **Trigger:** an explicit `--inherited` flag on `/holacracy:context`. Without the flag, the command's behavior and tool calls are byte-for-byte unchanged; the inherited path adds zero GlassFrog calls to the default.
2. **Payload:** `glassfrog_get_role_context(role_id)` (enclosing purpose chain to the Anchor Circle, parent-circle policy excerpts, org rules) plus `glassfrog_get_role_strategy(role_id)` (inherited strategy, pre-resolved). A 1–2 call ceiling.
3. **Placement:** the load procedure lives in a shared reference, `skills/shared/inherited-context-procedure.md`, mirroring the repo's existing shared-reference convention. The command points to it; the role skills can later invoke the same procedure (see "What this ADR does NOT do").
4. **Disconnect:** when GlassFrog is unavailable, the inherited path names the limitation and asks the actor to declare their enclosing-circle context — matching the fallback `commands/context.md` and `commands/tactical.md` already use.

This refines the ADR-0003 "keep it cheap" stance rather than overturning it: the default stays cheap; depth is available only on explicit request.

## Consequences

- The default `/holacracy:context` remains the cheap positional resolver ADR-0003 intended; cost discipline is preserved as the default, with an explicit, discoverable escalation.
- The `--inherited` load makes the "Strategy on file says…" framing achievable, since inherited strategy can now actually be loaded.
- Extracting the load into a shared procedure gives a clean seam for the follow-on work: skill-side lazy loading and the binding-constraints payload filter ([#35](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/35)) and cross-skill reuse ([#36](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/36)) build on it rather than re-implementing traversal.
- A v5-only dependency: the design relies on `get_role_context` returning `ancestor_roles` and on `get_role_strategy` resolving inheritance. If the MCP server is ever repointed to a v3-only endpoint, the load must be re-probed.

## What this ADR does NOT do

- It does **not** change the default behavior of `/holacracy:context`. No-flag invocations are unchanged.
- It does **not** expand full per-ancestor policy bodies or apply the Art 4.2/2.3.3 binding-constraints filter — the command surfaces parent-policy excerpts only. Full bodies and the binding filter are deferred to [#35](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/35).
- It does **not** add skill-side lazy loading or cross-skill caching. Those are [#35](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/35) and [#36](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/36); this ADR only establishes the opt-in command load and the shared procedure they reuse.
- It is distinct from [#17](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/17) (surfacing unprocessed tensions in the same command): a sibling expansion that shares the "keep cheap" rationale but is not governed by this decision.
