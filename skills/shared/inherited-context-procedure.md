# Inherited Context Procedure — Shared Reference

This document is shared across holacracy skills and commands. It defines how to load and render a role's **inherited context** — the governance that flows down from the enclosing circles: the enclosing-circle purpose chain to the Anchor Circle, the parent circle's policies, and the role's inherited strategy.

Load this when an opt-in inherited-context load is requested — today via `/holacracy:context --inherited`; in future via a role skill that needs the enclosing-circle frame before doing role work (see issue #35).

It assumes a **single already-resolved role** (`role_id`). Resolution of *which* role/circle the actor is operating from is the job of [`actor-and-role-resolution.md`](actor-and-role-resolution.md) — run that first; this procedure starts once one role is settled.

---

## Why this is a separate, opt-in load

The base `/holacracy:context` resolution is deliberately cheap (identity + role roster; see [ADR-0003](../../docs/adr/0003-glassfrog-tension-api-adoption.md)). Inherited context is **not** loaded by default — it is requested explicitly. Two reasons:

1. **Cost.** Loading every role's context eagerly is large (`glassfrog_get_me(include_roles: true)` returns ~114k characters in a 75-role org). Inherited context is therefore always scoped to **one resolved role**, never the whole roster.
2. **Relevance.** Inherited purpose and strategy matter when the actor is about to interpret governance or prioritize work (Constitution v5 Art 4.2, Art 2.3.3) — not for a quick "which hats do I wear?" check.

The load is **1–2 GlassFrog calls** for the resolved role. It does not walk the hierarchy by hand — the v5 API resolves the ancestor chain and inherited strategy server-side.

---

## The Procedure

### Step 1 — Load the role's governance bundle

Call `glassfrog_get_role_context(role_id)`. A single call returns the role plus a `governance` block. Read these fields:

- `governance.ancestor_roles` — the enclosing chain **up to the Anchor Circle**, each level with `name` + `purpose` + `parent_role_id`. This is the inherited purpose chain; the API returns it directly (you do **not** call `get_role_tree`/`get_org_tree` for it — those return *descendants*, not ancestors).
- `governance.parent_role` — the immediate enclosing circle, including its `policies` (as **excerpts**).
- `governance.org_rules` — the org's Constitution sections (preamble, structure, duties, tactical, distributed authority, governance process), with summaries.
- `governance.sibling_roles` — peer roles in the same circle (context for who else shares the circle).

### Step 2 — Load the inherited strategy

Call `glassfrog_get_role_strategy(role_id)`. The response carries the strategy `body`, and when the strategy cascades from an enclosing circle, `inherited: true` plus `inherited_from_role_id`. The cascade is **pre-resolved by the API** — surface the body and name its source; do not reconstruct it from the ancestor chain.

A role with no strategy set returns a plain "no strategy set" message — that is a normal state, not an error.

### Step 3 — Render the "Inherited governance context" block

Append a block beneath the existing role roster. Suggested shape:

```
**Inherited governance context — [Role Name]**

Enclosing purpose (sub-circle → Anchor):
- [Parent Circle]: [purpose]
- [Grandparent Circle]: [purpose]
- … up to [Anchor Circle]: [purpose]

Inherited strategy: [strategy body]
  (inherited from [inherited_from role name], or "set on this role" / "none on record")

Policies constraining the parent circle ([Parent Circle]):
- [Policy title] — [excerpt]
- …

Constitution: v[constitution_version] on file ([N] sections).
```

Keep it scannable. For a deep org, show the full chain to the Anchor; if a chain is unusually long, summarize the middle levels rather than truncating the Anchor (the Anchor's purpose is the most load-bearing). Omit a sub-block cleanly when its source is empty (no strategy → drop the strategy line; no parent policies → drop the policies sub-block) rather than rendering an empty stub.

---

## Scope and Non-Goals

- **One resolved role per load.** Never call `glassfrog_get_me(include_roles: true)` to bulk-load — that is the expensive path this procedure exists to avoid.
- **Parent-policy excerpts only.** This procedure surfaces the immediate parent circle's policy excerpts from `get_role_context`. It does **not** call `glassfrog_list_role_policies` per ancestor to expand full policy bodies, and does not yet apply a binding-constraints filter (which policies actually bind the focal role). That refinement — full bodies + Art 4.2/2.3.3 binding filter — is tracked in issue #35.
- **No cross-skill caching here.** Reusing a loaded result across skills in one session is issue #36; this procedure performs the load each time it is invoked.

---

## When GlassFrog Data Is Unavailable

Mirror the disconnect convention used elsewhere in the plugin ([`commands/context.md`](../../commands/context.md) asks the user to declare context; [`commands/tactical.md`](../../commands/tactical.md) defers disconnect handling to the skill rather than re-handling it inline):

1. **Name the limitation:** "GlassFrog isn't connected, so I can't load your enclosing-circle context. I'll work from what you tell me."
2. **Ask the actor to declare it:** "What is your enclosing circle's purpose and strategy, and are there super-circle policies that constrain this role?"
3. **Do not silently assume** the inherited context — treat user-declared governance as asserted-not-verified.

---

## Tool Reference (GlassFrog API v5)

| Tool | Returns |
|---|---|
| `glassfrog_get_role_context(role_id)` | Role + `governance`: `ancestor_roles` (to Anchor), `parent_role` with policy excerpts, `sibling_roles`, `org_rules` |
| `glassfrog_get_role_strategy(role_id)` | Strategy body + `inherited` / `inherited_from_role_id` (cascade pre-resolved) |
| `glassfrog_list_role_policies(role_id)` | Full policy bodies for a role (used by #35, not this procedure) |
| `glassfrog_get_role_tree` / `glassfrog_get_org_tree` | **Descendants** only — not used for ancestor traversal |

See [`../holacratic-ai-governance/references/glassfrog-api-constraints.md`](../holacratic-ai-governance/references/glassfrog-api-constraints.md) for the full read/write capability map.
