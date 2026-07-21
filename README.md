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
- [`shared/project-well-formedness.md`](skills/shared/project-well-formedness.md) — the rubric for judging whether a GlassFrog project is well-formed (outcome / next-action / owner / DoD) and well-placed (goal / authority / assignment). State vocabulary, DoD-as-body-convention, and the live status enum. Loaded by `/holacracy:review-project`.
- [`shared/project-review-critics.md`](skills/shared/project-review-critics.md) — the five critic lenses, the finding schema, and the severity/floor/cap/dedupe rules for `/holacracy:review-project`. Seeds both the inline backlog walk and the deep-review subagents.
- [`shared/project-capture-flow.md`](skills/shared/project-capture-flow.md) — the draft-and-confirm P-flow used to file a well-formed project at intake: soft-gate on the rubric's Family A (teach + drafted fix, never hard-block), then the additive write chain `glassfrog_create_role_project(role_id, description, status:"current")` → `glassfrog_create_action(…, parent_project_id:<new project>)` for the first next-action, plus a light skippable goal-link nudge. Per-project confirmation; no auto-file. Loaded by `/holacracy:capture-project` and the `project-capture` subagent.

**Subagents**

- [`agents/tension-capture.md`](agents/tension-capture.md) — handles the multi-step tension capture flow (resolve sensing role → triage → draft body → per-tension confirm → `glassfrog_create_tension(role_id, body)`). Dispatched by `/holacracy:capture-tension` and by ambient tension-language detection in `holacratic-ai-governance`. The Secretary-scoped `/holacracy:tactical` flow has its own in-meeting capture path documented in `skills/holacracy-secretary/SKILL.md` — this subagent is the cross-role, out-of-meeting surface.
- [`agents/project-critic.md`](agents/project-critic.md) — read-only single-lens critic for the deep-review path of `/holacracy:review-project`. The command fans out five in parallel (one per lens) against a single named project for genuine adversarial independence; each returns findings in the canonical schema and never writes.
- [`agents/project-capture.md`](agents/project-capture.md) — handles the multi-step project capture flow (resolve owner role → soft-gate on rubric Family A → draft outcome + first next-action → per-project confirm → `create_role_project` then `create_action` with `parent_project_id` → light skippable goal nudge). Dispatched by `/holacracy:capture-project`. The capture-time twin of the `project-critic` review path; never auto-files, one project per dispatch.
- [`agents/holacracy-coach.md`](agents/holacracy-coach.md) — context-isolated heavy lifting. Handed a heavyweight task — a Governance Meeting transcript to capture (today, from [`/holacracy:governance`](commands/governance.md)); org-wide policy/role audits or cascade drafting as the v0.5 policy work lands — it does the read-heavy work in its own context window, drafts the output to a file, and returns a short structured summary. **Read-only on GlassFrog** (a `tools` allowlist of read tools only, with every write also denied): it never files, so the main session reviews the draft and performs any write under human confirmation — the two-stage review pattern.

**Slash commands**

- [`/holacracy:context`](commands/context.md) — resolve and display the current actor + role roster across circles. Optionally focus on one circle (`/holacracy:context Operations Circle`).
- [`/holacracy:check-authority`](commands/check-authority.md) — informational authority lookup for a scenario, grounded in `authority-boundaries.md` and the Constitution. Surfaces the path to a formal Secretary ruling when appropriate.
- [`/holacracy:tactical`](commands/tactical.md) — prime Secretary scope for an in-meeting Tactical capture session. Operates MCP-first (durable role-backlog capture, not the ephemeral GlassFrog meeting UI queue) and reads the routine ledger for a pre-tactical-prep packet — the same store the session-start hook reads — pull-building one on demand if none is on file. Accepts an optional circle-name argument (`/holacracy:tactical Operations Circle`).
- [`/holacracy:governance`](commands/governance.md) — prime **both** the Facilitator and Secretary skills together for a Governance Meeting (IDM facilitation + governance capture). Resolves the actor's standing in the target circle into three cases — Core Role holder, Circle Member (a real IDM participant, oriented to their touchpoints), or no-role (Observer/Advisor) — and surfaces a pre-governance-prep packet if a routine has produced one. A supplied transcript is handed to the `holacracy-coach` subagent, which captures it in an isolated context and returns a draft for review (the coach is read-only on GlassFrog; any filing happens back in the main session under confirmation). Accepts an optional circle-name argument (`/holacracy:governance Operations Circle`).
- [`/holacracy:capture-tension`](commands/capture-tension.md) — capture a tension to a role's GlassFrog backlog outside the in-meeting context, via a draft-and-confirm flow. Optional `$ARGUMENTS` for inline tension text. Files exactly one tension per invocation; the constitutional safeguard requires explicit human confirmation before any write. The cross-role, cross-session companion to `/holacracy:tactical`'s in-meeting capture.
- [`/holacracy:process-inbox`](commands/process-inbox.md) — walk through unprocessed tensions on the actor's roles and decide what to do with each (archive false positives, mark catch-up processed, edit body, or defer). Per-tension decisions; surfaces supersession candidates inline. A user-facing surface for clearing role-backlog debt between meetings.
- [`/holacracy:supersession-sweep`](commands/supersession-sweep.md) — sweep tensions filed in the current session for supersession (S.5.5.1d). Offers archive or merge for subsumed tensions. Also offered implicitly by `holacratic-ai-governance` on session-close signals. Useful because in-flow capture can produce overlapping tensions that benefit from a single review pass.
- [`/holacracy:routines`](commands/routines.md) — register a draft-only routine for a circle (Secretary pre-tactical-prep, or the stalled-project sweep), or list active routines. The minimal surface for the agentic-routines mechanism; draft-only, with no proactive fire unless the `scheduled-tasks` MCP is present.
- [`/holacracy:review-project`](commands/review-project.md) — adversarial review of GlassFrog **projects** against the well-formedness rubric. Runs five critic lenses (actionability, goal-alignment, scope-authority, assignment-fit, red-team) over one project or a backlog; surfaces findings with drafted fixes; applies additive fixes (`create_action`, `link_goal_supporting_project`) with a per-item confirmation, leaves reframes/archives as advisory drafts, and routes scope/assignment gaps to the tension flow. No argument or a circle name walks the backlog inline; a named project gets a deep review via independent critic subagents. Never auto-writes.
- [`/holacracy:capture-project`](commands/capture-project.md) — capture-time well-formedness guardrail: file a **new** project as a well-formed outcome with a first next-action, via a draft-and-confirm flow. Optional `$ARGUMENTS` for inline project text. Soft-gates on the rubric's Family A (outcome-framed / first next-action / clear owner), teaching the missing element with a drafted fix rather than hard-blocking; files additively (`create_role_project` then `create_action` with `parent_project_id`) with one per-project confirmation, then a light skippable goal-link nudge. The capture-time twin of `/holacracy:review-project` — prevents thin projects at intake instead of cleaning them up after the fact. Never auto-files; one project per invocation.
- [`/holacracy:stalled-project-sweep`](commands/stalled-project-sweep.md) — back-of-loop lifecycle sweep for GlassFrog **projects**. Surfaces un-moving projects (no next-action, old `created_at`, or `status: "waiting"`) and offers per item to re-energize (draft a next-action) or archive (`status: "archived"`). Per-item confirm; never auto-archives; archive-over-delete. The project-side twin of `/holacracy:supersession-sweep`, and — unlike `/holacracy:review-project` — it *performs* the archive write (a lifecycle transition, not an authorship edit). Schedulable as a draft-only routine.

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
- The second routine: **stalled-project sweep** ([`skills/holacracy-secretary/references/stalled-sweep-routine.md`](skills/holacracy-secretary/references/stalled-sweep-routine.md)) — assembles a stalled-project review packet on a cadence so stall-catching stops depending on anyone remembering to run [`/holacracy:stalled-project-sweep`](commands/stalled-project-sweep.md). Registered via [`/holacracy:routines register stalled-sweep <circle>`](commands/routines.md). This is the surface that takes on the "projects lacking recent updates" inference the pre-tactical routine deferred (GlassFrog exposes no last-touched timestamp; the sweep infers staleness honestly and says so).
- Routines never auto-file proposals, auto-issue rulings, auto-assign roles, or auto-archive projects. They draft for human review.

**Still planned**
- Per-role routine catalogs for Facilitator, Lead Link, Rep Link, and more Secretary routines (post-tactical anti-pattern audit, quarterly strategy review, pre-enclosing-circle prep, weekly self-audit).
- Connector-gated packet elements once GlassFrog exposes the reads: "projects lacking recent updates" and "overdue/next actions".
- Tension-capture graduations (each gated on its own ADR):
  - **Option D** — auto-file from explicit human tension statements ("file this as a tension: ...") without the per-tension confirmation block.
  - **AI-agent self-filing** — scheduled routines that fire as AI-agent role-fillers gain the ability to file tensions on their own role.

**Planned for v0.5.0 — Policy work + new skills**
- New `holacracy-policy-steward` skill: cross-circle policy inventory, conflict/gap audit, single-circle proposal drafting, **cascading multi-circle proposal drafting** (filing N proposals across N circles with rollup tracking, two-stage review).
- New skills: `holacracy-circle-member`, `holacracy-tension-coach`, `holacracy-role-onboarding`, `holacracy-cross-circle-coordination`.
- Slash commands: `/holacracy:policy:audit`, `/holacracy:policy:cascade` — dispatching org-wide audits and cascade drafting to the `holacracy-coach` subagent (which shipped in v0.10.0 for governance-transcript capture).

Tracked as issues on this repo as the work is broken out.

## License

MIT — see [LICENSE](LICENSE).
