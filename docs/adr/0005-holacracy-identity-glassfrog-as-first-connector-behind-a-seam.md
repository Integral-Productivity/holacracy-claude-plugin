# 5. Holacracy is the product identity; GlassFrog is the first connector behind a governance-data seam

Date: 2026-06-17

## Status

Accepted

## Context

This plugin couples two layers that are easy to conflate:

1. **Practice intelligence** — Constitution fluency, the four Core Role co-pilots, the developmental loop, and constitutional logic such as the role-vs-person triage gate and the supersession check (S.5.5.1d). This layer is true of Holacracy regardless of which record-keeping tool an org uses.
2. **Live structural grounding** — reading and writing an org's real circles, roles, domains, policies, checklists, metrics, tensions, and proposals. Today this is supplied entirely by GlassFrog through the bundled MCP connector.

Three existing facts already separate these layers in practice:

- **The GlassFrog infrastructure is already its own artifact.** The MCP *server* lives in a separate repo (`Integral-Productivity/glassfrog-mcp-server`) and its own Vercel deployment. This plugin ships only the `.mcp.json` that points at it.
- **The practice layer is built to detach.** All five skills degrade gracefully without GlassFrog, falling back to constitutional knowledge and user-provided context (README, "Working without GlassFrog").
- **A repoint is already anticipated.** The README states that if an official GlassFrog MCP server is published, "this plugin will repoint" — and a v3→v4/GraphQL API migration is already in motion.

A `STRATEGY.md` interview (2026-06-17) surfaced the underlying question directly: ship the MCP built-in for a frictionless out-of-box experience, *and* decide how much of the current scope is GlassFrog-specific versus Holacracy-general — i.e., whether some scope belongs in a separate GlassFrog plugin.

The two desires are about different axes: **what ships together** (the bundle) versus **where the identity/code boundary sits** (the seam). They are only in conflict if a clean boundary is assumed to require a separate installable package.

## Decision

Treat **Holacracy as the durable product identity** and **GlassFrog as the first (and currently only) connector**, behind a named governance-data seam — within a single plugin that ships the MCP built-in.

1. **One plugin, MCP built-in.** The out-of-box experience keeps the GlassFrog MCP bundled via `.mcp.json`. No second install, no separate package — today.
2. **Name the seam.** Skills target a governance-data boundary — resolve actor, list roles/domains/authority, list and create tensions — rather than GlassFrog API calls scattered through practice logic. GlassFrog is the first implementation behind that boundary.
3. **Keep practice logic tool-agnostic.** Constitution fluency, Core Role co-piloting, authority boundaries, and tension *triage* (role-vs-person, supersession) carry no GlassFrog dependency. What is genuinely GlassFrog-specific is narrow: the `.mcp.json` wiring, the API constraints (body-only `create_tension`, same-session list-back, v3→v4 maturation), actor/agent→role resolution mechanics, and raw CRUD orchestration. That narrow set is the "Governance-data grounding (GlassFrog-first)" track in `STRATEGY.md`.
4. **Defer a separate plugin.** Do not extract a `glassfrog-claude-plugin` now. Revisit only when there is a concrete trigger: a second backend (e.g., Holaspirit), HolacracyOne's official MCP, or a demonstrated audience for GlassFrog operations *without* the Holacracy-practice framing.

## Consequences

- The out-of-box experience stays frictionless: one plugin, MCP bundled, no install dance.
- The product's defensible identity rides on the practice layer, which outlives any single SaaS backend. A future repoint (official GlassFrog MCP, v4/GraphQL, or another tool) touches the connector behind the seam, not the practice skills.
- Premature extraction is avoided: no second package, no cross-repo version coordination, and no split audience to maintain before a real second backend exists.
- A latent obligation is accepted: as new skills are written, GlassFrog-specific calls must be kept behind the governance-data boundary rather than leaking into practice logic, or the seam erodes and a later split gets harder.
- The seam gives a clean, low-cost extraction path if a trigger later appears — the boundary already exists conceptually (separate MCP server repo, graceful degradation), so a future `glassfrog-claude-plugin` would mostly relocate the connector manifest and any tool-specific power-user skills.

## What this ADR does NOT do

- It does **not** create a `glassfrog-claude-plugin` or change packaging today. It records the identity/seam stance and the deferral, not a refactor.
- It does **not** prescribe the connector interface's exact signatures. It commits to *having* a governance-data boundary, not to a finalized API; that detail is left to the skills and to the GlassFrog API maturation already underway.
- It does **not** remove or weaken graceful degradation. The without-GlassFrog fallback remains the behavior when no connector is present.
- It does **not** govern the v3→v4 GlassFrog API migration itself, which proceeds on its own track; this ADR only places that work on the GlassFrog side of the seam.
