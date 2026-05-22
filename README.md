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
- [`shared/actor-and-role-resolution.md`](skills/shared/actor-and-role-resolution.md) — actor identity + role/circle resolution procedure. Every role skill loads this to figure out who's acting and from which circle/role before producing any output. Defines the prompt preamble for scheduled routines (v0.3+).

**Slash commands**

- [`/holacracy:context`](commands/context.md) — resolve and display the current actor + role roster across circles. Optionally focus on one circle (`/holacracy:context Operations Circle`).
- [`/holacracy:check-authority`](commands/check-authority.md) — informational authority lookup for a scenario, grounded in `authority-boundaries.md` and the Constitution. Surfaces the path to a formal Secretary ruling when appropriate.

**Session hook**

- [`hooks/session-start`](hooks/hooks.json) — silent by default. When the agentic-routines mechanism (v0.3+) has registered routines for this actor and either there are fires today or there are anomalies, this hook surfaces a brief briefing at session start. Fail-silent on any error.

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

## What's coming

The plugin is being expanded in three phases. v0.2.0 (this release) ships the foundation: actor + role-context awareness across all five skills, the first two slash commands, and a conditional SessionStart hook. The next two releases build on that:

**v0.3.0 — Agentic Core Roles + most commands**
- Shared `skills/shared/agentic-routines.md` reference defining the routine-catalog mechanism, the prompt preamble for scheduled work, and constitutional safeguards.
- Per-role routine catalogs for Facilitator, Secretary, Lead Link, Rep Link (e.g., pre-tactical prep, post-tactical anti-pattern audit, quarterly strategy review, pre-enclosing-circle prep, weekly self-audit).
- Routines never auto-file proposals, auto-issue rulings, or auto-assign roles. They draft for human review.
- Slash commands: `/holacracy:tactical`, `/holacracy:governance`, `/holacracy:propose`, `/holacracy:routines:list`.

**v0.4.0 — Policy work + new skills + subagent**
- New `holacracy-policy-steward` skill: cross-circle policy inventory, conflict/gap audit, single-circle proposal drafting, **cascading multi-circle proposal drafting** (filing N proposals across N circles with rollup tracking, two-stage review).
- New skills: `holacracy-circle-member`, `holacracy-tension-coach`, `holacracy-role-onboarding`, `holacracy-cross-circle-coordination`.
- `holacracy-coach` subagent for context-isolated heavy lifting (governance meeting transcript processing, org-wide audits, cascade drafting).
- Slash commands: `/holacracy:policy:audit`, `/holacracy:policy:cascade`.

Tracked as issues on this repo as the work is broken out.

## License

MIT — see [LICENSE](LICENSE).
