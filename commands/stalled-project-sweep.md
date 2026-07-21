---
description: Sweep a role's or circle's GlassFrog projects for stall. Surfaces un-moving projects (no next-action, old, or status "waiting") and offers per item to re-energize (draft a next-action) or archive (status "archived"). Per-item confirm; never auto-archives.
argument-hint: ['scope: "mine" | "recent" | circle name, optional; default "mine"']
---

# /holacracy:stalled-project-sweep

Back-of-loop lifecycle sweep for GlassFrog **projects**. It surfaces projects that have stopped moving and offers, one at a time, to **re-energize** them (draft a concrete next-action) or **archive** them (`status: "archived"` — the soft-collapse the plugin prefers over deletion). It is the "suspenders" of the project-triage effort: the guardrail keeps new projects well-formed and the review panel audits their form, but neither watches for *decay over time* — this does.

This is the project-side twin of `/holacracy:supersession-sweep` (which sweeps filed tensions). Where that sweep dedups, this one re-energizes or retires.

Load the rubric `skills/shared/project-well-formedness.md` at the start — it defines the `stale` and `blocked` states this sweep emits (states it reserves specifically for this sweep) and the closed project-status enum. This command owns the *detection* logic that produces those states; the rubric owns their meaning.

## What this command does

1. **Resolve actor + role roster.** Follow `skills/shared/actor-and-role-resolution.md` Steps 1-2: `glassfrog_get_me`, then `glassfrog_list_my_roles`.

2. **Resolve scope from $ARGUMENTS.** Default is `mine`:
   - `mine` (default) — the actor's own `current` projects across every role they fill. For each role, `glassfrog_list_role_projects(role_id, status: "current", include: ["actions"])`.
   - `recent` — the same set, restricted to projects whose `created_at` is older than the age threshold (the corroboration signal, surfaced explicitly so the user sees *why* each qualifies).
   - A circle name — that circle's projects across its roles: `list_role_projects` per role plus `glassfrog_list_sub_projects` for the recursive view.

   **Why the default is `mine`, not `session`:** the tension twin defaults to `session` because tensions are filed into an in-conversation cache. Projects have no such cache — they live only in GlassFrog. So the project analog of "the things in front of me right now" is `mine`: the actor's own current projects.

   Also read each role's `status: "waiting"` projects — the `blocked` signal (step 4) lives there, and a `current`-only load would miss it.

   If a target can't be resolved (actor fills no role in the named circle, no projects found), name the constraint honestly and stop.

3. **Load each project with its actions.** The `include: ["actions"]` parameter returns the project's attached actions inline — this is what lets the sweep see whether a next-action exists without a second call per project.

4. **Apply the staleness heuristic** (the detection logic; the rubric reserves the states, this command produces them):

   - **`stale` — primary signal:** a `current` project with **zero attached actions**. This is rubric dimension A2 restated: *a project without a next-action is stalled by definition.* No-action is the trigger.
   - **Age — corroborating only:** an old `created_at` (default **90 days**; override via the scope/threshold argument) *raises confidence* and is shown in the finding, but **never trips `stale` on its own.** A project with a live next-action is not stale no matter how old it is; an action-less project two weeks old is a weaker `stale` than an action-less project a year old, and the finding says so.
   - **`blocked`:** `status: "waiting"` — a first-class signal the rubric reserves for this sweep. Present it as `blocked`, not `stale`: the project isn't neglected, it's waiting on something. The re-energize/archive offer still applies (the dependency may be dead), but the framing is different.
   - **Exempt — never flagged:** `status: "someday"` and `status: "scheduled"`. These are *deliberately* not-now; treating them as stalled would punish correct backlog hygiene.

   **Be honest about the heuristic.** GlassFrog exposes **no last-touched timestamp** for a project. Staleness here is *inferred* from `created_at` plus action-absence — it cannot see a project that was actively discussed yesterday but never had an action attached. Say this out loud when presenting findings: a long-horizon project (a multi-quarter outcome that legitimately moves slowly) can look identical to an abandoned one. The user's per-item judgment is the real filter; the heuristic only decides what to *show* them.

5. **Present flagged projects to the user one at a time:**

   ```
   Stalled project  [N of M]

     [description excerpt]              (proj_xxx, owned by [Role] of [Circle])
     Verdict:  stale | blocked
     Signals:  no next-action · created [date] (~[age]) · status "[status]"
     Caveat:   inferred from age + action-absence; no last-touched timestamp —
               if this is a legitimately slow long-horizon project, defer it.

   Action:
     [e] re-energize  -> draft a next-action, then create_action(role_id, parent_project_id, description, status: "current")
     [a] archive      -> update_project(proj_xxx, status: "archived")
     [d] defer         -> no action; leave it as-is
     [q] quit          -> stop the sweep; everything not yet acted on stays untouched
   ```

   For `[e]`, draft the next-action *first* and show it, so the user confirms a concrete step rather than a blank promise — the same "make the next physical action explicit" discipline the rubric's A2 test applies.

6. **Apply the user's decision:**
   - `[e]` — `glassfrog_create_action` with `parent_project_id` (this project), the owning `role_id`, the drafted `description`, and `status: "current"`. Trust the returned id as the same-session confirmation — do **not** list-back to verify (same propagation caveat as tensions).
   - `[a]` — `glassfrog_update_project(project_id, status: "archived")`. This is the one lifecycle write the sweep performs.
   - Surface any write failure honestly — never swallow it: *"I couldn't apply that — GlassFrog returned [error]. The draft is still here; retry or adjust?"*

7. **Summarize at the end.** Projects swept, stale vs blocked counts, next-actions drafted, projects archived, items deferred.

## Behaviour

- **Per-item decision — never batched.** Each project is its own confirm. `[q]` stops the whole sweep; everything not yet acted on stays untouched.
- **Never auto-archive.** Archiving always requires an explicit per-item keystroke. The heuristic decides what to *surface*; only the human decides what to retire.
- **Conservative bias.** When a `stale` verdict is thin (action-less but recent, or a plausibly-slow long-horizon outcome), lean toward recommending `[e]` or `[d]` over `[a]`. Retiring a live-but-slow project is the costly false positive; leaving a dead one one more cycle is cheap.
- **Archive over delete — always.** The sweep never calls `glassfrog_delete_project`. Archive is the soft-collapse; a mistakenly-archived project is recoverable, a deleted one is not.
- **Degrade gracefully.** If a read tool is unavailable on an older MCP server, name the constraint and sweep with what you have (*"Your GlassFrog MCP server doesn't return actions inline yet — I can't detect the no-action signal, so I'll flag on age and `waiting` status only, less reliably."*).

## What this command does NOT do

- It does **not** delete projects. Archive (`status: "archived"`) is the only collapse mechanism.
- It does **not** edit project descriptions, re-frame outcomes, re-assign roles, or make governance changes — those are `/holacracy:review-project`'s job. This sweep is lifecycle-only: restart it, or retire it.
- It does **not** auto-archive, batch, or act without a per-item human keystroke.
- It does **not** invent a last-touched timestamp. It infers staleness and says so.

### Deliberate divergence from `/holacracy:review-project`

`/holacracy:review-project` refuses to call `glassfrog_update_project` at all — there, archive is an *advisory draft* the human applies themselves, to protect the role-filler's authorship of their own project *wording*. **This sweep diverges on purpose:** it performs `update_project(status: "archived")` on per-item confirm. Archiving is a *lifecycle transition*, not a rewrite of the role-filler's words, and lifecycle management is this command's entire reason to exist. Re-energize (`create_action`) is additive and matches review-project exactly. Do not "reconcile" the two surfaces by making this sweep advisory-only — the difference is the design.

## Scheduling

This sweep can run as a scheduled, draft-only **agentic routine** so stall-catching stops depending on anyone remembering to run it. The routine assembles a stalled-project review *packet* to the routine ledger for the session-start hook to surface; it never archives or drafts actions itself — those writes stay behind this command's per-item confirm. See `skills/holacracy-secretary/references/stalled-sweep-routine.md` for the routine content and `/holacracy:routines register stalled-sweep <circle>` to turn it on.
