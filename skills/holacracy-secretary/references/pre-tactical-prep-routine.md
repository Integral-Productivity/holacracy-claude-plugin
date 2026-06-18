# Pre-Tactical-prep routine

The Secretary's first agentic routine. It assembles a **draft** Tactical prep packet from live GlassFrog data ahead of a circle's expected Tactical cadence, and writes it to the routine ledger so the session-start hook and `/holacracy:tactical` can surface it. Draft only — the human still runs the meeting.

Loaded as `../shared/agentic-routines.md` defines the mechanism; this file defines the routine's content. The routine runs as a scheduled-task `SKILL.md` whose prompt is built from the template below at registration time (`/holacracy:routines`).

## Routine prompt template

The registered prompt opens with the canonical scheduled-work preamble from `../shared/actor-and-role-resolution.md` (acting Secretary agent + ids, circle, accountability, output channel, and the **"Draft only"** safeguard), then:

1. **Resolve scope.** Confirm the acting Secretary agent and the target circle (`glassfrog_get_me`, `glassfrog_list_my_roles`), scoped to the one circle. Never bulk-load the roster (see `docs/solutions/tooling-decisions/glassfrog-v5-inherited-context-single-call.md`).
2. **Read circle state** (the readable tools only):
   - `glassfrog_list_checklist_items` — items and their status.
   - `glassfrog_list_metrics` — metrics due or out of range.
   - `glassfrog_list_role_tensions` — unprocessed tensions on the circle's roles, as candidate agenda items.
   - `glassfrog_list_frequencies` — to derive the expected Tactical cadence.
3. **Derive cadence, never assert occurrence.** Compute expected cadence from frequencies, or use a Secretary-declared cadence. GlassFrog exposes no meeting-occurrence data, so state "Tactical expected `<cadence>`; last occurrence unknown" — never invent a last-meeting date (AE1). If no cadence can be derived, ask the Secretary to declare one rather than guessing (AE2).
4. **Compose the draft packet** with these sections: checklist status, metrics due/out-of-range, and unprocessed tensions as candidate agenda items. Connector-gated elements — "projects lacking recent updates" and "overdue/next actions" — are out of v1 (no read tool / no update timestamp); omit them without error.
5. **Teach on the judgment calls (R11).** Where prep judgment is non-obvious, annotate *why* a candidate belongs — the source signal plus the role or constitutional reason (e.g. why an unprocessed tension is agenda-worthy). Do not annotate self-evident items (a checklist item that is simply due). This is what makes the packet developmental rather than a finished hand-off.
6. **Write the ledger** per `../shared/agentic-routines.md`: write the full draft to the sidecar (`packet_path`), then append/update the ledger line with `packet_summary`, `built_at`, the surfacing window, and `last_status: ok`.

## Draft-only boundary

The routine reads and drafts. It never files or processes tensions, assigns people, issues rulings, or modifies governance (ADR-0003, `../shared/tension-capture-flow.md`). A candidate tension surfaced as an agenda item stays a candidate for the human to act on in the meeting.

## Degradation

- **GlassFrog unavailable:** produce no packet; name the gap; take no other action (F4 / AE4). Set `last_status: error`.
- **Partial GlassFrog** (e.g. checklists load but the tensions call fails): produce the available sections and give each unavailable section an explicit gap marker rather than silently omitting it (AE5).
