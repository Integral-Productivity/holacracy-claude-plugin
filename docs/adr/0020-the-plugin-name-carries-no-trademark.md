# 20. The plugin name carries no trademark

Date: 2026-10-23

## Status

Accepted (2026-10-23, Kraig Parkinson)

No earlier ADR chose the name `holacracy`; it came with the extraction from the
skills monorepo. This record replaces that unrecorded choice. ADRs 0001 to 0019
still use the old identifiers. They are a record of their time and are not
edited.

## Context

"Holacracy" is a trademark of HolacracyOne, LLC. Its
[trademark page](https://www.holacracy.org/trademark/) lets anyone make a
derivative work of the CC BY-SA Constitution, but says a derivative work may not
use Holacracy in its name, "to avoid confusion between your work and the
official Holacracy document".

This plugin is such a derivative work. Two reference files adapt Constitution
text under CC BY-SA 4.0 (see [NOTICE](../../NOTICE)). Before 1.0 the mark was in
every name the plugin shipped: the plugin, its catalog, the `/holacracy:` command
prefix, four skill names, the coach agent, the MCP tool prefix, and the
SessionStart directive header. The repository is already public.

Three options were considered:

1. Keep the name until HolacracyOne answers a permission request. The risk
   stays open for as long as the answer takes, and every new user learns the
   old names.
2. A name that echoes the mark, such as `holacraft`. It is shorter to explain,
   but a name chosen to sound like the mark is the confusion the terms forbid.
3. A name that describes the field, not the method: `self-org`.

## Decision

1. The plugin is named `self-org`. Kraig chose it on 2026-10-23, and a
   permission request to HolacracyOne goes out in parallel. A "yes" does not
   reverse this record by itself; a new ADR would.
2. Every name the plugin ships uses `self-org`:

   | Surface | Before | After |
   | --- | --- | --- |
   | Plugin | `holacracy` | `self-org` |
   | Self-hosted catalog | `integral-productivity-holacracy` | `integral-productivity-self-org` |
   | Command prefix | `/holacracy:` | `/self-org:` |
   | Skills | `holacracy-facilitator`, `-secretary`, `-lead-link`, `-rep-link`, `holacratic-ai-governance` | `self-org-facilitator`, `-secretary`, `-lead-link`, `-rep-link`, `self-org-ai-governance` |
   | Agent | `holacracy-coach` | `self-org-coach` |
   | MCP tool prefix | `mcp__plugin_holacracy_glassfrog-extended__` | `mcp__plugin_self-org_glassfrog-extended__` |
   | Release component | `holacracy` | `self-org` |
   | Directive header | `**Holacracy plugin: ...**` | `**self-org plugin: ...**` |
   | Routine titles | `holacracy/<role>/...` | `self-org/<role>/...` |

3. "Holacracy" stays where it describes the method: the Constitution, a
   Holacratic role, the trademark notice. Role names (Facilitator, Lead Link)
   are method vocabulary and stay.
4. Where a rename would silently break a working install, the old identifier is
   still accepted:
   - The SessionStart hook surfaces routines titled `self-org/...` or
     `holacracy/...`.
   - `scripts/grounding-readout.sh` counts the two old directive headers from a
     fixed list, so sessions before the rename stay measurable.
   - The `HOLACRACY_*` environment variables and the
     `~/.claude/holacracy/routines.jsonl` ledger path do not change. They are
     local configuration that users and schedulers already reference, not a
     name shipped to others.
5. `skills-lint.sh` check 12 fails any shipped surface that names the plugin by
   its old identifiers. Exceptions are pairs in
   `evals/legacy-names-allow.txt`, each with a reason.
6. The change ships as 1.0.0 through a `feat!` commit. Every command name
   changes, so it is a breaking change.

## Consequences

- An existing user must uninstall `holacracy@<catalog>`, install
  `self-org@<catalog>`, and sign in to GlassFrog again, because the connector's
  credential is stored under the plugin's name. The README's upgrade section
  gives the steps.
- Saved prompts, docs, and habits that type `/holacracy:` stop working. Claude
  Code registers one name per plugin, so no alias is possible.
- Two follow-ups are outside this repository: renaming the GitHub repository
  (GitHub redirects the old URLs) and renaming the entry in the private labs
  catalog. Until the labs entry changes, `install-channel-check.yml` reports
  that channel red after merge. That is the alarm working.
- A branch cut before the rename fails check 12 on its first CI run, instead of
  shipping an old command name.
- Removing the `holacracy/` routine prefix and the legacy readout markers is a
  later change, once no ledger carries old titles.
