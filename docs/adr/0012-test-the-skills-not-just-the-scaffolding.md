# 12. Test the skills, not just the scaffolding

Date: 2026-08-04

## Status

Accepted

## Context

This repository had, until now, rigorous testing pointed at the wrong half of
itself.

`.github/workflows/scripts-test.yml` runs mutation-checked bash suites over two
shell files, under two timezones, with shellcheck, and its header argues at
length for each guard. `release-latency-alarm.yml` is a genuine fitness function
with three escalating alarm layers. `version-authority.yml` enforces an
invariant whose violation once broke five consecutive PRs
([ADR-0010](0010-release-please-is-the-sole-writer-of-the-plugin-version.md)).

Meanwhile the roughly thirty markdown files that **are** the plugin — six
skills, thirteen commands, four subagents, ten shared references — had exactly
one automated gate between them: `claude plugin validate`, a JSON-schema check
on `plugin.json`. Nothing verified that a relative load path resolved, that a
cited step number existed, that a skill's hand-maintained `version:` moved when
its content did, or that any of it behaved as written.

On the maturity model this org itself maintains (the `promptops-consulting`
skill), that places the repo at a strong Stage 3 — per-skill versioning, release
automation, ADRs, CI — with the defining Stage 4 property absent: *"automated
evaluation tied to CI: skills tested before merge."*

### The evidence

[PR #166](https://github.com/Integral-Productivity/holacracy-claude-plugin/pull/166)
paid the bill three times in one change:

1. A link-resolution script was written by hand, run once, and discarded. The
   next contributor starts from zero.
2. Four gates in `skills/shared/triage-gates.md` were renumbered, requiring
   fourteen citations remapped across six files. The recurrence risk was
   mitigated by **adding a warning paragraph to `CLAUDE.md`**.
3. The behavioural claim at the centre of the PR — that the authority gate now
   fires before venue routing — shipped **unverified**, because no harness
   existed that could assert it.

The second is the sharpest. `CLAUDE.md` had *already* stated, for months, that a
role skill's `references/` file must load shared references via `../../shared/`
and not `../shared/`. Writing it down changed nothing: three files violated it,
and **nine broken load paths were sitting on `main`** when the first draft of the
lint in this ADR's implementation ran. A rule that only exists in prose is a rule
that is not enforced.

### Why not just run behavioural evals

Because they cannot gate a PR. Behavioural evaluation of a GlassFrog-backed
skill needs model calls, wall-clock, and organizational data; a per-PR gate needs
to be deterministic, offline, and sub-second. Treating them as one thing means
either a slow flaky gate or no gate. They are two tiers with different economics
and belong on different cadences.

## Decision

**Testing is tiered by cost, and each tier runs at the cadence its cost allows.**

1. **Tier 1 — static integrity, gates every PR.** `scripts/skills-lint.sh`, six
   deterministic offline checks over every shipped markdown file: path
   resolution, `Step N` citation integrity, per-artifact frontmatter contract,
   skill-version-bumped-on-content-change, referenced-command existence, and
   orphaned shared references. Runs in about a second; wired into the existing
   `scripts-test.yml` rather than a new workflow, because that file already
   declares itself the home for repo-local bash suites and explains why it
   carries no `paths:` filter.

2. **Tier 2 — behavioural evals on recorded fixtures, nightly and on demand.**
   Reuses the `skill-creator` harness (`run_eval`, `aggregate_benchmark`, the
   grader agent, the eval viewer) rather than inventing one. Golden cases are
   drawn from the 2026-08-01 backlog run, which produced labelled ground truth
   most projects have to fabricate.

3. **Tier 3 — triggering accuracy.** `run_loop.py` over the six skill
   descriptions, 60/40 train/test, best description selected on **test** score.
   This plugin's skills genuinely compete with one another, so the near-miss
   negatives that make the exercise worthwhile are naturally available.

4. **Tier 4 — wild telemetry.** The structured session log tracked as
   [#71](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/71),
   plus an eval-regression alarm reusing `release-latency-alarm.yml`'s
   three-layer idempotent shape.

Four decisions inside Tier 1 are load-bearing enough to record:

**Path resolution is strict, not permissive.** A candidate resolves from the
citing file's own directory or the repo root — not from "any plausible base". A
multi-base resolver would have accepted `../shared/agentic-routines.md` inside
`skills/holacracy-secretary/references/`, which resolves from the *skill* root
but not from the file doing the loading. Strictness is the only reason the check
can see that defect class at all.

**Allowlists are keyed on the pair, never the path.**
`../shared/authority-boundaries.md` is correct prose in `CLAUDE.md`, whose
subject *is* the path convention, and simultaneously a real bug in a role
skill's `references/` file. A path-keyed allowlist would excuse the first while
silencing the second — how an allowlist becomes a blindfold.

**Forward references are legitimate, and they expire.** #166 deliberately points
at `/holacracy:process-tension`, which does not exist; the alternative was to
quietly widen triage's scope to fill the gap, which is the conflation
[ADR-0011](0011-separate-tension-readiness-from-tension-disposition.md) exists to
undo. So a forward reference is allowed when declared in
`evals/forward-references.txt` **against an open issue**. When the issue closes,
the lint goes red and somebody decides whether the command shipped or the plan
died. Vapour becomes debt with a date on it.

**Every check must be mutation-proven.** `skills-lint.test.sh` asserts, per
check, both that a seeded defect fails the lint *and* that it passes with that
check skipped. The second assertion is the load-bearing one: without it a check
whose defects another check incidentally catches would pass a naive suite while
buying nothing. This is the property that makes `grounding-readout.test.sh`
trustworthy, and it is now the price of admission for any new check.

## Consequences

**Easier**

- The nine broken load paths on `main` are fixed, and that class cannot recur
  silently. Two rules that lived only in `CLAUDE.md` prose are now assertions.
- Renumbering a shared reference stops being a hand-audit. #166's fourteen
  citations would have been checked mechanically.
- `CLAUDE.md` gets shorter and more honest: paragraphs that asked contributors
  to remember things are replaced by pointers to the check that enforces them.
- A contributor can run the whole static tier locally in about a second, offline,
  with no credentials.

**Harder**

- Six checks are six things that can produce a false positive, and the first run
  produced several — `Step 0.5` read as `Step 0`, citations bound across a whole
  table row, commands whose procedures are numbered lists rather than `## Step`
  headings. Each forced a narrowing. A check that cries wolf gets disabled, so
  the burden is on the check to be precise, and precision is ongoing work.
- The mutation requirement makes adding a check roughly twice the work.
- Tier 2 fixtures will ship in a **public repository** carrying data from a real
  organization. Redaction by default is a hard requirement of the capture
  harness, not a nicety, and it is the main reason Tier 2 is a separate issue
  rather than part of this change.
- Tiers 2 and 3 need `ANTHROPIC_API_KEY` in CI, which is a new secret and a new
  standing cost.

**Deferred**

- Everything above Tier 1. This ADR records the whole program; only the static
  tier ships with it. `evals/cases/tension-triage/evals.json` is present as the
  worked template — assertions written, fixture uncaptured, not running in CI —
  so the next slice starts from a shape rather than a blank page.

## Related

- [ADR-0008](0008-session-injected-honest-grounding-directive.md) and
  `scripts/grounding-readout.sh` — the existing telemetry leg, and the source of
  the mutation-checking convention this ADR generalizes.
- [ADR-0010](0010-release-please-is-the-sole-writer-of-the-plugin-version.md) —
  the precedent that a documentary rule is not an enforced rule, and that the
  fix is a check.
- [ADR-0011](0011-separate-tension-readiness-from-tension-disposition.md) — the
  change whose costs motivated this one.
- [`evals/README.md`](../../evals/README.md) — the behavioural tier's contract,
  golden cases, and redaction requirement.

## Amendments

### 2026-08-04 — fixtures capture schemas, not redacted responses (#170)

The Consequences section above says Tier 2 fixtures ship "carrying data from a
real organization" with "redaction by default." **Implementing #170 showed that
framing was wrong, and the approach inverted.**

Probing the live API found that a single `list_my_roles` record carries
`fillers[].name` and `fillers[].email` — PII repeated across all 81 roles — plus
`purpose`, `accountabilities[].description` and `domains[].description`, which
together read as a map of the organization's strategy. The API also returns
full-length ids where ADR-0011's issue thread publishes only truncated display
forms, so a recorded fixture would expose something genuinely new rather than
re-publishing what was already out.

Redacting that means substituting essentially every string in the payload, at
which point the only thing genuinely recorded is the **schema** — which is where
the value was, since the schema is what reveals fields nobody knew about.

**So: capture the schema, generate the content.** `scripts/glassfrog-schema-capture.py`
replaces every scalar with its type name and refuses to emit if that erasure did
not fully apply. `scripts/glassfrog-fixture-gen.py` builds a synthetic
organization from a hand-authored scenario spec and validates it against the
captured schema, so a fixture cannot silently drift from the real API shape.

The safety property changes character, and that is the point. Redaction is a
process that fails by missing a field; this is structural — no real string has a
path into a committed file. It matters more than the usual defence-in-depth
argument because a leak is not undone by a later commit: it is in git history.

Two further findings from the same work:

- **`run_eval.py` is the triggering detector, not the behavioural runner.** The
  Decision text above lists it among the Tier 2 components reused from
  `skill-creator`. It returns a boolean for whether a skill fired, which is Tier
  3's question. `aggregate_benchmark.py`, `agents/grader.md` and the eval viewer
  *are* reusable; the runner that produces `grading.json` has to be built.
- **The stub reproduces the API's defects deliberately.** It returns direct
  children only from `list_subrole_tensions` and 422s `meeting_type` on
  `update_tension`. A stub that smoothed either over would let a skill pass an
  eval by doing something that fails in production — worse than no eval, because
  it manufactures confidence.

The original Decision text is left standing, per the ADR-0011 precedent for
Option D: a decision record documents what was decided when, and rewriting it
falsifies the record.
