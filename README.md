# holacracy

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

**Shared reference**

- [`shared/authority-boundaries.md`](skills/shared/authority-boundaries.md) — cross-role authority reference loaded by the four role skills when authority questions span more than one Core Role.

## GlassFrog connector

The plugin ships an `.mcp.json` that wires up the [GlassFrog](https://app.glassfrog.com) MCP server at:

```
https://ipllc-glassfrog-mcp-server.vercel.app/mcp
```

This is an HTTP MCP server protected by OAuth — **each user authorises with their own GlassFrog API key on first use**. No API keys are shared across users. The server is hosted by Integral Productivity LLC for convenience; the upstream server source is currently private (an official GlassFrog MCP server may be published later, at which point this plugin will repoint).

To use the connector you need a GlassFrog API key:

1. Log into [app.glassfrog.com](https://app.glassfrog.com)
2. Click your name → **Profile / Account**
3. Navigate to **API Keys**
4. Generate a new key — label it something memorable like `claude-holacracy-plugin`
5. Copy the key immediately (it will not be shown again)

Then, the first time a skill invokes a `glassfrog_*` tool, Claude will run the OAuth handshake against the MCP server — paste your API key when prompted.

### Working without GlassFrog

All five skills degrade gracefully if the GlassFrog MCP is not connected. They will operate on constitutional knowledge and context the user provides directly, and will name that limitation clearly (e.g., "I don't have live governance data, so I'm working from what you've shared.").

## Future work

Tracked as issues on this repo:

- [Add slash commands](https://github.com/Integral-Productivity/holacracy/issues) — `/holacracy:tactical`, `/holacracy:governance`, `/holacracy:check-authority`, `/holacracy:propose`
- Add a `holacracy-coach` subagent for context-isolated heavy lifting (e.g., processing full Governance Meeting transcripts)
- Add an optional SessionStart hook that primes `holacratic-ai-governance` when GlassFrog tools are detected

## License

MIT — see [LICENSE](LICENSE).
