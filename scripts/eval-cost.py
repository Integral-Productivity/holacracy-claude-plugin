#!/usr/bin/env python3
"""Derive eval cost figures from the per-run cost records, and correct the benchmark.

    scripts/eval-cost.py aggregate --run-tree "$RUNNER_TEMP/benchmark" \
                                   --out "$RUNNER_TEMP/benchmark/cost-summary.json"
    scripts/eval-cost.py correct --benchmark "$RUNNER_TEMP/benchmark/benchmark.json" \
                                 --cost "$RUNNER_TEMP/benchmark/cost-summary.json"

WHY THE DERIVATION LIVES HERE AND NOT IN THE RUNNER
---------------------------------------------------
`run-behavioural-eval.py` stores what the result event reported, verbatim, and
interprets none of it. That split is what makes an unrecognised usage field
harmless: it cannot reach an arithmetic path, because the only arithmetic is
here. It also means a change to the rules below is re-runnable over artifacts
CI already retained, instead of costing another graded run.

WHICH FIELDS ARE SUMMED, AND WHY IT IS A NAMED SET
--------------------------------------------------
"Every field the result event reports" cannot be implemented literally, and the
reasons are all live shapes rather than hypotheticals:

  service_tier      a STRING sitting in an object otherwise full of counts;
                    int() raises on it, in a path that runs after a 40-minute
                    paid run
  cache_creation    the 1-hour cache tier's nested breakdown, reported
                    ALONGSIDE the flat cache_creation_input_tokens it
                    decomposes -- summing both double-counts cache creation and
                    corrupts the hit-rate denominator with it
  server_tool_use   {"web_search_requests": N}, not a token count at all

So storage keeps everything and derivation sums TOKEN_FIELDS. A field outside
that set is retained in the record and contributes to nothing here. Cache
creation is counted from the flat field only, which is what makes the nested
breakdown's presence a no-op rather than a doubling.

WHY USD IS READ AND NEVER COMPUTED
----------------------------------
The result event carries `total_cost_usd`, and each `modelUsage` entry carries
`costUSD`. A price table kept in this repo would drift silently with every
pricing change and be wrong in a way nothing would detect. Cost is a field
read.

TWO SOURCES, TWO JOBS
---------------------
`usage` is authoritative for token totals: it is the aggregate the CLI reports,
it is what the pre-existing figure was computed from, and the correction widens
that same figure to cover the grader -- so the reconciliation compares like
with like. `modelUsage` is authoritative for attribution and USD, because it is
per model and one pass can be served by several (the eval tool set offers
`Task`, whose subagent turns can be served by a different model, and
cache-tier-suffixed names key separately). They are computed differently
upstream and can disagree; a disagreement warns rather than letting one
silently win.

A PASS THAT FAILED IS NOT A PASS THAT COST NOTHING
--------------------------------------------------
`not_invoked` is a structural zero. `failed` means the call was launched and
billed -- a full-timeout generation thrown away -- with its usage unrecoverable.
Averaging the second into the first as zero under-reports spend on exactly the
runs that wasted it, so unknown-cost passes are counted and reported, never
folded into a total as zeros.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys

# The flat token fields, and the only things summed anywhere in this file.
# `cache_creation_input_tokens` is the flat total; the nested `cache_creation`
# object that accompanies it on the 1-hour tier decomposes this same number and
# is deliberately absent from this list.
TOKEN_FIELDS = (
    "input_tokens",
    "output_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
)

# `modelUsage` is camelCase where `usage` is snake_case, because they come from
# different layers upstream. Neither is normalized at rest; the mapping lives
# here, at the one place both are read.
MODEL_FIELDS = {
    "input_tokens": "inputTokens",
    "output_tokens": "outputTokens",
    "cache_creation_input_tokens": "cacheCreationInputTokens",
    "cache_read_input_tokens": "cacheReadInputTokens",
}

PASSES = ("executor", "grader")


def warn(message: str) -> None:
    """A GitHub Actions annotation that is still readable outside CI."""
    print(f"::warning::{message}", file=sys.stderr)


def count(value) -> int:
    """A token count, or zero for anything that is not one.

    Guards the three ways a usage object carries a non-count: a string
    (`service_tier`), a nested object (`cache_creation`, `server_tool_use`), and
    a bool -- which is an int in Python and would otherwise add 1.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    return int(value)


def sum_tokens(usage: dict | None) -> dict:
    """The named fields, each defaulting to zero, plus their total."""
    usage = usage or {}
    out = {field: count(usage.get(field)) for field in TOKEN_FIELDS}
    out["total"] = sum(out[field] for field in TOKEN_FIELDS)
    return out


def hit_rate(created: int, read: int) -> float | None:
    """Cache reads over cache reads plus cache creations.

    None rather than 0.0 when nothing was cached either way: a run with no cache
    activity has no hit rate, and reporting 0.0 would read as "caching is on and
    missing every time", which is a different and alarming claim.
    """
    denominator = created + read
    if denominator <= 0:
        return None
    return round(read / denominator, 4)


def model_totals(model_usage: dict | None) -> dict:
    """Per-model token counts and USD, keyed by the model that served them.

    Every entry is kept. Taking the first key -- which is how the executor model
    is resolved elsewhere -- would silently drop a subagent's model and its
    spend.
    """
    out = {}
    for name, entry in (model_usage or {}).items():
        if not isinstance(entry, dict):
            continue
        totals = {field: count(entry.get(camel)) for field, camel in MODEL_FIELDS.items()}
        totals["total"] = sum(totals.values())
        cost = entry.get("costUSD")
        totals["usd"] = float(cost) if isinstance(cost, (int, float)) and not isinstance(cost, bool) else None
        out[str(name)] = totals
    return out


def derive_pass(record: dict | None, label: str) -> dict:
    """One pass's derived figures, from its stored raw record."""
    record = record or {}
    status = record.get("status") or "unknown"
    tokens = sum_tokens(record.get("usage"))
    models = model_totals(record.get("model_usage"))
    usd = record.get("total_cost_usd")
    usd = float(usd) if isinstance(usd, (int, float)) and not isinstance(usd, bool) else None

    # A pass that was launched and failed has real, unrecoverable spend. Flagged
    # so a total can say how much of itself is missing instead of implying zero.
    cost_unknown = status == "failed"

    # AE10: the two sources should agree. Compared only when the per-model map
    # carries the full field set -- a partial map is a reporting difference, not
    # a discrepancy, and warning on it would train readers to ignore the warning.
    model_total = sum(m["total"] for m in models.values())
    entries = [e for e in (record.get("model_usage") or {}).values() if isinstance(e, dict)]
    full = bool(entries) and all(
        all(camel in entry for camel in MODEL_FIELDS.values()) for entry in entries)
    if status == "ok" and full and model_total != tokens["total"]:
        warn(f"{label}: usage reports {tokens['total']} tokens but the per-model map "
             f"sums to {model_total}; recording the usage figure")

    return {
        "status": status,
        "reason": record.get("reason"),
        "tokens": tokens,
        "cache_hit_rate": hit_rate(tokens["cache_creation_input_tokens"],
                                   tokens["cache_read_input_tokens"]),
        "usd": usd,
        "models": models,
        "cost_unknown": cost_unknown,
    }


def read_json(path: pathlib.Path):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        warn(f"{path}: unreadable ({exc}); skipping")
        return None


def collect(tree: pathlib.Path) -> dict:
    """Walk `eval-*/<config>/run-*/cost.json` into a per-run list.

    `eval_id` is read from eval_metadata.json rather than parsed out of the
    directory name, so it is byte-identical to the value the aggregator copied
    into its own rows. The correction joins on it, and a join key derived two
    different ways is a join waiting to break.
    """
    runs = []
    cli_versions = set()
    for eval_dir in sorted(tree.glob("eval-*")):
        if not eval_dir.is_dir():
            continue
        meta = read_json(eval_dir / "eval_metadata.json") or {}
        eval_id = meta.get("eval_id", eval_dir.name)
        for run_dir in sorted(eval_dir.glob("*/run-*")):
            record = read_json(run_dir / "cost.json")
            if record is None:
                continue
            config = run_dir.parent.name
            label = f"{eval_id}/{config}/{run_dir.name}"
            if record.get("cli_version"):
                cli_versions.add(str(record["cli_version"]))
            passes = {p: derive_pass((record.get("passes") or {}).get(p), f"{label} {p}")
                      for p in PASSES}
            runs.append({
                "eval_id": eval_id,
                "config": config,
                "run_number": int(run_dir.name.split("-")[-1]) if run_dir.name.split("-")[-1].isdigit() else None,
                # The figure the correction writes: both passes, over the named
                # fields, which is exactly what R10 defines.
                "tokens_total": sum(passes[p]["tokens"]["total"] for p in PASSES),
                "passes": passes,
            })
    return {"runs": runs, "cli_versions": sorted(cli_versions)}


def summarize(runs: list) -> dict:
    """Per-config totals, kept split by pass and never blended."""
    configs: dict = {}
    for run in runs:
        bucket = configs.setdefault(run["config"], {
            "runs": 0,
            "tokens_total": 0,
            "usd": 0.0,
            "usd_known": False,
            "passes_with_unknown_cost": 0,
            "passes": {p: {"tokens": {f: 0 for f in (*TOKEN_FIELDS, "total")},
                           "usd": 0.0, "usd_known": False,
                           "unknown_cost": 0, "not_invoked": 0}
                       for p in PASSES},
            "models": {},
        })
        bucket["runs"] += 1
        bucket["tokens_total"] += run["tokens_total"]
        for name in PASSES:
            entry = run["passes"][name]
            target = bucket["passes"][name]
            for field in (*TOKEN_FIELDS, "total"):
                target["tokens"][field] += entry["tokens"][field]
            if entry["usd"] is not None:
                target["usd"] += entry["usd"]
                target["usd_known"] = True
                bucket["usd"] += entry["usd"]
                bucket["usd_known"] = True
            if entry["cost_unknown"]:
                target["unknown_cost"] += 1
                bucket["passes_with_unknown_cost"] += 1
            if entry["status"] == "not_invoked":
                target["not_invoked"] += 1
            for model, totals in entry["models"].items():
                agg = bucket["models"].setdefault(
                    model, {"tokens": 0, "usd": 0.0, "usd_known": False, "passes": 0})
                agg["tokens"] += totals["total"]
                agg["passes"] += 1
                if totals["usd"] is not None:
                    agg["usd"] += totals["usd"]
                    agg["usd_known"] = True

    for bucket in configs.values():
        for name in PASSES:
            tokens = bucket["passes"][name]["tokens"]
            bucket["passes"][name]["cache_hit_rate"] = hit_rate(
                tokens["cache_creation_input_tokens"], tokens["cache_read_input_tokens"])
            bucket["passes"][name]["usd"] = (round(bucket["passes"][name]["usd"], 6)
                                             if bucket["passes"][name]["usd_known"] else None)
        created = sum(bucket["passes"][p]["tokens"]["cache_creation_input_tokens"] for p in PASSES)
        read = sum(bucket["passes"][p]["tokens"]["cache_read_input_tokens"] for p in PASSES)
        bucket["cache_hit_rate"] = hit_rate(created, read)
        bucket["usd"] = round(bucket["usd"], 6) if bucket["usd_known"] else None
        for agg in bucket["models"].values():
            agg["usd"] = round(agg["usd"], 6) if agg["usd_known"] else None
    return configs


def cmd_aggregate(args) -> int:
    tree = pathlib.Path(args.run_tree)
    if not tree.is_dir():
        print(f"run tree not found: {tree}", file=sys.stderr)
        return 2
    collected = collect(tree)
    summary = {
        "schema": 1,
        "cli_versions": collected["cli_versions"],
        "configs": summarize(collected["runs"]),
        "runs": collected["runs"],
    }
    if not collected["runs"]:
        warn(f"{tree}: no cost.json records were found; the cost summary is empty")
    if len(collected["cli_versions"]) > 1:
        warn("this run spanned more than one CLI version: "
             + ", ".join(collected["cli_versions"]))
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(summary, indent=2))
    print(f"cost summary written to {out} ({len(collected['runs'])} runs)")
    return 0


def stats(values: list) -> dict:
    """The aggregator's own {mean, stddev, min, max} shape, recomputed.

    Matched to `calculate_stats` upstream rather than improved on: this
    overwrites a block the aggregator wrote, and a differently-shaped
    replacement would break every reader of it, including eval-report.py.
    """
    if not values:
        return {"mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0}
    n = len(values)
    mean = sum(values) / n
    # SAMPLE variance (n - 1), and 0.0 for a single value -- upstream's choice,
    # mirrored rather than corrected. Using the population form here would make
    # the corrected stddev differ from every other stddev in the same file for
    # no reason a reader could see.
    stddev = math.sqrt(sum((x - mean) ** 2 for x in values) / (n - 1)) if n > 1 else 0.0
    return {
        "mean": round(mean, 4),
        "stddev": round(stddev, 4),
        "min": round(min(values), 4),
        "max": round(max(values), 4),
    }


def cmd_correct(args) -> int:
    """Replace the aggregator's `tokens` figure with a real token count.

    WHY THIS IS NEEDED AT ALL
    -------------------------
    The aggregator reads run duration from grading.json and only falls back to
    timing.json -- the one place a token count lived -- when that duration is
    zero. The runner always writes a nonzero duration, so the fallback never
    fires, `tokens` is never assigned from a token count, and a later guard
    fills it from `output_chars`. The column labelled tokens holds a transcript
    character count.

    That guard is `if not result.get("tokens")`, a TRUTHINESS test, so a
    genuine zero falls through to output_chars too. Making the upstream
    fallback fire is therefore not an available shortcut -- there is no value
    the runner could write that survives it -- which is why the correction is
    structurally required rather than a preference.

    The defect is local plumbing, not an upstream mistake: the aggregator
    documents output_chars as a deliberate proxy for callers with no real usage
    data. This repo has it and simply never delivered it to the branch that
    would consume it.

    WHY IT IS UNCONDITIONAL
    -----------------------
    "Replace only when the figure is not already a token count" names a
    condition no code can test: a token count and a character count are both
    ints, with nothing distinguishing them. And an upstream figure that was
    correct but executor-only would be left alone while still failing to
    reconcile with an executor-plus-grader breakdown. Recomputing every time is
    idempotent, reconciles by construction, and turns "upstream already
    correct" into an assertion that the warning below stays silent.
    """
    bench_path = pathlib.Path(args.benchmark)
    cost_path = pathlib.Path(args.cost)
    benchmark = read_json(bench_path)
    cost = read_json(cost_path)
    if benchmark is None or cost is None:
        print("benchmark or cost summary could not be read", file=sys.stderr)
        return 2

    # Keyed exactly as the aggregator keys its rows. The suite qualifier in
    # eval_id is what makes this unambiguous; without it two case files' eval 0
    # produce the same key and the figures land on the wrong rows.
    by_key = {}
    by_config: dict = {}
    for run in cost.get("runs", []):
        key = (run.get("eval_id"), run.get("config"), run.get("run_number"))
        by_key[key] = run["tokens_total"]
        by_config.setdefault(run.get("config"), []).append(run["tokens_total"])

    changed, missed, disagreed = 0, 0, 0

    # Site 1 of 3: the per-run rows.
    for row in benchmark.get("runs", []):
        key = (row.get("eval_id"), row.get("configuration"), row.get("run_number"))
        if key not in by_key:
            missed += 1
            warn(f"no cost record for run {key}; leaving its tokens figure as reported")
            continue
        result = row.setdefault("result", {})
        if result.get("tokens") != by_key[key]:
            if result.get("tokens"):
                disagreed += 1
            result["tokens"] = by_key[key]
            changed += 1

    # Site 2 of 3: the per-config statistics block.
    summary = benchmark.get("run_summary") or {}
    for config, totals in by_config.items():
        entry = summary.get(config)
        if not isinstance(entry, dict):
            warn(f"run_summary has no entry for config {config!r}; its tokens were not corrected")
            continue
        recomputed = stats(sorted(totals))
        if entry.get("tokens") != recomputed:
            entry["tokens"] = recomputed
            changed += 1

    # Site 3 of 3: the delta, which is a PREFORMATTED STRING and a sibling of
    # the config keys -- the shape that crashed a paid run in #199. Rewritten in
    # the aggregator's own f"{x:+.0f}" format so benchmark.md, which renders it
    # verbatim, cannot disagree on format rather than value.
    delta = summary.get("delta")
    if isinstance(delta, dict) and len(by_config) >= 2:
        primary = summary.get("with_skill") or {}
        baseline = summary.get("without_skill") or {}
        p_mean = (primary.get("tokens") or {}).get("mean", 0)
        b_mean = (baseline.get("tokens") or {}).get("mean", 0)
        delta["tokens"] = f"{p_mean - b_mean:+.0f}"
        changed += 1

    if disagreed:
        warn(f"{disagreed} run(s) carried a tokens figure that disagreed with the "
             f"recomputed token count; the recomputed value was written")
    if missed:
        warn(f"{missed} benchmark row(s) had no matching cost record")

    bench_path.write_text(json.dumps(benchmark, indent=2))
    print(f"corrected {changed} tokens figure(s) in {bench_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="mode", required=True)

    agg = sub.add_parser("aggregate", help="walk the run tree into a cost summary")
    agg.add_argument("--run-tree", required=True,
                     help="the benchmark directory the runner produced")
    agg.add_argument("--out", required=True, help="where to write cost-summary.json")
    agg.set_defaults(func=cmd_aggregate)

    fix = sub.add_parser("correct", help="rewrite the aggregator's tokens figure")
    fix.add_argument("--benchmark", required=True,
                     help="benchmark.json, rewritten in place")
    fix.add_argument("--cost", required=True,
                     help="the cost-summary.json produced by `aggregate`")
    fix.set_defaults(func=cmd_correct)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
