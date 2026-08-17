# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## What this repo is

A public Claude Code plugin for engaging with [Holacracy](https://www.holacracy.org/) from inside Claude. The plugin bundles six skills (four Core Role co-pilots, a governance-aware operating frame, and a checklist & metric portfolio audit) and wires up the GlassFrog MCP as a connector.

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
    ├── checklist-metric-audit/
    └── shared/
        └── authority-boundaries.md
```

## Shared reference

`skills/shared/authority-boundaries.md` is loaded by the four role skills via the relative path `../shared/authority-boundaries.md`. If a role skill's `references/` file needs to load it, the path is `../../shared/authority-boundaries.md`. **This rule is now enforced** — `scripts/skills-lint.sh` check 1 resolves every backticked path from the file that cites it. It had been stated here for months and three files violated it anyway, with nine broken load paths sitting on `main` until the check found them.

`skills/shared/triage-gates.md` holds the five gates every tension passes through, loaded by the `tension-capture` subagent, `/holacracy:capture-tension`, `/holacracy:tension-triage`, `/holacracy:supersession-sweep`, the `holacratic-ai-governance` skill, and the Rep Link's `references/tension-triage-guide.md` (which extends it and keeps its own filename). Callers cite gates by number, so renumbering the file means editing every caller — it was renamed from `tension-triage.md` and gained a new Step 1 in one pass ([ADR-0011](docs/adr/0011-separate-tension-readiness-from-tension-disposition.md)), which shifted all four original steps. **You no longer have to remember this**: `skills-lint.sh` check 2 asserts every `` `X.md` Step N `` citation names a heading that exists in `X.md`.

The plugin separates **tension readiness** (`/holacracy:tension-triage` — is this well-formed, non-duplicate, still real?) from **tension disposition** (`/holacracy:process-tension` — what output does it become?). Do not let a readiness surface start producing outputs; that conflation is what ADR-0011 exists to undo. `/holacracy:process-tension` and the authority-class write commands are not built yet — see [#120](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/120) and its child issues.

`skills/shared/project-well-formedness.md` (the project-quality rubric) and `skills/shared/project-review-critics.md` (the five critic lenses + finding schema) are loaded by the `/holacracy:review-project` command and the `project-critic` subagent. The rubric is also loaded (Family A only) by the `/holacracy:capture-project` command and the `project-capture` subagent, and by `/holacracy:stalled-project-sweep` (which emits the rubric's reserved `stale`/`blocked` states — the sweep owns the detection logic that produces them). The rubric is the single source of truth for "well-formed enough"; keep it and the critic spec in sync.

`skills/shared/project-capture-flow.md` (the draft-and-confirm P-flow for filing a well-formed project at intake) is loaded by the `/holacracy:capture-project` command and the `project-capture` subagent. It is the create-flow twin of `skills/shared/tension-capture-flow.md`; keep the two flows' constitutional-safeguard and confirmation-block conventions aligned.

`skills/checklist-metric-audit/` audits a circle's checklist items and metrics against its purpose, accountabilities, and domains, then remediates directly through the GlassFrog MCP. It leans on the constitutional distinction that checklist items and metrics are **operational, not governance** (Art. 3.2), so — unlike governance edits — it applies changes without a proposal. Its companion command is `/holacracy:audit-portfolio`. When an audit finding actually needs a new accountability or domain, it hands off to `/holacracy:capture-tension` rather than papering over the gap.

## GlassFrog MCP

Wired in via `.mcp.json` at the repo root. Server is `https://ipllc-glassfrog-mcp-server.vercel.app/mcp`, hosted on Vercel by Integral Productivity LLC, OAuth-protected so each user brings their own GlassFrog API key. If that URL ever moves (e.g., to a canonical `mcp.glassfrog.*` once an official server lands), update `.mcp.json` and land it as a `feat:` commit — release-please computes the version bump. Do not hand-edit the version; see § Versioning.

## Editing skills

The skills here are the canonical source of truth. The original five were extracted from the [Integral-Productivity/skills](https://github.com/Integral-Productivity/skills) monorepo; newer skills such as `checklist-metric-audit` originate here. Updates land here first.

## Testing the skills

**The markdown is the product. Test it like code.** Run before you push:

```bash
bash scripts/skills-lint.sh              # static integrity, ~1s, offline
bash scripts/skills-lint.test.sh         # the lint's own mutation-checked suite
```

`skills-lint.sh` runs six checks over every shipped markdown file: path
resolution, `Step N` citation integrity, frontmatter contract, skill-version
bumped when content changed, referenced-command existence, and orphaned shared
references. CI runs both on every PR via `scripts-test.yml`, plus
`--base origin/<base>` so the version-bump check has something to diff against.

CI also runs `shellcheck` over `scripts/*.sh`, and **it is pinned** — version and
digest both, with `--severity` stated rather than defaulted. Before #209 the
runner image chose the version and the operator's Homebrew chose a different one,
so PR #207 passed locally and failed in CI on the same command. Check your local
version against the pin in `scripts-test.yml` before trusting a green local run:

```bash
shellcheck --version   # must match SHELLCHECK_VERSION in scripts-test.yml
```

Two escape hatches, both under `evals/` and both requiring a written reason:

- `lint-allow-paths.txt` — a path that intentionally does not resolve from the
  file citing it, keyed on the **pair** so allowlisting CLAUDE.md's description
  of a convention does not also excuse a real bug elsewhere.
- `forward-references.txt` — a slash command named in prose before it exists.
  **Every entry needs an open issue.** When the issue closes, the lint goes red,
  so a forward reference cannot quietly become a stale one.

Behavioural evaluation — does the skill actually *do* what it says — is a
separate tier that costs API calls and runs nightly, not per-PR. See
[`evals/README.md`](evals/README.md) and
[ADR-0012](docs/adr/0012-test-the-skills-not-just-the-scaffolding.md).

```bash
bash scripts/evals-harness.test.sh          # fixture harness, mutation-checked
bash scripts/run-behavioural-eval.test.sh   # the nightly runner's suite, offline
bash scripts/eval-report.test.sh            # the step-summary renderer's suite
bash scripts/eval-cost.test.sh              # the cost ledger's arithmetic
```

`eval-cost.test.sh` runs offline against a committed fixture of the aggregator's
output shape, and against the **real** pinned aggregator when `AGGREGATOR` is
set — which CI does, via `scripts/fetch-pinned-aggregator.sh`. CI also sets
`REQUIRE_AGGREGATOR=1`, which turns "use the real one when available" from a
branch into an assertion: a fetch that silently produced nothing would otherwise
leave the gate checking the correction against its own fixture and still
reporting green.

**A mutation harness that cannot fail is worse than no mutation harness.** Both
`eval-cost.test.sh` and `eval-report.test.sh` build their mutants through a
helper whose exit status is checked, and each suite self-tests that helper
against a deliberately absent target. The first version did neither: the
builder's `assert` fired into a stream nothing read, the mutant was never
written, and the case then ran a nonexistent file — which fails, which is
exactly what "the mutant behaves differently" asserts. Measured, with three
targets moved and semantics untouched: `27 cases passed`, exit 0, five of six
mutation cases vacuous. If you add a mutation case, the target string is a
coupling to real code, and drift in it must be loud.

**Both of those run on every PR; the graded tier they guard does not.**
`.github/workflows/skills-eval.yml` runs `scripts/run-behavioural-eval.py`
nightly and on `workflow_dispatch`, against `ANTHROPIC_API_KEY`. That asymmetry
is deliberate and it is also the risk: an instrument that executes once a day
against a secret no laptop holds is [#122](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/122)'s
shape exactly. So the suite substitutes a fake model that replays a scripted plan
through the *real* stub over the *real* generated MCP config, and everything but
the model is exercised offline, per PR.

Three things about the runner are worth knowing before you change it:

- **A run that did not really happen must fail every assertion, not pass the
  negative ones.** An empty write log contains no forbidden write, so
  `no_write_of` passes on a session that never ran. Five conditions are treated
  as execution failures for exactly this reason: the executor did not start, the
  result event carried `is_error`, the session had the wrong *shape*, a control
  leg reached the checkout on disk, or the model made no tool calls at all. Four
  of the five were live defects, not hypotheticals.
- **The session's shape is checked, not assumed.** Read off the `system/init`
  event: the session must offer a `Skill` tool, `with_skill` must have at least
  one `holacracy:` command registered, and the control must have none. Before
  [#226](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/226)
  the harness could not tell "the plugin did not load" from "the plugin loaded
  and changed nothing" — both produce a healthy transcript and a scoreable
  grading — and four graded runs reported deltas between two configurations that
  were both the base model.
- **`--bare` is gone, and must not come back.** It bought hermeticity in one flag
  and clamped the built-in tool set to `Bash, Edit, Read`. There is no `Skill`
  tool in that set, so no skill could be invoked in either leg, whatever
  `--plugin-dir` loaded; `--tools default` does not undo it. Hermeticity now comes
  from `CLAUDE_CONFIG_DIR` pointed at an empty per-run directory, a cwd outside
  this checkout, and a withheld `Bash`/`Glob`/`Grep`/`Write`. One consequence is
  deliberate: the plugin's own SessionStart hook is now live in `with_skill`, so
  read a delta as *what installing this plugin does*, not *what a skill's prose
  does*.
- **`--plugin-dir` and `--strict-mcp-config` are load-bearing, not tidying.**
  `--plugin-dir` is the only route by which the plugin enters the session —
  a claim the `--validate-only` preflight now checks rather than asserts.
  `--strict-mcp-config` is what stops the plugin's own `.mcp.json` — which points
  at the **production** GlassFrog connector — from loading alongside the stub.
- **The cheapest tier is a session that never authenticates.** The CLI emits its
  `system/init` event *before* it checks credentials, so `--validate-only` starts
  a real session per config, reads the tool list and the registered commands, and
  kills it. No API key, no model turn, no cost. Every fact needed to spot #226 was
  available this way from the first day; it took four paid runs and an artifact
  download instead. Run it before you touch the runner:

  ```bash
  python3 scripts/run-behavioural-eval.py --out /tmp/probe --validate-only \
    --case evals/cases/tension-triage/evals.json
  ```
- **Ordering claims are checked in Python, not judged.** "Successor before
  archive" and "no write without confirmation" are read off the stub's write log.
  Deterministic, free, and the cheapest available reduction in the variance that
  `evals/README.md` says makes a nightly job ignorable.

Every assertion must declare `discriminating`, and a non-discriminating one must
carry `why_kept`. The runner refuses a case file that omits either. An assertion
that passes with the skill disabled measures nothing, and the only defensible
exception is a constitutional floor that must hold in every configuration.

`evals/benchmark.json` is the baseline [#173](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/173)'s
regression alarm compares against. **It is still unmeasured**, and says so in its own
body. `ANTHROPIC_API_KEY` is configured now — that blocker is gone — but the
first graded run taken after it
([31229964963](https://github.com/Integral-Productivity/holacracy-claude-plugin/actions/runs/31229964963))
ran its two arms on two different models and so measured the models. Seed it
from a real `workflow_dispatch` run, never by hand: a baseline nobody measured
is the same report-health-from-absent-evidence failure the grounding readout
section below spends a page on.

**A baseline is only comparable against runs of the same model, and only against
runs of a harness that loads the plugin.** The first condition is recorded in the
file (`metadata.executor_model`); the second is not, and is what
[#226](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/226)
turned from a theoretical caveat into a rule — every number produced before
[#227](https://github.com/Integral-Productivity/holacracy-claude-plugin/pull/227)
merged compared the base model against itself. Re-seed after any change to how
the session is constructed, and read the `--validate-only` session-shape
preflight before trusting a run at all.

**Fixtures never contain real GlassFrog data, and that is structural rather than
procedural.** `scripts/glassfrog-schema-capture.py` reduces a live response to
type names; `scripts/glassfrog-fixture-gen.py` builds a synthetic org from a
hand-authored `evals/scenarios/*.json` and validates it against that schema.
Never commit a recorded response — the live API returns filler names and email
addresses on every role record, this repo is public, and a leak is not undone by
a later commit. § 2 of the harness suite is the guard that asserts it.

`evals/stub/glassfrog_stub.py` **reproduces the live API's defects on purpose**:
`list_subrole_tensions` returns direct children only, and `update_tension` 422s
on `meeting_type`. Do not "fix" either — a stub that smoothed them over would let
a skill pass an eval by doing something that fails in production.

**Do not add a check without adding its mutation case.** `skills-lint.test.sh`
asserts, for every check, both that a seeded defect fails the lint *and* that it
passes with that check skipped. The second half is what proves the check is
load-bearing rather than incidentally covered by another.

## Versioning

**release-please is the sole writer of the plugin version. Never hand-edit it.**

Three files carry the plugin version, and `release-please-config.json` (`release-type: simple`) owns all three end to end:

| File | Role |
| --- | --- |
| `.release-please-manifest.json` | the released-version baseline release-please reads |
| `version.txt` | required by `release-type: simple` |
| `.claude-plugin/plugin.json` `$.version` | the user-visible version, rewritten as an `extra-files` target |

Do not edit any of them — not in a feature PR, not "to keep them in sync," not because a version looks stale. They are written only by the `chore(main): release X.Y.Z` PR that `release-please.yml` opens. Five feature PRs hand-bumped `plugin.json` to 0.10.0 while the manifest sat at 0.6.0, and the next release would have *downgraded* the visible version to 0.7.0 (issue #100). `.github/workflows/version-authority.yml` now fails any PR that tries.

**What you do instead: write a Conventional Commit.** The type drives the bump — `fix:` → patch, `feat:` → minor, `feat!:` / `BREAKING CHANGE:` → major (this repo sets `bump-minor-pre-major: false`, so a breaking change takes 0.x straight to 1.0.0). A bundle-shape change — skill, command, or agent added; MCP repointed — is expressed by using `feat:`, not by editing a number.

**Merging the release PR is the release act.** It writes all three files, updates `CHANGELOG.md`, tags `vX.Y.Z`, and `promote-stable.yml` fast-forwards the `stable` branch the public marketplace tracks. Don't let the release PR sit — an unmerged release PR freezes the shipped version, which is what makes hand-bumping feel necessary in the first place.

**To force a specific version** (rare), add a one-shot footer as the final line of the commit message *and* the PR body, and let release-please do the writing:

```
Release-As: 1.2.3
```

Do not use the `release-as` key in `release-please-config.json` — it is sticky and pins every subsequent release until someone removes it.

**Everything else in `plugin.json` is hand-maintained** — `description`, `keywords`, `author`. Edit those freely; only `$.version` is off-limits.

**Skill versions stay manual.** Each skill carries its own `version:` in frontmatter, unrelated to the plugin version and untouched by release-please. Bump a skill's version when its content changes meaningfully.

Convention of record: [`docs/adr/0010-release-please-is-the-sole-writer-of-the-plugin-version.md`](docs/adr/0010-release-please-is-the-sole-writer-of-the-plugin-version.md), which amends ADR-0002's manual release steps and leaves its tag-driven `stable` promotion intact.

## Measuring whether the grounding directive fired

**Do not grep transcripts for the directive text.** It is the obvious move and it is wrong:

```bash
# WRONG — do not use this
grep -l "Holacracy plugin: role-grounding" ~/.claude/projects/*/*.jsonl
```

On 2026-08-03 that returned **10 files** against a true **3**. Whole-file grep cannot tell *the hook injected this* from *the session read or quoted it* — and the sessions most likely to read the hook source are this repo's own. It is the same mistake that produced the false 2.2% in [#122](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/122) and the 23 false positives in [#123](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/123).

Use the instrument, which counts only hook-output records and derives its marker from the live hook:

```bash
scripts/grounding-readout.sh --since-start 2026-08-03T19:52
```

Two things to get right when reading it:

- **`--since-start`, not `--since`.** `--since` filters on file mtime, which misfiles any session that began before the cutoff and was appended to afterwards — five of them in the 2026-08-03 window. `--since-start` buckets by the session's first record.
- **The in-repo line is corroboration, not the result.** This repo's own sessions are held out of every headline figure and reported separately, because they work on the directive itself. Judge the experiment on the cross-repo figures.

- **`plugin versions seen` is the first thing to read on a bad number.** The hook stamps the running version into every payload, and the readout reports which versions actually ran. A large `no version stamp` count means copies too old to carry the stamp — which is the [#122](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/122) condition exactly, and what took archaeology across three install channels to find the first time.

The instrument is a proxy and says so: an assistant verbatim-quoting a documentation example still scores. [#71](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/71) tracks the structured session log that would replace it.

### The alarms

The readout is descriptive — it has no thresholds and always exits 0. Three alarms fail loudly. (The heading carried a count until [#187](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/187); it was wrong by one for as long as the third alarm had existed, which is why the count is gone rather than corrected — the same fix [#143](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/143) made to `scripts-test.yml`'s header.)

```bash
scripts/grounding-fire-rate-check.sh      # did the directive stop reaching sessions?
scripts/plugin-version-skew-check.sh      # is the loaded version behind `stable`?
scripts/release-pr-age-check.sh           # has anything actually shipped?
```

The first two read the readout's output and run **operator-local**, alongside the weekly `grounding-pdca1-readout` task — they read `~/.claude/projects` and `~/.claude/plugins`, which no CI runner has. CI runs their test suites, which drive them entirely through fixtures (`--readout-json`, `--fixture-root`, `--loaded-json`).

**The third is not operator-local, and that is the thing to get right about it.** It reads only the GitHub API — no `~/.claude`, no local install — so it runs anywhere `gh` is authenticated, and it already runs on a schedule: `.github/workflows/release-latency-alarm.yml` fires it daily at 15:17 UTC and on `workflow_dispatch`. Hand-running it is for verification, not coverage. Its verification affordances are `--now` (a synthetic clock) and `--pr-json` (substitute the open-PR list for a fixture — PR metadata only; the reads of `stable` and of the PR's head branch still hit the live repo). Neither is used by the workflow. Reading this section and coming away thinking all three need a human at a laptop is the misread that leaves the scheduled one hand-run and the operator-local two uncovered.

It belongs in this section because it guards the precondition the other two measure against: merging is not shipping. Consumers install from `stable`, `stable` only advances when `promote-stable.yml` fires on a `vX.Y.Z` tag, and that tag only exists once the release PR merges. A directive that has not been released cannot reach any session no matter what the handler says — that is Layer 1 of [#122](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/122), the 34-day freeze [#129](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/129) was filed for.

Exit codes are the same for all three: `0` clear, `1` alarm (a tracking issue is filed and updated, and auto-closed when it recovers), `2` usage or operational error. Add `--dry-run` to see the report without writing to GitHub — on all three, a `--dry-run` that *would* have alarmed still exits 1. The release check adds one notification layer the other two have nowhere to put: a sticky comment on the release PR itself, upserted by the same marker as the tracking issue, so the alarm appears where the merge happens.

The skew check adds `n/a` for a channel that is provably not in use — no plugin cache, no install record, no desktop-app surface. That is a fact, not a fault, and it does not alarm. `UNKNOWN` is different: it means a channel that *is* in use could not be read, which is the #122 condition.

**`2` includes "nothing to measure."** An empty window, an unreadable readout, or a probe root with no plugin channels all exit 2 rather than reporting clear. Reporting health from absent evidence is precisely the failure #122 documents, and neither operator-local alarm is permitted to commit it.

**The release check does not hold that line as tightly, and you should know where.** Its clear paths still exit `0` when `stable` or `compare/stable...main` could not be read; the unreadable figure degrades to `<unknown>` inside the report behind a `::warning::` rather than escalating to `2`. Its one genuinely absent-evidence state is handled differently again: `stable` behind `main` with *no* open release PR is a `::warning::` on an exit `0`, because it is not release latency — it is release-please having taken its soft-failure path, or a tag cut without `promote-stable.yml` fast-forwarding `stable` ([#108](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/108)). A green run of this check is therefore weaker evidence than a green run of the other two. Read the report, not just the exit code.

## Agent skills

### Issue tracker

Issues are tracked in this repo's GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles map identity to existing repo labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. `CONCEPTS.md` at the root holds shared domain vocabulary (entities, named processes, status concepts) — relevant when orienting to the codebase or discussing domain concepts. See `docs/agents/domain.md`.

### Documented solutions

`docs/solutions/` — documented solutions to past problems (bugs, best practices, tooling decisions, workflow patterns), organized by category with YAML frontmatter (`module`, `tags`, `problem_type`). Relevant when implementing or debugging in documented areas.
