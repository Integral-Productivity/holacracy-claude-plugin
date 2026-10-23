# 21. Every work-item lifecycle stage has a command or a tracked gap

Date: 2026-10-23

## Status

Accepted (2026-10-23, Kraig Parkinson, A3 countermeasures C4 and C5)

## Context

From July to October 2026 the plugin had no project-readiness command, and
nobody could see it. The 2026-07-20 project-triage ideation proposed one,
nothing tracked it, and the gap surfaced only when a person counted idle
projects by hand. [ADR-0011](0011-separate-tension-readiness-from-tension-disposition.md)
compared the tension and project families in a table, but the table had no
readiness row, so the project column looked complete.

The root cause is that the plugin had no shared model of work-item lifecycle
stages. Each family (tensions, projects, checklist items and metrics) was
designed on its own, so a missing stage looked the same as a stage nobody
needs. Actions have the same empty slots today.

## Decision

1. `CONCEPTS.md` § Work-item lifecycle holds two closed lists: the work-item
   types and the lifecycle stages.
2. [docs/surface-map.md](../surface-map.md) is a table with a row per type and
   a column per stage. Each cell names a built command by its bare file name,
   or an open tracking issue, or both. A Context column links the ideation and
   ADRs behind each row.
3. `scripts/skills-lint.sh` check 13 enforces the map, with three hardenings:
   - **Review trigger.** The lint fails when a type or stage in the glossary
     has no row or column, or when the map has a row or column the glossary
     does not name. A change that adds a type or a stage edits both.
   - **Staleness.** In CI, a cell held only by issues fails when an issue is
     closed or has had no activity for 90 days. Locally the issue number alone
     is accepted, so the lint stays offline (the same gate as check 5).
   - **July replay.** The test suite rebuilds the map as it stood on
     2026-07-21 and asserts that the lint fails on Project × Readiness.
4. Commands are named without the plugin prefix, so the map does not change
   when the prefix does.

The check is number 13 because the legacy-name check in the self-org rename
takes number 12, and that change also takes ADR number 0020.

## Consequences

- A new work-item type or stage cannot ship without a place in the map.
- An issue that holds a cell must stay alive: a 90-day-idle issue fails CI, so
  the gap is looked at again or the command is built.
- The map does not check the quality of a command, only that one exists.
- Rows for goals, targets, and policies are out of scope until the glossary
  names them.
