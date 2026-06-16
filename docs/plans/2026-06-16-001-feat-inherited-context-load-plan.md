---
date: 2026-06-16
type: feat
issue: 34
origin: docs/brainstorms/2026-06-16-context-inherited-context-probe-requirements.md
---

# feat: Add opt-in inherited-context load to /holacracy:context (--inherited)

## Summary

Give `/holacracy:context` an opt-in `--inherited` flag that loads inherited Holacratic context — the enclosing-circle purpose chain to the Anchor Circle, parent-circle policies, and the role's inherited strategy — for a resolved role/circle. Without the flag the command's behavior is unchanged. The load logic lives in a new shared reference so the skill-side lazy path (#35) and cross-skill reuse (#36) can slot in later.

---

## Problem Frame

`/holacracy:context` resolves only positional context (identity + flat role roster). It never loads purpose, strategy, policies, or domains from enclosing circles, so any role work built on it is under-grounded — and `skills/shared/actor-and-role-resolution.md:73` already narrates "Strategy on file says…" as if inherited strategy were loaded when it is not. [ADR-0003](../adr/0003-glassfrog-tension-api-adoption.md) deliberately kept the command cheap (issue #17), so the fix must be additive and opt-in, not a default change. A live GlassFrog v5 probe (origin doc) settled the cost question: inherited context is a 1–2 call load, not a hierarchy walk.

---

## Requirements

Traces to origin `docs/brainstorms/2026-06-16-context-inherited-context-probe-requirements.md` (R5–R7) and issue #34.

- R1. A new flag `--inherited` on `/holacracy:context` loads inherited context for a resolved role/circle via `glassfrog_get_role_context(role_id)` plus `glassfrog_get_role_strategy(role_id)` — a 1–2 call ceiling (origin R5).
- R2. Without `--inherited`, the command's behavior and tool calls are byte-for-byte unchanged from today; the inherited path adds zero GlassFrog calls to the default (origin R6, ADR-0003).
- R3. The inherited load is scoped to a resolved role/circle, never the full roster (`get_me include_roles` is ~114k chars — origin F5).
- R4. The load surfaces the ancestor purpose chain to the Anchor Circle, parent-circle policy excerpts, and inherited strategy (with its `inherited_from` source). Per-ancestor full policy bodies are out of scope (deferred to #35).
- R5. GlassFrog-disconnected behavior matches the sibling convention: the command names the limitation and asks the user to declare context, mirroring `commands/context.md`'s existing fallback and `commands/tactical.md`'s defer-to-skill pattern.
- R6. The load procedure lives in a reusable shared reference so #35 (skill-side lazy load) and #36 (cross-skill reuse) reuse it rather than re-implementing traversal.
- R7. An ADR records the cheap-default / opt-in-deep decision; the plugin version is bumped.

---

## Key Technical Decisions

- **Trigger: an explicit `--inherited` flag now, with a shared-procedure seam for the lazy path later.** The flag is discoverable and deterministic and keeps the default unchanged. The load logic is extracted into a shared reference (not inlined in the command) so #35 can later have the role skills invoke the same procedure lazily. Resolves origin Q2.
- **Payload: `get_role_context` + `get_role_strategy` (2-call ceiling).** `get_role_context` returns the ancestor purpose chain + parent-policy excerpts + org rules in one call; `get_role_strategy` returns the inherited strategy pre-resolved (`inherited: true`, `inherited_from_role_id`). Full per-ancestor policy bodies (`list_role_policies` per ancestor, binding-constraints filtering) are deferred to #35. Resolves origin Q1.
- **Placement: a new shared reference `skills/shared/inherited-context-procedure.md`.** Matches the repo's existing shared-reference convention (`actor-and-role-resolution.md`, `authority-boundaries.md` loaded via relative paths). `commands/context.md` points to it; #35 will have the skills embed it.
- **ADR-0004** records the decision. Next free number confirmed against `docs/adr/` (0001–0003 exist) and open PRs.
- **Versioning:** bump `.claude-plugin/plugin.json` 0.4.0 → 0.5.0 (new command capability changes the bundle surface). Commands carry no version frontmatter; the role skills are untouched by #34, so their `version:` fields stay.

---

## High-Level Technical Design

The default path is untouched; `--inherited` adds a scoped, post-resolution load for the focused role.

```mermaid
flowchart TD
    A["/holacracy:context [circle] [--inherited]"] --> B{--inherited present?}
    B -->|no| C["Default path UNCHANGED:\nget_me + list_my_roles + scheduled routines"]
    B -->|yes| D[Resolve to a single role/circle\nper actor-and-role-resolution.md]
    D --> E{GlassFrog connected?}
    E -->|no| F[Name the limitation;\nask user to declare inherited context\n(sibling fallback)]
    E -->|yes| G["get_role_context(role_id)\n→ ancestor purpose chain to Anchor,\nparent policies (excerpts), org rules"]
    G --> H["get_role_strategy(role_id)\n→ inherited strategy + inherited_from"]
    H --> I[Render 'Inherited governance context'\nsection beneath the role roster]
    C --> Z[Output for the user to read]
    F --> Z
    I --> Z
```

*Directional — the prose in the units below is authoritative.*

---

## Implementation Units

### U1. Shared inherited-context procedure

**Goal:** Create the reusable procedure that loads and renders inherited context for a resolved role, so the command and (later) the skills share one implementation.

**Requirements:** R1, R3, R4, R5, R6.

**Dependencies:** none.

**Files:**
- `skills/shared/inherited-context-procedure.md` (new)

**Approach:** Document, in the same instructional style as `skills/shared/actor-and-role-resolution.md`, a procedure that assumes a single resolved `role_id` and: (1) calls `glassfrog_get_role_context(role_id)`, reading `governance.ancestor_roles` (name + purpose to the Anchor Circle), `governance.parent_role.policies` (excerpts), and `governance.org_rules`; (2) calls `glassfrog_get_role_strategy(role_id)` and surfaces the body plus, when `inherited: true`, the `inherited_from_role_id` source; (3) renders an "Inherited governance context" block — enclosing purpose chain, inherited strategy, parent-policy titles+excerpts. Specify the disconnect fallback (name the limitation; ask the user to declare inherited context) matching `commands/context.md`. State the scope rule (one resolved role; never `get_me include_roles`) and the explicit non-goal (no per-ancestor `list_role_policies` expansion — that is #35). Note the v5 tool names and that `get_role_tree`/`get_org_tree` are descendant-only (so ancestors come from `get_role_context`).

**Patterns to follow:** `skills/shared/actor-and-role-resolution.md` (structure, step framing, "When GlassFrog Data Is Unavailable" section); the corrected `skills/holacratic-ai-governance/references/glassfrog-api-constraints.md` (tool names, payload shapes).

**Test scenarios:**
- Happy path (deep org): given a role nested 3+ levels, the procedure as written yields the full ancestor purpose chain to the Anchor Circle, the parent-policy excerpts, and the inherited strategy with its source — verified by a dry run against the live GlassFrog (e.g. Product Architecture, as in the origin probe).
- Edge (flat/solo org): given a role one level under the Anchor, the rendered chain is short but well-formed (no error, no empty-section noise).
- Edge (no inherited strategy): given a role whose `get_role_strategy` returns "no strategy set", the block omits strategy gracefully rather than rendering a stub.
- Error (disconnected): given GlassFrog unavailable, the procedure names the limitation and asks the user to declare context — no silent assumption.
- Test expectation: behavioral/dry-run verification (markdown procedure; no unit-test harness in this repo).

### U2. Wire `--inherited` into the command

**Goal:** Add the opt-in flag to `/holacracy:context` and delegate the load to U1, leaving the default path untouched.

**Requirements:** R1, R2, R5, R7.

**Dependencies:** U1.

**Files:**
- `commands/context.md`

**Approach:** Update the `argument-hint` frontmatter to `[circle name to focus on, optional] [--inherited]`. In the body, add an "Inherited context (opt-in)" subsection: when `$ARGUMENTS` contains `--inherited`, after resolving identity + roster, run the U1 procedure for the resolved/focused role and render its block beneath the existing roster; otherwise the existing flow is unchanged. Reaffirm in the Behaviour section that the default path adds no GlassFrog calls and that `--inherited` requires a resolvable role (if the actor named no circle and fills the target role in many circles, ask which — reuse the existing multi-match resolution). Point to `skills/shared/inherited-context-procedure.md` for the procedure, mirroring how the command already delegates to `actor-and-role-resolution.md`.

**Patterns to follow:** the existing `commands/context.md` "Behaviour" + "Full resolution procedure" delegation; `commands/tactical.md` disconnect handling (defer to the shared/skill path, do not re-handle inline).

**Test scenarios:**
- Invariant (default unchanged): given no `--inherited`, the command's described tool calls and output are identical to the pre-change version — diff shows only additive content.
- Happy path: given `/holacracy:context "Enterprise Architecture" --inherited`, the output appends the inherited-context block for that circle's resolved role.
- Edge (flag, no circle, single match): `--inherited` with no circle name but the actor fills the target role in exactly one circle → resolves silently and loads.
- Edge (flag, multi-match): `--inherited` with an ambiguous role → asks which circle before loading (no wasted call).
- Error (disconnected): `--inherited` while GlassFrog is down → the sibling fallback fires.
- Test expectation: behavioral/dry-run verification.

### U3. ADR-0004 — opt-in inherited context

**Goal:** Record the cheap-default / opt-in-deep decision and its relationship to ADR-0003 / issue #17.

**Requirements:** R7.

**Dependencies:** U1, U2 (decision is stable once the shape is set).

**Files:**
- `docs/adr/0004-opt-in-inherited-context-in-context-command.md` (new)

**Approach:** Use the repo's adr-tools template (mirror `0003-glassfrog-tension-api-adoption.md`). Status Accepted. Context: the inherited-context gap, the ADR-0003 "keep cheap" stance, the v5 probe finding (single-call bundle). Decision: load inherited context only behind `--inherited`, scoped to a resolved role, via `get_role_context` + `get_role_strategy`, with the procedure in a shared reference. Consequences: default stays cheap; #35/#36 extend the same seam; per-ancestor policy expansion deferred. Supersedes/relates: refines the ADR-0003 deferral for the inherited-context case (distinct from #17's tension-surfacing case).

**Patterns to follow:** `docs/adr/0003-glassfrog-tension-api-adoption.md` structure and the "What this ADR does NOT do" section.

**Test scenarios:** Test expectation: none — decision record, no behavior. Verify the next-number reservation against `docs/adr/` immediately before writing (no 0004 collision).

### U4. Version bump

**Goal:** Reflect the new command capability in the plugin version.

**Requirements:** R7.

**Dependencies:** U2.

**Files:**
- `.claude-plugin/plugin.json`

**Approach:** Bump `version` 0.4.0 → 0.5.0 (minor: additive command capability changes the bundle surface). Leave role-skill `version:` fields unchanged — #34 does not modify their behavior. Let the existing release-please flow handle the changelog/tag; do not hand-edit release artifacts.

**Patterns to follow:** the version field in `.claude-plugin/plugin.json`; `CLAUDE.md` Versioning guidance.

**Test scenarios:**
- Verification: `claude plugin validate` passes (the repo's manifest CI gate) with the bumped version and the new files present.
- Test expectation: none — metadata change; covered by the validate gate.

---

## Scope Boundaries

### In scope
- The `--inherited` flag, its load behavior, the disconnect fallback, the shared procedure, ADR-0004, and the version bump.

### Deferred to Follow-Up Work
- **#35** — relocate/extend the load through the shared reference so the role skills embed it (lazy path), apply the binding-constraints payload filter (per-ancestor `list_role_policies`, Art 4.2/2.3.3), and reconcile the `actor-and-role-resolution.md:73` narration. This plan creates the shared procedure #35 builds on.
- **#36** — reuse a loaded inherited-context result across role skills in one session (declaration block → session ledger).

### Outside scope
- Changing the default `/holacracy:context` behavior. Any policy/governance *write* path.

---

## Open Questions (Deferred to Implementation)

- The exact rendered shape of the "Inherited governance context" block (ordering, how many ancestor levels to show before summarizing) — settle while writing U1 against real output; the origin example shape is the starting point.
- Whether `--inherited` should also accept a depth bound (e.g. `--inherited=2`) — default to full-chain-to-Anchor for now; add a bound only if real output is unwieldy.

---

## Sources & Research

- Origin requirements: [docs/brainstorms/2026-06-16-context-inherited-context-probe-requirements.md](../brainstorms/2026-06-16-context-inherited-context-probe-requirements.md)
- Live GlassFrog v5 probe (this session): `get_role_context`, `get_role_strategy`, `list_role_policies`, `get_role_tree` against org "Integral Productivity".
- Corrected API reference: [skills/holacratic-ai-governance/references/glassfrog-api-constraints.md](../../skills/holacratic-ai-governance/references/glassfrog-api-constraints.md) (PR #37).
- [ADR-0003](../adr/0003-glassfrog-tension-api-adoption.md) and issue #17 (the "keep cheap" stance).
- Related issues: #35, #36 (depend on this load path).
