#!/usr/bin/env bash
# Regression tests for scripts/eval-report.py.
#
# Run: bash scripts/eval-report.test.sh
# No framework — plain asserts. Exits non-zero on first failure.
#
# WHAT THIS GUARDS
# ----------------
# The report block crashed once and took a complete, paid-for graded run with
# it (#199): it called .get("mean") on run_summary["delta"]["pass_rate"], which
# aggregate_benchmark.py stores as a preformatted STRING. The step died, the
# artifact upload gated below it was skipped, and ~25 minutes of paid execution
# was discarded. The fix was verified by hand and nothing in the repo would
# have caught it again.
#
# It parses a schema owned by an external repository, pinned at a commit we
# bump deliberately (#195), and it runs only in the graded tier — nightly at
# best, real money to exercise. That combination is why the check belongs on
# the per-PR gate ADR-0012 argues for: deterministic, offline, sub-second.
#
# THE MUTATION PROPERTY
# ---------------------
# Same contract as skills-lint.test.sh and run-behavioural-eval.test.sh. For
# each defense there is a mutant with ONLY that defense removed, and the suite
# asserts BOTH:
#
#   the case for that defense   -> FAILS on the mutant  (the defense does its job)
#   every OTHER case            -> PASSES on the mutant (nothing else covers it)
#
# The second half is load-bearing. Three of these four defenses are one-token
# differences — `.get(k)` vs `[k]`, `or {}` vs nothing — and a defense some
# other defense incidentally covers would pass a naive suite while buying
# nothing.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
REPORT="$HERE/eval-report.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CASES=0
fail() { echo "FAIL: $1"; exit 1; }
pass() { CASES=$((CASES + 1)); }

# ---------------------------------------------------------------------------
# Fixtures.
# ---------------------------------------------------------------------------
# REAL is the aggregator's actual output shape, produced by running the pinned
# aggregate_benchmark.py over a synthetic benchmark tree. Every field here was
# copied from that output rather than imagined, including the thing that broke
# #199: `delta` sits INSIDE run_summary as a sibling of the config keys, and
# its pass_rate is the string "+0.50", not a stats dict.
cat > "$TMP/real.json" <<'EOF'
{
  "metadata": { "skill_name": "holacracy", "executor_model": "claude-sonnet-5" },
  "run_summary": {
    "with_skill": {
      "pass_rate": { "mean": 0.9375, "stddev": 0.125, "min": 0.75, "max": 1.0 },
      "time_seconds": { "mean": 12.5, "stddev": 0.0, "min": 12.5, "max": 12.5 },
      "tokens": { "mean": 0.0, "stddev": 0.0, "min": 0, "max": 0 }
    },
    "without_skill": {
      "pass_rate": { "mean": 0.4375, "stddev": 0.125, "min": 0.25, "max": 0.5 },
      "time_seconds": { "mean": 12.5, "stddev": 0.0, "min": 12.5, "max": 12.5 },
      "tokens": { "mean": 0.0, "stddev": 0.0, "min": 0, "max": 0 }
    },
    "delta": { "pass_rate": "+0.50", "time_seconds": "+0.0", "tokens": "+0" }
  }
}
EOF

# A run carrying a config the baseline has never seen. Normal the first time a
# configuration is added.
cat > "$TMP/new-config.json" <<'EOF'
{
  "run_summary": {
    "with_skill": { "pass_rate": { "mean": 0.5, "stddev": 0.1 } },
    "brand_new_config": { "pass_rate": { "mean": 0.8, "stddev": 0.3 } }
  }
}
EOF

echo '{"run_summary": {}}' > "$TMP/empty-summary.json"
echo '{}' > "$TMP/no-summary.json"

# A baseline whose every statistic is null -- the shape evals/benchmark.json
# carried before it was seeded (#183), and the shape it or any sibling would
# carry again before its own next seeding. Kept as a synthetic fixture rather
# than read off the real committed file: the file is now measured, and a check
# for "does a null mean render as n/a" must not depend on the committed
# baseline's own re-seedable content staying null forever.
cat > "$TMP/unmeasured-baseline.json" <<'EOF'
{ "run_summary": {
    "with_skill":    { "pass_rate": { "mean": null, "stddev": null } },
    "without_skill": { "pass_rate": { "mean": null, "stddev": null } } } }
EOF

# A measured baseline, so the delta column has something real to compute.
cat > "$TMP/measured-baseline.json" <<'EOF'
{ "run_summary": {
    "with_skill":    { "pass_rate": { "mean": 0.8, "stddev": 0.05 } },
    "without_skill": { "pass_rate": { "mean": 0.4, "stddev": 0.05 } } } }
EOF

# --cache-index fixtures (U5). "real" run-behavioural-eval.py output shape:
# _run_summary alongside whatever leg_<hash> entries happen to be in the
# index -- the section must ignore those, reading only _run_summary.
cat > "$TMP/cache-all-hits.json" <<'EOF'
{
  "leg_aaaa": { "last_executed": "2026-08-16T00:00:00+00:00", "successful": true },
  "_run_summary": {
    "generated_at": "2026-08-17T00:00:00+00:00",
    "hits": 3,
    "misses": 0,
    "legs": [
      { "case": "eval-a", "config": "with_skill", "cache_hit": true },
      { "case": "eval-a", "config": "without_skill", "cache_hit": true },
      { "case": "eval-b", "config": "with_skill", "cache_hit": true }
    ]
  }
}
EOF

cat > "$TMP/cache-mixed.json" <<'EOF'
{
  "_run_summary": {
    "generated_at": "2026-08-17T00:00:00+00:00",
    "hits": 2,
    "misses": 1,
    "legs": [
      { "case": "eval-a", "config": "with_skill", "cache_hit": true },
      { "case": "eval-a", "config": "without_skill", "cache_hit": false },
      { "case": "eval-b", "config": "with_skill", "cache_hit": true }
    ]
  }
}
EOF

echo '{}' > "$TMP/cache-empty.json"

# A real leg-keyed index that predates this unit -- no _run_summary key at all.
cat > "$TMP/cache-no-summary.json" <<'EOF'
{ "leg_aaaa": { "last_executed": "2026-08-10T00:00:00+00:00", "successful": true } }
EOF

# Malformed shapes a hand-edited or half-written index could carry.
echo '[1, 2, 3]' > "$TMP/cache-not-a-dict.json"
echo '{"_run_summary": "oops"}' > "$TMP/cache-summary-not-a-dict.json"
echo '{"_run_summary": {"hits": "not-a-number", "misses": null, "legs": "oops"}}' \
  > "$TMP/cache-bad-fields.json"
# A file that will not parse as JSON at all -- e.g. a partial write from an
# interrupted job. Unlike --baseline/--current (load() is deliberately strict,
# see eval-report.py), --cache-index reads a file on an unprotected branch
# (KTD1) via its own tolerant loader (load_cache_index_file), and this is the
# shape that distinguishes the two: it must degrade, not crash.
printf 'not json at all' > "$TMP/cache-bad.json"

# The COMMITTED baseline, used as-is rather than copied. If evals/benchmark.json
# is ever edited into a shape this report cannot read, that is a defect in the
# pair and this suite is where it should surface.
BASELINE="$REPO/evals/benchmark.json"
[ -f "$BASELINE" ] || fail "evals/benchmark.json is missing; case 2 has nothing to read"

report() {  # $1 = current, $2 = baseline, rest = interpreter override
  local script="${3:-$REPORT}"
  python3 "$script" --current "$1" --baseline "$2" 2>&1
}

report_cache() {  # $1 = current, $2 = baseline, $3 = cache-index, rest = script override
  local script="${4:-$REPORT}"
  python3 "$script" --current "$1" --baseline "$2" --cache-index "$3" 2>&1
}

# ---------------------------------------------------------------------------
# 1. The aggregator's real shape, including the delta-as-string sibling.
# ---------------------------------------------------------------------------
# This is #199 itself. The `delta` entry must never reach the per-config loop,
# and its preformatted string must still appear as the headline.
OUT="$(report "$TMP/real.json" "$TMP/measured-baseline.json")" \
  || { echo "$OUT"; fail "the aggregator's real shape crashed the report"; }
echo "$OUT" | grep -q '^| delta |' \
  && { echo "$OUT"; fail "the delta sibling was rendered as if it were a config"; }
echo "$OUT" | grep -qF 'with_skill − without_skill pass rate: **+0.50**' \
  || { echo "$OUT"; fail "the aggregator's preformatted delta was not reported"; }
# 0.9375 − 0.8 formats as +0.137, not +0.138: 0.1375 has no exact binary
# representation and lands just below the midpoint. Asserted as the literal the
# report actually emits, because the report's job is to print a stable string,
# not to be arithmetically re-derived here.
echo "$OUT" | grep -qF '| with_skill | 0.938 | 0.125 | 0.8 | +0.137 |' \
  || { echo "$OUT"; fail "the with_skill row did not compute against the baseline"; }
pass

# ---------------------------------------------------------------------------
# 2. An unmeasured baseline, whose every statistic is null.
# ---------------------------------------------------------------------------
# This is the shape evals/benchmark.json carries before a graded run seeds it.
# `mean - None` is a TypeError, so the baseline and delta columns must read
# "n/a" instead.
OUT="$(report "$TMP/real.json" "$TMP/unmeasured-baseline.json")" \
  || { echo "$OUT"; fail "an unmeasured baseline crashed the report"; }
[ "$(echo "$OUT" | grep -c '| n/a | n/a |')" = "2" ] \
  || { echo "$OUT"; fail "a null baseline statistic did not render as n/a"; }
pass

# 2a. The committed baseline, used as-is rather than copied. If
# evals/benchmark.json is ever edited into a shape this report cannot read,
# that is a defect in the pair and this suite is where it should surface.
# Once #183 seeded it (2026-08-17, run 32058594541) it carries real numbers,
# so this checks the report computes a real delta against it rather than
# falling back to "n/a" -- the null-baseline behaviour above already covers
# the pre-seeding shape via its own synthetic fixture.
OUT="$(report "$TMP/real.json" "$BASELINE")" \
  || { echo "$OUT"; fail "the committed baseline crashed the report"; }
echo "$OUT" | grep -qF '| with_skill | 0.938 | 0.125 | 0.5861 | +0.351 |' \
  || { echo "$OUT"; fail "the with_skill row did not compute against the committed baseline"; }
echo "$OUT" | grep -qF '| without_skill | 0.438 | 0.125 | 0.5333 | -0.096 |' \
  || { echo "$OUT"; fail "the without_skill row did not compute against the committed baseline"; }
pass

# A baseline file that does not exist at all is the same story, one step
# earlier: a normal state, not an error.
OUT="$(report "$TMP/real.json" "$TMP/does-not-exist.json")" \
  || { echo "$OUT"; fail "a missing baseline file crashed the report"; }
echo "$OUT" | grep -q "with_skill" || { echo "$OUT"; fail "a missing baseline produced no rows"; }
pass

# ---------------------------------------------------------------------------
# 3. A config present in the run but missing from the baseline.
# ---------------------------------------------------------------------------
OUT="$(report "$TMP/new-config.json" "$TMP/measured-baseline.json")" \
  || { echo "$OUT"; fail "a config missing from the baseline crashed the report"; }
echo "$OUT" | grep -q '^| brand_new_config | 0.800 | 0.300 | n/a | n/a |' \
  || { echo "$OUT"; fail "an unknown config did not fall back to n/a"; }
# It is still eligible for the wide-variance warning; being new is not being exempt.
echo "$OUT" | grep -q 'Wide variance' \
  || { echo "$OUT"; fail "a 0.30 stddev did not trigger the wide-variance warning"; }
pass

# ---------------------------------------------------------------------------
# 4. An empty run_summary, and an absent one.
# ---------------------------------------------------------------------------
# A run that produced nothing is exactly when the report still has to render:
# the expensive part already happened and the reader needs to see the header.
for f in empty-summary no-summary; do
  OUT="$(report "$TMP/$f.json" "$BASELINE")" \
    || { echo "$OUT"; fail "$f crashed the report"; }
  echo "$OUT" | grep -q "## Behavioural eval results" \
    || { echo "$OUT"; fail "$f produced no report header"; }
  # Exactly one `| ` line: the column header. Any second one is a data row
  # conjured from a run_summary that has no configs in it.
  rows="$(echo "$OUT" | grep -c '^| ')"
  [ "$rows" = "1" ] || { echo "$OUT"; fail "$f produced $rows table rows; expected the header alone"; }
  pass
done

# ---------------------------------------------------------------------------
# 5. --cache-index: the change-aware cache's hit/miss summary (U5, R6).
# ---------------------------------------------------------------------------
# Independent of everything above: --cache-index is optional, and omitting it
# (every case 1-4 above) must render exactly as before this flag existed --
# no section, no crash, no behaviour change to the baseline table.
OUT="$(report "$TMP/real.json" "$TMP/measured-baseline.json")" \
  || { echo "$OUT"; fail "omitting --cache-index crashed the report"; }
echo "$OUT" | grep -q "Change-aware eval cache" \
  && { echo "$OUT"; fail "the cache section rendered even though --cache-index was never passed"; }
pass

# 5a. An all-cache-hit night reads as a clean skip, not a silent no-op --
#     Success Criteria bullet 1. Leg-keyed entries elsewhere in the same
#     file (leg_aaaa) must be ignored; only _run_summary drives this.
OUT="$(report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-all-hits.json")" \
  || { echo "$OUT"; fail "an all-cache-hit index crashed the report"; }
echo "$OUT" | grep -q '| cache hits (unchanged, skipped) | 3 |' \
  || { echo "$OUT"; fail "the all-hit run did not report 3 hits"; }
echo "$OUT" | grep -q '| fresh executions | 0 |' \
  || { echo "$OUT"; fail "the all-hit run did not report 0 misses"; }
echo "$OUT" | grep -q 'Clean skip' \
  || { echo "$OUT"; fail "an all-cache-hit night did not read as a clean skip"; }
pass

# 5b. A mixed hit/miss night shows correct per-leg (per-config) counts, and
#     never mislabels a hit as a miss or vice versa: with_skill is 2 hits/0
#     misses, without_skill is 0 hits/1 miss, matching the seeded legs
#     exactly -- not just the totals.
OUT="$(report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-mixed.json")" \
  || { echo "$OUT"; fail "a mixed hit/miss index crashed the report"; }
echo "$OUT" | grep -q '| cache hits (unchanged, skipped) | 2 |' \
  || { echo "$OUT"; fail "the mixed run did not report 2 hits"; }
echo "$OUT" | grep -q '| fresh executions | 1 |' \
  || { echo "$OUT"; fail "the mixed run did not report 1 miss"; }
echo "$OUT" | grep -q '^| with_skill | 2 | 0 |' \
  || { echo "$OUT"; fail "with_skill's per-config hit/miss breakdown was wrong"; }
echo "$OUT" | grep -q '^| without_skill | 0 | 1 |' \
  || { echo "$OUT"; fail "without_skill's per-config hit/miss breakdown was wrong"; }
echo "$OUT" | grep -q 'Clean skip' \
  && { echo "$OUT"; fail "a mixed run was reported as a clean skip"; }
pass

# 5c. Never crashes on an empty index (the very first run ever), a missing
#     index file, or one that does not parse as JSON at all -- all three must
#     render a "no data" line, not raise. The unparseable case is what
#     load_cache_index_file exists for: --cache-index reads a file on the
#     unprotected eval-cache-index branch (KTD1), unlike --baseline/--current,
#     which are deliberately loaded strictly (see eval-report.py's load()).
for f in "$TMP/cache-empty.json" "$TMP/does-not-exist-cache-index.json" "$TMP/cache-bad.json"; do
  OUT="$(report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$f")" \
    || { echo "$OUT"; fail "$f crashed the cache-summary section"; }
  echo "$OUT" | grep -q "Change-aware eval cache" \
    || { echo "$OUT"; fail "$f produced no cache section header"; }
  echo "$OUT" | grep -q "No cache-run summary available" \
    || { echo "$OUT"; fail "$f did not render the no-data line"; }
  pass
done
# The unparseable cache-index file must not take the pass-rate table with it,
# same isolation rule as the cost section below.
OUT="$(report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-bad.json")"
echo "$OUT" | grep -q "## Behavioural eval results" \
  || { echo "$OUT"; fail "an unparseable cache-index file deleted the pass-rate table"; }
pass

# 5d. A real leg-keyed index that predates _run_summary must degrade to the
#     same "no data" line rather than crash or report bogus zeros.
OUT="$(report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-no-summary.json")" \
  || { echo "$OUT"; fail "a pre-U5 index crashed the report"; }
echo "$OUT" | grep -q "No cache-run summary available" \
  || { echo "$OUT"; fail "a pre-U5 index did not degrade to the no-data line"; }
pass

# 5e. Malformed shapes -- a top-level non-dict, a non-dict _run_summary, and
#     non-numeric hits/misses/legs -- must all render rather than raise.
for f in "$TMP/cache-not-a-dict.json" "$TMP/cache-summary-not-a-dict.json" \
         "$TMP/cache-bad-fields.json"; do
  OUT="$(report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$f")" \
    || { echo "$OUT"; fail "$f crashed the cache-summary section"; }
  echo "$OUT" | grep -q "Change-aware eval cache" \
    || { echo "$OUT"; fail "$f produced no cache section header"; }
  pass
done

# ---------------------------------------------------------------------------
# mutate <name> <find> <replace>  ->  echoes the mutant's path
# The builder's exit status is load-bearing, and used not to be.
#
# `assert mutated != text` fires on a drifted target, but the heredoc's status
# was never propagated: the function went on to `echo "$dst"` and returned 0, so
# the call site's `|| fail` could not fire. The case then ran the report through
# a path that does not exist, which fails -- and "the mutant fails" is exactly
# what these cases assert, so a drifted target produced a green vacuous pass.
# Returning non-zero and requiring a non-empty mutant is what makes the call
# sites' `|| fail` mean something.
mutate() {
  local name="$1" find="$2" repl="$3"
  local dst="$TMP/mut-$name.py"
  rm -f "$dst"
  python3 - "$REPORT" "$dst" "$find" "$repl" <<'PY'
import pathlib, sys
src, dst, find, repl = sys.argv[1:5]
text = pathlib.Path(src).read_text()
mutated = text.replace(find, repl)
if mutated == text:
    sys.stderr.write(f"mutation target not found: {find[:70]}\n")
    raise SystemExit(1)
pathlib.Path(dst).write_text(mutated)
PY
  # shellcheck disable=SC2181  # the heredoc above is the command whose status matters
  if [ $? -ne 0 ] || [ ! -s "$dst" ]; then
    return 1
  fi
  echo "$dst"
}

# Self-test: an absent target must make mutate() fail, or every case below that
# says "could not build the X mutant" is unreachable and the mutations are
# decorative.
if mutate selftest 'this string is deliberately absent from eval-report.py' 'x' >/dev/null 2>&1; then
  fail "the mutate() helper accepted an absent target; every mutation case below is vacuous"
fi
pass

# ---------------------------------------------------------------------------
# 6. MUTATION — each mutant removes exactly one defense (pass-rate table).
# ---------------------------------------------------------------------------
# 6a. Stop excluding the `delta` sibling. This is the #199 defect exactly:
#     .get("mean") lands on the string "+0.50".
M="$(mutate delta 'if k != DELTA_KEY' 'if True')" || fail "could not build the delta mutant"
report "$TMP/real.json" "$TMP/measured-baseline.json" "$M" >/dev/null 2>&1 \
  && fail "the delta-as-string shape survived a report that does not exclude it, so case 1 proves nothing"
pass
# ...and the defense is specific rather than incidental. Cases 3 and 4 still
# pass on this mutant because none of their fixtures carries a `delta` key.
# (Case 2 shares case 1's fixture and so legitimately depends on the same
# defense; it is not claimed as independent coverage.)
for f in new-config empty-summary no-summary; do
  report "$TMP/$f.json" "$BASELINE" "$M" >/dev/null 2>&1 \
    || fail "the delta mutant also broke $f, so case 1 is not isolating that defense"
done
pass

# 6b. Compute the delta without the isinstance guard, so a null baseline mean
#     reaches arithmetic.
M="$(mutate nulls \
  'delta = f"{mean - bm:+.3f}" if isinstance(bm, (int, float)) else "n/a"' \
  'delta = f"{mean - bm:+.3f}"')" || fail "could not build the null mutant"
report "$TMP/real.json" "$TMP/unmeasured-baseline.json" "$M" >/dev/null 2>&1 \
  && fail "a null baseline statistic survived arithmetic, so case 2 proves nothing"
pass
report "$TMP/real.json" "$TMP/measured-baseline.json" "$M" >/dev/null 2>&1 \
  || fail "the null mutant also broke the measured-baseline case, so case 2 is not isolating that defense"
pass

# 6c. Index the baseline instead of .get()ing it, so an unknown config raises.
M="$(mutate missing 'base_summary.get(config)' 'base_summary[config]')" \
  || fail "could not build the missing-config mutant"
report "$TMP/new-config.json" "$TMP/measured-baseline.json" "$M" >/dev/null 2>&1 \
  && fail "an unknown config survived a direct index, so case 3 proves nothing"
pass
report "$TMP/real.json" "$TMP/measured-baseline.json" "$M" >/dev/null 2>&1 \
  || fail "the missing-config mutant also broke case 1, so case 3 is not isolating that defense"
pass

# 6d. Iterate run_summary without the None guard, so an absent one raises.
M="$(mutate empty 'in (summary or {}).items()' 'in summary.items()')" \
  || fail "could not build the empty-summary mutant"
report "$TMP/no-summary.json" "$BASELINE" "$M" >/dev/null 2>&1 \
  && fail "an absent run_summary survived an unguarded iteration, so case 4 proves nothing"
pass
report "$TMP/real.json" "$TMP/measured-baseline.json" "$M" >/dev/null 2>&1 \
  || fail "the empty-summary mutant also broke case 1, so case 4 is not isolating that defense"
pass

# ---------------------------------------------------------------------------
# 7. MUTATION — each mutant removes exactly one cache-summary defense (U5).
# ---------------------------------------------------------------------------
# 7a. Drop the top-level isinstance(index, dict) guard in render_cache_summary,
#     so a cache index that is not a dict at all (e.g. a JSON array) reaches
#     `.get()` and raises. A real dict index -- even one exercising a
#     DIFFERENT cache-summary defense (case 5a's all-hits index) -- must
#     still render fine, since removing this guard changes nothing when the
#     index really is a dict.
M="$(mutate cache-index-guard \
  'index.get("_run_summary") if isinstance(index, dict) else None' \
  'index.get("_run_summary")')" || fail "could not build the cache-index-guard mutant"
report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-not-a-dict.json" "$M" >/dev/null 2>&1 \
  && fail "a non-dict cache index survived without the isinstance guard, so case 5e proves nothing"
pass
report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-all-hits.json" "$M" >/dev/null 2>&1 \
  || fail "the cache-index-guard mutant also broke a real dict index, so case 5e is not isolating that defense"
pass

# 7b. Disable the isinstance(summary, dict) guard, so a _run_summary that is
#     not a dict -- missing entirely (summary is None) or present with the
#     wrong type (case 5e's "oops" string) -- reaches `.get()` and raises.
#     case 5e's bad-fields fixture has a real dict _run_summary (only its
#     inner fields are malformed, which is the as_int defense's job, not
#     this one), so it must still render fine on this mutant.
M="$(mutate cache-summary-guard \
  'if not isinstance(summary, dict):' \
  'if False and not isinstance(summary, dict):')" \
  || fail "could not build the cache-summary-guard mutant"
report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-summary-not-a-dict.json" "$M" >/dev/null 2>&1 \
  && fail "a non-dict _run_summary survived without the isinstance guard, so case 5e proves nothing"
pass
report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-bad-fields.json" "$M" >/dev/null 2>&1 \
  || fail "the cache-summary-guard mutant also broke the malformed-fields fixture, so case 5e is not isolating that defense"
pass

# 7c. Stop catching the as_int() coercion's TypeError/ValueError, so a
#     non-numeric hits/misses field (case 5e's bad-fields fixture) raises
#     instead of coercing to 0. A fixture with real numeric hits/misses
#     (case 5b's mixed index) must be unaffected, since int() never raises
#     on an int it is already given.
M="$(mutate cache-hits-int 'except (TypeError, ValueError):' 'except ():')" \
  || fail "could not build the cache-hits-int mutant"
report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-bad-fields.json" "$M" >/dev/null 2>&1 \
  && fail "a non-numeric hits/misses field survived without the int guard, so case 5e proves nothing"
pass
report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-mixed.json" "$M" >/dev/null 2>&1 \
  || fail "the cache-hits-int mutant also broke a real numeric hits/misses fixture, so case 5b is not isolating that defense"
pass

# 7d. Load --cache-index with the strict loader instead of the soft one.
#     Same shape as the cost section's own 8-mut2 below: the malformed
#     cache-index file must then kill the whole report, proving the separate
#     loader is what keeps the failure inside the cache section.
M="$(mutate cache-softload 'render_cache_summary(load_cache_index_file(args.cache_index))' \
  'render_cache_summary(load(args.cache_index))')" \
  || fail "could not build the strict-cache-load mutant"
report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-bad.json" "$M" >/dev/null 2>&1 \
  && fail "the malformed cache-index file survived a strict load, so case 5c proves nothing"
pass
# ...and the strict-load mutant leaves the well-formed case working, so this
# is isolating the loader rather than breaking cache-summary rendering
# generally.
report_cache "$TMP/real.json" "$TMP/measured-baseline.json" "$TMP/cache-all-hits.json" "$M" >/dev/null 2>&1 \
  || fail "the strict-cache-load mutant also broke the well-formed case; it is not isolating the loader"
pass

# ---------------------------------------------------------------------------
# 8. The cost section renders, and its failure degrades ALONE.
# ---------------------------------------------------------------------------
# The pass-rate table is the paid run's headline. Because this step is
# `continue-on-error: true`, an exception raised while rendering cost would turn
# the step yellow and silently delete that table from the step summary -- so the
# cost section is held to a stronger rule than the four shapes above.
cat > "$TMP/cost.json" <<'EOF'
{"schema": 1, "cli_versions": ["1.2.3"],
 "configs": {
   "with_skill": {"runs": 1, "tokens_total": 780, "usd": 0.012,
     "passes_with_unknown_cost": 0,
     "passes": {"executor": {"tokens": {"total": 700}, "cache_hit_rate": 0.9,
                             "usd": 0.01, "unknown_cost": 0, "not_invoked": 0},
                "grader": {"tokens": {"total": 80}, "cache_hit_rate": 0.9,
                           "usd": 0.002, "unknown_cost": 0, "not_invoked": 0}},
     "models": {}},
   "without_skill": {"runs": 1, "tokens_total": 280, "usd": 0.01,
     "passes_with_unknown_cost": 0,
     "passes": {"executor": {"tokens": {"total": 200}, "cache_hit_rate": null,
                             "usd": 0.008, "unknown_cost": 0, "not_invoked": 0},
                "grader": {"tokens": {"total": 80}, "cache_hit_rate": 0.9,
                           "usd": 0.002, "unknown_cost": 0, "not_invoked": 0}},
     "models": {}}},
 "runs": []}
EOF

cost_report() {  # $1=cost $2=cost-baseline ("" for none) $3=interpreter override
  local script="${3:-$REPORT}"
  if [ -n "$2" ]; then
    python3 "$script" --current "$TMP/real.json" --baseline "$TMP/measured-baseline.json" \
      --cost "$1" --cost-baseline "$2" 2>&1
  else
    python3 "$script" --current "$TMP/real.json" --baseline "$TMP/measured-baseline.json" \
      --cost "$1" 2>&1
  fi
}

# Cache hit rate is readable from ONE run, with no baseline. That is the whole
# motivating question -- it is a ratio inside a single run, so it does not wait
# on a committed baseline that does not exist yet.
OUT="$(cost_report "$TMP/cost.json" "")" || { echo "$OUT"; fail "the cost section crashed the report"; }
echo "$OUT" | grep -q "### Cost" || { echo "$OUT"; fail "no cost section was rendered"; }
echo "$OUT" | grep -q "90%" || { echo "$OUT"; fail "cache hit rate is not rendered"; }
echo "$OUT" | grep -q "## Behavioural eval results" \
  || { echo "$OUT"; fail "the pass-rate table vanished when cost was added"; }
pass

# No comparison supplied means no delta, not a delta against nothing.
echo "$OUT" | grep -q '| n/a |$' || { echo "$OUT"; fail "an absent comparison did not render as n/a"; }
pass

# A config the comparison has never seen reads as an absence. Same rule the
# pass-rate table already follows for a newly added case.
python3 -c "
import json
d = json.load(open('$TMP/cost.json'))
del d['configs']['without_skill']
json.dump(d, open('$TMP/cost-partial.json', 'w'))"
OUT="$(cost_report "$TMP/cost.json" "$TMP/cost-partial.json")" \
  || { echo "$OUT"; fail "a partial comparison crashed the report"; }
# The USD column is deliberately left out of this pattern: a literal dollar sign
# is either a shellcheck SC2016 warning in single quotes or a positional
# expansion in double quotes, and the assertion is about the delta.
echo "$OUT" | grep -q '^| with_skill | executor | 700 | 90% | .* | +0 |' \
  || { echo "$OUT"; fail "a known config produced no delta against the comparison"; }
pass

# Billed-but-unrecoverable spend is stated, never folded in as zero.
python3 -c "
import json
d = json.load(open('$TMP/cost.json'))
d['configs']['with_skill']['passes']['grader']['unknown_cost'] = 1
json.dump(d, open('$TMP/cost-unknown.json', 'w'))"
OUT="$(cost_report "$TMP/cost-unknown.json" "")"
echo "$OUT" | grep -q "billed but reported no usage" \
  || { echo "$OUT"; fail "a billed pass with no usage was not surfaced"; }
pass

# Absent and malformed both state the absence rather than crashing.
echo '{}' > "$TMP/cost-empty.json"
OUT="$(cost_report "$TMP/cost-empty.json" "")" || { echo "$OUT"; fail "an empty cost file crashed the report"; }
echo "$OUT" | grep -q "No cost data" || { echo "$OUT"; fail "an empty cost file did not say so"; }
# A cost file that will not parse at all. This one is easy to get wrong: the
# obvious implementation loads it in main(), OUTSIDE the cost section's
# boundary, so the raise takes the pass-rate table with it -- #199's shape, one
# file over. The load must fail into the section, not around it.
printf 'not json at all' > "$TMP/cost-bad.json"
OUT="$(cost_report "$TMP/cost-bad.json" "")" \
  || { echo "$OUT"; fail "an unparseable cost file crashed the whole report"; }
echo "$OUT" | grep -q "## Behavioural eval results" \
  || { echo "$OUT"; fail "an unparseable cost file deleted the pass-rate table"; }
echo "$OUT" | grep -q "could not be read" \
  || { echo "$OUT"; fail "an unparseable cost file did not state the absence"; }
pass

# THE ONE THAT MATTERS: a cost summary that PARSES but carries a shape nobody
# guarded -- a null where a mapping was assumed. This is #199's actual profile,
# and the pass-rate table must survive it intact.
cat > "$TMP/cost-weird.json" <<'EOF'
{"schema": 1, "cli_versions": ["1.2.3"],
 "configs": {"with_skill": {"passes": {"executor": null, "grader": 42}}}}
EOF
OUT="$(cost_report "$TMP/cost-weird.json" "")" \
  || { echo "$OUT"; fail "an unexpected cost shape crashed the whole report"; }
echo "$OUT" | grep -q "## Behavioural eval results" \
  || { echo "$OUT"; fail "an unexpected cost shape deleted the pass-rate table"; }
echo "$OUT" | grep -qE "Cost data could not be rendered|### Cost" \
  || { echo "$OUT"; fail "an unexpected cost shape produced no cost section at all"; }
pass

# Omitting --cost leaves the report exactly as it was, so every consumer that
# does not pass it is unaffected.
OUT="$(report "$TMP/real.json" "$TMP/measured-baseline.json")"
echo "$OUT" | grep -q "### Cost" && fail "a report with no --cost still rendered a cost section"
pass

# 8-mut. Remove the failure boundary. The unexpected shape must then take the
# whole report down, proving the boundary is what saves it.
M="$(mutate boundary 'try:
        return cost_rows(cost, base_cost)
    except Exception as exc:  # noqa: BLE001 -- see the docstring; this is the boundary
        return ["\n### Cost\n",
                f"_Cost data could not be rendered: {type(exc).__name__}: {exc}_"]' \
  'return cost_rows(cost, base_cost)')" || fail "could not build the boundary mutant"
cost_report "$TMP/cost-weird.json" "" "$M" >/dev/null 2>&1 \
  && fail "the unexpected shape survived without the boundary, so that case proves nothing"
pass
# ...and the boundary is specific: the well-formed cost file still renders on
# the same mutant, so it is not masking an ordinary bug.
cost_report "$TMP/cost.json" "" "$M" >/dev/null 2>&1 \
  || fail "the boundary mutant also broke the well-formed case; the boundary is hiding a real defect"
pass

# 8-mut2. Load the cost summary with the strict loader instead of the soft one.
# The malformed file must then kill the whole report, proving the separate
# loader is what keeps the failure inside the section.
M="$(mutate softload 'cost = load_cost(args.cost) if args.cost else None' \
  'cost = load(args.cost) if args.cost else None')" \
  || fail "could not build the strict-load mutant"
cost_report "$TMP/cost-bad.json" "" "$M" >/dev/null 2>&1 \
  && fail "the malformed cost file survived a strict load, so that case proves nothing"
pass
# ...and the strict-load mutant leaves the well-formed case working, so this is
# isolating the loader rather than breaking cost rendering generally.
cost_report "$TMP/cost.json" "" "$M" >/dev/null 2>&1 \
  || fail "the strict-load mutant also broke the well-formed case; it is not isolating the loader"
pass

echo "eval-report.test.sh: $CASES cases passed"
