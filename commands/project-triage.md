---
description: Walk the actor's current GlassFrog projects and decide what each one needs next — retire the ones that fail a reality check (done, duplicate, superseded, owner role gone) and give every other project one saved route (needs-info, ready-for-agent, ready-for-human) that the next pass resumes from. With a leading `needs-info`, walk the needs-info queue instead and record each answer. Readiness only; the deep quality audit belongs to /self-org:review-project.
argument-hint: "[needs-info] [circle name, optional]"
---

# /self-org:project-triage

Walk the `current` projects on the actor's roles and decide, for each one, **what it needs next before anyone can act on it**. Save that answer on the project, with its reason, so the next pass starts where this one stopped.

The command has two modes:

- **Standard pass** (`/self-org:project-triage [circle]`) — walk untriaged projects and `needs-info` projects that have moved.
- **`needs-info` resolution mode** (`/self-org:project-triage needs-info [circle]`) — walk every `needs-info` project in scope, `current` and `waiting`, whether or not it has moved, ask its open question, and record the answer. This is how the queue drains: without it, a question its owner never sees waits forever.

Triage answers *"is this project still real, and who acts next?"* It does not answer *"is this project well written?"* — that is `/self-org:review-project`'s question, and the two are separated deliberately ([ADR-0018](../docs/adr/0018-separate-project-readiness-from-project-quality.md)), the same split [ADR-0011](../docs/adr/0011-separate-tension-readiness-from-tension-disposition.md) made for tensions.

Load two shared references at the start:

1. `skills/shared/project-triage-gates.md` — the reality gates, the routing order, the note line, and the movement rule.
2. `skills/shared/triage-states.md` — the closed list of states this command may write, and the write rules.

## The safeguard (non-negotiable)

**Draft, show, then write one project at a time.** No GlassFrog write happens without the user's confirmation of that one project. Never batch. The user can quit at any point and the remaining projects stay as they are.

**Write only what the actor owns.** In Holacracy only a role's filler updates or closes that role's projects. A project on a role the actor does not fill is walked and drafted, never written: its block shows the draft for the owner to apply and offers no write key.

## What this command does

1. **Resolve actor + role roster.** Follow `skills/shared/actor-and-role-resolution.md` Steps 1–2: `glassfrog_get_me`, then `glassfrog_list_my_roles`. Keep the set of role ids the actor fills.

2. **Resolve mode and scope from $ARGUMENTS.** A leading `needs-info` selects the resolution mode; the rest of the argument is the circle name. In the resolution mode, make every list call below twice, once with `status: "current"` and once with `status: "waiting"`, and union the results.
   - **No argument** → the actor's own roles: `glassfrog_list_role_projects(role_id, status: "current")` for each.
   - **A circle name** → that circle's projects: `glassfrog_list_subrole_projects(circle_role_id, status: "current")`, repeated for each sub-circle (`has_subroles == true`) and unioned. Treat the call as direct-children-only, as `list_subrole_tensions` is (see `/self-org:tension-triage` step 3).

   If the circle cannot be resolved, name the constraint and stop.

3. **Check that state writes can work.** `glassfrog_set_project_tags` is offered only when the GlassFrog MCP server enables project tag writes, and it accepts only the account that holds the server's web session. If the tool is not in your tool list, or the first tag write is refused, say so once and continue with state tags as **drafts only**. The note line and every status change it carries (closures `[c]`/`[a]`, a move to `waiting`, a return to `current`) still write through `glassfrog_update_project`, because the note line is the record (`project-triage-gates.md` Step 6). Name it again in the summary.

4. **Filter (resume rule).** Read each project's `tags` and `note`, and the role's actions once with `glassfrog_list_role_actions(role_id)` (circle scope: `glassfrog_list_subrole_actions`), grouped by `parent_project_id`. Then:
   - no state tag, or `needs-triage` → walk it, unless the last triage line routes a state: then treat that route as the tag (a failed or unavailable tag write leaves only the line);
   - `needs-info` → walk it only if it has moved, per `project-triage-gates.md` Step 6;
   - `ready-for-agent` or `ready-for-human` → count it, do not walk it.

   In the **resolution mode**, keep only projects whose route is `needs-info`: the tag, or, when the tag is missing, a last triage line that routes `needs-info` (a failed or unavailable tag write must not hide a `waiting` project). Ignore movement, except that a project whose last triage line is `needs-info -- answered; add first action:` is counted and not walked until it moves (`project-triage-gates.md` Step 6). Walk the rest **oldest last triage line first**; a project with no triage line goes first.

5. **Run the gates, then route.** For each project to walk, apply `project-triage-gates.md` Steps 1–4 (outcome reached, duplicate, superseded, owner role gone) and stop at the first that fires. A survivor is routed by Step 5 to exactly one state. Keep a list of duplicate survivors as you go, per Step 2.

6. **Walk each project with the user.** Present one block:

   ```
   Project [N of M] on [Role name] of [Circle name]
   Outcome: [description]
   Status:  [current | waiting]   Tags: [tags or none]   Last triage: [line or none]
   Next action: [first current action, or none]

   Draft: [ready-for-human | ready-for-agent | needs-info | completed | archived]
   Reason: [one line, the same text the note line will carry]
   [Duplicate: survivor is "<other project>", which stays]
   [Asks:      <owner role> | <other role, circle, or party>]          (needs-info only)
   [Waits for: <what it waits for>  -> status: waiting]                (needs-info, another party only)

   Note line: Triage <UTC now, at write time>: <draft> -- <reason>
   Status after: [unchanged | waiting | current]
   Tags after: [the full tag_names array, other tags kept]   (state routes only)

     [w] write the route      -> note line (+ status change, if any), then tag read-modify-write
     [c] complete             -> note line + status: completed   (gate failures only)
     [a] archive              -> note line + status: archived    (gate failures only)
     [r] review it            -> hand this one project to /self-org:review-project
     [d] defer                -> no write
     [q] quit                 -> stop; the rest stay as they are
   ```

   For a `needs-info` draft, decide who must answer by `project-triage-gates.md` Step 5: the owner role keeps `current`; another role, circle, or outside party drafts `status: waiting`; when unclear, the owner. The user corrects the addressee before the write like any other part of the draft.

   In the **resolution mode**, show the open question first, before any draft route:

   ```
   Open question: [the question from the last triage line]
   Asks:          [addressee from that line]
   Blocking:      [rubric Family A findings, named only: no outcome, no next action, no clear owner; or none]
   Suggested first step (draft): [one line, only when there is no next action]
   ```

   Ask the user for the answer. The suggested first step is labeled a draft and is never stated as a fact. With the answer, re-run Steps 1–5 of the gates using it as new evidence, then show the block above with the new draft route and note line. Three outcomes:

   - **A gate fails** (the answer says the outcome is done, duplicated, or superseded) → `[c]` or `[a]` as usual.
   - **There is a next action** → route to `ready-for-agent` or `ready-for-human`; a `waiting` project returns to `current` in the same note write.
   - **Still no next action** → the route stays `needs-info` with the note line `needs-info -- answered; add first action: <draft> (<owner role>)` and status `current`. The owner adds the action in GlassFrog or with `/self-org:stalled-project-sweep` `[e]`; the next standard pass sees the project once it moves. If the answer shows someone else must still act, keep or set `waiting` with a `(waits on ...)` line instead.

   A gate failure offers `[c]` and `[a]` instead of `[w]`. A project on a role the actor does not fill offers `[r]`, `[d]` and `[q]` only. When the user disagrees with the draft, take their route and reason instead, as long as the state is in the closed list.

7. **Write on confirmation**, per `project-triage-gates.md` Step 6: read the project with `glassfrog_get_project`, append the note line with `glassfrog_update_project`, adding `status` in the same call for `[c]`/`[a]` and whenever the route changes it (`waiting` for another party, `current` when a `waiting` project is routed back), then for a state call `glassfrog_set_project_tags(project_id, tag_names)` with the read-modify-write from `triage-states.md` Step 3. Refuse any state name outside that file's Step 1 table before the call. Surface every error; never swallow a failed write.

8. **Summarize.** Count walked, routed to each state, completed, archived, deferred, and skipped as already `ready-for-*`. Count `needs-info` projects by status (`current`, `waiting`) and those answered and awaiting a first action, so a move to `waiting` or an answer without an action does not look like progress. List projects drafted for another role's owner. Say whether state writes were drafts only (step 3).

## Behaviour

- **Gates before form.** A project that is already done, duplicated, or superseded does not need its outcome reworded. Asking the reality question first is what keeps the pass cheap.
- **Archive is a status, not a tag.** `completed` when the outcome exists, `archived` otherwise. Both are reversible in GlassFrog. Deletion is permanent and this command does not offer it.
- **No tag without a reason.** Every state write appends its note line first. A bare tag loses why the project was routed, and the next triager has to work it out again.
- **Never write a rubric verdict as a tag.** `needs-next-action`, `needs-outcome`, `executor-mismatch` and the rest are findings from `/self-org:review-project`. Triage writes only the four states in `triage-states.md`.
- **A past-tense title is not a status.** Projects are titled in past tense as an idiom. Gate 1 needs evidence, not grammar.
- **The movement rule is a heuristic.** Say so when a `needs-info` project is skipped and the user expected to see it; they can name it and ask to reopen it as `needs-triage`.
- `waiting`, `someday` and `scheduled` projects are out of the standard pass's scope. `/self-org:stalled-project-sweep` owns `waiting`; the other two are deliberately not-now. The resolution mode is the one exception: it reads `waiting` projects that carry `needs-info`, because their question is the queue it drains.
- **Who must answer sets the status.** A `needs-info` project stays `current` when its owner must answer and moves to `waiting` only when someone else must (ADR-0022). The tag stays in both cases.

## Where this command stops

Triage decides readiness. It does not reword an outcome, link a goal, or re-assign a role — those are quality findings, and `[r]` hands one project to `/self-org:review-project` for them. The standard pass drafts no next action. The resolution mode shows at most one labeled `Suggested first step (draft)` and names it in the answered note line; that is a deliberate, scoped exception to ADR-0018, and it never creates, rewords, or critiques an action. Creating the first next action belongs to `commit-action` ([#161](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/161)); until it ships, the owner adds the action in GlassFrog or with `/self-org:stalled-project-sweep` `[e]`. It does not create a successor project either: a superseded project whose successor does not exist yet is routed to `needs-info` with the successor as the open question, and `/self-org:capture-project` can file it.

## Why this command exists

Most current projects in a real org were found idle, and nothing told anyone which ones still mattered. `/self-org:review-project`'s backlog walk ran five critic lenses on every project every time and saved nothing, so nobody ran it often. This command is the cheap, repeatable pass: retire what is no longer real, route the rest once, and resume from the saved route next time.
