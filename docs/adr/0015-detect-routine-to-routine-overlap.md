# 15. Detect routine-to-routine overlap before registering, and stop filtering non-conforming tasks out of sight

Date: 2026-08-10

## Status

Proposed

## Context

[ADR-0006](0006-routine-substrate-scheduler-fires-ledger-surfaces.md) established the routine substrate along a single **vertical** path — a routine fires, stores its packet in `~/.claude/holacracy/routines.jsonl`, and the session-start hook surfaces it. That ADR is scoped entirely to one routine's lifecycle. Nothing in its Decision or Consequences addresses how two routines relate to each other, and it explicitly deferred the adjacent question:

> "It does **not** repoint `commands/context.md` … `context.md` reports the routine *inventory* (a scheduled-future query, distinct from past output) … converging them belongs with the governance routine, not this v1."

That deferral is the only place the word "inventory" appears in the ADR. The horizontal question — *what does this circle's full set of routines look like, and do any of them duplicate each other* — was never decided.

A live case makes the gap concrete. A circle (Market Applied Innovation, read 2026-08-10) carries **five** scheduled tasks that each scan part of the same circle at four different times on different days, none aware of the others:

| Task | Cadence | Territory |
| --- | --- | --- |
| `Platform Engineering circle pull` | Mon 07:30 | Platform Engineering sub-circle |
| `Product delivery watch` | Mon 08:00 | Product role |
| `Customer Success scan` | Tue 08:00 | Customer Success role |
| `Launch readiness scan` | Fri 08:00 | GTM Catalyst role |
| `Company goals status` | monthly, 1st | Circle Lead |

Four of the five are pre-tactical work in all but name. Together they do, badly and four times over, what one registered `holacracy/secretary/pre-tactical-prep/<circle>` routine does once.

Two properties of the current design make this invisible rather than merely unhandled.

**1. Discovery filters *to* the convention, so non-conforming work disappears.** `skills/shared/agentic-routines.md` establishes `holacracy/<role>/<routine>/<scope>` and notes the prefix is load-bearing. Three surfaces then filter on it:

- `commands/routines.md` — "filtered to titles starting `holacracy/`"
- `commands/context.md` — "filtered to tasks whose title starts with `holacracy/`"
- `hooks-handlers/session-start.sh` — "Routine discovery relies on the user's scheduled tasks being tagged with titles that start with `holacracy/…`"

None of the five tasks above uses the prefix. So `/holacracy:routines list` renders an empty roster and, per its own instruction, says "so plainly if none exist." **The user is told they have zero routines while five fire weekly.** A filter designed to avoid scanning unrelated tasks also guarantees the tool cannot see Holacracy work that was set up by hand — which is exactly how every user's first routines get created.

**2. `register` never reads before it writes.** The command goes from cadence derivation (step 2) straight to `create_scheduled_task` (step 4). It never calls `list_scheduled_tasks` to ask what already covers the target circle. Collision is caught only incidentally, by `taskId` uniqueness on the derived slug, and only for the identical routine type on the identical circle.

The plugin already has the conceptual machinery to fix this and simply has not pointed it at routines. `/holacracy:supersession-sweep` deduplicates *tensions* with the S.5.5.1d test — *would this still exist if the other were resolved?* — and `skills/shared/project-review-critics.md` carries dedupe rules for findings. Overlap is a solved problem here for two other object types.

## Decision

Treat routine-to-routine relations as a first-class concern of `/holacracy:routines`, via three changes.

1. **`list` partitions instead of filtering.** Call `mcp__scheduled-tasks__list_scheduled_tasks` **unfiltered**, then bucket into *conforming* (`holacracy/<role>/<routine>/<scope>`) and *candidate* (everything else). Render the candidate bucket as an explicit uncertainty — "N scheduled tasks look like Holacracy work but are not named to the convention, so I cannot tell which circle they cover" — with a proposed conforming rename for each. Never report "no routines" on the basis of a filtered read.

2. **Circle-keyed overlap check.** Group routines by circle: conforming ones by their parsed `<scope>` slug, candidate ones by circle or role names matched in the task prompt body (the prompt is the only identity carrier a non-conforming task has). Flag any circle holding more than one routine, showing each one's cron time and the GlassFrog read tools its prompt calls. **Two routines calling the same read tool against the same circle is the operational definition of redundant scan territory.** Apply the supersession test verbatim, substituting routines for tensions: *would this routine still be needed if the other one ran?*

3. **`register` gains a pre-flight gate.** Before creating a task, run the circle-keyed check for the target circle. On a hit, name the collision — the existing routine, its cadence, its territory — and offer consolidate-or-proceed. Never silently add the sixth.

Two supporting changes make the decision actionable rather than advisory:

4. **Add `unregister <title>`.** `commands/routines.md` currently documents pausing and editing as deferred, so a user who accepts a consolidation recommendation **cannot complete it inside the plugin** — they must delete the superseded tasks by hand through the MCP. A detection feature whose remedy lives outside the tool will be ignored.

5. **State the residual limit honestly.** Matching a non-conforming task to a circle by scanning its prompt body is a heuristic and will produce false positives. Say so in the output, the way `skills/holacracy-secretary/references/stalled-sweep-routine.md` carries its false-positive caveat about missing last-touched timestamps. A sweep that always finds something trains the user to ignore it.

## Consequences

- The `holacracy/` prefix keeps its load-bearing role for the session-start hook, which still needs a cheap filtered read. Only the two human-facing surfaces (`routines list`, and later `context`) move to partitioned reads. The hook's cost profile is unchanged.
- `register` becomes one call more expensive. That is the correct trade: registering a duplicate routine costs a recurring token spend forever, and the pre-flight costs one list call once.
- Reusing the supersession vocabulary keeps one meaning of "redundant" across tensions, project findings, and routines, rather than inventing a third.
- Prompt-body matching is the weak joint. If routine identity later moves into structured metadata on the scheduled task, the heuristic can be retired. Until then it is the only signal a hand-created task carries.
- This is a partial answer to the inventory question ADR-0006 deferred. It decides overlap detection for `commands/routines.md`; it does not decide how `commands/context.md` should render the inventory.

## What this ADR does NOT do

- It does **not** change `hooks-handlers/session-start.sh`. The hook keeps its filtered read.
- It does **not** repoint `commands/context.md`. That surface still reports a flat routine list; converging it with the partitioned view is follow-on work, and remains where ADR-0006 left it.
- It does **not** add pausing, schedule editing, or per-role routine catalogs. `unregister` is added because consolidation is unachievable without it; the rest stay deferred.
- It does **not** auto-consolidate or auto-rename anything. Every finding is a draft recommendation requiring explicit confirmation, consistent with the plugin's no-auto-file stance.
