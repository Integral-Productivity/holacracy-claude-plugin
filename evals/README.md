# evals — testing what the plugin does, not just what it says

This directory holds the behavioural half of the plugin's testing. The static
half lives in [`scripts/skills-lint.sh`](../scripts/skills-lint.sh) and gates
every PR; this half costs API calls and wall-clock, so it runs nightly and on
demand.

The split is the point. A lint can prove a path resolves and a cited step
exists. It cannot prove that `/holacracy:tension-triage` actually asks the
authority question *before* it routes a tension to a venue — and that claim
shipped unverified in [#166](https://github.com/Integral-Productivity/holacracy-claude-plugin/pull/166)
precisely because there was nowhere to assert it.

See [ADR-0012](../docs/adr/0012-test-the-skills-not-just-the-scaffolding.md).

## Layout

```
evals/
  README.md                       this file
  benchmark.json                  the baseline #173's regression alarm compares against
  lint-allow-paths.txt            check 1 allowlist  (citing-file, path, reason)
  forward-references.txt          check 5 allowlist  (command, issue, reason)
  scenarios/*.json                hand-authored synthetic orgs, one per case
  fixtures/schema/*.json          captured API shapes; every scalar is a type name
  fixtures/glassfrog/*.json       generated from scenarios/, validated against schema/
  stub/glassfrog_stub.py          the MCP server that serves a fixture
  cases/<surface>/evals.json      prompts + assertions, grouped by the surface they drive
```

Cases are grouped by **surface**, not one file per case, so several golden cases
that exercise the same command share a file. Three of the four live under
`/holacracy:tension-triage`, because that is where the gates they test are
specified — including successor-before-archive, which reads like a job for
`/holacracy:supersession-sweep` and is not: that command handles supersession
*between two tensions* and explicitly does not file new ones, while a tension
superseded *structurally by a role* is Step 1 territory and triage's to act on.

`lint-allow-paths.txt` and `forward-references.txt` live here rather than under
`scripts/` because they are test data, not implementation — the same reason the
eval cases do.

## Why recorded fixtures, not the live org

Three reasons, in order of how much they'd hurt:

1. **Evals must not write to production governance.** A behavioural eval of a
   capture flow inevitably exercises the write path.
2. **A live org is not deterministic.** The backlog changes between runs, so a
   regression and a Tuesday would look identical.
3. **CI has no GlassFrog credentials**, and giving it any would mean giving a
   nightly job standing access to a real organization's records.

### Capture the schema; generate the content

This section originally said "record live responses, redact the tension bodies."
**Probing the live API showed that far too narrow**, and the approach inverted.

One `list_my_roles` record carries `fillers[].name` and `fillers[].email` — real
PII, repeated across all 81 roles — plus `purpose`,
`accountabilities[].description` and `domains[].description`, which together read
as a map of the organization's strategy. And the API returns full-length ids
where [#120](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/120)
publishes only truncated display forms, so a recorded fixture would expose
something genuinely new.

Redacting all of that means substituting essentially every string in the payload.
At which point the only thing actually recorded is the **schema** — which is
where the value was, because it is what tells you about fields you did not know
existed.

So:

| Step | Tool | What crosses into the repo |
|---|---|---|
| Capture | [`scripts/glassfrog-schema-capture.py`](../scripts/glassfrog-schema-capture.py) | Key names, nesting, optionality. **Every scalar replaced by its type name.** |
| Generate | [`scripts/glassfrog-fixture-gen.py`](../scripts/glassfrog-fixture-gen.py) | A synthetic org built from a hand-authored `scenarios/*.json`, validated against the captured schema |
| Replay | [`evals/stub/glassfrog_stub.py`](stub/glassfrog_stub.py) | Nothing — it serves the generated fixture |

**This is a public repository**, and the property that protects it is structural:
no real string has a path into a committed file. A redaction pass fails by
missing a field, and a missed field is published — and a leak is not undone by a
later commit, because it is in git history. There is no equivalent failure mode
here, and `scripts/evals-harness.test.sh` § 2 asserts it rather than assuming it.

The capture tool is a **filter**, not a client: it reads a response on stdin. The
MCP connector is available to an agent session, not to an arbitrary script, so a
human obtains one response and pipes it through. The real response exists in a
pipe; only type names reach the repo.

### The stub reproduces the API's bugs on purpose

`list_subrole_tensions` is documented recursive — its own tool description still
says so — and returns **direct children only**, with `has_next_page: false`
suppressing suspicion ([glassfrog-mcp-server#122](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/122)).
`update_tension` **422s on `meeting_type`** ([#123 comment](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/123#issuecomment-5149496749)).

The stub does both. A stub that quietly recursed, or that accepted `meeting_type`,
would let a skill pass an eval by doing something that fails in production —
worse than having no eval, because it manufactures confidence.

### Writes are recorded, not refused

Two golden cases assert write **ordering** — successor before archive, and no
write before an explicit confirmation. Ordering is only checkable against a log,
so the stub appends `{seq, tool, args}` to `$GLASSFROG_STUB_WRITE_LOG` and
returns a plausible success. Reads never appear in that log, which is what makes
"no write without confirmation" assertable at all.

## The golden cases

The 2026-08-01 backlog run — 47 unprocessed tensions down to 21 — produced
labelled ground truth that most projects have to invent. Each case below has a
known-correct disposition that a human reached and recorded on
[#120](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/120).

| Case | Fixture | Asserts |
|---|---|---|
| Authority gate fires first | `ten_03c044b3`, ◎Product Architecture holds the Productboard domain | Output is *convert*, **not** *route to governance*. The tension waited 21 months for a meeting that was never required. |
| Blended tension partitioned | `ten_00fc5815` | The body is **partitioned**, not refused (loses the structural half) and not left fused (unresolvable — it sat that way 15 months). |
| Successor before archive | `ten_343f2946`, `ten_564abcab`, superseded by ◎Information Security Officer | The successor is written **before** the archive. Archiving alone drops a live, material exposure. |
| Person tension refused | synthetic | No `create_tension` is drafted; the IDR route is surfaced. |
| Circle sweep completeness | 47 tensions across 18 circles; a root call returns 21 | All 47 surface. This is [glassfrog-mcp-server#122](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/122) caught from the consumer side. |

A case is only worth keeping if it can fail. Assertions that pass with the skill
disabled are non-discriminating and should be cut — the aggregation step reports
the with-skill/without-skill delta precisely so that shows up.

## Running

### Building a fixture

```bash
# schema capture — a human pipes ONE live response through; nothing here dials out
python3 scripts/glassfrog-schema-capture.py --tool list_my_roles < response.json \
  > evals/fixtures/schema/list_my_roles.json

# generate the synthetic org a case needs
python3 scripts/glassfrog-fixture-gen.py evals/scenarios/authority-already-held.json

# the whole fixture harness, mutation-checked
bash scripts/evals-harness.test.sh
```

### Running the evals

```bash
# offline: validate every case, prove each fixture actually starts the stub, and
# prove each config's SESSION SHAPE — that a Skill tool exists at all, and that
# --plugin-dir registers the plugin in with_skill and nothing in without_skill.
# The session-shape probe starts a real `claude` and kills it at the init event,
# which the CLI emits before it authenticates: no API key, no model turn, no cost.
# Add --no-session-probe where `claude` is not on PATH.
python3 scripts/run-behavioural-eval.py --out /tmp/probe --validate-only \
  --case evals/cases/tension-triage/evals.json \
  --case evals/cases/capture-tension/evals.json

# the runner's own suite — mutation-checked, no API key, gates every PR
bash scripts/run-behavioural-eval.test.sh

# a graded run. Needs ANTHROPIC_API_KEY: each session runs under a redirected
# CLAUDE_CONFIG_DIR, so a login stored in the operator's own config dir is not
# visible to it. A signed-in operator without the variable gets "Not logged in",
# and the runner reports that as an execution error rather than scoring the run.
ANTHROPIC_API_KEY=... python3 scripts/run-behavioural-eval.py \
  --out benchmarks/local --runs 3 \
  --case evals/cases/tension-triage/evals.json \
  --case evals/cases/capture-tension/evals.json
```

Each run is hermetic by construction: `CLAUDE_CONFIG_DIR` pointed at an empty
per-run directory (no installed plugin, setting, hook or memory), a cwd in a temp
sandbox outside this checkout (nothing for `CLAUDE.md` discovery to walk up to),
`--plugin-dir` as the only route by which the plugin enters the session, and
`--strict-mcp-config` so the stub is the only MCP server. That last one is not
tidiness — without it the plugin's own `.mcp.json` loads too, and it points at
the **production** GlassFrog connector.

This used to be one flag, `--bare`. It also removed the `Skill` tool, which made
every with/without delta the graded tier produced a comparison of the base model
against itself ([#226](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/226)).
Two consequences of the replacement are worth carrying: the eval session's
built-in tools are restricted to `Skill,Task,Read` — no shell, because a control
leg with one reaches this checkout by `find /` — and the plugin's SessionStart
hook is now live in `with_skill`, so a delta measures the plugin as installed
rather than a skill's prose in isolation.

### What is reusable from `skill-creator`, and what is not

An earlier draft of this file said Tier 2 "reuses the `skill-creator` harness
(`run_eval`, …)". **That was wrong and is corrected here.**

| Component | Tier 2 use |
|---|---|
| `scripts/run_eval.py` | **No.** It is the *triggering* detector — it returns a boolean for whether a skill fired. That is Tier 3's job (#172). |
| `scripts/aggregate_benchmark.py` | **Yes**, as-is. Consumes a tree of `grading.json` files, emits `benchmark.json`/`.md` with mean ± stddev and the with/without delta. |
| `agents/grader.md` | **Yes** — the grading pass. |
| `eval-viewer/generate_review.py` | **Yes** — qualitative review UI. |
| The runner that *produces* `grading.json` | **Has to be built.** #171. |

`run_eval.py` is still worth reading: it shells out to real `claude -p` with
`cwd=<project root>` and `CLAUDECODE` stripped from the environment, which is the
pattern #171's runner should borrow. It is also why the stub works at all — a
project-scoped `.mcp.json` in the eval's temp directory points at the stub, so
the eval exercises the real MCP path rather than a simulation of it.

`benchmark.json` reports pass-rate, time, and tokens per configuration with mean
± stddev and the delta. High-variance cases are flaky, not hard — treat a wide
stddev as a defect in the case, not a finding about the skill.

## Status

| Piece | State |
|---|---|
| Tier 1 static lint | **ships** (#168) |
| Schema capture, fixture generator, replay stub, harness tests | **ships** (#170) |
| Write-response schemas | derived from the MCP tools' documented contracts, **not captured** — capturing them means creating and deleting throwaway records in a live org, and that was not done for a testing convenience |
| The four golden cases, the runner, its suite, the nightly workflow | **ships** (#171) |
| A measured `benchmark.json` | **blocked on `ANTHROPIC_API_KEY`**, which is a repository secret and a human action. The committed baseline is explicitly unmeasured and says so. |
| Circle-sweep case (47 tensions, 18 circles) | deferred from #171 by design — the stub already reproduces the non-recursive traversal it needs, so it can follow without new harness work |
| Triggering accuracy | #172 |
| Eval-regression alarm | #173 |

### Reading a result before trusting it

Prompts are natural language and **identical across `with_skill` and
`without_skill`**, so the delta measures what the plugin changes rather than how
the surface was invoked. The cost of that choice: a case can fail because the
surface never engaged at all, which is a *triggering* finding (#172) wearing a
behavioural finding's clothes. Read the transcript before reading the score.

Three conditions make a run unscoreable rather than failing, and the runner
records them as an execution error: the executor did not start, the session
reported an error, or the model made no tool calls. Each exists because an empty
write log satisfies every negative assertion — a session that never ran issues no
forbidden write. Two of the three were live defects in the runner, and the second
was found by its first real run against the CLI.
