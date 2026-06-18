# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

> Seeded from the agentic-routines area. The broader Holacracy domain (Circle, Role, Core Role, Tension, Tactical, Governance, and the Core Role names) is canonical Holacracy vocabulary defined within the skills themselves; a repo-wide concept map is a `ce-compound-refresh` bootstrap, not yet run here.

## Agentic routines

### Routine
A scheduled, draft-only unit of Core Role work the plugin prepares on a cadence and surfaces for a human to review — it never acts on the organization. Distinct from a generic scheduled task: a routine carries Holacratic role identity (it fires as a declared agent acting in a specific role and circle) and the constitutional draft-only safeguard.

A routine runs as a fresh agent session with full tool access, reads the governance data its single resolved role needs, composes a draft, and writes that draft to the Routine ledger. It never files or processes tensions, assigns people, issues rulings, or modifies governance — surfaced candidates are always left for the human to act on.

### Routine ledger
The durable per-actor store a routine writes after each fire, and that the surfaces read — the session-start briefing and the owning role command. It is the source of truth that bridges the scheduler (which fires routines but stores no output) and the session-start briefing (which has no live tool access). Each entry carries scheduling metadata plus a short packet summary, a build timestamp, a Surfacing window, and a pointer to the full draft.

### Surfacing window
The span during which a built routine packet is shown at session start, rather than only on its exact fire day. A window is used because a routine can fire late — when the app was closed at the scheduled time — so the packet should stay visible across the prep-to-meeting period.
