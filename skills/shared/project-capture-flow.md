# Project Capture Flow -- Shared Reference

This document specifies the canonical **P-flow** used by every project capture in this plugin: the on-demand `/holacracy:capture-project` command and the `project-capture` subagent (and, later, ambient project-language detection and stalled-sweep escalation).

The P-flow is **draft-and-confirm**: Claude proposes a complete project (owner role + outcome-framed description + a first next-action), soft-gates it against the well-formedness rubric's Family A, the human confirms or edits per-project, and only on explicit confirmation do the write calls fire. No auto-file. No silent file. Per-project confirmation, never batched.

This is the create-flow **twin of `./tension-capture-flow.md`**. Where tension capture files a lived gap on a role's backlog, project capture files a desired outcome plus its first physical step -- and, unlike tension capture, it *teaches* the shape of a well-formed project as it goes. That teaching is the whole point: thin projects exist because they get filed thin, and the cheapest place to fix that is the moment of filing.

---

## The Constitutional Safeguard

> **Draft and confirm only.** Do not call `glassfrog_create_role_project`, `glassfrog_create_action`, or `glassfrog_link_goal_supporting_project` without explicit human confirmation. Do not review, reframe, archive, or re-own *existing* projects on the human's behalf -- that is `/holacracy:review-project`'s job. One project per invocation; never batch.

This is non-negotiable across every code path that files a project. The principle mirrors the tension boundary: Claude is a capture *assistant* and a *coach on form*; the human decides what actually lands. The soft-gate never becomes a hard gate -- a determined human can file an imperfect project, because the teaching already happened.

---

## What a project is (grounding)

Load `./project-well-formedness.md` for the full rubric. The one distinction this flow turns on:

- A **Project** is *a specific outcome the role will work toward* -- a desired end-state, not an activity. ("Onboarding guide published to the wiki", not "Work on the onboarding guide.")
- A **Next-Action** is the concrete physical step that moves it. ("Draft the guide's table of contents.")

A well-formed project reads as an outcome **and** has at least one next-action defined. This flow files both in one confirmed pass.

---

## The Capture Flow

### Step 1 -- Determine intent

The flow can begin in three ways:

1. **Explicit command.** User runs `/holacracy:capture-project` (optionally with the project text as `$ARGUMENTS`). Intent is clear; proceed.
2. **Ambient detection.** *(future)* `holacratic-ai-governance` is loaded and Claude observes project-shaped language in conversation ("I need to get X done", "we should build Y", "my goal this quarter is Z"). Claude **pauses** and offers to capture: *"That sounds like a project worth filing -- want me to draft one?"* If the user assents, proceed. If they deflect, drop it.
3. **Stalled-sweep escalation.** *(future, #76)* The stalled-project sweep surfaces a role with no live projects and offers to capture one. User confirms or skips; proceed for those they confirm.

Only the explicit path ships in this phase. The other two are named here as the extension seam -- the same P-flow serves them when they land.

Never proceed past Step 1 without the user's clear assent to capture.

### Step 2 -- Resolve owner role

Follow the procedure in `./actor-and-role-resolution.md`, **with the target = any role the actor fills in the relevant circle** (not a single named target role).

1. Confirm actor identity via `glassfrog_get_me`.
2. Load the actor's role roster via `glassfrog_list_my_roles`.
3. Narrow to the circle the project's content implies (use conversation context, or ask).
4. Within that circle, identify the role(s) the actor fills that the project's outcome most plausibly attaches to.
5. If exactly one plausible owner role -> use silently.
6. If multiple -> ask: *"This could be owned by [Role A] or [Role B] -- which role is accountable for this outcome?"*
7. If zero (the actor fills no role in that circle) -> name the constraint per `./actor-and-role-resolution.md` Step 3.

Announce the resolved context in the first response, e.g. *"Filing on **Marketing of General Company Circle** (role_id: role_xxx)."*

### Step 3 -- Elicit the project (if starting thin)

If the user passed no `$ARGUMENTS`, ask for the **outcome** first: *"What outcome do you want this role to move toward?"* Preserve the user's own words; the project is theirs, not a rewrite.

If the user passed text, use it as the seed and move to Step 4 -- the soft-gate does the completing.

### Step 4 -- Soft-gate on rubric Family A (teach, don't block)

Load `./project-well-formedness.md` and run **Family A only**, internally. Surface only the dimensions that produce a gap. For each gap, present a **drafted fix** and a one-line teaching of *why it matters* -- never an interrogation.

- **A1. Outcome-framed.** Apply the "Done when ___" test. If the description is an activity ("Work on the onboarding guide", "Improve the process"), draft an outcome reframe and teach the distinction:
  > *"That reads as an activity. A project is the outcome you're driving toward -- so it's clear when it's done. How about: **'Onboarding guide published to the wiki'**? (Then 'done' is obvious: the guide is up.)"*

- **A2. Has a first next-action.** At capture time the project does not exist yet, so this is **elicited**, not checked via `list_role_projects`. If the user named no concrete next step, draft one from the outcome and teach:
  > *"A project without a next step stalls the moment it's filed. What's the first physical action -- something you could literally do next? I'd suggest: **'Draft the guide's table of contents.'**"*

- **A3. Clear owner role.** If Step 2 landed on a catch-all role (e.g. "General Company Circle") when a more specific role plausibly owns the outcome, name it and offer the clarification. (Whether it's the *best-fit* role is Family B / review-project's job -- not this gate.)

If the outcome needs an explicit acceptance note beyond its title, use the **DoD-as-body-convention** from the rubric (a trailing `DoD: ...` line in the description). Keep it short; skip it when the outcome title already makes "done" obvious.

If Family A passes clean, say so and go straight to Step 6 -- do not manufacture critique to look thorough.

### Step 5 -- Draft the project + first next-action

Assemble two strings:

- **Project description** -- outcome-framed, the user's words preserved, ≤2000 characters (per the live `create_role_project` schema, verified 2026-07-20), with an optional trailing `DoD:` line.
- **First next-action** -- one concrete physical step, ≤2000 characters (per the live `create_action` schema).

### Step 6 -- Present the per-project confirmation

Show the user a single, compact confirmation block:

```
Owner role:        [Role name] of [Circle name]    (role_id: role_xxx...)
Project:           [outcome-framed description, with DoD: line if used]
First next-action: [the concrete next step]
Notes:             [any Family-A teaching applied, e.g. "reframed from activity to outcome"]

File this? [y] yes  [e] edit  [n] no
```

The user can:

- **y / yes** -> Proceed to Step 7.
- **e / edit** -> Allow editing any field (owner role, project, next-action), then re-present. Loop until y or n.
- **n / no** -> Abort. Confirm the abort; nothing is written. Return to the original conversation.

Per-project confirmation. Never batched.

### Step 7 -- File the project, then its first next-action (additive write chain)

On confirmation, two calls **in order** -- the action cannot attach until the project id exists:

```
1. glassfrog_create_role_project(role_id, description, status: "current")  -> Project { id: proj_xxx, ... }
2. glassfrog_create_action(role_id, <first-next-action>, parent_project_id: proj_xxx, status: "current")  -> Action { id: act_xxx, ... }
```

- **Set `status: "current"` explicitly on both.** The `create_role_project` default "depends on org config"; do not rely on an unknown default. `current` is a member of the closed enum `archived | cancelled | completed | current | scheduled | someday | waiting` (verified live 2026-07-20).
- **`parent_project_id` is the attachment mechanism** -- it is what makes the action the project's first next-action (satisfying rubric A2). Feed the id returned by call 1 into call 2.
- **Trust the returned ids. Do not list-back to verify.** `glassfrog_list_role_projects` / `list_project_actions` may not return the just-created records immediately (propagation/scoping) -- the create responses are the only reliable same-session confirmation. This is the same caveat documented for tensions in `../holacratic-ai-governance/references/glassfrog-api-constraints.md`.

**On error:**

- If **call 1** fails, surface honestly: *"Couldn't file the project -- GlassFrog returned [error]. The draft is still here; want me to retry or adjust?"* Do not attempt call 2.
- If **call 2** fails after call 1 succeeded, report the split state plainly: *"The project filed (proj_xxx), but I couldn't attach the first next-action -- GlassFrog returned [error]. Want me to retry just the action?"* Never silently swallow it; the project exists but is a stub until the action lands.

### Step 8 -- Goal-alignment nudge, then acknowledge and return

After a successful file, a **light, skippable** nudge:

1. Call `glassfrog_list_role_goals(role_id)`.
2. **If it returns ≥1 goal**, offer one line: *"Want to link this project to one of [Role]'s goals? [1] [Goal A]  [2] [Goal B]  [s] skip."* On a pick, call `glassfrog_link_goal_supporting_project(goal_id, proj_xxx)`. On skip, move on.
3. **If it returns zero goals**, skip **silently** -- no "this role has no goals" noise.

Scope-authority and assignment-fit are **out of scope** here -- those are `/holacracy:review-project`'s heavier, often-premature-at-birth checks.

Return a compact structured result:

```
Filed project: [description excerpt, ~60 chars]
Project ID:    [proj_xxx]
First action:  [act_xxx]  ([next-action excerpt])
Owner role:    [Role name] of [Circle name]
Goal link:     [linked to "Goal A" | offered, skipped | none (role has no goals)]
```

Then continue the original conversation. Do not interrogate the user about next steps -- they will work the project on their own time.

---

## What the Flow Does NOT Do

- **No auto-file.** Every project passes through Step 6 confirmation, every time.
- **No batched confirmation.** One project per invocation. If the user describes a second project mid-flow, finish or abort the current one, then surface the second separately.
- **No hard block.** The soft-gate teaches and drafts fixes; it never refuses to file. A determined user can file an activity-framed project -- that's their call.
- **No existing-project review.** Reviewing, reframing, re-owning, or archiving projects already on file is `/holacracy:review-project`'s job, not this flow's.
- **No scope-authority or assignment-fit check.** Those are Family B (review-project), deliberately deferred -- they are often premature at a project's birth.
- **No deletion.** `glassfrog_delete_project` is permanent and out of scope here. Archiving (`status: "archived"`) is a review-project / sweep action, not a capture action.
- **No push to the GlassFrog UI.** The whole point is to keep capture cheap and in-conversation.

---

## When GlassFrog Is Not Connected

Name it. Do not fabricate a `role_id` or `proj_id`. Tell the user: *"GlassFrog isn't connected -- I can draft the project and its first next-action for you to file manually, but I can't call `create_role_project`. Want me to draft for manual entry?"* If yes, produce a plain-text draft (resolved owner role, outcome-framed description, first next-action, any DoD line) formatted for manual entry into the GlassFrog UI. Do not silently assume an actor or invent role data.

---

## How This Flow Composes with Other Surfaces

| Surface | How it uses this flow |
|---|---|
| `/holacracy:capture-project` | Entry at Step 1.1 (explicit command). Runs Steps 2–8 via the `project-capture` subagent. The capture-time twin of the after-the-fact `/holacracy:review-project`. |
| `/holacracy:review-project` | Operates on *existing* projects (Family A **and** B, adversarial critics, advisory reframes/archives). Where this flow prevents thin projects at intake, review-project cleans them up after the fact. Both load `./project-well-formedness.md` so "well-formed" means one thing. |
| `holacratic-ai-governance` (ambient detection) | *(future)* Entry at Step 1.2 (ambient). On user assent, dispatches the `project-capture` subagent to run Steps 2–8. |
| Stalled-project sweep (#76) | *(future)* Entry at Step 1.3 (escalation). A role with no live projects can route into this flow to capture one. |

All surfaces that file a project call the same `create_role_project` -> `create_action(parent_project_id)` primitive with the same constitutional safeguard. They differ in conversational shape, not in what lands in GlassFrog.
