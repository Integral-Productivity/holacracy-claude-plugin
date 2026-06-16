---
module: glassfrog-mcp-integration
date: 2026-06-16
problem_type: tooling_decision
component: tooling
severity: medium
tags:
  - glassfrog
  - mcp
  - api-v5
  - inherited-context
  - holacracy
  - role-context
applies_when:
  - "designing a GlassFrog MCP read for a role's enclosing-circle context"
  - "deciding whether inherited context costs one call or a hierarchy walk"
  - "trusting an in-repo API-constraints reference about what the MCP can read"
related_components:
  - documentation
---

# GlassFrog v5 returns a role's inherited context in one call — and the in-repo constraints doc lied about it

## Context

Designing inherited-context loading for `/holacracy:context` stalled on a contradiction. The repo's own `skills/holacratic-ai-governance/references/glassfrog-api-constraints.md` claimed two things that shaped the whole design space:

- "Policies are not exposed through the standard API."
- "The API does not provide a dedicated hierarchy endpoint" (super/sub inferred from role data).

If true, loading enclosing-circle purpose + policies would mean an N-call walk up the chain, and policies would have to be asked of the user. That framing is what made the feature look expensive enough to defer (see ADR-0003, issue #17). The contradiction: the live MCP server connected to the session exposed `glassfrog_get_role_context`, `glassfrog_list_role_policies`, `glassfrog_get_org_tree`, and `glassfrog_get_role_tree` — tools the constraints doc didn't mention. The doc had gone stale relative to GlassFrog **API v5**.

## Guidance

**Ground-truth the live MCP tool surface against the repo's API-constraints reference before designing reads on top of it.** A single live probe settled the design and corrected the doc. The v5 facts, verified against a real org (75 roles, 3+ levels deep):

- **`glassfrog_get_role_context(role_id)` is a single-call inherited-context bundle.** It returns the role (purpose, accountabilities, domains, skills, notes, projects, actions) plus a `governance` block:
  - `ancestor_roles` — the full chain **up to the Anchor Circle**, name + purpose + `parent_role_id` per level. This is the inherited purpose chain, resolved server-side.
  - `parent_role` — the immediate enclosing circle, with its `policies` as excerpts.
  - `org_rules` — the org's Constitution v5 sections.
  - `sibling_roles`.
- **`glassfrog_get_role_strategy(role_id)` resolves inheritance server-side** — returns the strategy `body` with `inherited: true` and `inherited_from_role_id` when it cascades from an enclosing circle. No manual walk.
- **`glassfrog_list_role_policies(role_id)` returns full policy bodies.** Policies are readable. (Policy *writes* remain impossible via API — that boundary is real.)
- **`get_role_tree` / `get_org_tree` go DOWN, not up** — descendants only. Ancestors come from `get_role_context.ancestor_roles`.
- **`glassfrog_get_me(include_roles: true)` is huge** (~114k characters in a 75-role org). Scope inherited loads to one resolved role; never bulk-load the roster.

Net: inherited context is a **1–2 call, single-role** load, not a hierarchy walk. "Cheap" and "complete" stopped being in tension.

## Why This Matters

The stale reference doc wasn't just incomplete — it was *load-bearing wrong*. It had made a whole feature look expensive (an N-call walk plus a user-prompt for unreadable policies), which is exactly the cost profile that got the work deferred. One unverified sentence in a reference file can misdirect an entire ideation: a downstream agent that trusts "policies are not exposed" designs around a constraint that doesn't exist, and the design it produces is more complex than reality requires. A fresh-context verifier even flagged the v5 tools as "not grounded in repo files" — correctly, because the repo's docs predated them. That absence *was* the gap; the live tool registry was the ground truth.

## When to Apply

- Any time a design decision rests on "the API can/can't read X" sourced from an in-repo reference rather than the live tool surface — probe first.
- Specifically for GlassFrog: prefer `get_role_context` over composing `get_role` + per-level `get_circle` calls for inherited context; prefer `get_role_strategy`'s `inherited` flag over reconstructing the cascade by hand.
- When an MCP server tracks a versioned upstream API (here, v5), treat a reference doc that names v3-era fields (`parent_circle_id`, `sub_circle_id`, `is_circle`) as a staleness signal.

## Examples

Stale reference (before — `glassfrog-api-constraints.md`):

```
### What Cannot Be Read
- Policies: GlassFrog policies are not exposed through the standard API.
- Cross-link relationships: ... the API does not provide a dedicated hierarchy endpoint.
```

Live v5 reality (after one probe):

```jsonc
// glassfrog_get_role_strategy(role_id) on a nested role:
{ "body": "Support the strategies of …",
  "inherited": true,
  "inherited_from_role_id": "role_c659…" }

// glassfrog_get_role_context(role_id).governance.ancestor_roles:
[ { "name": "Enterprise Architecture", "purpose": "Shape the corporation…" },
  { "name": "Market Applied Innovation", "purpose": "Deliver … to the marketplace" },
  { "name": "… Anchor Circle", "purpose": "Enabling the actualization…", "parent_role_id": null } ]

// glassfrog_list_role_policies(role_id) → full title + body per policy (readable)
```

Design consequence: the inherited-context load became `get_role_context` + `get_role_strategy` (2 calls, one role) instead of an N-level walk, and the reference doc was corrected in the same change (PR #37).
