#!/usr/bin/env bash
# Regression tests for scripts/run-behavioural-eval.py.
#
# Run: bash scripts/run-behavioural-eval.test.sh
# No framework — plain asserts. Exits non-zero on first failure.
#
# WHY THIS SUITE MATTERS MORE THAN USUAL
# --------------------------------------
# The runner's own job only happens at 03:00 in a nightly workflow, against an
# API key CI holds and no laptop does. That is the exact shape of issue #122: an
# instrument nobody has watched run, reporting a plausible-looking number. So
# every path in the runner except the literal `claude` invocation is exercised
# here, offline, on every PR.
#
# HOW THE FAKE EXECUTOR WORKS
# ---------------------------
# BEHAVIOURAL_EVAL_CLAUDE_BIN swaps in a fake `claude` that reads a PLAN and
# replays it. The fake does not fabricate a write log: it parses the
# --mcp-config the runner generated, launches the REAL stub from it, and issues
# real MCP tools/call requests. So a plan that says "archive, then create" walks
# the whole path — generated config, stub launch, write log, read_writes,
# mechanical check — and only the model is substituted.
#
# THE MUTATION PROPERTY
# ---------------------
# For each mechanical check there is a plan violating ONLY that check, and the
# suite asserts BOTH directions:
#
#   that assertion              -> FAILS   (the check does its job)
#   every OTHER assertion       -> PASSES  (nothing else covers it)
#
# The second is the load-bearing half, and it is the same guarantee
# skills-lint.test.sh gets from SKILLS_LINT_SKIP: a check that some other check
# incidentally catches would pass a naive suite while buying nothing.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNNER="$HERE/run-behavioural-eval.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
CASES=0
pass() { CASES=$((CASES + 1)); }

FIXTURE="evals/fixtures/glassfrog/structural-supersession.json"
SEC_ROLE="$(python3 -c "
import json;print(json.load(open('$REPO/$FIXTURE'))['key_map']['role:security-officer'])")"
OPS_ROLE="$(python3 -c "
import json;print(json.load(open('$REPO/$FIXTURE'))['key_map']['role:platform-ops'])")"
TEN_VENDOR="$(python3 -c "
import json;print(json.load(open('$REPO/$FIXTURE'))['key_map']['ten:vendor-access'])")"

# ---------------------------------------------------------------------------
# The fake executor.
# ---------------------------------------------------------------------------
cat > "$TMP/fake-claude.py" <<'PY'
#!/usr/bin/env python3
"""Stand in for `claude`, replaying a plan through the REAL stub."""
import json, os, subprocess, sys

argv = sys.argv[1:]
def opt(name):
    return argv[argv.index(name) + 1] if name in argv else None

if os.environ.get("FAKE_CLAUDE_DIE"):
    sys.stderr.write("simulated executor failure\n")
    sys.exit(3)

# A well-formed event stream that reports an error. This is what the real CLI
# emits when `--bare` cannot authenticate, and it is NOT an empty stream.
if os.environ.get("FAKE_CLAUDE_AUTH_FAIL") and "--json-schema" not in argv:
    print(json.dumps({"type": "assistant",
                      "message": {"content": [{"type": "text",
                                               "text": "Not logged in · Please run /login"}]}}))
    print(json.dumps({"type": "result", "is_error": True,
                      "result": "Not logged in · Please run /login"}))
    sys.exit(0)

# The grading pass is the call carrying --json-schema.
if "--json-schema" in argv:
    if os.environ.get("FAKE_GRADER_DIE"):
        sys.stderr.write("simulated grader failure\n")
        sys.exit(4)
    plan = json.load(open(os.environ["FAKE_PLAN"]))
    verdicts = plan.get("grader", [])
    print(json.dumps({"type": "result", "result": json.dumps({"expectations": verdicts})}))
    sys.exit(0)

plan = json.load(open(os.environ["FAKE_PLAN"]))
leg = plan["with_skill"] if "--plugin-dir" in argv else plan.get("without_skill", {})

cfg = json.load(open(opt("--mcp-config")))["mcpServers"]["glassfrog"]
proc = subprocess.Popen([cfg["command"], *cfg["args"]],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
                        env={**os.environ, **cfg["env"]})

def rpc(idx, method, params=None):
    proc.stdin.write(json.dumps(
        {"jsonrpc": "2.0", "id": idx, "method": method, "params": params or {}}) + "\n")
    proc.stdin.flush()
    return json.loads(proc.stdout.readline())

rpc(1, "initialize")
content = []
if leg.get("text"):
    content.append({"type": "text", "text": leg["text"]})
results = []
for i, call in enumerate(leg.get("calls", []), start=2):
    reply = rpc(i, "tools/call",
                {"name": call["tool"], "arguments": call.get("args", {})})
    content.append({"type": "tool_use", "id": f"t{i}",
                    "name": f"mcp__glassfrog__{call['tool']}",
                    "input": call.get("args", {})})
    results.append({"type": "tool_result", "tool_use_id": f"t{i}",
                    "is_error": reply["result"].get("isError", False),
                    "content": reply["result"]["content"]})
proc.stdin.close()
proc.wait(timeout=10)

print(json.dumps({"type": "assistant", "message": {"content": content}}))
if results:
    print(json.dumps({"type": "user", "message": {"content": results}}))
print(json.dumps({"type": "result", "is_error": False,
                  "result": leg.get("final", "done"),
                  "usage": {"input_tokens": 100, "output_tokens": 200}}))
PY
chmod +x "$TMP/fake-claude.py"

FAKE="python3 $TMP/fake-claude.py"
# BEHAVIOURAL_EVAL_CLAUDE_BIN takes a single executable, so wrap the two words.
cat > "$TMP/fake-claude" <<EOF
#!/usr/bin/env bash
exec $FAKE "\$@"
EOF
chmod +x "$TMP/fake-claude"

# A case file carrying exactly the mechanical checks under test, and nothing
# judged — so a section can only go red for the reason it is named after.
write_case() {  # $1 = destination
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
{
  "skill": "holacracy",
  "surface": "/holacracy:tension-triage",
  "status": "fixture",
  "evals": [
    {
      "eval_id": 0,
      "eval_name": "mechanical-checks",
      "fixture": "$FIXTURE",
      "prompt": "fixture prompt",
      "ground_truth": "fixture",
      "assertions": [
        { "text": "successor before archive", "discriminating": true,
          "check": { "kind": "write_ordering",
                     "first": { "tool": "glassfrog_create_tension",
                                "args_contain": { "role_id": "$SEC_ROLE" } },
                     "then":  { "tool": "glassfrog_update_tension",
                                "args_contain": { "status": "archived" } } } },
        { "text": "no meeting_type on any write", "discriminating": true,
          "check": { "kind": "no_write_of",
                     "match": { "args_match": { "meeting_type": "." } } } },
        { "text": "no create_tension on platform ops", "discriminating": true,
          "check": { "kind": "no_write_of",
                     "match": { "tool": "glassfrog_create_tension",
                                "args_contain": { "role_id": "$OPS_ROLE" } } } },
        { "text": "a successor exists", "discriminating": true,
          "check": { "kind": "write_present",
                     "match": { "tool": "glassfrog_create_tension" } } }
      ]
    }
  ]
}
EOF
}
write_case "$TMP/case/evals.json"

# Run the runner over a plan and print "<assertion text>=<passed>" per line.
verdicts() {  # $1 = plan json path, $2 = out dir, rest = extra runner args
  local plan="$1" out="$2"; shift 2
  rm -rf "$out"
  FAKE_PLAN="$plan" BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
    python3 "$RUNNER" --case "$TMP/case/evals.json" --out "$out" \
      --configs with_skill "$@" >/dev/null 2>&1
  python3 -c "
import json,sys
g=json.load(open('$out/eval-case-0/with_skill/run-1/grading.json'))
for e in g['expectations']: print(f\"{e['text']}={e['passed']}\")"
}

verdict_of() {  # $1 = verdict block, $2 = assertion text
  echo "$1" | grep -F "$2=" | cut -d= -f2
}

# The clean plan: create the successor, then archive both originals.
cat > "$TMP/plan-clean.json" <<EOF
{ "with_skill": {
    "text": "Archiving alone would drop a live exposure no other record carries.",
    "calls": [
      { "tool": "glassfrog_create_tension",
        "args": { "role_id": "$SEC_ROLE", "body": "Successor to the archived originals: unreviewed vendor access and live credentials for departed contributors." } },
      { "tool": "glassfrog_update_tension",
        "args": { "tension_id": "$TEN_VENDOR", "status": "archived" } }
    ] } }
EOF

# ---------------------------------------------------------------------------
# 1. The clean plan passes every mechanical check.
# ---------------------------------------------------------------------------
CLEAN="$(verdicts "$TMP/plan-clean.json" "$TMP/out-clean" --no-grade)"
echo "$CLEAN" | grep -q "=False" \
  && { echo "$CLEAN"; fail "a correct run failed a mechanical check"; }
[ "$(echo "$CLEAN" | wc -l | tr -d ' ')" = "4" ] \
  || { echo "$CLEAN"; fail "expected 4 graded assertions"; }
pass

# Writes really travelled through the stub, not around it.
python3 -c "
import json
rows=[json.loads(l) for l in open('$TMP/out-clean/eval-case-0/with_skill/run-1/outputs/writes.jsonl')]
assert [r['seq'] for r in rows]==[1,2], rows
assert rows[0]['tool']=='glassfrog_create_tension', rows[0]
" || fail "the fake executor did not drive the real stub"
pass

# ---------------------------------------------------------------------------
# 2. MUTATION — each plan violates exactly one check.
# ---------------------------------------------------------------------------
# 2a. Archive first, successor second. Ordering must fail; nothing else may.
cat > "$TMP/plan-order.json" <<EOF
{ "with_skill": { "calls": [
    { "tool": "glassfrog_update_tension",
      "args": { "tension_id": "$TEN_VENDOR", "status": "archived" } },
    { "tool": "glassfrog_create_tension",
      "args": { "role_id": "$SEC_ROLE", "body": "successor written too late" } }
] } }
EOF
V="$(verdicts "$TMP/plan-order.json" "$TMP/out-order" --no-grade)"
[ "$(verdict_of "$V" "successor before archive")" = "False" ] \
  || { echo "$V"; fail "ordering check passed on an archive-first run"; }
for other in "no meeting_type on any write" "no create_tension on platform ops" "a successor exists"; do
  [ "$(verdict_of "$V" "$other")" = "True" ] \
    || { echo "$V"; fail "'$other' also caught the ordering defect; the ordering check is not load-bearing"; }
done
pass

# 2b. Ordering must NOT pass by vacuity. A run that creates the successor and
#     never archives anything has satisfied nothing — and this is the failure
#     mode a naive `min(first) < min(then)` silently scores green, because
#     min() over an empty set never happens.
cat > "$TMP/plan-vacuous.json" <<EOF
{ "with_skill": { "calls": [
    { "tool": "glassfrog_create_tension",
      "args": { "role_id": "$SEC_ROLE", "body": "successor with nothing archived" } }
] } }
EOF
V="$(verdicts "$TMP/plan-vacuous.json" "$TMP/out-vacuous" --no-grade)"
[ "$(verdict_of "$V" "successor before archive")" = "False" ] \
  || { echo "$V"; fail "ordering check passed vacuously when no archive was issued"; }
pass

# 2c. meeting_type on a write. The stub 422s it exactly as the live API does,
#     so a skill that tries it fails in production; the check has to see it.
cat > "$TMP/plan-meeting-type.json" <<EOF
{ "with_skill": { "calls": [
    { "tool": "glassfrog_create_tension",
      "args": { "role_id": "$SEC_ROLE", "body": "successor" } },
    { "tool": "glassfrog_update_tension",
      "args": { "tension_id": "$TEN_VENDOR", "status": "archived", "meeting_type": "governance" } }
] } }
EOF
V="$(verdicts "$TMP/plan-meeting-type.json" "$TMP/out-mt" --no-grade)"
[ "$(verdict_of "$V" "no meeting_type on any write")" = "False" ] \
  || { echo "$V"; fail "meeting_type check passed on a write carrying meeting_type"; }
[ "$(verdict_of "$V" "no create_tension on platform ops")" = "True" ] \
  || { echo "$V"; fail "the platform-ops check also caught the meeting_type defect"; }
pass

# 2d. Successor written on the WRONG role. args_contain must discriminate on the
#     argument value, not merely on the tool name.
cat > "$TMP/plan-wrong-role.json" <<EOF
{ "with_skill": { "calls": [
    { "tool": "glassfrog_create_tension",
      "args": { "role_id": "$OPS_ROLE", "body": "successor left on the wrong role" } },
    { "tool": "glassfrog_update_tension",
      "args": { "tension_id": "$TEN_VENDOR", "status": "archived" } }
] } }
EOF
V="$(verdicts "$TMP/plan-wrong-role.json" "$TMP/out-wrong-role" --no-grade)"
[ "$(verdict_of "$V" "no create_tension on platform ops")" = "False" ] \
  || { echo "$V"; fail "args_contain did not discriminate on role_id"; }
[ "$(verdict_of "$V" "a successor exists")" = "True" ] \
  || { echo "$V"; fail "write_present should still see a create_tension on any role"; }
[ "$(verdict_of "$V" "successor before archive")" = "False" ] \
  || { echo "$V"; fail "ordering should fail: no successor on the covering role preceded the archive"; }
pass

# 2e. The model read the backlog and declined to write anything. This is the
#     legitimate "no writes" run — distinct from § 4d, where nothing was called
#     at all. write_present must fail on it rather than treating silence as
#     success, while no_write_of correctly holds vacuously.
cat > "$TMP/plan-silent.json" <<'EOF'
{ "with_skill": {
    "text": "I read the backlog and would not write anything without your confirmation.",
    "calls": [ { "tool": "glassfrog_list_my_roles", "args": {} } ] } }
EOF
V="$(verdicts "$TMP/plan-silent.json" "$TMP/out-silent" --no-grade)"
[ "$(verdict_of "$V" "a successor exists")" = "False" ] \
  || { echo "$V"; fail "write_present passed on a run that issued no writes"; }
[ "$(verdict_of "$V" "no meeting_type on any write")" = "True" ] \
  || { echo "$V"; fail "a no_write_of check should hold vacuously; only positive checks must not"; }
pass

# ---------------------------------------------------------------------------
# 3. Case-file validation.
# ---------------------------------------------------------------------------
# The issue's instruction — cut non-discriminating assertions — only survives if
# writing one is impossible to do silently.
_reject() {  # $1 = case json body, $2 = expected stderr fragment, $3 = label
  printf '%s\n' "$1" > "$TMP/bad-case.json"
  local out
  if out="$(BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" python3 "$RUNNER" \
             --case "$TMP/bad-case.json" --out "$TMP/out-bad" --validate-only 2>&1)"; then
    fail "$3: the runner accepted a malformed case file"
  fi
  echo "$out" | grep -qF "$2" || fail "$3: expected '$2', got: $out"
}
_reject '{"evals":[{"eval_id":0,"eval_name":"n","prompt":"p","fixture":"'"$FIXTURE"'",
  "assertions":[{"text":"undeclared"}]}]}' \
  "does not declare" "undeclared discriminating"
pass

_reject '{"evals":[{"eval_id":0,"eval_name":"n","prompt":"p","fixture":"'"$FIXTURE"'",
  "assertions":[{"text":"floor","discriminating":false}]}]}' \
  "why_kept" "non-discriminating with no why_kept"
pass

_reject '{"evals":[{"eval_id":0,"eval_name":"n","fixture":"'"$FIXTURE"'",
  "assertions":[{"text":"t","discriminating":true}]}]}' \
  "missing required field 'prompt'" "missing prompt"
pass

# ---------------------------------------------------------------------------
# 4. Failure modes must fail loudly, never quietly green.
# ---------------------------------------------------------------------------
# 4a. A grader that cannot be reached fails every judged assertion. Passing them
#     would report a green nightly on a run nobody graded.
mkdir -p "$TMP/case-judged"
cat > "$TMP/case-judged/evals.json" <<EOF
{ "evals": [ { "eval_id": 0, "eval_name": "judged", "fixture": "$FIXTURE",
  "prompt": "p", "ground_truth": "g",
  "assertions": [ { "text": "a judged claim", "discriminating": true } ] } ] }
EOF
FAKE_PLAN="$TMP/plan-clean.json" FAKE_GRADER_DIE=1 \
  BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
  python3 "$RUNNER" --case "$TMP/case-judged/evals.json" --out "$TMP/out-nograder" \
    --configs with_skill >/dev/null 2>&1
python3 -c "
import json
g=json.load(open('$TMP/out-nograder/eval-case-judged-0/with_skill/run-1/grading.json'))
e=g['expectations'][0]
assert e['passed'] is False, e
assert 'grader unavailable' in e['evidence'], e
assert g['summary']['pass_rate']==0.0, g['summary']
" || fail "an unreachable grader did not fail its judged assertions"
pass

# 4b. An executor that cannot run fails everything, mechanical included, and
#     says why. A mechanical check over an empty write log would otherwise
#     report "no writes — pass" for a run that never happened.
FAKE_PLAN="$TMP/plan-clean.json" FAKE_CLAUDE_DIE=1 \
  BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
  python3 "$RUNNER" --case "$TMP/case/evals.json" --out "$TMP/out-dead" \
    --configs with_skill --no-grade >/dev/null 2>&1
python3 -c "
import json
g=json.load(open('$TMP/out-dead/eval-case-0/with_skill/run-1/grading.json'))
assert g['execution_error'], g
assert g['summary']['pass_rate']==0.0, g['summary']
assert all('did not execute' in e['evidence'] for e in g['expectations']), g['expectations']
" || fail "a dead executor produced a grading that did not record the failure"
pass

# 4c. A session that ERRORS while emitting a well-formed event stream must not
#     score green. This is not hypothetical: the first live run of this runner
#     hit it. `--bare` reads only ANTHROPIC_API_KEY or an apiKeyHelper, so an
#     operator signed in interactively gets one "Not logged in" turn with
#     is_error set — and every negative assertion passed, because a model that
#     never ran issues no forbidden write.
FAKE_PLAN="$TMP/plan-clean.json" FAKE_CLAUDE_AUTH_FAIL=1 \
  BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
  python3 "$RUNNER" --case "$TMP/case/evals.json" --out "$TMP/out-auth" \
    --configs with_skill --no-grade >/dev/null 2>&1
python3 -c "
import json
g=json.load(open('$TMP/out-auth/eval-case-0/with_skill/run-1/grading.json'))
assert g['execution_error'], 'an is_error result event was not treated as a failure'
assert 'Not logged in' in g['execution_error'], g['execution_error']
assert 'ANTHROPIC_API_KEY' in g['execution_error'], \
    'the auth failure did not name the cause an operator can act on'
assert g['summary']['pass_rate']==0.0, g['summary']
" || fail "a session that reported an error still scored assertions"
pass

# 4d. A run that made NO tool calls cannot support an assertion about tool use.
#     Distinct from 4c: this stream carries no error at all, it simply did
#     nothing — and a `no_write_of` check over an empty log passes on it.
cat > "$TMP/plan-no-calls.json" <<'EOF'
{ "with_skill": { "text": "Here is what I would do.", "calls": [] } }
EOF
FAKE_PLAN="$TMP/plan-no-calls.json" BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
  python3 "$RUNNER" --case "$TMP/case/evals.json" --out "$TMP/out-nocalls" \
    --configs with_skill --no-grade >/dev/null 2>&1
python3 -c "
import json
g=json.load(open('$TMP/out-nocalls/eval-case-0/with_skill/run-1/grading.json'))
assert g['execution_error'], 'a run with zero tool calls was treated as valid'
assert 'no tool calls' in g['execution_error'], g['execution_error']
assert g['summary']['pass_rate']==0.0, g['summary']
" || fail "a run that called no tools still scored its negative assertions green"
pass

# 4e. A missing fixture is an error, not a skipped eval.
sed "s|$FIXTURE|evals/fixtures/glassfrog/does-not-exist.json|" \
  "$TMP/case/evals.json" > "$TMP/case-missing.json"
BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" python3 "$RUNNER" \
  --case "$TMP/case-missing.json" --out "$TMP/out-missing" --validate-only >/dev/null 2>&1 \
  && fail "a missing fixture did not fail the run"
pass

# ---------------------------------------------------------------------------
# 5. HERMETICITY — the flags that keep an eval away from the live org and away
#    from the operator's own installed copy of this plugin.
# ---------------------------------------------------------------------------
python3 - "$RUNNER" <<'PY' || fail "the executor command lost a hermeticity flag"
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("runner", sys.argv[1])
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
cfg = pathlib.Path("/tmp/x.json")

with_skill = runner.build_command("p", "with_skill", cfg, None)
without = runner.build_command("p", "without_skill", cfg, None)

# --strict-mcp-config is what stops the plugin's own .mcp.json -- which points at
# the PRODUCTION GlassFrog connector -- from being loaded alongside the stub.
for cmd, label in ((with_skill, "with_skill"), (without, "without_skill")):
    assert "--strict-mcp-config" in cmd, (label, cmd)
    assert "--bare" in cmd, (label, cmd)
    assert "--mcp-config" in cmd, (label, cmd)

# --plugin-dir is the ONLY route by which the plugin enters a session under
# --bare. If without_skill ever carried it, the delta would be measuring noise.
assert "--plugin-dir" in with_skill, with_skill
assert "--plugin-dir" not in without, without
PY
pass

# The generated MCP config names the server `glassfrog`. Under any other name
# every mcp__glassfrog__* tool the skills were written against fails to resolve,
# and the eval would score a plumbing error as a behavioural finding.
python3 - "$RUNNER" <<'PY' || fail "the generated MCP config does not match the real connector's server name"
import importlib.util, json, pathlib, sys
spec = importlib.util.spec_from_file_location("runner", sys.argv[1])
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
live = json.loads((runner.REPO / ".mcp.json").read_text())
generated = runner.mcp_config(pathlib.Path("/f.json"), pathlib.Path("/w.jsonl"))["mcpServers"]
assert set(generated) == set(live), (sorted(generated), sorted(live))
PY
pass

# ---------------------------------------------------------------------------
# 6. The SHIPPED case files, against the SHIPPED fixtures.
# ---------------------------------------------------------------------------
# Every id a mechanical check names must exist in that case's fixture. A check
# keyed on a stale id matches nothing, and a `no_write_of` keyed on nothing
# passes forever.
python3 - "$REPO" <<'PY' || fail "a shipped case names an id its fixture does not carry"
import json, pathlib, re, sys
repo = pathlib.Path(sys.argv[1])
seen = 0
for case_file in sorted((repo / "evals" / "cases").glob("*/evals.json")):
    doc = json.loads(case_file.read_text())
    for case in doc["evals"]:
        fixture = json.loads((repo / case["fixture"]).read_text())
        known = set(fixture["key_map"].values())
        blob = json.dumps([a.get("check") for a in case["assertions"]])
        for ident in re.findall(r'\b(?:role|ten|per|org)_[0-9a-f]{32}\b', blob):
            seen += 1
            assert ident in known, (case_file.name, case["eval_name"], ident)
assert seen, "no ids were checked; the guard is not exercising anything"
PY
pass

# Every shipped case validates and its fixture starts the stub.
SHIPPED=()
for f in "$REPO"/evals/cases/*/evals.json; do SHIPPED+=(--case "$f"); done
[ "${#SHIPPED[@]}" -gt 0 ] || fail "no shipped case files were found to validate"
python3 "$RUNNER" --out "$TMP/out-shipped" --validate-only "${SHIPPED[@]}" \
  >/dev/null 2>&1 || fail "a shipped case file failed validation or its fixture probe"
pass

# ---------------------------------------------------------------------------
# 7. The emitted tree is what aggregate_benchmark.py reads.
# ---------------------------------------------------------------------------
# skill-creator's aggregator is reused as-is, so the contract is its directory
# layout and the keys it pulls out of grading.json. Getting this wrong produces
# an empty benchmark rather than an error.
python3 -c "
import json, pathlib
root = pathlib.Path('$TMP/out-clean')
eval_dir = root / 'eval-case-0'
assert (eval_dir / 'eval_metadata.json').exists()
assert json.loads((eval_dir / 'eval_metadata.json').read_text())['eval_id'] == 0
run = eval_dir / 'with_skill' / 'run-1'
assert list(eval_dir.glob('*/run-*')), 'aggregator globs config/run-*'
g = json.loads((run / 'grading.json').read_text())
for key in ('passed', 'failed', 'total', 'pass_rate'):
    assert key in g['summary'], key
for exp in g['expectations']:
    for key in ('text', 'passed', 'evidence'):
        assert key in exp, (key, exp)
assert 'total_duration_seconds' in json.loads((run / 'timing.json').read_text())
assert 'total_tool_calls' in g['execution_metrics']
assert (run / 'outputs' / 'transcript.md').exists()
" || fail "the emitted tree does not match what aggregate_benchmark.py consumes"
pass

# The transcript has to carry tool calls with their arguments, because the
# grader reads it. A transcript of assistant prose alone would let "which tool
# was called with what" be graded on the model's own account of what it did.
grep -q "glassfrog_create_tension" "$TMP/out-clean/eval-case-0/with_skill/run-1/outputs/transcript.md" \
  || fail "the transcript did not record the tool calls the grader needs"
grep -q "$SEC_ROLE" "$TMP/out-clean/eval-case-0/with_skill/run-1/outputs/transcript.md" \
  || fail "the transcript recorded a tool call without its arguments"
pass


# ---------------------------------------------------------------------------
# 8. Two case files sharing an eval_id do not collide.
# ---------------------------------------------------------------------------
# `eval_id` is unique only WITHIN a case file, and every file numbers from 0.
# Keyed on it alone, the second suite's eval 0 overwrote the first's and a
# whole surface vanished from a green benchmark that reported the remainder as
# the complete suite (#201).
#
# The mutation half carries more weight here than usual: the defect is SILENT.
# The run succeeds, the aggregate is plausible, and nothing errors. An
# assertion that only checked "the run exited 0" would have passed throughout
# the entire period the bug was live.
write_case "$TMP/suite-a/evals.json"
write_case "$TMP/suite-b/evals.json"
rm -rf "$TMP/out-collide"
FAKE_PLAN="$TMP/plan-clean.json" BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
  python3 "$RUNNER" --case "$TMP/suite-a/evals.json" --case "$TMP/suite-b/evals.json" \
    --out "$TMP/out-collide" --configs with_skill --no-grade >/dev/null 2>&1
[ -f "$TMP/out-collide/eval-suite-a-0/with_skill/run-1/grading.json" ] \
  && [ -f "$TMP/out-collide/eval-suite-b-0/with_skill/run-1/grading.json" ] \
  || fail "two case files sharing eval_id 0 did not both produce results"
pass

# Mutation: revert to the flat eval-<id> key and the collision must return,
# proving the suite qualifier is what prevents it rather than some incidental
# property of the run. The runner resolves REPO from its own location and
# fixtures relative to it, so the mutant needs a shadow root with evals/.
mkdir -p "$TMP/mut/scripts"
ln -s "$REPO/evals" "$TMP/mut/evals"
python3 - "$RUNNER" "$TMP/mut/scripts/run-behavioural-eval.py" <<'PY'
import pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = src.read_text()
mutated = text.replace("eval-{suite}-{", "eval-{")
# If the fix is refactored, this mutation stops reproducing the defect and the
# case below would pass while testing nothing. Fail loudly instead.
assert mutated != text, "mutation target not found: the eval dir naming moved"
dst.write_text(mutated)
PY
rm -rf "$TMP/out-collide-mut"
FAKE_PLAN="$TMP/plan-clean.json" BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
  python3 "$TMP/mut/scripts/run-behavioural-eval.py" \
    --case "$TMP/suite-a/evals.json" --case "$TMP/suite-b/evals.json" \
    --out "$TMP/out-collide-mut" --configs with_skill --no-grade >/dev/null 2>&1
mut_dirs="$(find "$TMP/out-collide-mut" -maxdepth 1 -type d -name 'eval-*' | wc -l | tr -d ' ')"
[ "$mut_dirs" = "1" ] \
  || fail "the flat-key mutant produced $mut_dirs eval dirs; expected 1 collided dir, so this case no longer proves the fix is load-bearing"
pass

echo "run-behavioural-eval.test.sh: $CASES cases passed"
