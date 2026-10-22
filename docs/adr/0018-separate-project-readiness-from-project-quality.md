# 18. Separate project readiness from project quality

Date: 2026-10-22

## Status

Proposed

## Context

[ADR-0011](0011-separate-tension-readiness-from-tension-disposition.md) split
tension work into two questions: *is this tension ready?* and *what does it
become?* Its comparison table marked the project column as already clean, with
`/holacracy:review-project` in the "assess quality" row. That reading was
correct about quality and silent about readiness. Projects have no readiness
surface, and `review-project` has been doing part of that job without saying so.

`/holacracy:review-project` has two modes:

- **Deep review** of one named project. Five independent critic subagents
  (actionability, goal alignment, scope and authority, assignment fit, red team)
  audit it, and the human confirms each fix.
- **Backlog walk** with no argument or a circle name. The same five lenses run
  inline over every current project and give each a one-line verdict.

The backlog walk looks like triage, but it lacks every property that makes
triage useful as a recurring practice. The reference is the
[mattpocock `triage` skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/triage/SKILL.md),
which the 2026-07-20 project-triage ideation set out to adapt:

| Triage property | Backlog walk today |
|---|---|
| Shows only items that need attention (untriaged, or changed since last triage) | Walks every current project, every run |
| Saves one state per item, so the next run resumes | Saves nothing; the verdict is gone at session end |
| Checks the item against reality first (already done? duplicate? rejected before?) | Assumes the project is real and audits its form |
| Routes the item: needs-info, ready-for-agent, ready-for-human, close | Produces findings, drafts, and tensions |
| Costs little per item; depth only when needed | Five lenses on every project |

The two jobs ask different questions. Quality asks *is this project good?*
Readiness asks *what happens next with this project, and who acts?* Fusing them
gives a walk that is too expensive to run often and too forgetful to run as a
practice. That is the same conflation ADR-0011 undid for tensions, found one
column over.

## Decision

**Project readiness and project quality are separate concerns, handled by
separate commands.**

1. **A new readiness command, `/holacracy:project-triage`**, owns the backlog
   walk. It is the project twin of `/holacracy:tension-triage`, named in the
   same noun-first form. Build tracked in
   [#393](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/393).

2. **`/holacracy:review-project` keeps only the deep single-project audit.** Its
   no-argument and circle-argument modes become deprecated paths that dispatch to
   `/holacracy:project-triage`, for the same reason ADR-0011 kept
   `process-inbox` as an alias: removing a shipped mode outright is a breaking
   change, and under `bump-minor-pre-major: false` that takes 0.x to 1.0.0.

3. **Triage states are routes, not quality verdicts.** The rubric's verdicts
   (`needs-outcome`, `needs-next-action`, `out-of-authority`, and the rest in
   `skills/shared/project-well-formedness.md`) stay as review findings. Triage
   assigns exactly one state:

   | State | Meaning |
   |---|---|
   | `needs-triage` | Not yet assessed, or reopened |
   | `needs-info` | The owner role must clarify before anyone can act |
   | `ready-for-agent` | Well enough formed that an AI agent filler can take the next action |
   | `ready-for-human` | Well enough formed, but the next action needs a person |
   | archived | Not to be pursued; closed with a stated reason |

   Agent versus human reuses the rubric's executor-fit check rather than
   inventing a second one.

4. **State is saved on the project as a GlassFrog tag**, through
   `glassfrog_set_project_tags`. No tag means untriaged. The tag vocabulary is
   closed and owned by `glassfrog-config`, so that repository carries the
   vocabulary change. Archive uses the project status, as
   `/holacracy:stalled-project-sweep` already does.

5. **Reality gates run before any quality check**, as authority runs first in
   ADR-0011: is the outcome already reached, is this a duplicate of another
   project, has it been superseded, does the owner role still exist? A project
   that fails a gate is archived or merged, and no rubric work is spent on it.

6. **Triage hands depth to review.** When a project needs more than a route,
   triage offers `/holacracy:review-project` on that one project. Triage never
   drafts reframes or runs the five lenses itself.

7. **Write classes stay narrow.** Triage writes only the state tag and, on
   confirmation, the archive status. It does not edit descriptions, create
   actions, or link goals; those remain review's additive writes. Every write is
   confirmed per project, never batched, as in every other plugin surface.

## Consequences

**Easier**

- Triage can run often because it is cheap and resumes from saved state. The
  project backlog gets the recurring practice that tensions have.
- `ready-for-agent` gives a queue that AI agent role fillers can pull from,
  which the plugin has no equivalent of today.
- review-project states honestly what it does: one project, in depth.
- The tension and project families now have the same shape: create, readiness,
  quality or disposition, and hygiene sweep.

**Harder**

- One more command. The cost is the same as ADR-0011's: two surfaces mean a
  handoff, and a handoff can drop context.
- A cross-repository dependency on `glassfrog-config` for the tag vocabulary.
  `glassfrog-config` records that GlassFrog tag writes replace the whole tag
  set; if `glassfrog_set_project_tags` behaves the same (to verify in #393),
  triage must read the project's existing tags and write them back with the
  state tag, or it deletes them.
- The deprecation window for review-project's walk modes must be removed later,
  in a major.

**Deferred**

- **Triage notes and resume.** Pocock's triage keeps notes on the item so the
  next session does not ask resolved questions again. No project-note API is
  confirmed. The candidates are a section of the project description under the
  DoD convention, or a role note; neither is chosen here. Until then, the saved
  state gives resume-by-bucket but not resume-by-question.
- The exact gate list and the name of its shared reference file, decided in #393.

## Related

- [ADR-0011](0011-separate-tension-readiness-from-tension-disposition.md) — the
  same split for tensions. This ADR extends its table rather than editing it.
- [ADR-0012](0012-test-the-skills-not-just-the-scaffolding.md) — the new command
  ships with an eval case.
- [#393](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/393)
  — the build issue.
