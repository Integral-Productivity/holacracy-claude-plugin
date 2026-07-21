---
description: Register and list Holacracy agentic routines. Turn on the Secretary pre-tactical-prep or stalled-project-sweep routine for a circle, or see which routines are active.
argument-hint: "[list | register pre-tactical-prep <circle> | register stalled-sweep <circle>]"
---

# /holacracy:routines

Manage the actor's Holacracy routines — scheduled, draft-only role work that the plugin prepares on a cadence and surfaces for human review. The mechanism is defined in `skills/shared/agentic-routines.md`.

This is the minimal surface: list active routines, and register a routine. Two routines are registerable today — the Secretary pre-tactical-prep routine and the stalled-project-sweep routine. Richer routine management (pausing, editing schedules, more per-role catalogs) is deferred.

## What this command does

Parse `$ARGUMENTS`:

- **`list`** (or no argument) — **show active routines.** Read the ledger (`${HOLACRACY_ROUTINE_LEDGER:-~/.claude/holacracy/routines.jsonl}`) and, when the `scheduled-tasks` MCP is available, `mcp__scheduled-tasks__list_scheduled_tasks` filtered to titles starting `holacracy/`. Render a roster: each routine's title, schedule, last fire + status, and whether a recent packet is on file. Say so plainly if none exist.

- **`register pre-tactical-prep <circle>`** — **turn the routine on for a circle.**
  1. Resolve the acting Secretary agent and the target circle via `skills/shared/actor-and-role-resolution.md` (`glassfrog_get_me`, `glassfrog_list_my_roles`). If the actor doesn't fill Secretary in `<circle>`, name the mismatch and stop. Announce the resolved scope.
  2. Determine the cadence: derive from the circle's `glassfrog_list_frequencies`, or ask the Secretary to declare it. Translate to a cron expression in local time.
  3. Build the routine prompt from `skills/holacracy-secretary/references/pre-tactical-prep-routine.md`, with the canonical scheduled-work preamble from `skills/shared/actor-and-role-resolution.md` filled in (acting agent + GlassFrog ids, circle, accountability, output channel, **"Draft only"**).
  4. Create the scheduled task: `mcp__scheduled-tasks__create_scheduled_task` with `taskId` / title `holacracy/secretary/pre-tactical-prep/<circle-slug>`, the prompt from step 3, and the cron from step 2. The `holacracy/` prefix is required so the session-start hook can find it.
  5. Confirm: name the registered routine, its cadence, and that it drafts only — the human still runs the meeting.

- **`register stalled-sweep <circle>`** — **turn the stalled-project-sweep routine on for a circle.**
  1. Resolve the acting agent and the target circle via `skills/shared/actor-and-role-resolution.md` (`glassfrog_get_me`, `glassfrog_list_my_roles`). Announce the resolved scope; if the actor fills no role in `<circle>`, name the mismatch and stop.
  2. Determine the cadence: a stall sweep runs on a slower rhythm than a meeting (e.g. monthly or per-quarter). Derive a sensible default from the circle's cadence or ask the actor to declare it. Translate to a cron expression in local time. Optionally accept an age threshold (default 90 days) to pass into the routine prompt.
  3. Build the routine prompt from `skills/holacracy-secretary/references/stalled-sweep-routine.md`, with the canonical scheduled-work preamble from `skills/shared/actor-and-role-resolution.md` filled in (acting agent + GlassFrog ids, circle, accountability, output channel, **"Draft only"**).
  4. Create the scheduled task: `mcp__scheduled-tasks__create_scheduled_task` with `taskId` / title `holacracy/secretary/stalled-sweep/<circle-slug>`, the prompt from step 3, and the cron from step 2. The `holacracy/` prefix is required so the session-start hook can find it.
  5. Confirm: name the registered routine, its cadence, and that it **drafts a packet only** — it never archives or drafts actions; the human runs `/holacracy:stalled-project-sweep` to act on the surfaced candidates per-item.

## Boundaries

- **Draft-only.** Registering a routine never grants it authority to act. The routine reads and drafts; it never files or processes tensions, assigns people, issues rulings, or modifies governance (`skills/shared/tension-capture-flow.md`, ADR-0003).
- **No scheduler, no proactive fire.** If the `scheduled-tasks` MCP is not present, registration can't create a proactive schedule — say so, and point the user at the on-demand path for the routine they were registering: `/holacracy:tactical` (pull-builds the pre-tactical packet) or `/holacracy:stalled-project-sweep` (runs the stall sweep interactively).
- **Minimal by design.** Pausing, editing schedules, and per-role routine catalogs beyond pre-tactical-prep are deferred follow-ups.
