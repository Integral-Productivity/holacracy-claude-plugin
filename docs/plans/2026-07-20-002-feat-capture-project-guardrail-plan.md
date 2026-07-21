---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-brainstorm
execution: code
date: 2026-07-20
deepened: 2026-07-20
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

**Product Contract preservation:** Product Contract unchanged. `ce-plan` added the Planning Contract (KTDs, Implementation Units, HTD, Verification Contract, Definition of Done) below the existing Product Contract; the WHAT above the `## Planning Contract` divider is carried verbatim from `ce-brainstorm`.

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

### Grounding

- **Depends on:** `skills/shared/project-well-formedness.md` (Family A — shipped in Phase 1, on main).
- **Model on:** `commands/capture-tension.md`, `agents/tension-capture.md`, `skills/shared/tension-capture-flow.md` (the create-flow twin).
- **Writes:** `glassfrog_create_role_project`, `glassfrog_create_action` (with `parent_project_id`), `glassfrog_link_goal_supporting_project` — all verified live. New-project `status` enum default `current`.

---

## Planning Contract

*Enriched by `ce-plan` 2026-07-20. Everything above this divider is the `ce-brainstorm` Product Contract (the WHAT), preserved verbatim. Everything below is the HOW.*

### Planning summary

Build a create-flow **twin of `/holacracy:capture-tension`** as three new artifacts — a thin command dispatcher, a `project-capture` subagent, and a shared `project-capture-flow.md` spec (the single source of truth the subagent implements) — plus a wire-up unit (README, CLAUDE.md, `plugin.json` version + description). No executable code: these are Claude Code plugin markdown surfaces. Verification is by scenario walkthrough and cross-reference integrity, not unit tests. The write chain, elicitation sequence, and soft-gate behaviour are grounded against the live GlassFrog tool schemas (inspected 2026-07-20).

### Depth & risk

**Standard.** Bounded feature, four implementation units, all product forks session-settled. Low code risk (markdown/prompt surfaces, additive GlassFrog writes only, per-item human confirmation before every write). The one elevated concern is *behavioural correctness of the write chain* — that the action attaches to the just-created project — which the HTD and U1/U2 test scenarios pin down.

### Key Technical Decisions

**KTD1 — Three-artifact twin (command → subagent → shared flow spec).** Resolves the plan's outstanding question "inline vs. subagent". `capture-tension` is not one file: it is `commands/capture-tension.md` (thin dispatcher) → `agents/tension-capture.md` (subagent) → `skills/shared/tension-capture-flow.md` (the B-flow spec both the subagent and ambient detection implement). A faithful twin reproduces that shape: `commands/capture-project.md` → `agents/project-capture.md` → `skills/shared/project-capture-flow.md`. The shared flow doc is the single source of truth; the command and subagent reference it rather than restating it. _(session-settled: user-directed — chosen over an inline-in-command flow: the invoking directive named all three `capture-tension` artifacts as the model, and the shared-spec pattern keeps every capture surface — command, future ambient detection, future stalled-sweep — reading one flow definition.)_

**KTD2 — Soft-gate on rubric Family A: teach + drafted fix, then file what the user confirms.** The subagent runs Family A (A1 outcome-framed, A2 has-a-next-action, A3 clear-owner) internally against `skills/shared/project-well-formedness.md`. For each *missing* element it surfaces a drafted fix plus a one-line teaching of why it matters — never an interrogation, never a hard block. A2 is special: at capture time the project does not yet exist, so "has a next-action" is elicited as *the first next-action to file alongside the project*, not checked via `list_role_projects`. _(session-settled: user-directed — chosen over a next-action hard floor and strict Family A gate: developmental nudge over enforcement; keeps capture cheap and users out of the GlassFrog UI.)_

**KTD3 — Additive write chain with explicit `status: "current"`; trust returned ids.** On confirmation: (1) `glassfrog_create_role_project(role_id, description, status: "current")` → returns a `proj_<32hex>` id; (2) `glassfrog_create_action(role_id, description, parent_project_id: <that proj id>, status: "current")` for the confirmed first next-action. The action's `parent_project_id` is what attaches it to the project (satisfying rubric A2). `status` is set **explicitly** — the live `create_role_project` schema documents its default as "depends on org config", so relying on an unknown org default is unsafe; `current` is a member of the closed enum `archived | cancelled | completed | current | scheduled | someday | waiting` (verified live 2026-07-20). This resolves the plan's outstanding question "is the default honored or should it be set explicitly". Do **not** list-back to verify; the create response id is the only reliable same-session confirmation (mirrors the tension-capture caveat). _(session-settled: user-directed, schema-confirmed — chosen over trusting the org-config default: explicit intent beats an unknown default.)_

**KTD4 — Light, skippable goal nudge, post-file, only when goals exist.** After a successful file, call `glassfrog_list_role_goals(role_id)`. If it returns ≥1 goal, offer a one-line skippable prompt to link the new project to one via `glassfrog_link_goal_supporting_project(goal_id, project_id)`. If zero goals, skip **silently** — no "this role has no goals" noise. Scope-authority and assignment-fit stay out of scope (review-project's job). _(session-settled: user-directed — chosen over well-formed-only and full-well-placed: plants the goal habit early without a full placement review at a project's birth.)_

**KTD5 — Constitutional safeguard: draft-and-confirm, per-item, never auto-file, never batch.** Carried verbatim from the tension lifecycle. No `create_role_project` / `create_action` / `link_goal_supporting_project` call fires without an explicit per-item human confirmation. One project per invocation.

**KTD6 — Do not edit `skills/shared/project-well-formedness.md` this session (shared-file conflict discipline).** That rubric carries a `*(Planned)* /holacracy:capture-project` pointer that would ideally flip to shipped when this lands — but the file is READ-ONLY this session (a sibling session may own the shipped project surfaces). The pointer flip is **deferred to follow-up** rather than risk a concurrent-edit conflict. Loading the rubric read-only is unaffected. _(project-constraint — from the invoking conflict-discipline directive.)_

### High-Level Technical Design

#### The capture flow (soft-gate elicitation → confirm → write → nudge)

```mermaid
flowchart TD
    A["/holacracy:capture-project [text?]"] --> B[Dispatch project-capture subagent]
    B --> C{Project text given?}
    C -- no --> D["Ask: what outcome do you want to move toward?"]
    C -- yes --> E[Resolve owner role<br/>actor-and-role-resolution.md]
    D --> E
    E --> F["Run rubric Family A internally<br/>A1 outcome · A2 next-action · A3 owner"]
    F --> G{Any Family-A gap?}
    G -- yes --> H["For each gap: drafted fix + 1-line teaching<br/>(reframe / propose first next-action / clarify owner)"]
    G -- no --> I[Present per-item confirmation block]
    H --> I
    I --> J{File this?}
    J -- edit --> H
    J -- no --> K[Abort — nothing written — return]
    J -- yes --> L["create_role_project(role_id, description, status: current)<br/>→ proj_id"]
    L --> M["create_action(role_id, first-next-action,<br/>parent_project_id: proj_id, status: current)"]
    M --> N{list_role_goals(role_id) → any?}
    N -- yes --> O["Offer skippable link_goal_supporting_project(goal_id, proj_id)"]
    N -- none --> P[Skip silently]
    O --> Q[Acknowledge + return structured result]
    P --> Q
    L -- error --> R[Surface error honestly · draft preserved · offer retry]
    M -- error --> R
```

*Directional guidance for review — not implementation specification.*

#### The write chain (why order matters)

The action **cannot** attach to the project until the project id exists. `create_role_project` must complete and return its `proj_<32hex>` id *before* `create_action` is called, because `parent_project_id` is the attachment mechanism that satisfies rubric A2 (has-a-next-action). A failure at step 1 aborts step 2 (no orphan action); a failure at step 2 leaves a filed project with its gap surfaced honestly to the user (offer a retry of just the action).

### Output Structure

```
holacracy-claude-plugin/
├── commands/
│   └── capture-project.md          NEW — thin dispatcher (twin of capture-tension.md)
├── agents/
│   └── project-capture.md          NEW — the capture subagent (twin of tension-capture.md)
├── skills/shared/
│   └── project-capture-flow.md     NEW — the P-flow spec (single source of truth)
├── README.md                       MODIFIED — surface the command + agent + shared ref
├── CLAUDE.md                       MODIFIED — note the new shared reference & its loaders
└── .claude-plugin/plugin.json      MODIFIED — version bump + description
```

---

## Implementation Units

### U1. `skills/shared/project-capture-flow.md` — the P-flow spec (single source of truth)

**Goal.** Author the canonical capture flow that the subagent implements, mirroring `skills/shared/tension-capture-flow.md`'s structure and voice. This is where the elicitation sequence, soft-gate behaviour, write chain, and goal nudge are specified once.

**Requirements.** R1, R3, R4, R5, R6, R7, R8, R9. Implements KTD2, KTD3, KTD4, KTD5.

**Dependencies.** None (reads the shipped rubric read-only).

**Files.** Create `skills/shared/project-capture-flow.md`.

**Approach.** Structure as a **P-flow** paralleling the tension B-flow's eight steps:

1. **Determine intent** — three entry points: explicit command (`/holacracy:capture-project`, optional `$ARGUMENTS`); *(future)* ambient detection of project-shaped statements; *(future)* stalled-sweep escalation. Only the explicit path ships now; name the others as the extension seam (twin of tension-capture-flow's three entries).
2. **Resolve owner role** — per `./actor-and-role-resolution.md`, target = any role the actor fills in the relevant circle; silent-when-one, ask-when-multiple, name-the-constraint-when-zero. Announce the resolved context.
3. **Elicit / complete the project** — if no text given, ask for the outcome first. Preserve the user's own words.
4. **Run rubric Family A internally, soft-gate** — load `./project-well-formedness.md`; check A1 (outcome-framed — the "Done when ___" test), A2 (a first next-action to file alongside — *elicited*, not list-checked, since the project doesn't exist yet), A3 (clear owner role). For each gap: present a **drafted fix** + a one-line teaching of why it matters. Never hard-block; the DoD-as-body-convention is available when an outcome needs an explicit acceptance note.
5. **Draft the project + first next-action** — outcome-framed description (≤2000 chars per schema); a concrete first next-action (≤2000 chars).
6. **Per-item confirmation block** — show owner role + role_id, project description, first next-action, and any teaching notes; `[y] file · [e] edit · [n] abort`. Loop on edit.
7. **File (additive write chain)** — `create_role_project(role_id, description, status: "current")` → capture `proj_id`; then `create_action(role_id, <first-next-action>, parent_project_id: proj_id, status: "current")`. Trust returned ids; no list-back. Surface any error honestly; draft preserved; offer retry.
8. **Goal nudge + acknowledge/return** — `list_role_goals(role_id)`; if goals, offer one skippable `link_goal_supporting_project`; if none, skip silently. Return a compact structured result (project id, action id, owner role + circle, goal-link status). Include a "When GlassFrog is not connected" section and a "What the flow does NOT do" section (no scope-authority/assignment checks, no existing-project review, no hard block, no batch), mirroring the tension flow doc.

**Patterns to follow.** `skills/shared/tension-capture-flow.md` (section shape, constitutional-safeguard callout, confirmation-block format, the "does NOT do" and "not connected" sections, the composes-with-other-surfaces table). Use repo-relative reference paths in prose (e.g. `./project-well-formedness.md`, `./actor-and-role-resolution.md`) as the tension flow doc does.

**Test scenarios (walkthrough, not code — this is a prompt spec).**
- *Activity-stub start:* description "Work on the onboarding guide" → A1 fires → drafted reframe "Onboarding guide published to the wiki" + teaching; A2 elicits a first next-action → both drafted → confirm → file. (Covers R3, R4.)
- *Well-formed start:* "Q3 pricing page shipped" with a stated next-action → no Family-A finding → straight to confirmation. (Covers R4 "silent when clean".)
- *Multiple owner roles:* actor fills two plausible roles in the circle → asks which. (Covers R2.)
- *Abort at confirmation:* `[n]` → nothing written. (Covers R7.)
- *Goal nudge present / absent:* role with ≥1 goal → skippable link offered; role with 0 goals → silent. (Covers R6.)
- *Write failure:* `create_role_project` errors → honest surface, draft preserved, retry offered; `create_action` errors after project filed → project reported, action retry offered. (Covers R8.)
- *GlassFrog absent:* name the constraint; offer a plain-text draft for manual entry; no fake role_id. (Covers R9.)

**Verification.** Reads as a peer of `tension-capture-flow.md`; a reviewer can trace each of R1–R9 to a step; all reference paths resolve; the write chain order and explicit `status: "current"` are unambiguous.

---

### U2. `agents/project-capture.md` — the capture subagent

**Goal.** The subagent that runs the P-flow end to end and returns a structured result, twin of `agents/tension-capture.md`.

**Requirements.** R1–R9. Implements KTD1, KTD2, KTD3, KTD4, KTD5.

**Dependencies.** U1 (implements the flow U1 specifies).

**Files.** Create `agents/project-capture.md`.

**Approach.** YAML frontmatter (`name: project-capture`, a `description:` that states trigger conditions — invoked by `/holacracy:capture-project`, *(future)* ambient project-language detection, *(future)* stalled-sweep escalation — and the never-auto-file / never-batch / per-project-confirmation contract; `model: inherit`). Body mirrors `tension-capture.md`: **Constitutional safeguard** (draft-and-confirm; no `create_role_project` / `create_action` / `link_goal_supporting_project` without explicit confirmation); **Canonical references** (load `skills/shared/project-capture-flow.md`, `skills/shared/project-well-formedness.md` Family A, `skills/shared/actor-and-role-resolution.md`, and `skills/holacratic-ai-governance/references/glassfrog-api-constraints.md` for the current call shapes and the no-list-back caveat); **Dispatch input** (project text, optional circle/role hint, dispatch source); **Operating procedure** stepping through the P-flow (resolve owner → soft-gate Family A → draft → confirm → write chain → goal nudge → return); **When GlassFrog is not connected**; **Boundaries you do not cross** (no governance change, no proposals, no existing-project review, no scope-authority/assignment ruling, no batch, one project per dispatch).

**Patterns to follow.** `agents/tension-capture.md` verbatim in structure and voice; repo-relative reference paths in prose.

**Test scenarios (walkthrough).**
- *Dispatch with inline text* → resolves owner, runs soft-gate, returns structured result on file.
- *Dispatch with no text* → asks for the outcome before proceeding.
- *Confirmation contract* → never calls a write tool before an explicit `[y]`.
- *Sensed second project mid-run* → does not batch; finishes/aborts current, surfaces the second to the dispatcher (mirrors tension-capture's tail behaviour).
- *Return payload* → includes project id, first-action id, owner role + circle, goal-link status.

**Verification.** Frontmatter `description` is trigger-shaped and discoverable; every P-flow step from U1 is represented; boundaries section forbids the out-of-scope checks; no write path lacks a confirmation gate.

---

### U3. `commands/capture-project.md` — the thin dispatcher

**Goal.** The slash-command surface, twin of `commands/capture-tension.md`: parse `$ARGUMENTS`, dispatch the `project-capture` subagent, surface its structured result.

**Requirements.** R1, R7. Implements KTD1, KTD5.

**Dependencies.** U2 (dispatches it).

**Files.** Create `commands/capture-project.md`.

**Approach.** Frontmatter (`description:` — one line stating it captures a well-formed project via draft-and-confirm, soft-gates on Family A, files additively; `argument-hint: [project text, optional]`). Body mirrors `capture-tension.md`: "What this command does" (parse `$ARGUMENTS` → dispatch subagent with the text + source `explicit command` → surface result), "Behaviour" (one project per invocation; honours the not-connected fallback; constitutional safeguard; no list-back), "When to use this vs other surfaces" (contrast with `/holacracy:review-project` — capture-time guardrail vs after-the-fact adversarial review — and with the *(future)* stalled-sweep), "What this command does NOT do" (no existing-project review, no scope-authority/assignment checks, no hard block, no batch, no delete).

**Patterns to follow.** `commands/capture-tension.md` structure; cross-link `/holacracy:review-project` and the rubric with markdown links.

**Test scenarios (walkthrough).**
- *Inline text* → seeds the subagent.
- *No args* → command still dispatches; subagent asks for the outcome.
- *Result surfacing* → command reports project id + owner + goal-link status, then returns to the original conversation.

**Verification.** `argument-hint` present; dispatch target is `project-capture`; the "does NOT do" list matches the out-of-scope boundary; cross-links resolve.

---

### U4. Wire-up — README, CLAUDE.md, `plugin.json`

**Goal.** Surface the new command, agent, and shared reference so the bundle advertises them; bump the plugin version for the new surface.

**Requirements.** Discoverability for R1 (the command must be findable). Implements the "update README + CLAUDE.md; bump plugin version" directive.

**Dependencies.** U1, U2, U3 (documents what they add).

**Files.** Modify `README.md`, `CLAUDE.md`, `.claude-plugin/plugin.json`.

**Approach.**
- **README.md** — add three lines in the existing `## What's included` subsections, styled like their neighbours: a `shared/project-capture-flow.md` line in the shared-references list; an `agents/project-capture.md` line in the agents list; a `/holacracy:capture-project` line in the commands list, contrasting it with `/holacracy:review-project` (capture-time guardrail vs after-the-fact review). Optionally note the capture→review pairing in `## What's coming` if a Phase-3 line already exists.
- **CLAUDE.md** — extend the "Shared reference" section note that currently lists `project-well-formedness.md` / `project-review-critics.md` to add `project-capture-flow.md` and name its loaders (the `/holacracy:capture-project` command and the `project-capture` subagent). Keep the load-path guidance intact.
- **plugin.json** — bump `version` `0.7.0` → `0.8.0` (a new command surface is a bundle-shape change per the repo's versioning policy); extend `description` to mention the capture-time project guardrail; add a `project-capture` keyword.

**Patterns to follow.** Existing README list-item phrasing (see the `/holacracy:review-project` and `/holacracy:capture-tension` lines); the existing CLAUDE.md "Shared reference" paragraph.

**Test scenarios.** `Test expectation: none — documentation + manifest metadata only.` Verification is structural (below).

**Verification.** README links to all three new files resolve; CLAUDE.md names the new shared ref and its loaders; `plugin.json` is valid JSON, `version` is `0.8.0`, `description`/`keywords` mention the capture guardrail. Sanity-check with `python3 -m json.tool .claude-plugin/plugin.json`.

---

## Verification Contract

No executable test suite exists for this plugin — the artifacts are Claude Code markdown surfaces (prompts/specs). "Done" is proven by:

1. **Cross-reference integrity.** Every repo-relative reference path in the three new files resolves to a real file. The `../shared/` vs `skills/shared/` conventions match the surrounding files' usage (agents/commands use repo-relative `skills/shared/...` in prose, as `tension-capture.md` does).
2. **Twin fidelity.** `project-capture-flow.md`, `project-capture.md`, and `capture-project.md` each read as structural peers of their tension twins (same sections, same constitutional-safeguard callout, same confirmation-block shape).
3. **Requirement trace.** R1–R9 each map to a step in U1's flow spec and are honoured by U2/U3.
4. **Write-chain correctness.** The spec unambiguously orders `create_role_project` → capture `proj_id` → `create_action(parent_project_id)`, with explicit `status: "current"` on both, and no list-back.
5. **Boundary correctness.** The out-of-scope checks (scope-authority, assignment-fit, existing-project review, hard block, batch, delete) are explicitly forbidden in each artifact's "does NOT do" / "boundaries" section.
6. **Manifest validity.** `plugin.json` parses; version bumped to `0.8.0`; description/keywords updated.
7. **Scenario walkthrough.** The seven U1 scenarios (activity-stub, well-formed, multi-role, abort, goal-nudge present/absent, write-failure, GlassFrog-absent) each have a traceable path through the flow.

*(A live end-to-end smoke — actually running `/holacracy:capture-project` against GlassFrog to file a real project + action — is an execution-time check for the human reviewer, not a plan-time gate. Note it as a suggested manual acceptance step in the PR.)*

## Definition of Done

- `skills/shared/project-capture-flow.md`, `agents/project-capture.md`, `commands/capture-project.md` created, each a faithful twin of its tension counterpart, honouring R1–R9 and KTD1–KTD5.
- Write chain, soft-gate Family-A behaviour, and skippable goal nudge specified exactly once (in U1) and referenced (not restated) by U2/U3.
- README, CLAUDE.md updated to surface all three; `plugin.json` bumped to `0.8.0` with updated description/keywords.
- All cross-reference paths resolve; `plugin.json` is valid JSON.
- `project-well-formedness.md` left untouched (KTD6); the `(Planned)` pointer flip captured as a follow-up.
- PR opened with `Closes #75`; the manual live-smoke acceptance step noted for the reviewer.

---

## Scope Boundaries

### In scope
The four units above.

### Deferred to Follow-Up Work
- **Flip the `*(Planned)*` pointer in `skills/shared/project-well-formedness.md`** to reflect that `/holacracy:capture-project` has shipped. Deferred this session to avoid a concurrent-edit conflict on a shared project surface (KTD6). File as a follow-up issue once the sibling sessions on the shipped project surfaces have landed.
- **Ambient project-language detection** (a `holacratic-ai-governance` pattern that offers capture when it hears project-shaped statements) — the second entry point named but not built in U1's flow spec.
- **Stalled-sweep escalation into capture** — the third entry point; belongs with #76.

### Outside this product's identity (Phase 2)
- Scope-authority and assignment-fit checks (review-project's job).
- Reviewing / reframing / archiving existing projects.
- Any hard block or forced-perfection gate; any auto-file or unconfirmed write.

## Open Questions (execution-time)

- **Exact `description` wording** for `plugin.json` and the README lines — resolved at write time against the neighbouring entries' voice; not a blocker.
- **Whether `## What's coming` gets a capture→review→sweep line** — include only if it reads naturally alongside the existing roadmap entries.

## Sources & Research

- **Model artifacts (read):** `commands/capture-tension.md`, `agents/tension-capture.md`, `skills/shared/tension-capture-flow.md`.
- **Rubric (read-only dependency):** `skills/shared/project-well-formedness.md` (Family A + status enum + DoD-as-body-convention).
- **Resolution procedure:** `skills/shared/actor-and-role-resolution.md`.
- **API constraints:** `skills/holacratic-ai-governance/references/glassfrog-api-constraints.md`.
- **Live tool schemas (inspected 2026-07-20):** `glassfrog_create_role_project(role_id, description, status?, parent_project_id?, …)` — status default "depends on org config", enum `archived|cancelled|completed|current|scheduled|someday|waiting`, returns `proj_<32hex>`; `glassfrog_create_action(role_id, description, status?, parent_project_id?, …)`; `glassfrog_link_goal_supporting_project(goal_id, project_id)`; `glassfrog_list_role_goals(role_id) → Page<Goal>`.
- **Registration model:** `plugin.json` auto-discovers `commands/` and `agents/`; no enumeration needed. Current version `0.7.0`.

## Next step

`ce-work` to build the four units in dependency order (U1 → U2 → U3 → U4), then open a PR that `Closes #75`.
