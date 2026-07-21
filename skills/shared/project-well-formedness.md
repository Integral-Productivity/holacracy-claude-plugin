# Project Well-Formedness -- Shared Reference

This is the canonical rubric for judging whether a GlassFrog **project** is well-formed and well-placed. It is the project-side analog of `tension-triage.md`. Loaded by:

- `/holacracy:review-project` -- the adversarial project-review panel (via `project-review-critics.md`, which turns each dimension below into a critic lens).
- *(Planned)* `/holacracy:capture-project` -- the capture-time guardrail ([#75](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/75)).
- *(Planned)* the stalled-project sweep ([#76](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/76)).

Every project surface loads this file so "done enough" means one thing across the plugin. The rubric **describes**; it never auto-acts. Any fix it implies is drafted for a human to confirm.

---

## What a project is (constitutional grounding)

In Holacracy a **Project** is *a specific outcome the role will work toward* -- a desired end-state, not an activity. **Next-Actions** are the concrete physical steps that move the project. The two are distinct: the project names *where you're going*, the next-action names *the next step*. This distinction is the whole basis of the rubric -- a well-formed project reads as an outcome and has at least one next-action defined, on a role that is actually authorized to pursue it.

There is no "definition of done" field in GlassFrog and (per the note below) no free-text status. A well-stated project outcome **is** its definition of done: "Onboarding guide published to the wiki" is done when the guide is published. When a project needs an explicit acceptance note beyond its title, use the DoD-as-body-convention below.

---

## The two families

Run the dimensions in order. A project is **well-formed** when the first family passes and **well-placed** when the second does. A project can be perfectly well-formed and still mis-placed (serving no goal, out of authority, on the wrong role) -- both families matter.

### Family A -- Well-formed (is this an actionable statement of work?)

**A1. Outcome-framed.** Does the description name an end-state, not an activity?

> *Test:* rewrite the description as "Done when ___." If the blank fills naturally, it's an outcome. If the description *is* the activity ("Work on the onboarding guide", "Improve the process"), it's activity-framed -> **needs-outcome**.

**A2. Has a next-action.** Is there at least one concrete next physical action defined (an Action attached to the project)?

> *Test:* `list_role_projects(role_id, include: ["actions"])` returns the project's actions inline. Zero actions on a `current` project -> **needs-next-action**. A project without a next-action is stalled by definition.

**A3. Clear owner role.** Is the project owned by exactly one role, and is that role named clearly enough that a reader knows who is accountable?

> *Test:* the project has a `role_id`. If the owning role is a catch-all ("General Company Circle") when a more specific role exists, or the reader can't tell who is accountable -> **needs-owner**. (Whether it's the *best-fit* role is Family B / assignment-fit, not this.)

**A4. Definition of done legible.** Can a different role-filler, handed this project cold, tell when it's complete?

> **Substitution test:** *"If a different person energized this role tomorrow, could they tell -- from the project alone -- what 'done' looks like and what to do next?"* If no, the project leans on context that lives only in the current owner's head. Capture it via the DoD-as-body-convention.

### Family B -- Well-placed (is this the right project, on the right role, serving the right ends?)

**B1. Serves a goal.** Does the project support a goal or target the owning role or its circle holds?

> *Test:* is the project already a supporting project of a goal (`list_goal_supporting_projects`), or does one of the role's goals (`list_role_goals`) plausibly cover it? Neither -> **needs-goal** (an orphan project). *Caveat:* not every legitimate project maps to a formal goal -- maintenance and tension-driven work may not. Flag orphans as **questions**, never defects.

**B2. Scope within authority.** Does the project's scope fall within the owning role's accountabilities and domains?

> *Test:* read the role's accountabilities/domains (`get_role` / `glassfrog_get_role_context` / `list_role_domains`) and reason as `/holacracy:check-authority` does (from `authority-boundaries.md`). If the outcome reaches beyond what the role is authorized to do, or into another role's domain -> **out-of-authority**. This is **advisory only**: it names a governance question, it does not edit the project.

**B3. Best-fit owner.** Given the scope, is this the right role -- and is its filler resourced?

> *Test (structural, default):* would another existing role more naturally own this outcome? If yes, that's a role-fit gap. *Test (person-fit, opt-in only):* is the current filler resourced for it? -- surface only when the user explicitly asks; it's a Lead Link question. Advisory only; never re-assign.

---

## State vocabulary

A project's verdict is one state. When several apply, the verdict is the state of the **highest-severity** surviving finding; `well-formed` when none survive.

| State | Meaning | Family | Produced by |
|---|---|---|---|
| `well-formed` | Passes both families; no surviving findings | -- | any surface |
| `needs-outcome` | Activity-framed, not an outcome (A1) | A | review-project, capture-project |
| `needs-next-action` | No next-action defined (A2) | A | review-project, capture-project |
| `needs-owner` | Owner role unclear (A3) | A | review-project, capture-project |
| `needs-goal` | Serves no goal/target (B1) | B | review-project |
| `out-of-authority` | Scope exceeds role authority (B2/B3) | B | review-project |
| `stale` | No movement over time | -- | **sweep (#76) only** |
| `blocked` | Waiting on an external dependency | -- | **sweep (#76) only** |

`stale` and `blocked` require signals (age, `status: "waiting"`, no recent action) that belong to the sweep. `/holacracy:review-project` never emits them.

---

## DoD-as-body-convention

GlassFrog has no definition-of-done field. When a project needs an explicit acceptance note beyond a well-stated outcome, put it in the description body as a trailing line:

```
<outcome-framed description>

DoD: <what "done" concretely means>
```

This parallels the tension `[GOVERNANCE]`/`[TACTICAL]` body-prefix convention -- a body-level convention, not an API field. Keep it short; if the outcome title already makes "done" obvious (A1/A4 pass), no `DoD:` line is needed.

---

## Note on project status (verified against live GlassFrog API v5, 2026-07-20)

Project **status is a closed enum**, not free text: `archived | cancelled | completed | current | scheduled | someday | waiting`. (Older plugin references described it as "freeform text" -- that is stale.) Consequences for the surfaces that load this rubric:

- **Archive** a project by setting `status: "archived"` -- the soft-collapse the plugin prefers over deletion.
- `waiting` is a first-class signal the **sweep (#76)** reads for the `blocked` state.
- Do **not** invent status strings; only the seven enum values are valid.

---

## When the rubric feels heavy

Do not run all seven dimensions as an interrogation. Run them internally and surface only the dimensions that produce a finding the human needs to act on:

- Family A surfaces when a project isn't actionable as written -- otherwise silent.
- Family B surfaces goal/authority/assignment gaps as **questions**, never as defects the AI is certain about.
- On a genuinely well-formed, well-placed project, the honest output is "well-formed -- no findings." Do not manufacture critique to look thorough. A rubric that always finds something trains the user to ignore it.
