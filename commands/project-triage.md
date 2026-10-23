---
description: Walk the actor's current GlassFrog projects and decide what each one needs next — retire the ones that fail a reality check (done, duplicate, superseded, owner role gone) and give every other project one saved route (needs-info, ready-for-agent, ready-for-human) that the next pass resumes from. Readiness only; the deep quality audit belongs to /holacracy:review-project.
argument-hint: [circle name, optional]
---

# /holacracy:project-triage

Walk the `current` projects on the actor's roles and decide, for each one, **what it needs next before anyone can act on it**. Save that answer on the project, with its reason, so the next pass starts where this one stopped.

Triage answers *"is this project still real, and who acts next?"* It does not answer *"is this project well written?"* — that is `/holacracy:review-project`'s question, and the two are separated deliberately ([ADR-0018](../docs/adr/0018-separate-project-readiness-from-project-quality.md)), the same split [ADR-0011](../docs/adr/0011-separate-tension-readiness-from-tension-disposition.md) made for tensions.

Load two shared references at the start:

1. `skills/shared/project-triage-gates.md` — the reality gates, the routing order, the note line, and the movement rule.
2. `skills/shared/triage-states.md` — the closed list of states this command may write, and the write rules.

## The safeguard (non-negotiable)

**Draft, show, then write one project at a time.** No GlassFrog write happens without the user's confirmation of that one project. Never batch. The user can quit at any point and the remaining projects stay as they are.

**Write only what the actor owns.** In Holacracy only a role's filler updates or closes that role's projects. A project on a role the actor does not fill is walked and drafted, never written: its block shows the draft for the owner to apply and offers no write key.

## What this command does

1. **Resolve actor + role roster.** Follow `skills/shared/actor-and-role-resolution.md` Steps 1–2: `glassfrog_get_me`, then `glassfrog_list_my_roles`. Keep the set of role ids the actor fills.

2. **Resolve scope from $ARGUMENTS.**
   - **No argument** → the actor's own roles: `glassfrog_list_role_projects(role_id, status: "current")` for each.
   - **A circle name** → that circle's projects: `glassfrog_list_subrole_projects(circle_role_id, status: "current")`, repeated for each sub-circle (`has_subroles == true`) and unioned. Treat the call as direct-children-only, as `list_subrole_tensions` is (see `/holacracy:tension-triage` step 3).

   If the circle cannot be resolved, name the constraint and stop.

3. **Check that state writes can work.** `glassfrog_set_project_tags` is offered only when the GlassFrog MCP server enables project tag writes, and it accepts only the account that holds the server's web session. If the tool is not in your tool list, or the first tag write is refused, say so once and continue with state routes as **drafts only**. Status closures (step 6, `[c]`/`[a]`) still work through `glassfrog_update_project`. Name it again in the summary.

4. **Filter (resume rule).** Read each project's `tags` and `note`, and the role's actions once with `glassfrog_list_role_actions(role_id)` (circle scope: `glassfrog_list_subrole_actions`), grouped by `parent_project_id`. Then:
   - no state tag, or `needs-triage` → walk it;
   - `needs-info` → walk it only if it has moved, per `project-triage-gates.md` Step 6;
   - `ready-for-agent` or `ready-for-human` → count it, do not walk it.

5. **Run the gates, then route.** For each project to walk, apply `project-triage-gates.md` Steps 1–4 (outcome reached, duplicate, superseded, owner role gone) and stop at the first that fires. A survivor is routed by Step 5 to exactly one state. Keep a list of duplicate survivors as you go, per Step 2.

6. **Walk each project with the user.** Present one block:

   ```
   Project [N of M] on [Role name] of [Circle name]
   Outcome: [description]
   Status:  current   Tags: [tags or none]   Last triage: [line or none]
   Next action: [first current action, or none]

   Draft: [ready-for-human | ready-for-agent | needs-info | completed | archived]
   Reason: [one line, the same text the note line will carry]
   [Duplicate: survivor is "<other project>", which stays]

   Note line: Triage <UTC now, at write time>: <draft> -- <reason>
   Tags after: [the full tag_names array, other tags kept]   (state routes only)

     [w] write the route      -> note line, then tag read-modify-write
     [c] complete             -> note line + status: completed   (gate failures only)
     [a] archive              -> note line + status: archived    (gate failures only)
     [r] review it            -> hand this one project to /holacracy:review-project
     [d] defer                -> no write
     [q] quit                 -> stop; the rest stay as they are
   ```

   A gate failure offers `[c]` and `[a]` instead of `[w]`. A project on a role the actor does not fill offers `[r]`, `[d]` and `[q]` only. When the user disagrees with the draft, take their route and reason instead, as long as the state is in the closed list.

7. **Write on confirmation**, per `project-triage-gates.md` Step 6: read the project with `glassfrog_get_project`, append the note line with `glassfrog_update_project` (adding `status` for `[c]`/`[a]`), then for a state call `glassfrog_set_project_tags(project_id, tag_names)` with the read-modify-write from `triage-states.md` Step 3. Refuse any state name outside that file's Step 1 table before the call. Surface every error; never swallow a failed write.

8. **Summarize.** Count walked, routed to each state, completed, archived, deferred, and skipped as already `ready-for-*`. List projects drafted for another role's owner. Say whether state writes were drafts only (step 3).

## Behaviour

- **Gates before form.** A project that is already done, duplicated, or superseded does not need its outcome reworded. Asking the reality question first is what keeps the pass cheap.
- **Archive is a status, not a tag.** `completed` when the outcome exists, `archived` otherwise. Both are reversible in GlassFrog. Deletion is permanent and this command does not offer it.
- **No tag without a reason.** Every state write appends its note line first. A bare tag loses why the project was routed, and the next triager has to work it out again.
- **Never write a rubric verdict as a tag.** `needs-next-action`, `needs-outcome`, `executor-mismatch` and the rest are findings from `/holacracy:review-project`. Triage writes only the four states in `triage-states.md`.
- **A past-tense title is not a status.** Projects are titled in past tense as an idiom. Gate 1 needs evidence, not grammar.
- **The movement rule is a heuristic.** Say so when a `needs-info` project is skipped and the user expected to see it; they can name it and ask to reopen it as `needs-triage`.
- `waiting`, `someday` and `scheduled` projects are out of scope. `/holacracy:stalled-project-sweep` owns `waiting`; the other two are deliberately not-now.

## Where this command stops

Triage decides readiness. It does not reword an outcome, draft a next action, link a goal, or re-assign a role — those are quality findings, and `[r]` hands one project to `/holacracy:review-project` for them. It does not create a successor project either: a superseded project whose successor does not exist yet is routed to `needs-info` with the successor as the open question, and `/holacracy:capture-project` can file it.

## Why this command exists

Most current projects in a real org were found idle, and nothing told anyone which ones still mattered. `/holacracy:review-project`'s backlog walk ran five critic lenses on every project every time and saved nothing, so nobody ran it often. This command is the cheap, repeatable pass: retire what is no longer real, route the rest once, and resume from the saved route next time.
