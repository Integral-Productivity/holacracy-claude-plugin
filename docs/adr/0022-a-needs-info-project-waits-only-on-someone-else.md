# 22. A needs-info project waits only on someone else

Date: 2026-10-23

## Status

Accepted (2026-10-24). Kraig Parkinson chose the option on 2026-10-23 and accepted
it by merging PR #416.

Amends [ADR-0019](0019-the-triage-state-vocabulary-lives-in-the-plugin.md): adds
a status rule to the `needs-info` state. The closed list of four states is
unchanged.

## Context

`/self-org:project-triage` routes a project with an open question to
`needs-info`. The state is a project tag, and the question is in the project's
note line. In the first live pilot runs, most triaged projects landed in
`needs-info`, nearly all because they had no next action.

Two problems showed up ([#414](https://github.com/Integral-Productivity/self-org-claude-plugin/issues/414)):

1. **The need is hard to see.** GlassFrog shows a tag, not the question. A
   reader of the project list cannot tell a project that waits on its owner
   from one that waits on someone else.
2. **Nothing drains the queue.** That is #414's main subject and is out of
   scope here.

GlassFrog has a native project status, `waiting`. It is visible in GlassFrog's
own UI, and `project-well-formedness.md` already prefers native status over a
parallel convention. But `waiting` means "blocked on someone else". Most
`needs-info` questions are addressed to the owner role itself, which is not
blocked; it has work to do. Three options were considered:

1. **Always `waiting`.** Every `needs-info` project also moves to `waiting`.
   This hides owner work behind a "blocked" label. It also moves every such
   project out of `project-triage`'s scope (which reads `current` only) and
   lowers any "current projects idle" measure with no project moving.
2. **Tag only.** Keep today's rule. Visibility comes only from a future
   resolution pass (#414).
3. **Split by who must answer.** Use `waiting` only when the open question is
   addressed to someone other than the owner role.

## Decision

Option 3. When triage routes a project to `needs-info`, it reads who the note
line's question is addressed to:

| The question is for | Project status | Tag |
|---|---|---|
| The owner role (including the Circle Lead when the owner role is unfilled, because the work sits with the Circle Lead) | stays `current` | `needs-info` |
| Another role, another circle, or an outside party | `waiting` | `needs-info` |

Rules that follow from this:

- **The tag stays in both cases.** One tag means one queue: a resolution pass
  (#414) lists every `needs-info` project, whatever its status.
- **The note line names who must answer** in both cases, as it does today. For a
  `waiting` project it also names what the project waits for.
- **The status change is part of the confirmed write.** It goes in the same
  `glassfrog_update_project` call as the note line, after the user confirms,
  like a reality-gate close.
- **Leaving `waiting`.** When the answer arrives, the project goes back to
  `current` and is re-routed. `/self-org:stalled-project-sweep`, which already
  reads `waiting` projects as `blocked`, shows a `waiting` project that has not
  moved.
- **Measures.** Any measure of idle `current` projects must also count
  `waiting` projects that carry `needs-info`. Otherwise a status change would
  look like progress.

## Consequences

**Easier**

- A reader of GlassFrog can see at a glance which projects are blocked on
  someone else, without opening the note.
- `waiting` keeps its GlassFrog meaning, so the stall sweep's `blocked` framing
  stays correct.

**Harder**

- Triage must decide who a question is addressed to. When that is unclear, the
  default is the owner role, so the project stays `current`.
- Two surfaces now touch `needs-info` projects: triage (for `current`) and the
  stall sweep (for `waiting`). The resolution pass in #414 must read both
  statuses.
- Built with #414: `skills/shared/project-triage-gates.md` Step 5 and its
  write table, `commands/project-triage.md` (including the `needs-info`
  resolution mode), and `skills/shared/triage-states.md`, with evals 2 to 4 in
  `evals/cases/project-triage/evals.json`.
