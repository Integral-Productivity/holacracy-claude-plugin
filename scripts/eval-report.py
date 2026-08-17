#!/usr/bin/env python3
"""Render the graded eval report: a benchmark against the committed baseline.

Extracted from a heredoc inside .github/workflows/skills-eval.yml so it can be
tested (#204). It was not extracted for tidiness.

WHY THIS BLOCK, OF ALL THE BLOCKS
---------------------------------
It crashed once and took a complete, paid-for graded run with it (#199). The
call was `.get("mean")` on `run_summary["delta"]["pass_rate"]`, which
aggregate_benchmark.py stores as a PREFORMATTED STRING sitting as a sibling of
the config keys. The step died; being gated on a plain `if:`, the artifact
upload below it was skipped, and ~25 minutes of paid execution was discarded.
#200's `always()` upload limits that blast radius; it does not prevent the
crash, and nothing in the repo would have caught it a second time.

The rest of the profile is why it is worth a suite of its own:

  - It parses a schema owned by an EXTERNAL repository, cloned at a pinned
    commit (#195). Upstream can change that shape whenever the pin is bumped.
  - It runs only in the graded tier, which executes nightly at best and costs
    real money to exercise. Every other consumer of that schema is cheap to
    re-run; this one is not.

So it is checked here, deterministically and offline, on the per-PR gate that
ADR-0012 argues for -- rather than discovered by the next paid run.

THE CONTRACT
------------
This report is informational. #173 owns turning a delta into an alarm. What
this file owes its caller is that it never crashes on a well-formed benchmark:
a report that dies is strictly worse than a report that says "n/a", because the
run it was describing is the expensive part.

Four shapes it must survive, each with a case in eval-report.test.sh:

  1. the aggregator's real output, including the `delta`-as-string sibling
  2. the committed UNMEASURED baseline, whose every statistic is null
  3. a config present in the run but missing from the baseline
  4. an empty (or absent) run_summary

The cost section added later is held to a stronger version of the same rule.
#199 was none of those four shapes: it was a well-formed file carrying an
UNANTICIPATED TYPE. So the cost section renders behind its own failure
boundary and degrades alone -- the shape that breaks a renderer is by
definition the one nobody wrote a guard for, and a cost table is not worth
deleting the paid run's pass-rate table over.

Usage:
    python3 scripts/eval-report.py --current benchmark.json \
        --baseline evals/benchmark.json \
        --cost cost-summary.json
"""

import argparse
import json
import pathlib
import sys

# aggregate_benchmark.py stores this key INSIDE run_summary, as a sibling of
# the config keys, and its pass_rate is a preformatted string rather than a
# stats dict. Upstream excludes it by name everywhere it iterates
# (`k != "delta"`, its lines 287/389) and so must we -- otherwise .get("mean")
# lands on a str and the whole step dies. That is exactly what #199 was.
DELTA_KEY = "delta"

# Per evals/README.md, a case whose stddev is this wide is a defect in the
# case, not a finding about the skill.
WIDE_STDDEV = 0.2

# Marks a cost summary that could not be parsed, so the failure travels as DATA
# into the cost section's own boundary instead of raising at load time. See
# load_cost below for why that distinction is load-bearing.
UNREADABLE_KEY = "_unreadable"


def configs_only(summary):
    """The per-config entries, with the `delta` sibling removed.

    `summary or {}` because run_summary may be absent or null on a run that
    produced nothing; iterating None is a crash, and a run that produced
    nothing is exactly when the report still needs to render.
    """
    return {k: v for k, v in (summary or {}).items() if k != DELTA_KEY}


def stats_of(entry):
    """The pass_rate stats dict for one config, or {} when there is none.

    The committed baseline is unmeasured on purpose -- every statistic in it is
    null -- so this must tolerate a null entry, a null pass_rate, and a stats
    dict whose values are all null.
    """
    return (entry or {}).get("pass_rate") or {}


def render(cur, base, cost=None, base_cost=None):
    """Return the report as a list of lines."""
    cur_summary = configs_only(cur.get("run_summary"))
    base_summary = configs_only(base.get("run_summary"))

    lines = ["## Behavioural eval results\n",
             "| config | pass rate | stddev | baseline | delta |",
             "|---|---|---|---|---|"]

    for config, entry in sorted(cur_summary.items()):
        rate = stats_of(entry)
        # .get, not [] -- a config the baseline has never seen is normal the
        # first time a case is added, and must read as "n/a" rather than raise.
        bm = stats_of(base_summary.get(config)).get("mean")
        mean = rate.get("mean") or 0
        stddev = rate.get("stddev") or 0
        # isinstance, not a truthiness test: the unmeasured baseline's mean is
        # None, and `mean - None` is a TypeError that kills the whole report.
        delta = f"{mean - bm:+.3f}" if isinstance(bm, (int, float)) else "n/a"
        lines.append(f"| {config} | {mean:.3f} | {stddev:.3f} | "
                     f"{bm if bm is not None else 'n/a'} | {delta} |")

    # The aggregator's own with/without delta, which the loop above skips.
    headline = ((cur.get("run_summary") or {}).get(DELTA_KEY) or {}).get("pass_rate")
    if headline:
        lines.append(f"\nwith_skill − without_skill pass rate: **{headline}**")

    wide = [(c, stats_of(e).get("stddev") or 0) for c, e in cur_summary.items()
            if (stats_of(e).get("stddev") or 0) > WIDE_STDDEV]
    if wide:
        lines.append("\n> **Wide variance.** Per `evals/README.md`, a high-stddev "
                     "case is a defect in the case, not a finding about the skill: "
                     + ", ".join(f"`{c}` ({s:.2f})" for c, s in sorted(wide)))

    # Appended last and behind its own boundary, so everything above is already
    # built by the time the newest and least-proven code runs.
    if cost is not None:
        lines.extend(render_cost(cost, base_cost))

    return lines


def fmt_tokens(value):
    """A token count, or an explicit absence. Never a zero standing in for one."""
    return f"{value:,}" if isinstance(value, (int, float)) else "n/a"


def fmt_rate(value):
    return f"{value:.0%}" if isinstance(value, (int, float)) else "n/a"


def fmt_usd(value):
    return f"${value:.4f}" if isinstance(value, (int, float)) else "n/a"


def cost_rows(cost, base_cost):
    """The cost table's lines, per config, both passes, never blended."""
    unreadable = (cost or {}).get(UNREADABLE_KEY)
    if unreadable:
        return ["\n### Cost\n", f"_Cost data could not be read: {unreadable}_"]
    configs = (cost or {}).get("configs") or {}
    base_configs = (base_cost or {}).get("configs") or {}
    if not configs:
        return ["\n### Cost\n", "_No cost data in this run._"]

    lines = ["\n### Cost\n",
             "| config | pass | tokens | cache hit | USD | Δ tokens |",
             "|---|---|---|---|---|---|"]
    unknown = 0
    for config, entry in sorted(configs.items()):
        passes = (entry or {}).get("passes") or {}
        base_passes = ((base_configs.get(config) or {}).get("passes")) or {}
        for name in ("executor", "grader"):
            pass_entry = passes.get(name) or {}
            tokens = (pass_entry.get("tokens") or {}).get("total")
            base_tokens = ((base_passes.get(name) or {}).get("tokens") or {}).get("total")
            # .get on the baseline, never [] -- a config or pass the comparison
            # has never seen is normal the first time a case is added, and reads
            # as an absence rather than a delta against nothing.
            if isinstance(tokens, (int, float)) and isinstance(base_tokens, (int, float)):
                delta = f"{tokens - base_tokens:+,}"
            else:
                delta = "n/a"
            unknown += pass_entry.get("unknown_cost") or 0
            lines.append(f"| {config} | {name} | {fmt_tokens(tokens)} | "
                         f"{fmt_rate(pass_entry.get('cache_hit_rate'))} | "
                         f"{fmt_usd(pass_entry.get('usd'))} | {delta} |")

    if unknown:
        # Spend that was incurred and cannot be recovered. Saying so is the
        # whole reason `failed` is distinguished from `not_invoked` upstream:
        # reporting it as zero would understate the total silently.
        noun = "pass was" if unknown == 1 else "passes were"
        lines.append(f"\n> **{unknown} {noun} billed but reported no usage.** "
                     "That cost is real and is missing from the totals above.")

    versions = (cost or {}).get("cli_versions") or []
    if len(versions) > 1:
        lines.append("\n> **More than one CLI version produced these figures** ("
                     + ", ".join(f"`{v}`" for v in versions)
                     + "), so they are not strictly comparable.")
    return lines


def render_cost(cost, base_cost):
    """The cost section, isolated so its failure cannot take the report with it.

    #199 was not a missing file or malformed JSON. It was a well-formed file
    carrying an UNANTICIPATED TYPE -- a preformatted string where a stats dict
    was assumed -- meeting `.get("mean")`. Handling the two named absence cases
    is therefore not enough on its own; the shape that breaks a renderer is by
    definition the one nobody wrote a guard for.

    The consequence of getting it wrong is asymmetric. This step is
    `continue-on-error: true`, so an exception raised here would turn the step
    yellow and silently delete the paid run's headline pass-rate table from the
    step summary. A cost section is not worth that, so it degrades alone.
    """
    try:
        return cost_rows(cost, base_cost)
    except Exception as exc:  # noqa: BLE001 -- see the docstring; this is the boundary
        return ["\n### Cost\n",
                f"_Cost data could not be rendered: {type(exc).__name__}: {exc}_"]


def load(path):
    """Parse a benchmark file, or {} when it is not there.

    A missing baseline is the state this repo is actually in until a graded run
    seeds one, so it is a normal path rather than an error.
    """
    p = pathlib.Path(path)
    return json.loads(p.read_text()) if p.exists() else {}


def load_cost(path):
    """Parse a cost summary, returning a marker rather than raising.

    Deliberately NOT `load()`. Raising on malformed JSON is right for the
    benchmark itself -- a report about a run whose results cannot be read is
    worthless -- but wrong here, and the difference is easy to miss: the load
    happens in main(), which is OUTSIDE render_cost's boundary, so a malformed
    cost file would take the pass-rate table down with it. That is #199's shape
    exactly, one file over, and it defeats the isolation this section was given
    in the first place.

    So an unreadable cost summary travels as data and is rendered as a stated
    absence by the cost section alone.
    """
    p = pathlib.Path(path)
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return {UNREADABLE_KEY: f"{type(exc).__name__}: {exc}"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current", required=True,
                        help="benchmark.json produced by this run")
    parser.add_argument("--baseline", default="evals/benchmark.json",
                        help="the committed baseline to compare against")
    parser.add_argument("--cost", default=None,
                        help="cost-summary.json from this run; omitted means no cost section")
    # Supplied by path, never discovered. There is no committed cost baseline to
    # find, and a discovery heuristic inside a script whose contract is "never
    # crash" adds a failure mode to the one place that must not have one.
    parser.add_argument("--cost-baseline", default=None,
                        help="a cost summary to compare against; omitted means no delta column")
    args = parser.parse_args(argv)

    cost = load_cost(args.cost) if args.cost else None
    base_cost = load_cost(args.cost_baseline) if args.cost_baseline else None
    print("\n".join(render(load(args.current), load(args.baseline), cost, base_cost)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
