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

# The COMMITTED baseline, used as-is rather than copied. If evals/benchmark.json
# is ever edited into a shape this report cannot read, that is a defect in the
# pair and this suite is where it should surface.
BASELINE="$REPO/evals/benchmark.json"
[ -f "$BASELINE" ] || fail "evals/benchmark.json is missing; case 2 has nothing to read"

report() {  # $1 = current, $2 = baseline, rest = interpreter override
  local script="${3:-$REPORT}"
  python3 "$script" --current "$1" --baseline "$2" 2>&1
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
# 5. MUTATION — each mutant removes exactly one defense.
# ---------------------------------------------------------------------------
# mutate <name> <find> <replace>  ->  echoes the mutant's path
mutate() {
  local name="$1" find="$2" repl="$3"
  local dst="$TMP/mut-$name.py"
  python3 - "$REPORT" "$dst" "$find" "$repl" <<'PY'
import pathlib, sys
src, dst, find, repl = sys.argv[1:5]
text = pathlib.Path(src).read_text()
mutated = text.replace(find, repl)
# If the defense is refactored, the mutation stops reproducing the defect and
# the case below would pass while testing nothing. Fail loudly instead.
assert mutated != text, f"mutation target not found: {find!r}"
pathlib.Path(dst).write_text(mutated)
PY
  echo "$dst"
}

# 5a. Stop excluding the `delta` sibling. This is the #199 defect exactly:
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

# 5b. Compute the delta without the isinstance guard, so a null baseline mean
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

# 5c. Index the baseline instead of .get()ing it, so an unknown config raises.
M="$(mutate missing 'base_summary.get(config)' 'base_summary[config]')" \
  || fail "could not build the missing-config mutant"
report "$TMP/new-config.json" "$TMP/measured-baseline.json" "$M" >/dev/null 2>&1 \
  && fail "an unknown config survived a direct index, so case 3 proves nothing"
pass
report "$TMP/real.json" "$TMP/measured-baseline.json" "$M" >/dev/null 2>&1 \
  || fail "the missing-config mutant also broke case 1, so case 3 is not isolating that defense"
pass

# 5d. Iterate run_summary without the None guard, so an absent one raises.
M="$(mutate empty 'in (summary or {}).items()' 'in summary.items()')" \
  || fail "could not build the empty-summary mutant"
report "$TMP/no-summary.json" "$BASELINE" "$M" >/dev/null 2>&1 \
  && fail "an absent run_summary survived an unguarded iteration, so case 4 proves nothing"
pass
report "$TMP/real.json" "$TMP/measured-baseline.json" "$M" >/dev/null 2>&1 \
  || fail "the empty-summary mutant also broke case 1, so case 4 is not isolating that defense"
pass

echo "eval-report.test.sh: $CASES cases passed"
