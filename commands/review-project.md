---
description: Adversarial review of GlassFrog projects against the well-formedness rubric. Runs five critic lenses (actionability, goal-alignment, scope-authority, assignment-fit, red-team) over a project or a backlog, surfaces findings with drafted fixes, and applies additive fixes with a single per-item confirmation. Never auto-writes.
argument-hint: [project name/id, or circle name — optional]
---

# /holacracy:review-project

Review GlassFrog **projects** for quality: is each one well-formed (an actionable outcome with a next-action and a clear owner) and well-placed (serving a goal, within the owner role's authority, on the best-fit role)? For each finding, Claude drafts a fix; the human confirms per-item; only additive fixes are written to GlassFrog. This is the project-side analog of `/holacracy:process-inbox`.

Load two shared references at the start:

1. `skills/shared/project-well-formedness.md` -- the rubric (the seven dimensions, the state vocabulary, the DoD-as-body-convention, the status enum).
2. `skills/shared/project-review-critics.md` -- the five critic lenses, the finding schema, and the severity/floor/cap/dedupe rules.

## The safeguard (non-negotiable)

**Draft and confirm only.** Do not call `glassfrog_create_action` or `glassfrog_link_goal_supporting_project` without an explicit per-item human confirmation. Do not call `glassfrog_update_project` at all in this command -- description reframes and archives are surfaced as drafts the human applies themselves. Scope-authority and assignment-fit findings **never** write to the project; they route to the tension flow. Per-item confirmation, never batched. The user can quit at any point.

## What this command does

1. **Resolve actor + role roster.** Follow `skills/shared/actor-and-role-resolution.md` Steps 1-2: `glassfrog_get_me`, then `glassfrog_list_my_roles`.

2. **Arg gate -- pick the target set** from `$ARGUMENTS`:
   - **No argument** -> the actor's own role projects. For each role, `glassfrog_list_role_projects(role_id, status: "current", include: ["actions"])`. This is the **backlog walk** (inline critic passes).
   - **A circle name** -> that whole circle's projects: `list_role_projects` across the circle's roles + `glassfrog_list_sub_projects` for the recursive view. Still a **backlog walk** (inline passes).
   - **A named/identified project** -> resolve one project (by id `proj_<32hex>`, or by matching the name against `list_role_projects(..., q: "<name>")`; if ambiguous, ask which one) and run the **deep single-project review** (independent critic subagents -- see "Deep review" below).

   If a target can't be resolved (no matching project, actor fills no role in the named circle), name the constraint honestly and stop.

3. **Run the five lenses** against each target project, seeded from `project-review-critics.md`:
   - **Backlog walk** -> inline sequential passes (cheap, scales per project).
   - **Deep single-project** -> fan out one `project-critic` subagent per lens (see below).

4. **Dedupe, rank, cap.** Merge duplicate findings (same dimension + project -> keep highest severity), drop `low` findings (the floor), keep at most 6 per project (the cap).

5. **Present per project.**
   - **Backlog walk:** show a one-line verdict per project first -- its state (`well-formed`, `needs-outcome`, ...), where the verdict is the state of the highest-severity surviving finding. Expand the findings block **only for non-well-formed projects**. A `well-formed` project gets one line and no expansion.
   - **Deep single-project:** always expand the full findings block.

6. **The per-project findings block** (modeled on `/holacracy:process-inbox`):

   ```
   Project [N of M]: [description excerpt]   (proj_xxx, owned by [Role] of [Circle])
   Verdict: [state]

   Finding [i]:  [lens] · [severity]
     [plain-language gap statement]
     Drafted fix: [the drafted fix, rendered per its kind]

     Apply as:
       [a] apply         -> additive write on confirm (create-action / link-goal only)
       [c] copy draft    -> advisory draft (reframe / archive) — you apply it in GlassFrog
       [t] route tension -> dispatch tension-capture (scope-authority / assignment)
       [s] skip          -> no action on this finding
       [q] quit          -> stop the whole review, leave everything untouched
   ```

7. **Apply the confirmed fix** by its `write_class`:
   - **additive-on-confirm** (`create-action`, `link-goal`): fire the single call. `create-action` **must** pass `parent_project_id` (this project) plus the owning `role_id` and a concrete `description`, `status: "current"`. `link-goal` passes the chosen `goal_id` + `project_id`. Trust the returned id as the same-session confirmation -- do **not** list-back to verify (same propagation caveat as tensions).
   - **advisory-draft** (`reframe-description`, `archive`): show the exact text/action the human would apply (e.g. the reframed description, or `update_project(project_id, status: "archived")`). Do not call the write.
   - **advisory-route** (scope-authority / assignment): see "Hand-off to tension capture" below.
   - Surface any write failure honestly -- never swallow it: *"I couldn't apply the fix -- GlassFrog returned [error]. The draft is still here; retry or adjust?"*

8. **Summarize at the end.** Per the walk: projects reviewed, verdict distribution, actions created, goals linked, drafts handed to the user, tensions routed, findings skipped.

## Deep review (single named project)

When the argument resolves to one project, run the panel as **independent adversarial critics** for genuine independence:

1. Gather the project data once: the project record, its actions (`include: ["actions"]`), the owning role's context (`glassfrog_get_role_context`), goals (`list_role_goals`), and domains (`list_role_domains`).
2. Dispatch five `project-critic` subagents in parallel (`agents/project-critic.md`), one per lens, each seeded with that shared data + its lens name. Each returns findings in the schema.
3. Merge, dedupe, rank, cap (step 4 above), then present the expanded findings block (step 6) and apply per step 7.

The backlog walk does **not** use subagents -- its lenses run inline to keep a multi-project walk affordable.

## Hand-off to tension capture (scope-authority & assignment-fit)

A confirmed `advisory-route` finding is a *structural* gap -- the project is on a role that isn't authorized for its scope, or isn't the best-fit owner. That is a governance tension, not a project edit. On `[t]`:

- Dispatch the `tension-capture` subagent (`agents/tension-capture.md`) with: the tension text (front-loaded topic, e.g. *"Scope-authority gap: [Role] owns project [X] whose scope reaches into [other role/domain] -- ..."*), the sensing role hint, and an attribution preamble if carried on someone's behalf.
- The `tension-capture` subagent runs its own draft-and-confirm flow. It files a tension on a role's backlog; it does **not** touch the project.
- Reason about scope-authority from `skills/shared/authority-boundaries.md`, exactly as `/holacracy:check-authority` does.

Assignment-fit defaults to the structural role-fit reading. Only surface the person-fit reading when the user explicitly asks -- it's a Lead Link question.

## Behaviour

- **Per-finding decision -- never batched.** `[q]` stops the whole review; everything not yet applied stays untouched.
- **Additive writes only.** `create-action` and `link-goal` are the only calls this command makes to GlassFrog. Reframe and archive are drafts; scope/assignment route to tensions. This is deliberate (protects the role-filler's authorship of their own project wording).
- **No manufactured critique.** A well-formed project returns no findings. Do not invent gaps to look thorough.
- **Degrade gracefully.** If a read tool is unavailable on an older MCP server, name the constraint and run the lenses that can (*"Your GlassFrog MCP server doesn't expose goal listing yet -- skipping the goal-alignment lens."*).

## What this command does NOT do

- It does not edit project descriptions or archive projects on the user's behalf (advisory drafts only).
- It does not make governance changes, re-assign roles, or re-file projects.
- It does not resolve tensions -- it can *route* a structural gap to the tension flow, where the human decides.
- It does not write anything without a per-item human keystroke.

## Why this command exists

Projects get captured in GlassFrog with ease but arrive thin -- an activity instead of an outcome, no next-action, no definition of done, sometimes on the wrong role or serving no goal. The backlog then fills with items nobody can act on without re-thinking them. This command is the operational surface that turns thin projects into well-formed, well-placed ones -- and, by showing *why* each is weak from several angles, models good project form so the role-filler needs the review less over time.
