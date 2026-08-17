#!/usr/bin/env bash
# Regression suite for scripts/eval-cost.py.
#
# WHAT THIS GUARDS
# ----------------
# The cost ledger's arithmetic. `run-behavioural-eval.py` stores usage verbatim
# and interprets none of it, so every rule about which fields are summed, how
# the cache ratio is computed, and how the aggregator's mislabelled `tokens`
# figure is corrected lives in eval-cost.py -- and therefore here.
#
# WHY IT IS A SEPARATE SUITE
# --------------------------
# run-behavioural-eval.test.sh proves the RECORD is written correctly by driving
# a fake CLI through the real runner. This suite proves the DERIVATION is
# correct, and needs neither a CLI nor a stub: it authors cost records directly.
# Splitting them keeps a derivation-rule change from having to re-run the whole
# fake-session machinery to be tested.
#
# MUTATION CONTRACT
# -----------------
# Same as every other suite here: for each defense there is a mutant with ONLY
# that defense removed, and the suite asserts BOTH that the case for that
# defense fails on the mutant AND that the mutation target still exists. A
# mutation whose target has moved silently tests nothing, so it is an error.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COST="${1:-$REPO/scripts/eval-cost.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }
CASES=0
pass() { CASES=$((CASES + 1)); }

# ---------------------------------------------------------------------------
# Fixtures: a run tree authored directly, matching what the runner emits.
# ---------------------------------------------------------------------------
# Written by hand rather than captured, because the shapes that matter here are
# the ones a live run produces RARELY -- a billed grader failure, a nested cache
# breakdown, a two-model pass. Waiting for a nightly to emit them is how they go
# untested.
mk_run() {  # $1=tree $2=suite $3=local-id $4=config $5=run $6=cost.json body
  local dir="$1/eval-$2-$3/$4/run-$5"
  mkdir -p "$dir"
  printf '%s' "$6" > "$dir/cost.json"
  cat > "$1/eval-$2-$3/eval_metadata.json" <<EOF
{"eval_id": "$2-$3", "eval_id_local": $3, "suite": "$2", "eval_name": "$2-$3-name"}
EOF
}

# The ordinary shape: both passes ok, cache-bearing, full per-model map.
ok_pass() {  # $1=input $2=output $3=cache_create $4=cache_read $5=usd $6=model
  cat <<EOF
{"status": "ok", "reason": null,
 "usage": {"input_tokens": $1, "output_tokens": $2,
           "cache_creation_input_tokens": $3, "cache_read_input_tokens": $4},
 "model_usage": {"$6": {"inputTokens": $1, "outputTokens": $2,
                        "cacheCreationInputTokens": $3, "cacheReadInputTokens": $4,
                        "costUSD": $5}},
 "total_cost_usd": $5}
EOF
}

TREE="$TMP/tree"
mk_run "$TREE" suite-a 0 with_skill 1 "{\"schema\":1,\"cli_version\":\"1.2.3\",
  \"passes\":{\"executor\":$(ok_pass 100 200 40 360 0.01 model-x),
              \"grader\":$(ok_pass 10 20 5 45 0.002 model-y)}}"
mk_run "$TREE" suite-a 0 without_skill 1 "{\"schema\":1,\"cli_version\":\"1.2.3\",
  \"passes\":{\"executor\":$(ok_pass 100 100 0 0 0.008 model-x),
              \"grader\":$(ok_pass 10 20 5 45 0.002 model-y)}}"

"$COST" aggregate --run-tree "$TREE" --out "$TMP/summary.json" >/dev/null 2>&1 \
  || fail "aggregate exited non-zero on a well-formed tree"

q() { python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print($2)" "$TMP/summary.json"; }

# ---------------------------------------------------------------------------
# 1. Both passes are counted, and never blended.
# ---------------------------------------------------------------------------
# The grader is a second full model call per graded eval -- roughly half the
# spend -- and was previously invisible. 700 executor + 80 grader.
[ "$(q . "d['runs'][0]['tokens_total']")" = "780" ] \
  || fail "the per-run total does not cover both passes"
[ "$(q . "d['configs']['with_skill']['passes']['executor']['tokens']['total']")" = "700" ] \
  || fail "executor tokens are wrong or blended with the grader's"
[ "$(q . "d['configs']['with_skill']['passes']['grader']['tokens']['total']")" = "80" ] \
  || fail "grader tokens are wrong or blended with the executor's"
pass

# ---------------------------------------------------------------------------
# 2. Cache hit rate, readable from a single run with no baseline.
# ---------------------------------------------------------------------------
# 360 read / (360 read + 40 created) = 0.9 for the executor.
[ "$(q . "d['configs']['with_skill']['passes']['executor']['cache_hit_rate']")" = "0.9" ] \
  || fail "executor cache hit rate is not reads/(reads+creations)"
pass

# A run with no cache activity has NO hit rate. Reporting 0.0 would read as
# "caching is on and missing every time", which is a different claim.
[ "$(q . "d['configs']['without_skill']['passes']['executor']['cache_hit_rate']")" = "None" ] \
  || fail "a zero denominator produced a rate instead of an absence"
pass

# ---------------------------------------------------------------------------
# 3. USD is read, never computed from a price table.
# ---------------------------------------------------------------------------
[ "$(q . "d['configs']['with_skill']['usd']")" = "0.012" ] \
  || fail "config USD is not the sum of the reported per-pass figures"
[ "$(q . "d['configs']['with_skill']['models']['model-x']['usd']")" = "0.01" ] \
  || fail "per-model USD was not read from costUSD"
pass

# ---------------------------------------------------------------------------
# 4. The shapes a literal "sum every field" would break on.
# ---------------------------------------------------------------------------
# service_tier is a STRING; cache_creation is the 1-hour tier's nested
# breakdown reported ALONGSIDE the flat field it decomposes; server_tool_use is
# not a token count. Summing every field raises on the first and double-counts
# the second, which also corrupts the hit-rate denominator.
EXOTIC="$TMP/exotic"
mk_run "$EXOTIC" suite-a 0 with_skill 1 '{"schema":1,"cli_version":"1.2.3",
 "passes":{"executor":{"status":"ok","reason":null,
   "usage":{"input_tokens":100,"output_tokens":200,
            "cache_creation_input_tokens":40,"cache_read_input_tokens":360,
            "service_tier":"standard",
            "cache_creation":{"ephemeral_5m_input_tokens":30,
                              "ephemeral_1h_input_tokens":10},
            "server_tool_use":{"web_search_requests":2},
            "some_future_tokens":7},
   "model_usage":{"model-x":{"inputTokens":100,"costUSD":0.01}},
   "total_cost_usd":0.01},
  "grader":{"status":"not_invoked","reason":"no judged assertions",
   "usage":null,"model_usage":null,"total_cost_usd":null}}}'
"$COST" aggregate --run-tree "$EXOTIC" --out "$TMP/exotic.json" >/dev/null 2>&1 \
  || fail "aggregate crashed on a usage object carrying non-count fields"
eq() { python3 -c "
import json,sys
d=json.load(open('$TMP/exotic.json'))
print($1)"; }
# Still 700: the nested breakdown did not double-count, the string did not
# raise, the counter did not join in, and the novel scalar was ignored.
[ "$(eq "d['runs'][0]['tokens_total']")" = "700" ] \
  || fail "an unrecognised or nested field reached the token total"
[ "$(eq "d['configs']['with_skill']['passes']['executor']['cache_hit_rate']")" = "0.9" ] \
  || fail "the nested cache_creation breakdown corrupted the hit-rate denominator"
pass

# ---------------------------------------------------------------------------
# 5. A billed failure is not a zero.
# ---------------------------------------------------------------------------
# `not_invoked` cost nothing. `failed` means the subprocess launched and was
# billed -- a full-timeout generation thrown away -- with its usage
# unrecoverable. Folding the second into a total as zero under-reports spend on
# exactly the runs that wasted it.
STATES="$TMP/states"
mk_run "$STATES" suite-a 0 with_skill 1 "{\"schema\":1,\"cli_version\":\"1.2.3\",
  \"passes\":{\"executor\":$(ok_pass 100 200 40 360 0.01 model-x),
    \"grader\":{\"status\":\"failed\",\"reason\":\"timeout\",
      \"usage\":null,\"model_usage\":null,\"total_cost_usd\":null}}}"
mk_run "$STATES" suite-b 0 with_skill 1 "{\"schema\":1,\"cli_version\":\"1.2.3\",
  \"passes\":{\"executor\":$(ok_pass 100 200 40 360 0.01 model-x),
    \"grader\":{\"status\":\"not_invoked\",\"reason\":\"no judged assertions\",
      \"usage\":null,\"model_usage\":null,\"total_cost_usd\":null}}}"
"$COST" aggregate --run-tree "$STATES" --out "$TMP/states.json" >/dev/null 2>&1 \
  || fail "aggregate failed on a tree containing a failed grader"
sq() { python3 -c "
import json
d=json.load(open('$TMP/states.json'))
print($1)"; }
[ "$(sq "d['configs']['with_skill']['passes_with_unknown_cost']")" = "1" ] \
  || fail "the billed-but-unrecoverable grader was not counted as unknown cost"
[ "$(sq "d['configs']['with_skill']['passes']['grader']['not_invoked']")" = "1" ] \
  || fail "the structurally-zero grader was not counted separately"
pass

# ---------------------------------------------------------------------------
# 6. Every model in a pass survives.
# ---------------------------------------------------------------------------
# The eval tool set offers Task, whose subagent turns can be served by a
# different model, and cache-tier-suffixed names key separately. Taking the
# first key -- how the executor model is resolved elsewhere -- drops the rest.
MULTI="$TMP/multi"
mk_run "$MULTI" suite-a 0 with_skill 1 '{"schema":1,"cli_version":"1.2.3",
 "passes":{"executor":{"status":"ok","reason":null,
   "usage":{"input_tokens":115,"output_tokens":200,
            "cache_creation_input_tokens":40,"cache_read_input_tokens":360},
   "model_usage":{"model-x":{"inputTokens":100,"outputTokens":200,
                             "cacheCreationInputTokens":40,
                             "cacheReadInputTokens":360,"costUSD":0.01},
                  "model-sub":{"inputTokens":15,"outputTokens":0,
                               "cacheCreationInputTokens":0,
                               "cacheReadInputTokens":0,"costUSD":0.003}},
   "total_cost_usd":0.013},
  "grader":{"status":"not_invoked","reason":"none","usage":null,
            "model_usage":null,"total_cost_usd":null}}}'
"$COST" aggregate --run-tree "$MULTI" --out "$TMP/multi.json" >/dev/null 2>&1 \
  || fail "aggregate failed on a two-model pass"
[ "$(python3 -c "
import json;d=json.load(open('$TMP/multi.json'))
print(len(d['configs']['with_skill']['models']))")" = "2" ] \
  || fail "a two-model pass was collapsed to one model"
pass

# ---------------------------------------------------------------------------
# 7. The two usage sources disagreeing warns; it does not silently pick one.
# ---------------------------------------------------------------------------
MISMATCH="$TMP/mismatch"
mk_run "$MISMATCH" suite-a 0 with_skill 1 '{"schema":1,"cli_version":"1.2.3",
 "passes":{"executor":{"status":"ok","reason":null,
   "usage":{"input_tokens":100,"output_tokens":200,
            "cache_creation_input_tokens":40,"cache_read_input_tokens":360},
   "model_usage":{"model-x":{"inputTokens":100,"outputTokens":999,
                             "cacheCreationInputTokens":40,
                             "cacheReadInputTokens":360,"costUSD":0.01}},
   "total_cost_usd":0.01},
  "grader":{"status":"not_invoked","reason":"none","usage":null,
            "model_usage":null,"total_cost_usd":null}}}'
warn_out="$("$COST" aggregate --run-tree "$MISMATCH" --out "$TMP/mismatch.json" 2>&1 >/dev/null)"
case "$warn_out" in
  *"per-model map sums to"*) : ;;
  *) fail "a usage/model_usage disagreement produced no warning" ;;
esac
# `usage` still wins -- it is what the pre-existing figure was computed from, so
# the correction stays like-for-like.
[ "$(python3 -c "
import json;d=json.load(open('$TMP/mismatch.json'))
print(d['runs'][0]['tokens_total'])")" = "700" ] \
  || fail "the per-model map overrode usage as the token authority"
pass

# A PARTIAL per-model map is a reporting difference, not a discrepancy. Warning
# on it would train readers to ignore the warning.
partial_out="$("$COST" aggregate --run-tree "$EXOTIC" --out "$TMP/p.json" 2>&1 >/dev/null)"
case "$partial_out" in
  *"per-model map sums to"*) fail "a partial per-model map was reported as a disagreement" ;;
  *) : ;;
esac
pass

# ---------------------------------------------------------------------------
# 8. Absence is stated, never crashed on and never invented.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/empty"
empty_out="$("$COST" aggregate --run-tree "$TMP/empty" --out "$TMP/empty.json" 2>&1 >/dev/null)"
case "$empty_out" in
  *"no cost.json records"*) : ;;
  *) fail "an empty run tree did not say so" ;;
esac
[ "$(python3 -c "
import json;d=json.load(open('$TMP/empty.json'))
print(len(d['runs']))")" = "0" ] || fail "an empty tree produced runs"
pass

# An unparseable record is skipped with a reason rather than killing the run
# that produced every other record.
BAD="$TMP/bad"
mk_run "$BAD" suite-a 0 with_skill 1 '{"schema":1, this is not json'
mk_run "$BAD" suite-b 0 with_skill 1 "{\"schema\":1,\"cli_version\":\"1.2.3\",
  \"passes\":{\"executor\":$(ok_pass 100 200 40 360 0.01 model-x),
    \"grader\":{\"status\":\"not_invoked\",\"reason\":\"none\",\"usage\":null,
                \"model_usage\":null,\"total_cost_usd\":null}}}"
"$COST" aggregate --run-tree "$BAD" --out "$TMP/bad.json" >/dev/null 2>&1 \
  || fail "one unparseable record aborted the whole aggregation"
[ "$(python3 -c "
import json;d=json.load(open('$TMP/bad.json'))
print(len(d['runs']))")" = "1" ] \
  || fail "the readable record was not kept alongside the unreadable one"
pass

# A missing run tree is an operational error, not an empty success. Reporting
# health from absent evidence is the failure #122 documents at length.
missing_rc=0
"$COST" aggregate --run-tree "$TMP/nope" --out "$TMP/nope.json" >/dev/null 2>&1 || missing_rc=$?
[ "$missing_rc" = "2" ] || fail "a missing run tree exited $missing_rc; expected 2"
pass

# ---------------------------------------------------------------------------
# 9. The join key is the one the aggregator used.
# ---------------------------------------------------------------------------
# Read from eval_metadata.json, not parsed out of the directory name. The
# correction joins on it, and a key derived two different ways is a join
# waiting to break.
[ "$(q . "d['runs'][0]['eval_id']")" = "suite-a-0" ] \
  || fail "eval_id was not taken from eval_metadata.json"
pass

# ---------------------------------------------------------------------------
# Mutations.
# ---------------------------------------------------------------------------
mutate() {  # $1=label $2=find $3=replace
  python3 - "$COST" "$TMP/mut-$1.py" "$2" "$3" <<'PY'
import pathlib, sys
src, dst, find, repl = sys.argv[1:5]
text = pathlib.Path(src).read_text()
mutated = text.replace(find, repl, 1)
assert mutated != text, f"mutation target not found: {find[:60]}"
pathlib.Path(dst).write_text(mutated)
PY
  chmod +x "$TMP/mut-$1.py"
}

# The named field set is what stops non-counts entering the arithmetic. Widen it
# to "every field" and the exotic tree must break.
mutate widen \
  'out = {field: count(usage.get(field)) for field in TOKEN_FIELDS}' \
  'out = {field: count(usage.get(field)) for field in usage}'
python3 "$TMP/mut-widen.py" aggregate --run-tree "$EXOTIC" --out "$TMP/mut1.json" >/dev/null 2>&1
mut_total="$(python3 -c "
import json
try:
    d=json.load(open('$TMP/mut1.json')); print(d['runs'][0]['tokens_total'])
except Exception: print('crashed')" 2>/dev/null)"
[ "$mut_total" != "700" ] \
  || fail "widening the field set still produced 700; case 4 is not load-bearing"
pass

# The count() guard is what makes a string survivable.
mutate guard \
  'if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    return int(value)' \
  'return int(value or 0)'
python3 "$TMP/mut-guard.py" aggregate --run-tree "$EXOTIC" --out "$TMP/mut2.json" >/dev/null 2>&1
# With the guard gone AND the field set widened this raises; with only the guard
# gone the named set never hands it a string, so assert the guard is reachable
# by driving it directly.
python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('m', '$TMP/mut-guard.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
try:
    m.count('standard'); print('no-raise')
except (TypeError, ValueError): print('raised')
" | grep -q raised || fail "the count() guard mutant tolerates a string; the guard is not load-bearing"
pass

# The zero-denominator guard is what turns "no cache activity" into an absence.
mutate rate \
  'if denominator <= 0:
        return None' \
  'if denominator < 0:
        return None'
python3 "$TMP/mut-rate.py" aggregate --run-tree "$TREE" --out "$TMP/mut3.json" >/dev/null 2>&1
mut_rate="$(python3 -c "
import json
try:
    d=json.load(open('$TMP/mut3.json'))
    print(d['configs']['without_skill']['passes']['executor']['cache_hit_rate'])
except Exception: print('crashed')" 2>/dev/null)"
[ "$mut_rate" != "None" ] \
  || fail "removing the zero-denominator guard still produced None; case 2 is not load-bearing"
pass

# Blending the passes must break case 1.
mutate blend \
  '"tokens_total": sum(passes[p]["tokens"]["total"] for p in PASSES),' \
  '"tokens_total": passes["executor"]["tokens"]["total"],'
python3 "$TMP/mut-blend.py" aggregate --run-tree "$TREE" --out "$TMP/mut4.json" >/dev/null 2>&1
[ "$(python3 -c "
import json;d=json.load(open('$TMP/mut4.json'));print(d['runs'][0]['tokens_total'])")" != "780" ] \
  || fail "dropping the grader from the total still produced 780; case 1 is not load-bearing"
pass

echo "eval-cost.test.sh: $CASES cases passed"
