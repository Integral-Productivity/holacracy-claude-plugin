# Agentic routines — the routine-catalog mechanism

Shared reference loaded by role skills (`../shared/agentic-routines.md`) and by a skill's `references/*` files (`../../shared/agentic-routines.md`). It defines how a Holacracy routine is registered, fired, stored, and surfaced. It is the reusable mechanism; per-role routine *content* lives with each role skill.

A **routine** is a scheduled unit of role work that the plugin prepares on a cadence and surfaces for a human to review. Routines never act on the organization: they draft for human review. See `tension-capture-flow.md` for the constitutional draft-only contract this inherits.

## The substrate (per ADR-0006)

A routine rides three pieces, each doing the job it can do:

1. **The `scheduled-tasks` MCP fires it.** A routine is registered as a scheduled task whose `SKILL.md` prompt runs as a fresh, full Claude session on the cadence. The fired session has normal tool access — it can read GlassFrog and write files (unlike the session-start hook, which is plain shell with no MCP). The MCP stores no per-fire output.
2. **The routine writes its own output to the ledger.** Because the MCP stores nothing and the fired session has filesystem access, the routine's prompt appends/updates a line in the per-actor ledger as the last step of its run.
3. **The surfaces read the ledger.** The session-start hook surfaces a summary; the owning role command (e.g. `/holacracy:tactical`) reads the same ledger and pull-builds on demand when no entry exists.

When the `scheduled-tasks` MCP is absent (it is not bundled by the plugin), there is no proactive fire — only the on-demand pull-build path. A routine must never depend on MCP output storage.

## Title convention

Every routine title is `holacracy/<role>/<routine>/<scope>` — e.g. `holacracy/secretary/pre-tactical-prep/operations-circle`. The leading `holacracy/` is load-bearing: the session-start hook filters on it to find routine entries without scanning unrelated scheduled tasks. Use a kebab-cased circle slug for `<scope>`.

## The prompt preamble

A fired routine has no shared memory — the prompt is the only carrier of identity. Every routine prompt opens with the canonical scheduled-work preamble defined in `actor-and-role-resolution.md` (acting agent + GlassFrog id, acting role, acting circle + id, accountability, output channel, and the **"Draft only"** constitutional safeguard). Do not duplicate that block here — reference it and fill it at registration time.

## The ledger entry contract

The routine appends or updates one JSON object per line in `${HOLACRACY_ROUTINE_LEDGER:-~/.claude/holacracy/routines.jsonl}`. The session-start hook already parses these fields and must keep working unchanged for entries that lack the new ones — so every field below beyond the original five is **optional**.

| Field | Origin | Purpose |
|---|---|---|
| `id`, `title`, `next_fire`, `last_fire`, `last_status` | existing | scheduling metadata the hook already reads (`last_status` ∈ `ok` / `error` / `skipped`) |
| `packet_summary` | new | a short, hook-safe summary the hook surfaces (never the raw full draft) |
| `packet_path` | new | sidecar file path holding the full draft, read on demand by the owning command |
| `built_at` | new | ISO-8601 build time, surfaced as AE3's "as of" marker |
| `surface_from` / `surface_until` | new | the window during which the hook surfaces the entry — a window match, not an exact `next_fire`-day match, because a task may fire late (on next app launch) |

The full draft lives in the sidecar (`packet_path`), not inline, so the ledger line stays small and the hook never has to handle arbitrary body text. The hook surfaces only `packet_summary`.

## Lifecycle

1. **Register** — a role command (e.g. `/holacracy:routines`) creates the scheduled task with the canonical title and a prompt carrying the preamble.
2. **Fire** — the `scheduled-tasks` MCP runs the prompt on cadence as a fresh Claude session.
3. **Read & compose** — the routine resolves its actor/role/circle (`actor-and-role-resolution.md`), reads the governance data it needs (scoped to the one role), and composes a draft.
4. **Write** — the routine writes the sidecar full draft and appends/updates its ledger line (`packet_summary`, `packet_path`, `built_at`, window, `last_status: ok`; on failure, `last_status: error`).
5. **Surface** — the session-start hook surfaces the summary within the window; the owning command surfaces the full draft on demand.

## Safeguards

- **Draft only.** A routine never files proposals, processes tensions, assigns people, issues rulings, or modifies governance. It collects and drafts for human review. This is the non-negotiable contract in `tension-capture-flow.md`; AI-agent self-filing is explicitly out of scope (ADR-0003).
- **Single-role scope.** A routine reads only what its one resolved role needs; never bulk-load the roster (see `docs/solutions/tooling-decisions/glassfrog-v5-inherited-context-single-call.md`).
- **Fail quietly at the surface.** The hook is fail-silent; a malformed or missing ledger never breaks a session.

## Writing the ledger entry

The routine's prompt instructs Claude to append/update the ledger as its final step. The shape (illustrative, not prescriptive):

```jsonl
{"id":"pretac-operations-circle","title":"holacracy/secretary/pre-tactical-prep/operations-circle","next_fire":"2026-06-22T09:00:00Z","last_fire":"2026-06-22T08:55:00Z","last_status":"ok","built_at":"2026-06-22T08:55:00Z","surface_from":"2026-06-22T00:00:00Z","surface_until":"2026-06-22T23:59:59Z","packet_summary":"Tactical expected weekly. 3 checklist items due, 1 metric out of range, 2 unprocessed tensions to triage.","packet_path":"~/.claude/holacracy/packets/pre-tactical-prep-operations-circle.md"}
```

Append a new line per fire (or rewrite the matching `id`'s line). Write the full draft to `packet_path` first, then the ledger line — so the hook never points at a half-written sidecar.

## Validation

Validate the mechanism with a **stub routine** before wiring real content, so the write→surface path is proven independent of GlassFrog or the real packet:

- **Stub prompt:** "Write the sidecar `~/.claude/holacracy/packets/stub.md` with the text `stub packet`, then append a ledger line titled `holacracy/secretary/pre-tactical-prep/stub` with `last_status: ok`, today's `surface_from`/`surface_until`, a `built_at`, a `packet_summary` of `stub`, and that `packet_path`."
- **(a) Write→surface:** run the stub, open a fresh session, confirm the session-start hook surfaces the stub summary; confirm a legacy entry (only the original five fields) still renders unchanged.
- **(b) Fire path:** register the stub through the live `scheduled-tasks` MCP (a one-time `fireAt` a minute out) and confirm it produces the same ledger line when actually triggered — a green (a) never substitutes for an unproven (b).

Use `HOLACRACY_ROUTINE_LEDGER` to point at an isolated ledger during validation so real routines are untouched.
