---
description: Resolve and display the actor's current Holacracy context (identity + roles across circles), optionally focusing on one circle, optionally loading inherited governance
argument-hint: "[circle name to focus on, optional] [--inherited]"
---

# /holacracy:context

Resolve and display the actor's Holacracy context for this session.

## What this command does

1. **Resolves actor identity** via `glassfrog_get_me`. The actor is either the human authenticated to GlassFrog or, when this command is invoked from a scheduled routine, the AI agent declared in the routine's prompt.
2. **Loads the actor's role roster** via `glassfrog_list_my_roles` (or the appropriate filtered query for an actor other than yourself).
3. **Reports the resolved context** in a structured roster: each circle the actor participates in, with the roles they fill in that circle.
4. **If an argument was provided** ($ARGUMENTS), narrows the report to that circle and lists every role the actor fills there. Also notes which Core Role positions (Facilitator, Secretary, Lead Link, Rep Link) the actor holds in that circle.
5. **Reports operating constraints**: whether GlassFrog is connected, whether any role the actor fills has been retired or modified recently, whether any scheduled routines for this actor are currently registered with `mcp__scheduled-tasks__list_scheduled_tasks` (filtered to tasks whose title starts with `holacracy/`).

## Inherited context (opt-in `--inherited`)

By default this command loads **only** positional context (the three calls above) and adds no further GlassFrog calls — keep it that way.

When `$ARGUMENTS` contains the `--inherited` flag, after the roster is resolved, additionally load the **inherited governance context** for the focused role and render it beneath the roster:

- `--inherited` requires a single resolved role. If the actor named a circle (the other argument), use it. If the actor fills the target role in exactly one circle, resolve silently. If the actor fills it in several circles, ask which one **before** making any inherited-context call — don't load against an unresolved role.
- The load is the procedure in `skills/shared/inherited-context-procedure.md`: `glassfrog_get_role_context(role_id)` (enclosing purpose chain to the Anchor Circle, parent-circle policy excerpts, org rules) plus `glassfrog_get_role_strategy(role_id)` (inherited strategy, pre-resolved). A 1–2 call load, scoped to the one resolved role — never `glassfrog_get_me(include_roles: true)`.
- Without `--inherited`, none of these calls fire.

## Behaviour

- If GlassFrog is not connected, ask the user to declare the context: "I don't have live GlassFrog data. Whose role should I treat as the basis for this session?" When `--inherited` was requested while disconnected, follow the same fallback the inherited-context procedure defines (name the limitation, ask the actor to declare their enclosing-circle purpose, strategy, and constraining policies).
- If `$ARGUMENTS` names a circle the actor does not fill any role in, say so explicitly and offer Observer mode.
- If the actor fills the same role in many circles (e.g., Lead Link in 5 circles in a solo-operator org), summarize counts rather than enumerating every line.
- Output is for the user to read and confirm; do not advance into any role-specific work from this command.

## Full resolution procedure

The detailed procedure -- what to do when an actor fills multiple matches, how to handle stale governance state, how scheduled routines encode their identity at creation time -- lives in `skills/shared/actor-and-role-resolution.md`. Reference that file when explaining any nuance.

The `--inherited` load procedure (what `get_role_context` and `get_role_strategy` return, how to render the inherited block, the disconnect fallback, and what is intentionally out of scope) lives in `skills/shared/inherited-context-procedure.md`.

## Example output shape

```
**Actor**: Kraig Parkinson (person, GlassFrog id 12345)
GlassFrog connected. Roles loaded.

**Roles by circle:**

- General Company Circle
  - Lead Link
  - Facilitator

- Operations Circle
  - Secretary
  - Engineering Lead

- Marketing Circle
  - Rep Link (linking to General Company Circle)

**Active scheduled routines (3):**
- holacracy/secretary/pre-tactical-prep/operations-circle (fires Sundays 18:00)
- holacracy/lead-link/quarterly-strategy-review/general-company-circle (fires quarterly)
- holacracy/rep-link/pre-enclosing-circle-prep/marketing-circle (fires Tuesdays 09:00)

Tell me which scope you want to work in, or I'll resolve it when you describe the task.
```
