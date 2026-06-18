---
module: agentic-routines
date: 2026-06-18
problem_type: tooling_decision
component: tooling
severity: medium
applies_when: "Building scheduled or agentic routines on the Claude Code scheduled-tasks MCP, or designing any feature on top of an MCP whose storage and output semantics you have not verified live."
related_components:
  - scheduled-tasks-mcp
  - session-start-hook
  - glassfrog-mcp
tags:
  - mcp
  - scheduled-tasks
  - agentic-routines
  - claude-code
  - session-start-hook
  - ledger
  - probe-live
---

# scheduled-tasks MCP fires routines but stores no output — write your own durable store

## Context

When designing the plugin's first agentic routine (the Secretary pre-Tactical-prep routine), the architecture hinged on one unverified assumption: that the Claude Code `scheduled-tasks` MCP could *store* a routine's output where another surface could later read it. Two anticipatory references in the repo disagreed about the substrate — the session-start hook read a `routines.jsonl` ledger; a command read the `scheduled-tasks` MCP — and the plan made resolving this a hard gate before any code was written.

A live probe of the MCP settled it. The lesson generalizes beyond this one routine: **an MCP's scheduling capability and its storage capability are separate questions, and the second is easy to assume away.**

## Guidance

**Probe the `scheduled-tasks` MCP surface before designing on it.** Inspect the tool schemas (`create_scheduled_task`, `list_scheduled_tasks`, `update_scheduled_task`) and, if useful, call `list_scheduled_tasks` once. What the probe shows:

- A scheduled task **is a `SKILL.md` prompt** stored at `~/.claude/scheduled-tasks/<taskId>/SKILL.md`. When it fires, it runs as a **fresh, full Claude session** — so it has normal tool and MCP access (it can call other MCPs and write files). It carries no memory of the conversation that created it; the prompt is the only identity carrier.
- The MCP **stores no per-fire output.** `list_scheduled_tasks` returns only scheduling metadata: `taskId`, `description`, `schedule` / `cronExpression`, `enabled`, `nextRunAt`, `lastRunAt`, `path`. There is no result or body field. A run's output goes to its fresh session and an optional completion notification — nowhere durable.
- Tasks fire **only while the app is open**; if the app is closed when a task is due, it runs on next launch (so a routine can fire late).

**Consequence for design:** if you need a routine's output to outlive its run, the routine must **write its own durable store**. Because the fired routine is a full Claude session with filesystem access, it can do this directly. In this plugin, the routine appends a line to `~/.claude/holacracy/routines.jsonl` (an inline summary plus a sidecar path to the full draft); the session-start hook — which runs as plain shell with **no MCP access** — reads that ledger. The MCP is scheduler/executor only; the ledger is the source of truth both surfaces read. (Captured as `docs/adr/0006-routine-substrate-scheduler-fires-ledger-surfaces.md`.)

**This is a second instance of the live-probe-before-design rule** first captured in [`glassfrog-v5-inherited-context-single-call.md`](glassfrog-v5-inherited-context-single-call.md). The two are complementary: there, the live surface was *richer* than a stale in-repo doc claimed; here, the live surface is *exactly as documented but lacks a capability you'd assume* (output persistence). Same rule — verify the live tool surface — two opposite failure shapes.

## Why This Matters

The wrong assumption would have failed late and expensively. A plan that designed firing and storage on an assumed "the MCP stores the output" model would have frozen a ledger schema and a mechanism spec on top of a substrate that cannot do it — discovered only when wiring the surfacing path, after multiple dependent units were built. Making the probe a pre-build gate turned a stop-the-world risk into a 5-minute check that *confirmed* the bridge architecture (with one refinement: the routine writes the ledger itself).

It also clarifies a non-obvious capability split worth keeping straight: the **scheduled-task run** has full MCP access (it is a real Claude session), but the **session-start hook** does not (it is plain shell). Any data that must cross from the privileged run to the unprivileged hook has to land in a shell-readable file. That asymmetry is the whole reason the ledger exists.

## When to Apply

- Designing any scheduled or recurring agent behavior on the Claude Code `scheduled-tasks` MCP, especially when an output must be surfaced later (in a hook, a command, or a future session).
- More broadly: before committing an architecture to *any* MCP's behavior — scheduling, storage, output, idempotency, auth — probe the live tool surface rather than trusting a reference doc, a prior assumption, or anticipatory scaffolding. If a fork is empirically checkable against the live system, check it during design rather than writing a doc-only spec. *(auto memory [claude]: this matches the standing "probe checkable requirements live" preference.)*

## Examples

The probe, condensed — `create_scheduled_task` inputs vs. what `list_scheduled_tasks` returns:

```
create_scheduled_task(taskId, prompt, description, cronExpression | fireAt, notifyOnCompletion)
   -> stores a SKILL.md at ~/.claude/scheduled-tasks/<taskId>/, runs it as a fresh Claude session

list_scheduled_tasks() -> [{ taskId, description, schedule, cronExpression,
                             enabled, nextRunAt, lastRunAt, path }]
                          # note: no output / result / body field
```

The resulting bridge (each substrate does only what it can):

```
scheduled-tasks MCP   --fires-->   routine (fresh Claude session, full MCP access)
                                       |
                                       | reads GlassFrog, composes draft,
                                       | writes its OWN entry + sidecar
                                       v
                                   routines.jsonl ledger
                                       |
                   +-------------------+-------------------+
                   v                                       v
        session-start hook (shell, no MCP)         /holacracy:tactical (pull-builds
        surfaces the summary                        on demand if no entry)
```

Anti-pattern avoided: designing the routine to "let the MCP hold the output," then discovering at surfacing time that there is nowhere for it to live.
