# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## What this repo is

A public Claude Code plugin for engaging with [Holacracy](https://www.holacracy.org/) from inside Claude. The plugin bundles five skills (four Core Role co-pilots plus a governance-aware operating frame) and wires up the GlassFrog MCP as a connector.

## Layout

```
holacracy-claude-plugin/
├── .claude-plugin/plugin.json     manifest
├── .mcp.json                      GlassFrog MCP connector (HTTP + OAuth)
├── LICENSE                        MIT
├── README.md                      install + GlassFrog setup
├── CLAUDE.md                      this file
└── skills/
    ├── holacracy-facilitator/
    ├── holacracy-secretary/
    ├── holacracy-lead-link/
    ├── holacracy-rep-link/
    ├── holacratic-ai-governance/
    └── shared/
        └── authority-boundaries.md
```

## Shared reference

`skills/shared/authority-boundaries.md` is loaded by the four role skills via the relative path `../shared/authority-boundaries.md`. If a role skill's `references/` file needs to load it, the path is `../../shared/authority-boundaries.md`. Keep these paths intact when editing.

`skills/shared/project-well-formedness.md` (the project-quality rubric) and `skills/shared/project-review-critics.md` (the five critic lenses + finding schema) are loaded by the `/holacracy:review-project` command and the `project-critic` subagent, and will be loaded by the planned capture-guardrail and stalled-sweep surfaces. The rubric is the single source of truth for "well-formed enough"; keep it and the critic spec in sync.

## GlassFrog MCP

Wired in via `.mcp.json` at the repo root. Server is `https://ipllc-glassfrog-mcp-server.vercel.app/mcp`, hosted on Vercel by Integral Productivity LLC, OAuth-protected so each user brings their own GlassFrog API key. If that URL ever moves (e.g., to a canonical `mcp.glassfrog.*` once an official server lands), update `.mcp.json` and bump the plugin version.

## Editing skills

The five skills here are the canonical source of truth — they were extracted from the [Integral-Productivity/skills](https://github.com/Integral-Productivity/skills) monorepo. Updates land here first.

## Versioning

Plugin uses SemVer in `.claude-plugin/plugin.json`. Skills carry their own `version:` in frontmatter. Bump skill versions when content changes meaningfully; bump plugin version when the bundle shape changes (skills added/removed, MCP repointed, commands/agents added).

## Agent skills

### Issue tracker

Issues are tracked in this repo's GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles map identity to existing repo labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. `CONCEPTS.md` at the root holds shared domain vocabulary (entities, named processes, status concepts) — relevant when orienting to the codebase or discussing domain concepts. See `docs/agents/domain.md`.

### Documented solutions

`docs/solutions/` — documented solutions to past problems (bugs, best practices, tooling decisions, workflow patterns), organized by category with YAML frontmatter (`module`, `tags`, `problem_type`). Relevant when implementing or debugging in documented areas.
