# holacracy-claude-plugin

A Claude Code plugin for engaging with [Holacracy](https://www.holacracy.org/) from inside Claude — AI co-pilots that energize each of the four Core Roles (Facilitator, Secretary, Lead Link, Rep Link), a governance-aware operating frame for AI working inside any Holacracy-governed organization, and the GlassFrog MCP wired in as a connector so the skills can read live circle structure, roles, checklists, metrics, and projects.

## Install

From the Integral Productivity marketplace:

```
/plugin marketplace add Integral-Productivity/marketplace
/plugin install holacracy
```

Or add this repo directly to your plugin sources.

## What's included

**Core Role co-pilots**

- [`holacracy-facilitator`](skills/holacracy-facilitator/SKILL.md) — AI co-Facilitator for Tactical, Governance, Election, and Strategy meetings
- [`holacracy-secretary`](skills/holacracy-secretary/SKILL.md) — AI co-Secretary for records, scheduling, constitutional interpretation, and meeting capture
- [`holacracy-lead-link`](skills/holacracy-lead-link/SKILL.md) — AI co-Lead Link for strategy, role assignment, resource allocation, and governance tension drafting
- [`holacracy-rep-link`](skills/holacracy-rep-link/SKILL.md) — AI co-Rep Link for tension triage, enclosing-circle meeting prep, and constraint removal

**Governance frame**

- [`holacratic-ai-governance`](skills/holacratic-ai-governance/SKILL.md) — operating framework for AI engaging with any Holacracy-governed organization through GlassFrog. Grounds AI work in real role structure rather than generic assumptions.

**Shared references**

- [`shared/authority-boundaries.md`](skills/shared/authority-boundaries.md) — cross-role authority reference loaded by the four role skills when authority questions span more than one Core Role.
- [`shared/actor-and-role-resolution.md`](skills/shared/actor-and-role-resolution.md) — actor identity + role/circle resolution procedure. Every role skill loads this to figure out who's acting and from which circle/role before producing any output. Defines the prompt preamble for scheduled routines.
- [`shared/tension-triage.md`](skills/shared/tension-triage.md) — canonical role-vs-person triage gate, suggested-meeting-venue annotation (governance vs tactical, for the user's mental model — not an API field), supersession check (S.5.5.1d), and role-attribution policy. Loaded by Pattern 3, Pattern 5 (proactive sensing), the `tension-capture` subagent, and the three new `/holacracy:*` tension commands.
- [`shared/tension-capture-flow.md`](skills/shared/tension-capture-flow.md) — the draft-and-confirm B-flow used to file tensions to a role's GlassFrog backlog via `glassfrog_create_tension(role_id, body)`. Per-tension confirmation; no auto-file; constitutional safeguard preserved.

**Subagents**

- [`agents/tension-capture.md`](agents/tension-capture.md) — handles the multi-step tension capture flow (resolve sensing role → triage → draft body → per-tension confirm → `glassfrog_create_tension(role_id, body)`). Dispatched by `/holacracy:capture-tension` and by ambient tension-language detection in `holacratic-ai-governance`. The Secretary-scoped `/holacracy:tactical` flow has its own in-meeting capture path documented in `skills/holacracy-secretary/SKILL.md` — this subagent is the cross-role, out-of-meeting surface.

**Slash commands**

- [`/holacracy:context`](commands/context.md) — resolve and display the current actor + role roster across circles. Optionally focus on one circle (`/holacracy:context Operations Circle`).
- [`/holacracy:check-authority`](commands/check-authority.md) — informational authority lookup for a scenario, grounded in `authority-boundaries.md` and the Constitution. Surfaces the path to a formal Secretary ruling when appropriate.
- [`/holacracy:tactical`](commands/tactical.md) — prime Secretary scope for an in-meeting Tactical capture session. Operates MCP-first (durable role-backlog capture, not the ephemeral GlassFrog meeting UI queue) and reads the routine ledger for a pre-tactical-prep packet — the same store the session-start hook reads — pull-building one on demand if none is on file. Accepts an optional circle-name argument (`/holacracy:tactical Operations Circle`).
- [`/holacracy:governance`](commands/governance.md) — prime **both** the Facilitator and Secretary skills together for a Governance Meeting (IDM facilitation + governance capture). Resolves the actor's standing in the target circle into three cases — Core Role holder, Circle Member (a real IDM participant, oriented to their touchpoints), or no-role (Observer/Advisor) — and surfaces a pre-governance-prep packet if a routine has produced one. A supplied transcript is processed inline with a context-window-risk warning until the `holacracy-coach` subagent lands. Accepts an optional circle-name argument (`/holacracy:governance Operations Circle`).
- [`/holacracy:capture-tension`](commands/capture-tension.md) — capture a tension to a role's GlassFrog backlog outside the in-meeting context, via a draft-and-confirm flow. Optional `$ARGUMENTS` for inline tension text. Files exactly one tension per invocation; the constitutional safeguard requires explicit human confirmation before any write. The cross-role, cross-session companion to `/holacracy:tactical`'s in-meeting capture.
- [`/holacracy:process-inbox`](commands/process-inbox.md) — walk through unprocessed tensions on the actor's roles and decide what to do with each (archive false positives, mark catch-up processed, edit body, or defer). Per-tension decisions; surfaces supersession candidates inline. A user-facing surface for clearing role-backlog debt between meetings.
- [`/holacracy:supersession-sweep`](commands/supersession-sweep.md) — sweep tensions filed in the current session for supersession (S.5.5.1d). Offers archive or merge for subsumed tensions. Also offered implicitly by `holacratic-ai-governance` on session-close signals. Useful because in-flow capture can produce overlapping tensions that benefit from a single review pass.
- [`/holacracy:routines`](commands/routines.md) — register the Secretary pre-tactical-prep routine for a circle, or list active routines. The minimal v1 surface for the agentic-routines mechanism; draft-only, with no proactive fire unless the `scheduled-tasks` MCP is present.

**Session hook**

- [`hooks/session-start`](hooks/hooks.json) emits up to two things at session start, fail-silent on any error:
  - **A role-grounding directive** (on by default). It *demands* that the session resolve and announce its active Holacratic role/circle — per [`skills/shared/actor-and-role-resolution.md`](skills/shared/actor-and-role-resolution.md) — before its first substantive action, and flag any cross-role remit boundary. It is **honest by construction**: the hook has no GlassFrog access at fire time, so the directive requests the grounding and explicitly never claims it happened. Gate it with env vars: `HOLACRACY_GROUNDING_DIRECTIVE=off` disables it; `HOLACRACY_GROUNDING_REQUIRE_GLASSFROG=on` injects only when a GlassFrog connector is declared; `HOLACRACY_GROUNDING_REQUIRE_PATH=<regex>` injects only when `$PWD` matches. (Track A PDCA-1, [#62](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/62).)
  - **A routine briefing** (silent unless due). When the agentic-routines mechanism has registered routines for this actor and a routine packet is within its surfacing window or a last fire failed, this surfaces a brief briefing (the packet summary, its freshness, and a full-draft pointer).
- [`scripts/grounding-readout.sh`](scripts/grounding-readout.sh) — a lightweight, honest-by-construction readout of the grounding experiment: greps session transcripts for the three signals (resolve+announce, remit-crossing flag, chapter-mark) and prints counts and rates against the 0-baseline. `scripts/grounding-readout.sh --since YYYY-MM-DD`.

## GlassFrog connector

The plugin ships an `.mcp.json` that wires up the [GlassFrog](https://app.glassfrog.com) MCP server at:

```
https://ipllc-glassfrog-mcp-server.vercel.app/mcp
```

This is an HTTP MCP server protected by OAuth — **each user authorises with their own GlassFrog API key on first use**. No API keys are shared across users. The server is hosted by Integral Productivity LLC for convenience; the upstream server source is currently private (an official GlassFrog MCP server may be published later, at which point this plugin will repoint).

### Which GlassFrog API does the MCP use?

The deployed MCP currently calls the **GlassFrog REST API v3** (`https://api.glassfrog.com/api/v3`). An API v4 / GraphQL variant is in development; when it lands, this plugin will repoint and bump the version. Either way, the credential you need to generate is the same — a single **GlassFrog API key** scoped to your user account.

### Generate a GlassFrog API key

The MCP authenticates to GlassFrog with an `X-Auth-Token` header containing your personal API key (same permissions as your user account). To create one:

1. Log into [app.glassfrog.com](https://app.glassfrog.com)
2. Click your name → **Profile / Account**
3. Navigate to **API Keys** (not OAuth applications — this is a separate, simpler credential)
4. Generate a new key — label it something memorable like `claude-holacracy-plugin`
5. Copy the key immediately (it will not be shown again — if you lose it, regenerate)

There is only one token type to choose from — API keys carry the same scopes as your GlassFrog user account, so anything you can read or write in the GlassFrog UI is available to the MCP. Revoke or regenerate the key from the same page if you ever need to.

### First use

The first time a skill invokes a `glassfrog_*` tool, Claude runs the OAuth handshake against the MCP server — paste your API key when prompted. Tokens then refresh in the background; re-authentication is only required after 30 days of inactivity or if you regenerate the underlying GlassFrog API key.

### Working without GlassFrog

All five skills degrade gracefully if the GlassFrog MCP is not connected. They will operate on constitutional knowledge and context the user provides directly, and will name that limitation clearly (e.g., "I don't have live governance data, so I'm working from what you've shared.").

### Tension capture and the underlying API surface

The three new tension commands rely on `glassfrog_create_tension(role_id, body)`, `glassfrog_list_role_tensions`, `glassfrog_get_tension`, `glassfrog_update_tension`, and `glassfrog_delete_tension`. The MCP server hosted at the URL above includes them. Two practical caveats documented in [`glassfrog-api-constraints.md`](skills/holacratic-ai-governance/references/glassfrog-api-constraints.md):

- **Body-only create.** `glassfrog_create_tension` takes `role_id` and `body` only. The `label` and `meeting_type` fields are not part of the stable signature ([glassfrog-mcp-server#58](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/58)). Front-load the topic in the first sentence of the body since there is no label.
- **Same-session list-back is unreliable.** Immediately after creation, `glassfrog_list_role_tensions` may not include the new tension (propagation/scoping). The capture subagent treats the `create_tension` response ID as the only reliable same-session confirmation; the supersession sweep uses an internal session-ID cache for the same reason.

If a different / older GlassFrog MCP server is wired up without these endpoints, the `tension-capture` subagent falls back to drafting a plain-text tension formatted for manual entry, and the inbox/sweep commands degrade with a clear message.

## What's coming

The plugin is being expanded across releases. v0.2.0 shipped the foundation (actor + role-context awareness, the first two slash commands, conditional SessionStart hook). **v0.3.0 (this release) adds proactive tension capture**: a `tension-capture` subagent, three tension-focused slash commands, ambient detection of tension language during conversation, and the draft-and-confirm contract that lets Claude file to the GlassFrog tension inbox without crossing into tension *processing*. See [`docs/adr/0003-glassfrog-tension-api-adoption.md`](docs/adr/0003-glassfrog-tension-api-adoption.md) for the design rationale.

The next two releases continue building from that base:

**Agentic routines — now landing**
- Shared [`skills/shared/agentic-routines.md`](skills/shared/agentic-routines.md) defines the routine-catalog mechanism: the substrate bridge (the `scheduled-tasks` MCP fires a routine, the routine writes the `routines.jsonl` ledger, the session-start hook surfaces it), the prompt preamble for scheduled work, and the draft-only safeguard. See [`docs/adr/0006-routine-substrate-scheduler-fires-ledger-surfaces.md`](docs/adr/0006-routine-substrate-scheduler-fires-ledger-surfaces.md).
- The first routine: **Secretary pre-tactical-prep** ([`skills/holacracy-secretary/references/pre-tactical-prep-routine.md`](skills/holacracy-secretary/references/pre-tactical-prep-routine.md)), registered via [`/holacracy:routines`](commands/routines.md).
- Routines never auto-file proposals, auto-issue rulings, or auto-assign roles. They draft for human review.

**Still planned**
- Per-role routine catalogs for Facilitator, Lead Link, Rep Link, and more Secretary routines (post-tactical anti-pattern audit, quarterly strategy review, pre-enclosing-circle prep, weekly self-audit).
- Connector-gated packet elements once GlassFrog exposes the reads: "projects lacking recent updates" and "overdue/next actions".
- Tension-capture graduations (each gated on its own ADR):
  - **Option D** — auto-file from explicit human tension statements ("file this as a tension: ...") without the per-tension confirmation block.
  - **AI-agent self-filing** — scheduled routines that fire as AI-agent role-fillers gain the ability to file tensions on their own role.

**Planned for v0.5.0 — Policy work + new skills + heavier subagent**
- New `holacracy-policy-steward` skill: cross-circle policy inventory, conflict/gap audit, single-circle proposal drafting, **cascading multi-circle proposal drafting** (filing N proposals across N circles with rollup tracking, two-stage review).
- New skills: `holacracy-circle-member`, `holacracy-tension-coach`, `holacracy-role-onboarding`, `holacracy-cross-circle-coordination`.
- `holacracy-coach` subagent for context-isolated heavy lifting (governance meeting transcript processing, org-wide audits, cascade drafting).
- Slash commands: `/holacracy:policy:audit`, `/holacracy:policy:cascade`.

Tracked as issues on this repo as the work is broken out.

## License

MIT — see [LICENSE](LICENSE).
