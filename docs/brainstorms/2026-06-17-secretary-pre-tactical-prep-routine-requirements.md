---
date: 2026-06-17
topic: secretary-pre-tactical-prep-routine
---

# Secretary Pre-Tactical-Prep Routine — Requirements

## Summary

The plugin's first agentic routine: a Secretary pre-Tactical-prep routine that assembles a draft prep packet from live GlassFrog data ahead of a circle's expected Tactical cadence, and surfaces it when the Secretary-filler next opens Claude — so a meeting at risk of being skipped under load arrives with its agenda already built. Draft-only; the human still runs the meeting.

## Problem Frame

When an org is under load, the Tactical rhythm is the first thing to lapse — meetings get skipped because no one has time to prep them, and once skipped, checklists, metrics, and the tension backlog go stale until the operating cadence quietly dies. Per `STRATEGY.md`, this is the failure the "proactive practice-holding" track exists to attack, and it's the hardest case for an AI: a routine cannot make people meet. The leverage it does have is removing the prep cost that makes skipping the easy choice — assembling the agenda in advance so the meeting is cheaper to hold than to skip.

The plumbing was scaffolded in anticipation but never built: the session-start hook reads a routine ledger, `commands/tactical.md` looks for a pre-Tactical routine's output, and a scheduled-work prompt preamble exists — but nothing fires, registers, or stores a routine today.

Two assumptions this rests on, stated so they can be tested. First, that **prep cost is the marginal factor** tipping a Tactical from held to skipped — if the binding constraint under load is attendance or time-to-attend, a pre-built agenda moves a non-binding lever and v1's value reduces to "better-prepped when a Tactical is held." Second, that v1 **reaches the at-risk Secretary** — but in-session-only surfacing (R9) reaches the Secretary who opens Claude in the prep window, not the fully-buried non-opener that push delivery (deferred) would reach. The v1 hypothesis is therefore narrower than the problem frame: lowering prep cost for already-present Secretaries measurably raises hold rates.

## Key Decisions

- **Anticipate cadence, don't detect skips.** The routine fires on the circle's *expected* Tactical cadence rather than detecting that a meeting was missed. GlassFrog exposes no meeting-occurrence data, so skip-detection isn't reliably available; anticipation sidesteps it.
- **Stage-1 packet only for v1.** The intervention model is an escalating combination — prep packet (default) → cost-visibility when cadence slips → async-minimum on explicit request. v1 ships only the prep packet. The later stages need a slip signal and (for async) a push channel and tighter safeguards, so they are specified as the deferred escalation path, not built.
- **v1 establishes the minimal routine mechanism.** "Reuse the hook" reuses only the surfacing (read) half. v1 must add the firing, registration, and output-storage half this routine needs to exist — this routine is the mechanism's first instance, and the mechanism is the bulk of the build. Sequence v1 in two parts so the mechanism can be validated before the content work: first the mechanism (R1–R3), proven with a stub routine payload; then the Secretary packet (R4–R10) that consumes it.
- **Draft-only, never act.** The routine runs under the existing scheduled-work preamble's constitutional safeguard. It produces a draft for human review and never posts, files, assigns, rules, or modifies governance.
- **Develop, not just assemble.** Per STRATEGY's "develop, don't replace," the packet teaches where prep judgment is non-obvious (R11) rather than only handing over a finished agenda — guarding against prep-dependence and setting a developmental template for the routine catalog. Teaching is proportionate: mechanical items carry no added rationale.

## Actors

- A1. **Secretary role-filler (human)** — reviews the draft packet and runs the Tactical meeting.
- A2. **Pre-Tactical-prep routine (scheduled AI agent)** — builds the draft packet on cadence; draft-only.
- A3. **GlassFrog (system of record)** — source of roles, checklist items, metrics, projects, tensions, and frequencies.
- A4. **Surfacing surfaces** — the session-start hook and the `/holacracy:tactical` command, which present the packet to A1.

## Requirements

**Routine mechanism**

- R1. v1 adds the minimal mechanism the routine needs: register the routine, fire it on a schedule, store its output, and make that output discoverable to the surfacing surfaces. The repo today has only the read half. Depends on Q1 — the storage substrate must be reconciled before this is buildable.
- R2. The routine is identified per circle, following the identifier the codebase already anticipates: `holacracy/secretary/pre-tactical-prep/<circle>`.
- R3. The routine runs under the scheduled-work prompt preamble already defined in `skills/shared/actor-and-role-resolution.md`, carrying its draft-only safeguard.

**Packet contents**

- R4. The packet is a draft Tactical prep/agenda assembled from live GlassFrog data for the target circle.
- R5. The packet includes checklist-item status, metrics due or out of range, and unprocessed tensions on the circle's roles as candidate agenda items. (Two further elements — projects lacking recent updates, and overdue or next actions — are connector-gated and deferred from the v1 packet; see Dependencies.)
- R6. The packet states the circle's expected cadence and when the last Tactical is believed to have occurred, and flags when occurrence data is unavailable rather than asserting a date.
- R11. Where prep judgment is non-obvious, the packet annotates why a candidate item belongs — the source signal plus the role or constitutional reason — so it models the Secretary's prep judgment rather than only assembling it. Mechanically self-evident items (a checklist item that is simply due) need no annotation.

**Delivery and surfacing**

- R7. The routine builds the packet ahead of the circle's expected Tactical cadence.
- R8. The packet surfaces when the Secretary-filler next opens Claude (session-start hook) and on demand via `/holacracy:tactical <circle>`. Depends on Q1 — both surfacing paths must read the same reconciled substrate.
- R9. v1 surfaces only in-session; it sends no push or out-of-session notification.

**Safeguards**

- R10. The routine never acts on the org's behalf. Its output is a draft for human review — no posting, filing, assigning, ruling, or governance modification.

## Key Flows

- F1. **Scheduled build**
  - **Trigger:** the routine fires on the circle's expected Tactical cadence.
  - **Steps:** read the circle's GlassFrog state (A3) → compose the draft packet (R4–R6) → store the output and record it where the surfacing surfaces can find it (R1).
  - **Covered by:** R1, R4, R5, R6, R7, R10, R11
- F2. **Session surfacing**
  - **Trigger:** A1 opens Claude and a recent packet exists for a circle whose Tactical is due.
  - **Steps:** the session-start hook detects the due packet → surfaces a short summary plus a pointer to the full draft.
  - **Covered by:** R8
- F3. **Command pull**
  - **Trigger:** A1 runs `/holacracy:tactical <circle>`.
  - **Steps:** the command surfaces the routine's recent output for that circle, if any.
  - **Covered by:** R8
- F4. **Degraded (no GlassFrog)**
  - **Trigger:** the GlassFrog MCP is unavailable when the routine or command runs.
  - **Steps:** name the limitation and ask A1 to supply the circle context; do not fabricate a packet.
  - **Covered by:** R4

## Acceptance Examples

- AE1. **Covers R6, R7.** **Given** the circle's checklist/metric frequencies imply a weekly cadence, **when** the packet is built, **then** it states "Tactical expected weekly; last occurrence unknown" rather than inventing a last-meeting date.
- AE2. **Covers R6.** **Given** no cadence can be derived from GlassFrog, **when** the packet is built, **then** it asks the Secretary to declare the cadence instead of guessing.
- AE3. **Covers R8.** **Given** a packet built earlier whose underlying GlassFrog data has since changed, **when** it surfaces, **then** it is marked "as of <build time>" so the Secretary can judge its freshness.
- AE4. **Covers R4, R10.** **Given** GlassFrog is unavailable, **when** the routine runs, **then** it produces no packet, names the gap, and takes no other action.
- AE5. **Covers R4, R5.** **Given** GlassFrog returns some data categories but not others (e.g., checklist items load but the tensions call fails), **when** the packet is built, **then** it is produced with the available sections and each unavailable section carries an explicit gap marker rather than being silently omitted.
- AE6. **Covers R11.** **Given** an unprocessed tension surfaced as a candidate agenda item, **when** the packet lists it, **then** it names why the tension is agenda-worthy (the source signal and the role or constitutional reason), while a checklist item that is simply due is listed without added rationale.

## Validation

How the team would know v1 failed. Because the routine anticipates cadence rather than detecting occurrence, it cannot observe whether the prepped meeting happened, and the plugin has no central telemetry — so "the routine produced a packet" is not evidence the bet worked. v1 needs at least one observable proxy: the Secretary's self-report that the Tactical was held, or checklist/metric freshness for the circle as a stand-in for cadence kept. Name and capture that signal before concluding v1 succeeded.

## Scope Boundaries

**Deferred for later**

- Stage 2 (cost-visibility when cadence slips) and Stage 3 (async-minimum substitute) — the escalation path beyond the prep packet.
- Push / out-of-session delivery — the blind spot when the Secretary is too buried to open Claude.
- Other meeting types (Governance) and other roles' routines — future entries in the routine catalog.
- Skip / occurrence detection.

**Outside this product's identity**

- The routine running the meeting, or processing tensions and making decisions — that crosses "develop, don't replace" and is the line stage-3's gating protects.

## Dependencies / Assumptions

- **Firing/storage substrate is unbuilt and inconsistent (blocks R1).** The session hook reads `~/.claude/holacracy/routines.jsonl`; `commands/tactical.md` reads the `scheduled-tasks` MCP for `holacracy/secretary/pre-tactical-prep/<circle>`. The two anticipatory references point at different substrates. v1 must pick or bridge one source of truth.
- **Cadence is derived, not read.** GlassFrog exposes no meeting-schedule or occurrence API. "Expected cadence" is derived from `glassfrog_list_frequencies` (item-definition cadences such as Weekly/Monthly) or declared by the Secretary.
- **GlassFrog read tools.** The packet depends on listing checklist items, metrics, projects, role tensions, and frequencies. The routine degrades gracefully (F4) when GlassFrog is absent, consistent with the rest of the plugin.
- **Two packet elements are connector-gated (drop from v1).** GlassFrog has no action-read tool (only `glassfrog_create_action`), so "overdue or next actions" cannot be populated; and `list_projects` returns no update timestamp (only `created_at`), so "projects lacking recent updates" is not derivable from a single read. Both are deferred from the v1 packet pending connector capability.

## Outstanding Questions

All open items are technical decisions for planning, not product gaps — the product shape is settled.

**Deferred to planning**

- Q1. Which substrate is source of truth for routine output — the `routines.jsonl` ledger the hook reads, or the `scheduled-tasks` MCP the command reads — and how are the two surfacing paths kept consistent? (First task: reconcile the inconsistent anticipatory scaffolding.)
- Q2. How is "expected cadence" determined when item frequencies don't map cleanly to a meeting cadence?
- Q3. What lead time before the expected Tactical should the routine fire?
- Q4. Where the packet content persists (local file vs a GlassFrog draft note) and the visibility implications of each.
- Q5. The registration experience — how a Secretary turns the routine on for a given circle.

## Sources / Research

- `hooks/hooks.json:2-9`, `hooks-handlers/session-start.sh:36,49-50,29-34,71` — session-start hook reads the routine ledger and surfaces today/error entries; comments state the ledger writer doesn't exist yet.
- `commands/tactical.md:18` — anticipates the routine's output via `scheduled-tasks` MCP under `holacracy/secretary/pre-tactical-prep/<circle>`.
- `skills/shared/actor-and-role-resolution.md:102-117` — scheduled-work prompt preamble and the "Draft only" constitutional safeguard.
- `skills/shared/tension-capture-flow.md:11-15,124-127` — canonical draft-and-confirm / no-auto-file safeguard.
- `README.md:104` — `skills/shared/agentic-routines.md` and per-role routine catalogs listed as planned, confirming the mechanism's absence is intentional.
- GlassFrog tools referenced in the skills: `glassfrog_list_checklist_items`, `glassfrog_update_checklist_item`, `glassfrog_list_metrics`, `glassfrog_update_metric`, `glassfrog_list_projects`, `glassfrog_update_project`, `glassfrog_list_role_tensions`, `glassfrog_create_tension`, `glassfrog_list_frequencies`.
