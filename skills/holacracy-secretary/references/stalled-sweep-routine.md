# Stalled-sweep routine

A draft-only agentic routine that assembles a **stalled-project review packet** from live GlassFrog data on a cadence and writes it to the routine ledger, so the session-start hook and `/holacracy:stalled-project-sweep` can surface it. Draft only — the routine surfaces stalled candidates; the human runs the sweep to actually re-energize or archive.

`../shared/agentic-routines.md` defines the mechanism (scheduler fires → ledger → surfaces); this file defines the routine's content. The routine runs as a scheduled-task `SKILL.md` whose prompt is built from the template below at registration time (`/holacracy:routines register stalled-sweep <circle>`).

This is the second routine to ride the shared substrate, after Secretary pre-tactical-prep. Notably, pre-tactical-prep declared "projects lacking recent updates" *out of its v1* precisely because GlassFrog exposes no update timestamp — this routine is the surface that takes on that inference deliberately and honestly.

## Routine prompt template

The registered prompt opens with the canonical scheduled-work preamble from `../shared/actor-and-role-resolution.md` (acting agent + GlassFrog ids, circle, accountability, output channel, and the **"Draft only"** safeguard), then:

1. **Resolve scope.** Confirm the acting agent and the target circle (`glassfrog_get_me`, `glassfrog_list_my_roles`), scoped to the one circle. Never bulk-load the roster (see `docs/solutions/tooling-decisions/glassfrog-v5-inherited-context-single-call.md`).
2. **Read the circle's projects with actions:** for each role in the circle, `glassfrog_list_role_projects(role_id, status: "current", include: ["actions"])`, plus a `status: "waiting"` read for the `blocked` signal. Read only what the resolved circle needs.
3. **Apply the staleness heuristic** — the same detection defined in `commands/stalled-project-sweep.md` step 4; do not re-derive or drift it:
   - `stale` primary: a `current` project with **zero attached actions** (rubric A2).
   - Age (default 90 days, from the registration argument) corroborates — shown, never the sole trigger.
   - `status: "waiting"` → `blocked`.
   - `status: "someday" | "scheduled"` → exempt, never flagged.
4. **Compose the draft packet.** List the flagged projects grouped by verdict (`stale`, then `blocked`). For each: the project (title + `proj_` id + owning role), the signals that flagged it (no-action · age · status), and the honest false-positive caveat — GlassFrog exposes no last-touched timestamp, so a legitimately slow long-horizon project can look identical to an abandoned one; the human's judgment in the sweep is the real filter.
5. **Teach on the judgment calls (R11).** Where a flag is non-obvious, annotate *why* — the source signal plus the rubric or lifecycle reason (e.g. why an action-less project is stalled by definition; why a `waiting` project is `blocked` rather than `stale`). Do not annotate self-evident flags. This is what makes the packet developmental rather than a bare list.
6. **Write the ledger** per `../shared/agentic-routines.md`: write the full draft packet to the sidecar (`packet_path`) first, then append/update the ledger line with `packet_summary` (hook-safe, e.g. "4 stalled, 1 blocked project in Operations Circle — review to re-energize or archive"), `built_at`, the surfacing window, and `last_status: ok`.

## Draft-only boundary

The routine reads and drafts a packet. It **never** archives a project, drafts or files an action, assigns people, issues rulings, or modifies governance (ADR-0003, `../shared/tension-capture-flow.md`). A stalled project surfaced in the packet stays a *candidate* — the human runs `/holacracy:stalled-project-sweep` to make the per-item re-energize/archive decision, where every write is a confirmed keystroke. The routine's job is only to make the stall *visible on a cadence*; the acting stays with the human and the interactive command.

## Degradation

- **GlassFrog unavailable:** produce no packet; name the gap; take no other action (F4 / AE4). Set `last_status: error`.
- **Partial GlassFrog** (e.g. projects load but the actions include fails): the no-action signal is the primary trigger, so if actions can't be read, say so explicitly and fall back to the age + `waiting` signals only — flag less confidently and mark the degradation in the packet rather than silently emitting weaker findings as if they were full ones (AE5).
