---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-brainstorm
execution: code
date: 2026-07-20
issue: 76
project: 41
phase: 3
---

# Stalled-Project Sweep - Plan

> **Product Contract preservation:** unchanged. Planning enriched this file with the Planning Contract, Implementation Units, and Verification Contract below; the Goal Capsule and Product Contract are as `ce-brainstorm` wrote them.

## Goal Capsule

- **Objective:** Ship `/holacracy:stalled-project-sweep` — a back-of-loop twin of `/holacracy:supersession-sweep` that surfaces GlassFrog **projects** with no movement and offers, per item, to **re-energize** (draft a next-action) or **archive** (`status:"archived"`, the soft-collapse over deletion). It is the "suspenders" layer of the project-triage effort (Project #41): the instrument on the strategy's project capture→movement ratio, catching the tail the capture guardrail (#75) and the review panel (#77) both miss.
- **Product authority:** Kraig Parkinson (founder). Two design decisions confirmed via picker 2026-07-20 (see Key Decisions).
- **Open blockers:** none. Issue #76 was "blocked by #73"; #73's rubric (`project-well-formedness.md`) has shipped and already reserves the `stale`/`blocked` states this sweep emits.

## Product Contract

### Problem & value

Projects enter GlassFrog easily and then go quiet. Nothing in the org notices: GlassFrog exposes **no last-touched timestamp** for a project, so a stalled project looks identical to an active one in any list view. The backlog silently accumulates outcomes nobody is moving. The capture guardrail keeps *new* projects well-formed; the review panel audits *form*; neither watches for *decay over time*. The sweep is the missing back-of-loop organ: it periodically asks "which of my projects have stopped moving?" and offers the two honest responses — restart it with a concrete next step, or archive it — one project at a time, never automatically.

### Primary actor

A role-filler (any actor) reviewing their own project backlog, or a Secretary/circle member sweeping a circle's projects. Same actor model as `/holacracy:review-project`.

### Core behavior (in scope)

**Surface (command):** `/holacracy:stalled-project-sweep [scope]`

1. **Resolve actor + roles** via `skills/shared/actor-and-role-resolution.md` (`glassfrog_get_me`, `glassfrog_list_my_roles`).
2. **Resolve scope** from `$ARGUMENTS` (default `mine`):
   - `mine` (default) — the actor's own `current` projects across every role they fill. (The twin defaults to `session`; projects have no session-file cache, so `mine` is the project analog.)
   - `recent` — same set, restricted to projects whose `created_at` is older than the age threshold (the corroboration signal, surfaced explicitly).
   - a **circle name** — that circle's projects across its roles (`list_role_projects` per role + `glassfrog_list_sub_projects` for the recursive view).
3. **Load each project with its actions:** `glassfrog_list_role_projects(role_id, status:"current", include:["actions"])`. Also read `status:"waiting"` projects for the `blocked` signal.
4. **Apply the staleness heuristic** (detection logic lives in the sweep's own files, per the rubric's "signals belong to the sweep"):
   - **Primary — `stale`:** a `current` project with **zero attached actions** (rubric **A2**: a project without a next-action is stalled by definition).
   - **Corroborating — age:** old `created_at` (default **90 days**, arg-overridable) raises confidence and is shown in the finding, but **does not trip `stale` on its own** (a project with a live action is not stale however old).
   - **`blocked`:** `status:"waiting"` — a first-class signal the rubric reserves for this sweep.
   - **Exempt:** `status:"someday"` and `status:"scheduled"` are deliberately not-now; never flagged.
5. **Present flagged projects one at a time**, each with its verdict (`stale` / `blocked`), the signals that produced it, and the honest false-positive caveat. Per-item actions:
   - `[e] re-energize` → draft a concrete next-action; on confirm, `glassfrog_create_action(role_id, parent_project_id, description, status:"current")`.
   - `[a] archive` → on confirm, `glassfrog_update_project(project_id, status:"archived")` — the soft-collapse.
   - `[d] defer` → no action; leave it.
   - `[q] quit` → stop the sweep; everything not yet acted on stays untouched.
6. **Summarize:** projects swept, stale/blocked counts, actions drafted, projects archived, items deferred.

**Lifestyle-change layer (scheduled routine):** ship a routine reference file (`skills/holacracy-secretary/references/stalled-sweep-routine.md`) defining a **draft-only** scheduled sweep that assembles a stalled-project review *packet* to the routine ledger (per `agentic-routines.md` / ADR-0006), and wire a `register stalled-sweep <circle>` path into `/holacracy:routines`. The routine **never acts** — it surfaces stalled candidates in a packet for the human to sweep; the archive/re-energize writes stay behind the interactive command's per-item confirm.

### Explicitly out of scope (non-goals)

- **Auto-archive / batch action.** Never. Every write is one human keystroke. The routine drafts a packet; it does not archive.
- **Deletion.** Archive-over-delete is absolute; the sweep never calls `glassfrog_delete_project`.
- **Editing project descriptions / re-assigning roles / governance changes.** Reframes and role-fit gaps are `/holacracy:review-project`'s job; this sweep is lifecycle-only (restart vs archive).
- **Inventing a last-touched timestamp.** The sweep is honest that GlassFrog exposes none; it infers and says so.

### Key decisions

- **Archive is a *performed* write, not an advisory draft** *(session-settled: picker + issue #76 + task spec, 2026-07-20).* `/holacracy:review-project` deliberately refuses `glassfrog_update_project` (archives are advisory drafts, to protect the role-filler's authorship of their *wording*). The sweep **diverges**: archive is a lifecycle transition, not authorship, and lifecycle management is the sweep's whole purpose — so it performs `update_project(status:"archived")` on per-item confirm. **This divergence is intentional and must be documented in-file** so a future reader doesn't "reconcile" the two surfaces. Re-energize (`create_action`) is additive, identical to review-project.
- **Staleness = no-action primary, age corroborates** *(session-settled: picker, 2026-07-20).* Zero current actions trips `stale`; `created_at` older than the (arg-overridable, default 90d) threshold corroborates but never trips alone; `status:"waiting"`→`blocked`; `someday`/`scheduled` exempt. Most conservative posture — fewest false positives on legitimately slow long-horizon projects.
- **Default scope is `mine`, not `session`** *(derived).* Projects have no in-session file cache; `mine` (actor's own `current` projects) is the analog of the twin's `session` default.
- **Full routine layer in this PR** *(session-settled: picker, 2026-07-20).* Belt (command) + suspenders (per-item confirm, archive-over-delete) + lifestyle-change (scheduled draft-only routine wired into `/holacracy:routines`). Reuses the ADR-0006 substrate — no new scheduling mechanism.

### Success criteria / acceptance signals

Maps to issue #76 acceptance criteria:

- [ ] Staleness heuristic defined (no-action primary + age corroboration + `waiting`→`blocked` + `someday`/`scheduled` exempt), with the explicit no-last-touched-timestamp false-positive caveat surfaced to the user.
- [ ] Per-item confirm; never auto-archive; `[q]` leaves everything untouched.
- [ ] Archive via `status:"archived"`, never delete.
- [ ] Scheduling as an agentic routine is not merely "considered" but shipped: a routine reference file + `/holacracy:routines register stalled-sweep <circle>` path.
- [ ] Divergence from `/holacracy:review-project` on the archive write is documented in-file.
- [ ] Rubric touched only on the already-reserved `stale`/`blocked` rows, minimally/additively (or not at all).

### Assumptions to verify at plan/build time

- `glassfrog_list_role_projects` accepts `include:["actions"]` and a `status` filter (asserted by `review-project.md` and the rubric; confirm the live tool signature).
- `glassfrog_update_project` accepts `status:"archived"` (rubric verified the enum against live API v5, 2026-07-20).
- `glassfrog_create_action` accepts `parent_project_id` + `role_id` + `description` + `status` (asserted by `review-project.md`).

## Outstanding Questions

- None blocking. Age-threshold default (90d) is a starting value; the command exposes it as an argument so it can be tuned without a code change.

## Planning Contract

**Plan depth:** Standard. Deliverable is markdown command/skill/reference files for a Claude Code plugin — no application code, no automated test suite. "Verification" throughout means structural review against the twin file's shape and the acceptance criteria, plus a plugin-load sanity check. Where a unit is prompt-authoring with no behavioral code, `Test expectation: none` is used with concrete structural verification in its place.

**Key technical decisions (KTDs):**

- **KTD1 — Archive is a performed `update_project` write; re-energize is a performed `create_action` write** *(session-settled: user-directed — chosen over review-project's advisory-draft-only posture: archive is a lifecycle transition, not authorship, and lifecycle is the sweep's purpose; issue #76 + task spec).* The command's `[a]` and `[e]` both fire a single GlassFrog write on per-item confirm, trusting the returned id (no list-back, same propagation caveat as tensions). The in-file "What this does NOT do" section must state the deliberate divergence from `/holacracy:review-project` so it isn't "reconciled" away later.
- **KTD2 — Detection logic lives in the command file, not the shared rubric** *(derived from conflict discipline + rubric's own "signals belong to the sweep").* The rubric reserves the `stale`/`blocked` states; the heuristic that *produces* them (no-action primary, age corroborates, `waiting`→`blocked`, `someday`/`scheduled` exempt) is authored in `commands/stalled-project-sweep.md`. The rubric is touched only to point its reserved rows at the now-shipped sweep, if at all.
- **KTD3 — The routine reuses the ADR-0006 substrate** *(session-settled: user-directed — full routine layer, chosen over defer/note-only).* No new scheduling mechanism: the routine is a second *content* type riding `agentic-routines.md` (scheduler fires → `routines.jsonl` ledger → session-start hook surfaces). It drafts a packet only; the archive/re-energize writes stay behind the command's per-item confirm.
- **KTD4 — Default scope `mine`** *(derived).* Projects have no session-file cache; `mine` = actor's own `current` projects across their roles, the analog of the twin's `session` default.

**Assumptions to verify at build time** (asserted by `commands/review-project.md` + rubric; sibling #78 is authoring `glassfrog-api-constraints.md` — do not block on it):

- `glassfrog_list_role_projects(role_id, status:, include:["actions"])` returns actions inline.
- `glassfrog_update_project(project_id, status:"archived")` is valid (rubric verified the enum against live API v5, 2026-07-20).
- `glassfrog_create_action` accepts `parent_project_id` + `role_id` + `description` + `status`.

---

## Implementation Units

### U1. Author `commands/stalled-project-sweep.md` (the sweep command)

- **Goal:** The interactive back-of-loop command — resolve scope, detect stalled/blocked projects, present per-item, perform confirmed re-energize/archive writes.
- **Requirements:** all of the Product Contract "Core behavior (command)"; KTD1, KTD2, KTD4; issue #76 AC (heuristic, per-item confirm, archive-via-status, divergence documented).
- **Dependencies:** none.
- **Files:** `commands/stalled-project-sweep.md` (new).
- **Approach:** Twin of `commands/supersession-sweep.md` — same frontmatter shape (`description`, `argument-hint`), same numbered "What this command does" + "Behaviour" + "What this command does NOT do" structure. Sections to carry:
  1. Frontmatter: `description` (surfaces un-moving projects, offers re-energize/archive, per-item confirm, never auto-archives), `argument-hint: ['scope: "mine" | "recent" | circle name, optional; default "mine"']`.
  2. Actor/role resolution via `skills/shared/actor-and-role-resolution.md` (Steps 1–2).
  3. Scope resolution (`mine` default / `recent` / circle) — mirror supersession-sweep's scope block, adapted to projects (no session cache; explain why `mine` replaces `session`).
  4. Load projects with `list_role_projects(role_id, status:"current", include:["actions"])`; separately read `status:"waiting"` for `blocked`.
  5. **The staleness heuristic (detection logic — KTD2):** no-action primary trips `stale`; age (`created_at` older than the arg-overridable default **90 days**) corroborates only; `waiting`→`blocked`; `someday`/`scheduled` exempt. State the no-last-touched-timestamp false-positive caveat explicitly.
  6. Per-item presentation block (mirror supersession-sweep's fenced example) with actions `[e] re-energize` → `create_action(role_id, parent_project_id, description, status:"current")`, `[a] archive` → `update_project(project_id, status:"archived")`, `[d] defer`, `[q] quit`.
  7. Load the rubric `skills/shared/project-well-formedness.md` at the start (for the `stale`/`blocked` definitions and the status enum).
  8. Behaviour section: per-item never batched; conservative bias; degrade gracefully if a read tool is missing; honest write-failure surfacing.
  9. "What this does NOT do": no auto-archive, no delete, no description reframes/re-assignment (that's review-project), and **the explicit KTD1 divergence note** ("Unlike `/holacracy:review-project`, this command performs the archive write on confirm — archive is a lifecycle transition, not authorship").
- **Patterns to follow:** `commands/supersession-sweep.md` (structure, tone, per-item fenced block, "does NOT do" list); `commands/review-project.md` lines 58–62 (additive-write mechanics, trust-returned-id, degrade-gracefully wording).
- **Test expectation:** none — markdown command file. **Verification:** section-by-section presence check against the twin; heuristic spec matches KTD2 exactly; `[a]` maps to `update_project(status:"archived")`, `[e]` to `create_action(...parent_project_id...)`; divergence note present; false-positive caveat present.

### U2. Author `skills/holacracy-secretary/references/stalled-sweep-routine.md` (routine reference)

- **Goal:** The draft-only scheduled routine's content — assemble a stalled-project review *packet* to the ledger; never act.
- **Requirements:** Product Contract "Lifestyle-change layer"; KTD3; issue #76 AC ("scheduling as an agentic routine" shipped, not just considered).
- **Dependencies:** U1 (shares the heuristic — the routine references the command's detection spec rather than re-deriving it).
- **Files:** `skills/holacracy-secretary/references/stalled-sweep-routine.md` (new).
- **Approach:** Twin of `skills/holacracy-secretary/references/pre-tactical-prep-routine.md`. Open with the canonical scheduled-work preamble reference (`../shared/actor-and-role-resolution.md`), then a numbered routine-prompt template: resolve scope (single-circle, never bulk-load the roster), read the circle's `current` + `waiting` projects with actions, apply the U1 heuristic, compose a **draft packet** of stalled/blocked candidates (each annotated with the signal that flagged it and the honest false-positive caveat — the teach-on-judgment-calls move, R11), then write the ledger per `../shared/agentic-routines.md` (sidecar `packet_path` first, then the ledger line with `packet_summary`/`built_at`/window/`last_status`). Draft-only boundary section: the routine surfaces candidates; the human runs the sweep command to actually archive/re-energize. Degradation section: GlassFrog unavailable → no packet, `last_status: error`; partial → available sections + explicit gap markers.
- **Patterns to follow:** `skills/holacracy-secretary/references/pre-tactical-prep-routine.md` (whole shape, including its honest note that projects-without-update-timestamp is exactly the inference this routine owns).
- **Test expectation:** none — markdown reference file. **Verification:** structural parity with the pre-tactical-prep twin; draft-only boundary explicit; heuristic references U1 rather than duplicating; ledger-write steps match `agentic-routines.md`.

### U3. Wire `register stalled-sweep <circle>` into `commands/routines.md`

- **Goal:** Let the actor turn the scheduled sweep on for a circle, alongside the existing pre-tactical-prep registration.
- **Requirements:** KTD3; issue #76 AC (routine shipped + registerable).
- **Dependencies:** U2 (the routine content the registration builds its prompt from).
- **Files:** `commands/routines.md` (additive edit — not sibling-claimed).
- **Approach:** Extend the `$ARGUMENTS` parse and `argument-hint` to add a `register stalled-sweep <circle>` branch mirroring the existing `register pre-tactical-prep <circle>` steps: resolve actor + circle, derive cadence (or ask), build the prompt from `skills/holacracy-secretary/references/stalled-sweep-routine.md` with the canonical preamble, create the scheduled task titled `holacracy/secretary/stalled-sweep/<circle-slug>` (the `holacracy/` prefix is load-bearing for the hook), confirm draft-only. Keep the "minimal by design / no scheduler → pull-build path" boundaries; note that with no `scheduled-tasks` MCP, point the user at `/holacracy:stalled-project-sweep` for the on-demand path.
- **Patterns to follow:** the existing `register pre-tactical-prep <circle>` block in the same file (steps 1–5).
- **Test expectation:** none — markdown command file. **Verification:** the new branch parallels pre-tactical-prep step-for-step; title convention `holacracy/secretary/stalled-sweep/<slug>`; on-demand fallback points to the U1 command; `argument-hint` updated.

### U4. Point the rubric's reserved rows at the sweep; wire README + CLAUDE.md

- **Goal:** Make the shipped surfaces discoverable and close the rubric's "(planned)" reference now that the sweep exists.
- **Requirements:** issue #76 AC (rubric touched only on reserved rows, minimally/additively); repo discoverability conventions.
- **Dependencies:** U1, U2, U3.
- **Files:** `skills/shared/project-well-formedness.md` (minimal/additive — reserved `stale`/`blocked` rows + the "(Planned) the stalled-project sweep (#76)" line only), `README.md` (command list + shared-reference list + roadmap), `CLAUDE.md` (shared-reference note already mentions the planned sweep — update to shipped).
- **Approach:**
  - Rubric: change the "*(Planned)* the stalled-project sweep (#76)" loader line to reflect it now ships; leave the `stale`/`blocked` table rows' *meaning* intact (they already say "sweep (#76) only"). **Do not** touch any other row, the families, or the status-enum note. This is the one shared-file edit; keep it to those two spots. (Sibling #75 reads this file — additive, non-structural change only.)
  - README: add a `/holacracy:stalled-project-sweep` bullet to the command list (near lines 51–53), add the routine reference to the agentic-routines "now landing" list (line 113 area), and move the stalled-sweep item out of the deferred/roadmap list if present.
  - CLAUDE.md: the `skills/shared/project-well-formedness.md` note lists surfaces that load the rubric — update "planned capture-guardrail and stalled-sweep surfaces" to reflect the sweep now shipping.
- **Test expectation:** none — docs. **Verification:** rubric diff limited to the two spots; README lists the new command + routine; CLAUDE.md note current; no edits to `review-project.md`, `project-review-critics.md`, `project-critic.md`.

### U5. Version bump + keyword

- **Goal:** Reflect the new command in the plugin bundle metadata.
- **Requirements:** repo versioning convention (bump plugin version when commands added).
- **Dependencies:** U1–U4.
- **Files:** `.claude-plugin/plugin.json`.
- **Approach:** Bump `version` `0.7.0` → `0.8.0` (a command + routine added — bundle shape changed). Extend the `description` to mention the stalled-project sweep alongside the supersession sweep, and add a `project-triage` / `stalled-sweep` keyword if it sharpens discovery (keep the keyword list tight). No skill-frontmatter version bump needed — no existing skill's content changed (the new routine reference rides the Secretary skill but is a new file, not a content change to `SKILL.md`).
- **Test expectation:** none — manifest. **Verification:** valid JSON; version is `0.8.0`; description mentions the sweep.

---

## Verification Contract

- **Plugin loads clean:** the plugin parses and the new command is discoverable (commands are auto-discovered from `commands/`; confirm no manifest edit is required beyond the version bump).
- **Acceptance-criteria trace (issue #76):** heuristic defined with false-positive caveat (U1) · per-item confirm, never auto-archive (U1) · archive via `status:"archived"`, never delete (U1) · scheduling shipped as a routine (U2 + U3) · divergence from review-project documented in-file (U1) · rubric touched only on reserved rows (U4).
- **Conflict-discipline check:** `git diff --name-only` touches only `commands/stalled-project-sweep.md`, `skills/holacracy-secretary/references/stalled-sweep-routine.md`, `commands/routines.md`, `skills/shared/project-well-formedness.md` (two-spot additive), `README.md`, `CLAUDE.md`, `.claude-plugin/plugin.json`, and the plan doc. **Never** `commands/review-project.md`, `skills/shared/project-review-critics.md`, `agents/project-critic.md`, or the sibling-owned `commands/capture-project.md` / `docs/agents/glassfrog-api-constraints.md`.
- **Structural parity:** the command reads as a twin of `supersession-sweep.md`; the routine reads as a twin of `pre-tactical-prep-routine.md`.

## Definition of Done

- All five units authored; the six issue-#76 acceptance criteria trace to shipped text.
- `git diff --name-only` stays within the allowed set above.
- PR opened off `main`-based branch with `Closes #76`; CI green; Project #41 item ready to move to Done on merge.

---

## Conflict discipline (multi-session)

New files only for detection logic: `commands/stalled-project-sweep.md`, `skills/holacracy-secretary/references/stalled-sweep-routine.md`. Additive edits allowed: `commands/routines.md` (not sibling-claimed), `README.md`, `CLAUDE.md`. Rubric `skills/shared/project-well-formedness.md` — touch **only** the reserved `stale`/`blocked` rows if strictly necessary, minimally (sibling #75 reads this file). Do **not** touch `commands/review-project.md`, `skills/shared/project-review-critics.md`, `agents/project-critic.md`. Siblings building `capture-project.md` (#75) and `glassfrog-api-constraints.md` (#78).
