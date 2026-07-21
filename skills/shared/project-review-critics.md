# Project Review Critics -- Shared Reference

The five critic lenses, the finding schema, and the severity/cap/dedupe rules for `/holacracy:review-project`. Written so **both** execution modes seed from one spec with no drift:

- **Inline mode** (backlog walk) -- the command adopts each lens as a sequential reasoning pass in one context.
- **Subagent mode** (deep single-project review) -- the `project-critic` subagent (`agents/project-critic.md`) runs one lens per dispatch and returns findings in the schema below.

Every lens grounds on `project-well-formedness.md`. Load that rubric first; these lenses turn its dimensions into adversarial checks. The safeguard from the tension lifecycle holds here: **draft and confirm only** -- no critic writes anything; the command applies confirmed fixes per-item.

---

## The finding schema

Each lens returns zero or more findings. A finding is:

```
{
  "lens":        "actionability" | "goal-alignment" | "scope-authority" | "assignment-fit" | "red-team",
  "dimension":   "<rubric dimension, e.g. A1 outcome-framed>",
  "state":       "<state-vocabulary value the finding maps to>",
  "severity":    "blocking" | "high" | "moderate" | "low",
  "statement":   "<one-line plain-language gap>",
  "drafted_fix": { "kind": "<see kinds below>", "payload": { ... } },
  "write_class": "additive-on-confirm" | "advisory-draft" | "advisory-route"
}
```

**`drafted_fix.kind` and the write path:**

| kind | write_class | On confirm |
|---|---|---|
| `create-action` | additive-on-confirm | `glassfrog_create_action(role_id, description, parent_project_id, status: "current")` -- **must** pass `parent_project_id` (the reviewed project, `proj_<32hex>`) so the action attaches to *this project*, not a bare role |
| `link-goal` | additive-on-confirm | `glassfrog_link_goal_supporting_project(goal_id, project_id)` -- `goal_id` chosen per the goal-selection rule below |
| `reframe-description` | advisory-draft | **Not written.** Present the reframed description as a draft the human applies (protects their authorship) |
| `archive` | advisory-draft | **Not written.** Recommend `glassfrog_update_project(project_id, status: "archived")` as a draft the human applies |
| `route-to-tension` | advisory-route | Dispatch the `tension-capture` subagent (never a project write) |
| `none` | -- | Observation only; nothing to apply |

The two additive kinds are the only paths that write in Phase 1. `reframe-description` and `archive` are surfaced as drafts; `route-to-tension` goes to the tension flow. This is deliberate per the plan's KTD1.

---

## The five lenses

### 1. Actionability (rubric Family A)

Reads: the project record + its actions (`list_role_projects(role_id, include: ["actions"])`, or `list_project_actions`).

Flags:
- **A1 needs-outcome** -- activity-framed description. `drafted_fix: reframe-description` with an outcome-framed rewrite that preserves the owner's words as much as possible. `advisory-draft`.
- **A2 needs-next-action** -- zero actions on a `current` project. `drafted_fix: create-action` with a concrete first next-action in `payload.description` + the project's `role_id` and `parent_project_id`. `additive-on-confirm`.
- **A3 needs-owner** -- owner role unclear/catch-all. Usually `drafted_fix: none` (naming the better role is a governance question -> hand to assignment-fit). `advisory-draft` or `none`.
- **A4 DoD illegible** -- fails the substitution test. `drafted_fix: reframe-description` appending a `DoD:` line. `advisory-draft`.

### 2. Goal-alignment (rubric B1)

Reads: `list_goal_supporting_projects`, `list_role_goals`, `list_goal_targets`.

Flags:
- **B1 needs-goal** -- project supports no goal. `drafted_fix: link-goal`. `additive-on-confirm`.
- **Goal selection:** present the owning role's goals (`list_role_goals`) for a per-item pick; `payload.goal_id` is the chosen goal. Do not auto-pick.
- **Zero-goals branch:** if the role has **no goals**, there is nothing to link -- do **not** emit a `link-goal` write. Emit `route-to-tension` instead ("role has no goal for this project to support"), `advisory-route`, or `none` if that reads as noise.
- Remember the caveat: orphan projects are **questions**. Maintenance/tension-driven work legitimately has no goal. Severity `low`/`moderate`, never `blocking`.

### 3. Scope-authority (rubric B2) -- **advisory only**

Reads: `get_role` / `glassfrog_get_role_context` / `list_role_domains`; reasons from `authority-boundaries.md` exactly as `/holacracy:check-authority` does.

Flags:
- **B2 out-of-authority** -- scope exceeds the role's accountabilities/domains, or reaches into another role's domain. `drafted_fix: route-to-tension` (a sensed governance tension). `advisory-route`.
- **Never writes to the project.** This lens surfaces a governance question and the route; it does not edit, re-file, or archive.
- Be conservative: a false "overreach" flag on legitimate initiative-taking corrodes trust. Only flag when the mismatch is clear from the role's actual governance.

### 4. Assignment-fit (rubric B3) -- **advisory only**

Reads: `list_role_assignments`, role purposes, `list_skills` (only if person-fit is requested).

Flags:
- **Role-fit (default):** given the scope, another existing role would more naturally own this outcome. `drafted_fix: route-to-tension`. `advisory-route`.
- **Person-fit (opt-in only):** the current filler may not be resourced -- surface **only** when the user explicitly asks; it's a Lead Link question. Default to the structural role-fit reading.
- Never re-assigns. This is the most judgment-heavy, most politically sensitive lens -- highest bar before flagging.

### 5. Red-team -- what's missing / what could go wrong

Reads: everything the other lenses read; its job is to poke holes the rubric dimensions don't name -- hidden dependencies, an outcome that's really three projects, a "done" that can never be verified, a next-action that isn't actually the *next* physical step.

Flags: `drafted_fix: none` most often (it raises questions); occasionally `reframe-description` when the fix is a sharper outcome. Keep it sharp, not paranoid -- one or two real holes beat ten nitpicks.

---

## Severity, floor, cap, dedupe

- **Severity ladder:** `blocking > high > moderate > low`.
  - `blocking` -- the project cannot move as written (activity-framed *and* no next-action).
  - `high` -- a clear gap a reader would hit (no next-action, or out-of-authority).
  - `moderate` -- a real but non-urgent gap (no goal, weak DoD).
  - `low` -- a nitpick.
- **Floor:** drop `low` findings. They don't reach the confirmation block.
- **Cap:** at most **6** findings per project, keeping the highest severity. (Tunable -- start at 6.)
- **Dedupe:** same `dimension` + same project -> keep the highest-severity finding. Across lenses, if two findings recommend the same fix, merge them.

The floor and cap exist to stop over-critique. A wall of findings trains the user to dismiss the whole review. Fewer, sharper findings win.

---

## The advisory-only invariant

`scope-authority` and `assignment-fit` never produce a write to the project. Their only fix kinds are `route-to-tension` or `none`. If a critic in either lens ever drafts a `create-action`, `link-goal`, `reframe-description`, or `archive`, that is a bug -- re-route it to `route-to-tension` or drop it.
