# Work-item surface map

Which plugin command serves each lifecycle stage of each work-item type. The
types and stages are defined in [CONCEPTS.md](../CONCEPTS.md) § Work-item
lifecycle. `scripts/skills-lint.sh` check 13 enforces this file
([ADR-0021](adr/0021-every-work-item-lifecycle-stage-has-a-command-or-a-tracked-gap.md)).

**Cell grammar.** Each stage cell names a built command by its bare file name in
backticks (resolved as `commands/<name>.md`), or an open tracking issue
(`#NNN`), or both: a planned command and the issue that tracks it. An empty cell
fails the lint. A cell held only by an issue fails in CI when that issue is
closed or has had no activity for 90 days.

| Work-item type | Create | Readiness | Quality or disposition | Hygiene sweep | Context |
|---|---|---|---|---|---|
| **Tension** | `capture-tension` | `tension-triage` | `process-tension` #160 | `supersession-sweep` | [ADR-0011](adr/0011-separate-tension-readiness-from-tension-disposition.md) splits readiness from disposition; [ADR-0003](adr/0003-glassfrog-tension-api-adoption.md) |
| **Project** | `capture-project` | `project-triage` | `review-project` | `stalled-project-sweep` | [2026-07-20 project-triage ideation](ideation/2026-07-20-glassfrog-project-triage-ideation.html); [ADR-0018](adr/0018-separate-project-readiness-from-project-quality.md); [ADR-0019](adr/0019-the-triage-state-vocabulary-lives-in-the-plugin.md) |
| **Action** | `commit-action` #161 | #409 | #409 | #409 | The project row applied to actions ([#409](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/409)) |
| **Checklist item or metric** | #410 | #410 | `audit-portfolio` | #410 | [checklist-metric-audit skill](../skills/checklist-metric-audit/SKILL.md); [#410](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/410) |

Read a row left to right to see where a work item can stall unseen. Before this
map, the Project row's Readiness cell was empty from July to October 2026: the
ideation above proposed the command, and nothing tracked it.
