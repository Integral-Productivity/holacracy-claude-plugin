# Spike: a skill broker that composes a role's skills from GlassFrog

- **Issue:** #371
- **Date:** 2026-10-09
- **Context:** option D′ in Integral-Productivity/ip-agent-teams#367. GlassFrog holds role and capacity skill bindings with pins, Git holds tested content, and this plugin brokers between them.
- **Question:** Can a Claude Code session, interactive and headless, resolve a role, fetch its GlassFrog-linked skills, and follow them? What does that cost, and how does it fail?

## Result

**Yes, in both modes, at modest call cost.** But four findings constrain the design: tool names differ between runtimes, allowlists don't scope unattended runs, pinned skills aren't self-contained, and failing closed has to be part of the contract.

## Legs

| Leg | Setup | Outcome | Cost |
|---|---|---|---|
| 1. Interactive | This session, acting as Product Management of Product | `listSkills(role_id)` → `getSkill` → followed "Draft release notes" against v0.24.0 as a dry run | 2 GlassFrog calls plus 2 `gh` calls, after role resolution |
| 2. Headless | `claude -p`, write tools denied, dry run | Followed the skill correctly. Its draft caught #353, which the published v0.24.0 notes omit (`docs:` commits are excluded by Release Please). | 6 turns, 62 s, $1.35 |
| 3. Pin to Git | Binding pinned to `skills/holacracy-facilitator` at `a692d0c`, fetched with `gh api` | `SKILL.md` fetched in about 1 s (16 KB), but it cites 5 `references/` files and 2 `../shared/` files | 1 API call per file |
| 4. GlassFrog unreachable | `claude -p --strict-mcp-config` with no MCP servers | Printed `BROKER_UNAVAILABLE` and stopped, without improvising the skill from memory | 3 turns, 27 s, $0.53 |

## Findings

1. **Tool names differ by runtime.** The interactive session called `mcp__glassfrog-extended__*` and `mcp__claude_ai_GlassFrog_Official__*`. The headless run picked `mcp__claude_ai_GlassFrog_Extended__*`. A broker that hard-codes tool names breaks across runtimes. Resolve by capability, the same problem as #341.
2. **`--allowedTools` didn't scope the headless run.** It called connector tools that weren't on the allowlist. Least privilege for unattended brokers must come from deny rules or a scoped MCP config (`--strict-mcp-config`), not from an allowlist alone.
3. **Pinned skills aren't self-contained.** A pin to a single `SKILL.md` is incomplete. The skill's `references/` files and this repo's `../shared/` files have to come with it. So a pin must resolve to a **checkout** (plugin install, or a Managed Agents `github_repository` mount at `checkout`), not to a file fetch. The `../shared/` convention also crosses the skill-directory boundary that Managed Agents discovery (`.claude/skills/<name>/`, one level deep) and Skills API uploads (one directory) both assume, so these skills don't travel to Managed Agents as written (#373).
4. **Failing closed depends on the prompt.** Leg 4 refused to improvise only because the prompt said so. A broker contract must state "no GlassFrog, no skill" explicitly, matching the plugin's existing rule against reporting health from absent evidence.
5. **GlassFrog-hosted skills arrive unreviewed.** "Draft release notes" has no `description` (so nothing triggers it automatically), leaves "the target" undefined, and its step 5 writes to a public release with no confirmation step. Both runs followed it faithfully; a careless skill would be followed just as faithfully. That's the testability and integrity gap D′ assigns to Git. Tightening this skill is Integral-Productivity/product-management-claude-plugin#9.
6. **Most of the headless cost is inherited context, not the broker.** The unattended run loaded the operator's global instructions and every installed plugin. A production broker should run from a minimal configuration, the way `scripts/run-behavioural-eval.py` isolates with `CLAUDE_CONFIG_DIR`.

## Not tested (tracked in Integral-Productivity/ip-agent-teams#370)

- **Capacity bindings.** No capacity tags exist in GlassFrog, and adding one is a governance-adjacent write. Leg 3 stands in for the pin-resolution half of a capacity binding.
- **Triggering.** Every leg invoked the broker explicitly. Nothing here shows a GlassFrog-hosted skill being chosen automatically from its description.
- **Managed Agents.** Not exercised. Delivery there would go through a `github_repository` mount ([Managed Agents: Skills](https://platform.claude.com/docs/en/managed-agents/skills)).

## Implication for #367

D′ holds, with three amendments:
- A pin points at a repo and ref and is resolved as a checkout.
- The broker resolves tools by capability and fails closed.
- Skills meant to travel must be self-contained within their own directory.
