# 6. Routine substrate: the scheduler fires, the routine writes the ledger, the hook surfaces

Date: 2026-06-18

## Status

Accepted

## Context

The plugin's first agentic routine (a Secretary pre-Tactical-prep routine) needs a substrate that does three things: **fire** the routine on a cadence, **store** its output, and **surface** that output to the human. The anticipatory scaffolding pointed at two different, unreconciled substrates:

- The session-start hook reads a per-actor ledger at `~/.claude/holacracy/routines.jsonl` (`hooks-handlers/session-start.sh`). Hooks run as plain shell with **no MCP access**, so the ledger is the only thing the hook can consume.
- `commands/tactical.md` looks for routine output via the `scheduled-tasks` MCP (`mcp__scheduled-tasks__list_scheduled_tasks`), filtered to the title `holacracy/secretary/pre-tactical-prep/<circle>`.

A live probe of the `scheduled-tasks` MCP (2026-06-18) settled how it actually works:

- A scheduled task is a **`SKILL.md` prompt** stored at `~/.claude/scheduled-tasks/<taskId>/SKILL.md`. When it fires, it runs as a **fresh, full Claude session** — so it has normal tool and MCP access (it *can* call GlassFrog and write files), unlike the hook.
- The MCP **stores no per-fire output.** `list_scheduled_tasks` returns only scheduling metadata (`schedule`, `cronExpression`, `enabled`, `nextRunAt`, `lastRunAt`, `path`). There is no result/body field; a run's output goes to its fresh session and an optional completion notification, not to durable storage the hook could read.
- Tasks fire while the app is open; if the app is closed when a task is due, the task runs on next launch.

So neither substrate alone is sufficient: the MCP can fire but not store; the ledger can be read by the hook but is inert (nothing writes it).

## Decision

Bridge the two substrates by giving each the job it can do, with the **ledger as the single source of truth both surfacing surfaces read**.

1. **The `scheduled-tasks` MCP fires** the routine on the derived cadence by running its `SKILL.md` prompt.
2. **The routine writes its own output to the ledger.** Because the fired routine is a full Claude session (with GlassFrog and filesystem access) and the MCP stores nothing, the routine's prompt — as part of its run — reads GlassFrog, composes the packet, and appends/updates its `~/.claude/holacracy/routines.jsonl` entry (honoring `HOLACRACY_ROUTINE_LEDGER`). The entry carries scheduling metadata plus an **inline packet summary, a build timestamp, a surfacing window (`surface_from`/`surface_until`), and a sidecar path** to the full draft. New fields are optional so the hook's existing parse is unaffected.
3. **Both surfaces read the ledger.** The session-start hook surfaces a sanitized summary across the surfacing window; `/holacracy:tactical` reads the same ledger and pull-builds the packet on demand when no entry exists.
4. **Degradation floor.** When the `scheduled-tasks` MCP is not present (it is not bundled by the plugin), there is no proactive fire, but `/holacracy:tactical` still pull-builds the packet. The routine never depends on MCP output storage.

## Consequences

- The contested Q1 substrate split is resolved: the ledger is authoritative, the MCP is scheduler/executor only, and the hook and `/holacracy:tactical` converge on the same store.
- The "store output" problem the MCP cannot solve is solved by the routine writing the ledger itself — which is only possible because the fired routine is a full Claude session, not a shell hook. This is why GlassFrog reads live in the routine run, never in the hook.
- A useful simplification: the "routine" *is* a scheduled-task `SKILL.md` prompt, so most of the build is authoring markdown (the routine prompt, the mechanism spec, a registration command); the only executable change is the bash hook that surfaces the ledger.
- Proactive firing is gated on the unbundled `scheduled-tasks` MCP. For users without it, v1 delivers on-demand packet assembly (pull-build), not the proactive prep the hypothesis rests on — a known, stated limitation, not a silent gap.
- The app-must-be-open firing model means a packet may be built late (on next launch), which is why surfacing is a window match (`surface_from`/`surface_until`) rather than an exact-day match.

## What this ADR does NOT do

- It does **not** repoint `commands/context.md` or `commands/governance.md` onto the ledger. `context.md` reports the routine *inventory* (a scheduled-future query, distinct from past output) and `governance.md` references the deferred pre-*governance*-prep routine; converging them belongs with the governance routine, not this v1.
- It does **not** finalize the exact ledger field names or the sidecar file layout — those are settled in the mechanism spec (`skills/shared/agentic-routines.md`) and may adjust during implementation, as long as the hook's parse contract is preserved.
- It does **not** add AI-agent self-filing of tensions. The routine reads and drafts only; the draft-only / never-auto-act safeguard (ADR-0003, `skills/shared/tension-capture-flow.md`) is preserved.
