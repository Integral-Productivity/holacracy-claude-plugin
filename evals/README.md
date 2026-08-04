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
  lint-allow-paths.txt            check 1 allowlist  (citing-file, path, reason)
  forward-references.txt          check 5 allowlist  (command, issue, reason)
  fixtures/glassfrog/*.json       recorded, REDACTED MCP responses
  cases/<surface>/evals.json      prompts + assertions, skill-creator schema
```

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

Fixtures are captured once by a human against live GlassFrog, read-only, and
replayed offline thereafter.

### Redaction is mandatory, not optional

**This is a public repository.** Recorded GlassFrog responses carry real tension
bodies, role names, and people from a working organization. The capture harness
redacts by default: ids and response shape are preserved exactly (they are what
the code under test consumes), free-text bodies are replaced with synthetic text
of comparable length and structure.

Opting out is per-field and explicit. If you find yourself wanting to opt out
broadly, capture a smaller fixture instead.

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

The harness is the `skill-creator` skill's, not a bespoke one:

```bash
# one eval, both configurations
python -m scripts.run_eval --eval evals/cases/tension-triage/evals.json

# aggregate a completed iteration into benchmark.json + benchmark.md
python -m scripts.aggregate_benchmark <workspace>/iteration-N --skill-name holacracy

# open the review UI (qualitative outputs + the quantitative benchmark)
python <skill-creator>/eval-viewer/generate_review.py --benchmark <workspace>/iteration-N/benchmark.json
```

`benchmark.json` reports pass-rate, time, and tokens per configuration with mean
± stddev and the delta. High-variance cases are flaky, not hard — treat a wide
stddev as a defect in the case, not a finding about the skill.

## Status

Tier 1 (static lint) ships. The fixture harness, the five cases above, and the
nightly workflow are tracked as child issues of #120's successor epic — see the
issues linked from ADR-0012. `cases/tension-triage/evals.json` is present as the
worked template for the rest; its assertions are written and its fixture is not
yet captured, so it does not run in CI.
