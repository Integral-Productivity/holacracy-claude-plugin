---
artifact_contract: ce-unified-plan/v1
artifact_readiness: requirements-only
product_contract_source: ce-brainstorm
date: 2026-07-20
tracks:
  project: "GlassFrog Project Triage (layered rollout) — GitHub Project #41"
  issues: ["#75"]
  ideation: "docs/ideation/2026-07-20-glassfrog-project-triage-ideation.html"
  phase1_plan: "docs/plans/2026-07-20-001-feat-review-project-panel-plan.md"
---

# GlassFrog Project Triage — Phase 2: `/holacracy:capture-project` guardrail - Plan

## Goal Capsule

- **Objective.** Stop under-specified projects at the source: a capture flow that helps a role-filler state a project as an outcome with a first next-action *as they file it*, so the backlog fills with actionable work instead of thin stubs.
- **Product authority.** Kraig Parkinson (governance-champion + primary maintainer).
- **Open blockers.** None. Depends on the shipped rubric `skills/shared/project-well-formedness.md` (on main).

## Product Contract

### Problem

Thin projects exist because they get *filed* thin. `/holacracy:review-project` (Phase 1, the belt) cleans them up after the fact, but the systemic fix is at intake — the "lifestyle change" layer. A capture surface that gently insists on a well-formed outcome + a next-action turns the moment of filing into the moment of getting it right, and models good project form while doing so.

### Primary actor

A role-filler capturing a new project on a role they fill — new to Holacracy or just moving fast — who would otherwise file an activity-shaped stub with no next step.

### Desired outcome

Running `/holacracy:capture-project` (optionally with the project text inline) produces a well-formed project on the right role: outcome-framed, with a first next-action, filed after a single per-item confirmation — with the missing elements taught, not enforced.

### In scope (Phase 2)

1. **A create-flow command**, twin of `/holacracy:capture-tension`: accept optional `$ARGUMENTS` (project text) and converse to fill gaps; resolve the owner role via `skills/shared/actor-and-role-resolution.md`; draft; per-item confirm; write. Draft-and-confirm, never auto-file.
2. **Gate on the shipped rubric, Family A only** (outcome-framed / has a first next-action / clear owner role). Loaded from `skills/shared/project-well-formedness.md`.
3. **Soft-gate behaviour:** name any missing Family-A element with a drafted fix (an outcome reframe, a first next-action, an owner clarification) and *teach* it — but file whatever the user confirms, even if still imperfect. Never hard-block; never push the user to the GlassFrog UI.
4. **Writes (additive only):** `glassfrog_create_role_project(role_id, description, status: "current")`, then `glassfrog_create_action(role_id, description, parent_project_id: <new project>, status: "current")` for the confirmed first next-action. Trust returned ids (no list-back).
5. **Light goal-alignment nudge:** after filing, if the owner role has goals (`glassfrog_list_role_goals`), offer a one-line skippable option to link the project to one (`glassfrog_link_goal_supporting_project`). If the role has zero goals, skip silently.

### Out of scope (Phase 2)

- Scope-authority and assignment-fit checks — `/holacracy:review-project`'s job (heavier; often premature at a project's birth).
- Reviewing, reframing, or archiving *existing* projects (review-project) and stalled-project sweeping (#76).
- Any hard block or forced-perfection gate.
- Auto-filing, or filing without a per-item confirmation.

### Key decisions

1. **Soft-gate, not hard-gate.** Teach the missing element and offer a fix, but file what the user confirms. _(session-settled 2026-07-20 — chosen over a next-action hard floor and strict Family A: preserves capture as cheap and keeps users out of the UI; developmental nudge over enforcement.)_
2. **Well-formed at capture; a light goal nudge; authority deferred.** Gate Family A only, plus an optional skippable goal-link; leave scope-authority/assignment to review-project. _(session-settled 2026-07-20 — chosen over well-formed-only and full-well-placed: plants the goal habit early without the friction of a full placement review at birth.)_
3. **Twin of `/holacracy:capture-tension`.** Reuse its create-flow shape (optional args + converse, resolve owner role, draft-and-confirm, never auto-file). _(carried from Phase 1 / the shipped tension lifecycle.)_
4. **Additive writes only, project-scoped.** `create_role_project` then `create_action` with `parent_project_id`; optional `link_goal_supporting_project`. New projects default to `status: "current"` (closed enum, verified live). _(carried.)_

### Requirements

- **R1.** Accept optional `$ARGUMENTS` as the project text; converse to fill missing elements.
- **R2.** Resolve the owner role via `skills/shared/actor-and-role-resolution.md`; if ambiguous, ask.
- **R3.** Apply rubric Family A; for each missing element, present a drafted fix and a one-line teaching of *why* it matters.
- **R4.** Soft-gate: file whatever the user confirms; never hard-block. If the user files something still activity-framed, that's their call — the teaching happened.
- **R5.** File additively: `create_role_project(role_id, description, status: "current")`, then `create_action(role_id, description, parent_project_id, status: "current")` for the confirmed first next-action. Trust returned ids.
- **R6.** After filing, if `list_role_goals` returns goals, offer a skippable goal-link (`link_goal_supporting_project(goal_id, project_id)`); skip silently when there are none.
- **R7.** Draft-and-confirm, per-item; no auto-file; the user can abort at any point.
- **R8.** Surface write failures honestly; never swallow them.
- **R9.** Degrade gracefully if a needed read/write tool is unavailable (name the constraint; file what can be filed).

### Success criteria / acceptance signals

- Filing an activity-shaped stub surfaces the outcome + next-action gaps with drafted fixes, then files on confirm.
- A confirmed project creates both the project (`create_role_project`) and its first next-action (`create_action` with `parent_project_id`).
- The goal nudge appears only when the owner role has goals, and is skippable.
- No project is filed without a per-item human confirmation.
- The flow never hard-blocks a determined user.

### Outstanding questions (for `ce-plan`)

- Whether the flow is inline in the command or dispatches a `project-capture` subagent (twin of `tension-capture`).
- The exact conversational sequence for eliciting outcome + first next-action from a thin start.
- Whether `create_role_project`'s default status is honored by org config or should be set explicitly to `current`.

### Grounding

- **Depends on:** `skills/shared/project-well-formedness.md` (Family A — shipped in Phase 1, on main).
- **Model on:** `commands/capture-tension.md`, `agents/tension-capture.md`, `skills/shared/tension-capture-flow.md` (the create-flow twin).
- **Writes:** `glassfrog_create_role_project`, `glassfrog_create_action` (with `parent_project_id`), `glassfrog_link_goal_supporting_project` — all verified live. New-project `status` enum default `current`.

## Next step

`ce-plan` on this artifact for the HOW (command/subagent structure, the elicitation flow, the confirmation shape). On plan approval, #75 graduates `needs-triage` → `ready-for-human`.
