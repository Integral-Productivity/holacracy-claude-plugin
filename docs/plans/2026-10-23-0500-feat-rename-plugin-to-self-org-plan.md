---
title: "feat!: rename the plugin from holacracy to self-org"
date: 2026-10-23
type: feat
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# feat!: rename the plugin from holacracy to self-org

## Goal Capsule

- Objective: people can install, share, and talk about this plugin under a name that HolacracyOne's trademark rules allow, and every command, skill, and connector still works after they upgrade.
- Means: rename every shipped identifier that carries the mark to `self-org`, keep descriptive prose about Holacracy, and accept the legacy identifiers where a rename would silently break an existing install (KTD1, KTD5, KTD6).
- Authority: Kraig's decisions in the session (below) > this plan > repository conventions in `CLAUDE.md`.
- Stop conditions: stop if Claude Code rejects `self-org` as a plugin name or as an MCP tool prefix segment; stop if a rename would require rewriting a historical record (`docs/adr` 0001-0019, `docs/plans`, `docs/brainstorms`, `docs/solutions`, `docs/ideation`, `CHANGELOG.md`).
- Execution profile: one branch, one PR, held for Kraig (label `hold-for-review`, auto-merge off). PR #405 merges first; this branch then merges `main` and renames the command #405 adds.
- Who ships: `lfg` opens the PR; Kraig merges.

## Product Contract

### Summary

Rename the plugin from `holacracy` to `self-org` in every name it ships: plugin and catalog names, the `/holacracy:` command prefix, skill and agent names, the MCP tool prefix, the release-please component, and the SessionStart directive marker. Keep the word Holacracy where it describes the method (the Constitution, "Holacratic role", the trademark notice). Record the decision as ADR-0020. Release as 1.0.0 because every command name changes.

### Problem Frame

HolacracyOne's trademark page (https://www.holacracy.org/trademark/) lets anyone make derivative works of the CC BY-SA Constitution, but says "you may not brand your derivative work with Holacracy in its name, to avoid confusion between your work and the official Holacracy document". Two shipped reference files adapt Constitution text (see `NOTICE`), so the plugin is a derivative work, and its name, command prefix, and skill names all carry the mark. Kraig has asked HolacracyOne for permission, but the answer may take time, and the repository is already public.

### Requirements

- R1. No name the plugin ships carries the mark: plugin name, catalog plugin name, command prefix, skill names and folders, agent name, MCP tool prefix, release-please component, and the directive marker.
- R2. Every command that existed as `/holacracy:<x>` exists as `/self-org:<x>` with unchanged behavior.
- R3. Descriptive prose about Holacracy, the Constitution attribution in `NOTICE`, and the trademark notice stay.
- R4. Historical records stay unedited: `docs/adr/0001`-`0019`, `docs/plans` (except this plan), `docs/brainstorms`, `docs/solutions`, `docs/ideation`, `CHANGELOG.md`.
- R5. An existing user's scheduled routines titled `holacracy/...` keep appearing in the SessionStart briefing after the upgrade.
- R6. The grounding readout keeps counting directive firings from sessions that ran before the rename.
- R7. The README tells an existing user how to move from `holacracy@<catalog>` to `self-org@<catalog>`, including the GlassFrog re-authentication.
- R8. A lint check fails if a shipped file reintroduces a `/holacracy:` command or a `holacracy-` skill name, so a branch cut before the rename (PR #405) cannot reintroduce it silently.
- R9. The release is a major version (1.0.0), produced by release-please from a `feat!` commit, with no hand-edited version file.

### Key Decisions

- Rename now, while asking HolacracyOne in parallel. (session-settled: user-directed — chosen over keeping the name until HolacracyOne answers: the trademark page forbids the mark in a derivative work's name, and the repo is already public.) Governs R1.
- The new name is `self-org`. (session-settled: user-approved — chosen over holacraft/holacrafty and rolecraft: names the field, not the method, and has no likeness to the mark.) Governs R1, R2.
- The GitHub repository name does not change in this PR. (session-settled: user-approved — chosen over renaming the repo now: a settings action outside the branch; GitHub redirects old URLs.) Governs R4 scope of URLs.
- The PR is held for Kraig. (session-settled: user-directed — chosen over auto-merge on green: merging is Kraig's decision and this change breaks every command name.)

### Scope Boundaries

In scope: every shipped file (`_shipped_md` in `scripts/skills-lint.sh`), scripts, hooks, evals config and fixtures, workflows' comments, README, CLAUDE.md, CONCEPTS.md, STRATEGY.md, NOTICE, CONTRIBUTING, issue forms, and a new ADR-0020.

#### Deferred to Follow-Up Work

- Renaming the GitHub repository (Kraig, GitHub settings).
- Updating the `holacracy` entry in the private `Integral-Productivity/marketplace-labs` catalog (Kraig; not reachable from this session). Until it lands, the post-merge `install-channel-check.yml` run reports the labs channel red. That is the alarm working, not a defect.
- Renaming the `HOLACRACY_*` environment variables and the `~/.claude/holacracy/routines.jsonl` ledger path (see Assumptions).

#### Outside scope

- Any behavior change to a command, skill, or agent.
- Rewriting history or historical documents.

### Dependencies

- PR #405 (`/holacracy:project-triage`) is open and is merged by hand. It must merge before this PR; this branch then merges `main` and renames the new command. R8's lint check makes a missed rename fail CI.

## Planning Contract

### Key Technical Decisions

- KTD1. Name mapping. Plugin `holacracy` -> `self-org`; catalog `integral-productivity-holacracy` -> `integral-productivity-self-org`; skills `holacracy-facilitator|secretary|lead-link|rep-link` -> `self-org-facilitator|secretary|lead-link|rep-link`; `holacratic-ai-governance` -> `self-org-ai-governance`; agent `holacracy-coach` -> `self-org-coach`; release-please `package-name` -> `self-org`. Role names (Facilitator, Lead Link) are method vocabulary, not the mark, and stay.
- KTD2. MCP tool prefix becomes `mcp__plugin_self-org_glassfrog-extended__`. Claude Code accepts hyphens in this segment: this session itself exposes `mcp__plugin_browser-use_browser-use__*` and `mcp__plugin_ip-legal_Descrybe__*`. The old prefix is removed from `evals/glassfrog-server-prefixes.txt` rather than kept: that file grants tools to the coach shipped in the same release, and an install of this release never runs under the old prefix. The coach's `tools:`/`disallowedTools:` lines are regenerated with `scripts/glassfrog-tool-inventory.py coach-frontmatter`, never hand-edited.
- KTD3. Directive markers become `**self-org plugin: role-grounding directive**` and `**self-org plugin: role-grounding check (conditional directive)**`. `scripts/grounding-readout.sh` keeps deriving the live marker from the hook and also counts the two legacy markers from a fixed list, so pre-rename sessions stay measurable (R6). The legacy list is data in the readout, not derived, because the old hook source no longer exists at HEAD.
- KTD4. Routine title prefix: `self-org/` becomes the documented convention; the hook filter accepts `self-org/` or legacy `holacracy/` (R5). Removing the legacy prefix is a later, separate change.
- KTD5. `HOLACRACY_*` environment variables and the ledger default path stay unchanged. They are local configuration identifiers that users and launchd/Cowork setups already reference, not names the plugin ships to others; renaming them silently disables a working setup. Recorded as an assumption for Kraig to overturn.
- KTD6. GlassFrog OAuth: the credential key becomes `plugin:self-org:glassfrog-extended`, so users sign in once more. The hook's authentication gate matches any server name containing `glassfrog`, so its logic does not change; only fixtures do. README states the re-auth step (R7).
- KTD7. Add lint check 12, "no legacy plugin identifier in shipped files": fails on `/holacracy:` or `holacracy-<skill>` / `holacratic-ai-governance` in any `_shipped_md` file and in `.claude-plugin/*.json`. Allowlisted by pair (as built: a separate `evals/legacy-names-allow.txt`, because `lint-allow-paths.txt` is keyed on paths, not tokens) where prose must name the old identifier (ADR-0020, the README migration note, CLAUDE.md history). Ships with its mutation case per the repo rule.
- KTD8. Historical documents keep their old identifiers (R4). `scripts/skills-lint.sh` already excludes `docs/plans|brainstorms|solutions|ideation` and `CHANGELOG.md` from path checks and checks only links in `docs/adr`; renamed skill paths cited by markdown link inside an ADR must still resolve, so any such link is handled in ADR-0020 by a supersession note rather than by editing old ADRs. If a link in ADR 0001-0019 breaks, add a pair entry to `evals/lint-allow-paths.txt` with the reason "historical record, renamed in ADR-0020".
- KTD9. Commit as `feat!:` with a `BREAKING CHANGE:` footer; `bump-minor-pre-major: false` takes 0.28.1 to 1.0.0. Skill frontmatter versions get a major bump (x.y.z -> (x+1).0.0) because their invocation names change.

### High-Level Technical Design

What is accepted after the rename, by surface (directional):

| Surface | New identifier (written) | Legacy identifier still accepted |
|---|---|---|
| Command prefix | `/self-org:` | none (Claude Code registers one name) |
| MCP tool prefix | `mcp__plugin_self-org_glassfrog-extended__` | none |
| Directive marker (readout) | derived from live hook | fixed list of the two `Holacracy plugin:` markers |
| Routine titles (hook filter) | `self-org/` | `holacracy/` |
| Env vars, ledger path | unchanged `HOLACRACY_*`, `~/.claude/holacracy/` | n/a |

### Assumptions

- Keeping `HOLACRACY_*` env vars and the ledger path is acceptable under the trademark rule because they are local configuration, not product names (KTD5).
- `self-org` is free of a conflicting trademark. No search was run.
- Users accept one GlassFrog re-authentication (KTD6).

### Sequencing

U1 first (the decision of record). U2-U6 are the mechanical rename and can land in any order in one commit series; U7 (lint guard) comes after them so it runs green. U8 last. After PR #405 merges: merge `main`, rename its command, rerun the Verification Contract.

## Implementation Units

### U1. ADR-0020: the plugin name carries no trademark

- Goal: record the decision, the name mapping, the legacy-acceptance rules, and the follow-ups.
- Requirements: R1, R4, R9.
- Files: `docs/adr/0020-the-plugin-name-carries-no-trademark.md`.
- Approach: follow the shape of `docs/adr/0019-the-triage-state-vocabulary-lives-in-the-plugin.md`. Status Accepted. Cite the trademark page and `NOTICE`. List the mapping (KTD1), KTD3-KTD5, and the deferred items.
- Test scenarios: `skills-lint.sh` link check passes for the new ADR.
- Verification: lint clean.

### U2. Manifest, catalog, release component, install check

- Goal: the plugin installs as `self-org`.
- Requirements: R1, R7.
- Files: `.claude-plugin/plugin.json` (name, keywords; never `version`), `.claude-plugin/marketplace.json`, `release-please-config.json` (`package-name`), `scripts/install-channel-check.sh`, `scripts/install-channel-check.test.sh`, `scripts/release-pr-age-check.sh` and its test (release branch name), `.github/workflows/version-authority.yml` (comment), README `## Install`.
- Approach: rename values; keep the repo slug `Integral-Productivity/holacracy-claude-plugin`.
- Test scenarios: `install-channel-check.sh --local-only` passes with `self-org`; its test suite still replays #234; release-pr-age-check tests pass with the new branch name.
- Verification: both suites green.

### U3. Skill and agent renames

- Goal: skill and agent names carry no mark.
- Requirements: R1, R2.
- Files: `git mv` of the five skill folders and `agents/holacracy-coach.md`; each moved `SKILL.md` frontmatter `name:` and `version:`; every path reference to them in shipped files, scripts, evals, and `skills/shared/*` (e.g. `../holacratic-ai-governance/references/glassfrog-api-constraints.md`).
- Approach: move, then rewrite references; check 1 of `skills-lint.sh` proves every backticked path resolves.
- Test scenarios: lint checks 1, 3, 4, 6 pass; `--base origin/main` sees the version bumps.
- Verification: lint clean.

### U4. Command prefix

- Goal: every `/holacracy:<x>` reference becomes `/self-org:<x>`.
- Requirements: R2.
- Files: all shipped markdown under `commands/`, `agents/`, `skills/`, root docs; `scripts/run-behavioural-eval.py` and its test (registered-command preflight looks for the plugin's commands; the `skill` field names the plugin); `evals/cases/**`; `evals/forward-references.txt`.
- Approach: mechanical replacement limited to non-historical paths; then read `run-behavioural-eval.py` around the session-shape preflight to confirm it reads the plugin name from one place.
- Test scenarios: lint check 5 (referenced-command existence) passes; `run-behavioural-eval.test.sh` passes; `--validate-only` preflight registers `self-org:` commands when the CLI is available.
- Verification: suites green.

### U5. MCP tool prefix

- Goal: the coach gets its GlassFrog tools under the new prefix.
- Requirements: R1, R2.
- Files: `evals/glassfrog-server-prefixes.txt`, `agents/self-org-coach.md` (regenerated lines), `scripts/skills-lint.test.sh` fixtures, `CLAUDE.md` and README prose naming the prefix.
- Approach: update the prefixes file, run `python3 scripts/glassfrog-tool-inventory.py coach-frontmatter`, paste over the coach's two lines.
- Test scenarios: lint checks 9 and 10 pass; the lint suite's tool-grant cases pass with the new prefix.
- Verification: `skills-lint.test.sh` green.

### U6. Hook marker, routine prefix, readout

- Goal: R5 and R6 hold.
- Requirements: R1, R5, R6.
- Files: `hooks-handlers/session-start.sh`, `hooks-handlers/session-start.test.sh`, `scripts/grounding-readout.sh` and its test suite, `scripts/grounding-fire-rate-check.sh` fixtures if they embed the marker, `skills/shared/actor-and-role-resolution.md`, the secretary routine references.
- Approach: change both directive headers; accept `self-org/` or `holacracy/` in the routine filter; add a legacy-marker list to the readout's `has_marker`; update OAuth fixtures to `plugin:self-org:glassfrog-extended`.
- Test scenarios: a `holacracy/...` routine and a `self-org/...` routine both appear in the briefing; a transcript containing the old marker is counted; a transcript with the new marker is counted; a `foo/...` routine is ignored.
- Verification: `session-start.test.sh` and the readout suites green.

### U7. Lint check 12: no legacy plugin identifier

- Goal: R8.
- Requirements: R8.
- Files: `scripts/skills-lint.sh`, `scripts/skills-lint.test.sh`, `evals/lint-allow-paths.txt` (pair entries with reasons).
- Approach: new check over `_shipped_md` plus `.claude-plugin/*.json`; reuse the pair allowlist; add the mutation case (seeded `/holacracy:x` fails the lint; passes with the check skipped).
- Test scenarios: seeded defect fails; check-skipped run passes; current tree passes.
- Verification: `skills-lint.test.sh` green with one more case.

### U8. Docs

- Goal: readers see the new name and how to migrate.
- Requirements: R3, R7.
- Files: `README.md` (title, install, migration note, connector prefix), `CLAUDE.md`, `CONCEPTS.md`, `STRATEGY.md`, `NOTICE` (file list paths), `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/*.yml`.
- Approach: replace identifiers; keep descriptive Holacracy prose and the trademark notice; add "Upgrading from `holacracy`" with: uninstall `holacracy@<catalog>`, install `self-org@<catalog>`, sign in to GlassFrog again, rename scheduled routines to `self-org/` when convenient.
- Test scenarios: lint link checks pass; install-channel-check passes.
- Verification: lint clean.

## Verification Contract

Run from the repo root, all must pass:

- `bash scripts/skills-lint.sh --base origin/main`
- `bash scripts/skills-lint.test.sh`
- `bash scripts/evals-harness.test.sh`
- `bash scripts/run-behavioural-eval.test.sh`
- `bash scripts/eval-report.test.sh`
- `bash scripts/eval-cost.test.sh`
- `bash scripts/install-channel-check.sh --local-only` and `bash scripts/install-channel-check.test.sh`
- `bash hooks-handlers/session-start.test.sh`
- every other `scripts/*.test.sh` (grounding readout, alarms, release-pr-age-check)
- `shellcheck` over `scripts/*.sh` at the version pinned in `.github/workflows/scripts-test.yml` when available locally
- `python3 scripts/run-behavioural-eval.py --out <tmp> --validate-only --case evals/cases/tension-triage/evals.json` when the `claude` CLI is available
- grep: no `/holacracy:`, `holacracy-(facilitator|secretary|lead-link|rep-link|coach)`, `holacratic-ai-governance`, or `mcp__plugin_holacracy_` outside the historical paths and the allowlisted pairs.

## Definition of Done

- All Verification Contract commands pass on the branch head.
- No version file edited by hand; skill versions bumped.
- PR body states the breaking change, the migration steps, the #405 ordering, and the deferred items.
- The PR carries `hold-for-review` and auto-merge is off.
- No leftover experimental code or stray files in the diff.

## Sources & Research

- Trademark page: https://www.holacracy.org/trademark/ (fetched 2026-10-23).
- `NOTICE` (CC BY-SA excerpts), PR #403.
- Inventory at `f664e89`: 94 non-historical files mention the mark; 191 `/holacracy:<cmd>` command references; `HOLACRACY_*` env vars in the hook.
- Hyphenated plugin prefixes observed in this session's tool list (`mcp__plugin_browser-use_browser-use__*`).
- Research was done by inline reads and greps rather than research subagents: the work is a mechanical rename in a repo whose patterns are known in this session.
