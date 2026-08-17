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
# Exported for the fake executor, which builds its init event's slash_commands
# from it. Read from the manifest, the same source the runner reads.
PLUGIN_NS="$(python3 -c "
import json;print(json.load(open('$REPO/.claude-plugin/plugin.json'))['name'])")"
export PLUGIN_NS
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

# claude_cli_version() shells out to `claude --version` once per invocation of
# the runner, independent of every other env knob in this file, so the cache
# tests (§ 13/14) can compute the SAME cli_version the runner folds into its
# cache key. Fixed and unconditional -- this must answer identically whether
# or not any FAKE_* mutation below is active.
if "--version" in argv:
    print("2.5.0 (Claude Code)")
    sys.exit(0)

# Deliberately NOT whatever --model asked for. The runner must record what
# answered, not what was requested, and identical strings would let a runner
# that echoed the request pass § 9.
EXECUTOR_MODEL = "fake-executor-model"
ANALYZER_MODEL = "fake-analyzer-model"

# Reproduces graded run 31229964963, where every with_skill execution was
# answered by one model and every without_skill execution by another, purely
# because --model was blank and each session chose for itself.
if os.environ.get("FAKE_SPLIT_MODEL") and "--plugin-dir" not in sys.argv[1:]:
    EXECUTOR_MODEL = "fake-control-model"

# The namespace the plugin registers under, read from the manifest by the shell
# and handed in. Hard-coding it here would let a rename turn the plugin-loaded
# assertions into vacuous ones without anything going red.
PLUGIN_NS = os.environ["PLUGIN_NS"]

if os.environ.get("FAKE_CLAUDE_DIE"):
    sys.stderr.write("simulated executor failure\n")
    sys.exit(3)

# The session/init event, emitted first exactly as the real CLI emits it. Its
# `tools` and `slash_commands` are what session_shape_error reads, and the fake
# has to model the real dependency: --plugin-dir is what registers the plugin's
# namespace, and nothing else does. Each env knob below reproduces one live
# failure mode rather than a hypothetical one.
if "--json-schema" not in argv:
    has_plugin = "--plugin-dir" in argv
    # What `--bare` actually offered: no Skill, so no skill could ever fire.
    tools = (["Bash", "Edit", "Read"] if os.environ.get("FAKE_NO_SKILL_TOOL")
             else ["Task", "Read", "Skill"])
    commands = ["deep-research", "code-review"]
    plugin_cmds = [f"{PLUGIN_NS}:capture-tension", f"{PLUGIN_NS}:tension-triage"]
    if has_plugin and not os.environ.get("FAKE_PLUGIN_NOT_LOADED"):
        commands += plugin_cmds
    if not has_plugin and os.environ.get("FAKE_PLUGIN_LEAK"):
        commands += plugin_cmds
    if not os.environ.get("FAKE_NO_INIT"):
        print(json.dumps({"type": "system", "subtype": "init",
                          "tools": tools + [f"mcp__glassfrog__{t}" for t in
                                            ("glassfrog_get_me", "glassfrog_create_tension")],
                          "mcp_servers": [{"name": "glassfrog", "status": "connected"}],
                          "slash_commands": commands}))

# A well-formed event stream that reports an error. This is what the real CLI
# emits when it cannot authenticate, and it is NOT an empty stream.
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
    print(json.dumps({"type": "result",
                      "modelUsage": {ANALYZER_MODEL: {"inputTokens": 10}},
                      "result": json.dumps({"expectations": verdicts})}))
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
# A filesystem read of the checkout, which is how run-1 of graded run
# 31058151548 reached the shared spec in a leg that had no plugin.
if os.environ.get("FAKE_READ_PATH"):
    content.append({"type": "tool_use", "id": "t-read", "name": "Read",
                    "input": {"file_path": os.environ["FAKE_READ_PATH"]
                              + "/skills/shared/triage-gates.md"}})
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

print(json.dumps({"type": "assistant",
                  "message": {"model": EXECUTOR_MODEL, "content": content}}))
if results:
    print(json.dumps({"type": "user", "message": {"content": results}}))
print(json.dumps({"type": "result", "is_error": False,
                  "result": leg.get("final", "done"),
                  "modelUsage": {EXECUTOR_MODEL: {"inputTokens": 100}},
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

# A logging variant used only by § 14 (the cache index). It records every
# invocation's argv to $CACHE_INVOKE_LOG before delegating to the same fake
# executor above, so a cache-hit test can assert the CLI was invoked exactly
# once (the --version probe used to compute the cache key) rather than the
# full session/grading calls a fresh execution would make.
cat > "$TMP/fake-claude-logged" <<EOF
#!/usr/bin/env bash
if [ -n "\${CACHE_INVOKE_LOG:-}" ]; then
  printf '%s\n' "\$*" >> "\$CACHE_INVOKE_LOG"
fi
exec $FAKE "\$@"
EOF
chmod +x "$TMP/fake-claude-logged"

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
             --case "$TMP/bad-case.json" --out "$TMP/out-bad" \
             --validate-only --no-session-probe 2>&1)"; then
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
#     hit it. The session authenticates with ANTHROPIC_API_KEY and runs under a
#     redirected CLAUDE_CONFIG_DIR, so an operator whose login lives in their own
#     config dir gets one "Not logged in" turn with is_error set — and every
#     negative assertion passed, because a model that never ran issues no
#     forbidden write.
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
  --case "$TMP/case-missing.json" --out "$TMP/out-missing" \
  --validate-only --no-session-probe >/dev/null 2>&1 \
  && fail "a missing fixture did not fail the run"
pass

# ---------------------------------------------------------------------------
# 5. HERMETICITY — the flags that keep an eval away from the live org and away
#    from the operator's own installed copy of this plugin.
# ---------------------------------------------------------------------------
python3 - "$RUNNER" <<'PY' || fail "the executor command or environment lost a hermeticity property"
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
    assert "--mcp-config" in cmd, (label, cmd)
    # --bare bought hermeticity by also removing the Skill tool, which made the
    # whole tier measure the base model twice (#226). It must not come back.
    assert "--bare" not in cmd, (label, cmd)
    tools = cmd[cmd.index("--tools") + 1].split(",")
    assert "Skill" in tools, (label, tools)
    # The control reached the checkout with `find /` when it had a shell.
    for withheld in ("Bash", "Glob", "Grep", "Write"):
        assert withheld not in tools, (label, withheld, tools)

# --plugin-dir is the only route by which the plugin enters the session, given
# the empty CLAUDE_CONFIG_DIR and the out-of-tree cwd. If without_skill ever
# carried it, the delta would be measuring noise.
assert "--plugin-dir" in with_skill, with_skill
assert "--plugin-dir" not in without, without

# CLAUDE_CONFIG_DIR is what now hides the operator's installed plugins, settings
# and hooks. Inheriting the real one would put a globally-installed copy of this
# very plugin into the control leg.
env = runner.session_env(pathlib.Path("/sandbox/cfg"))
assert env["CLAUDE_CONFIG_DIR"] == "/sandbox/cfg", env.get("CLAUDE_CONFIG_DIR")
assert "CLAUDECODE" not in env
assert "CLAUDE_CODE_SIMPLE" not in env
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
# --no-session-probe because this case is about the CASE FILES and their
# fixtures. The session probe needs the real `claude` binary, which a CI runner
# does not have — and § 11 covers the probe against the fake instead.
python3 "$RUNNER" --out "$TMP/out-shipped" --validate-only --no-session-probe \
  "${SHIPPED[@]}" >/dev/null 2>&1 \
  || fail "a shipped case file failed validation or its fixture probe"
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
# Spelled as an explicit `if` rather than `A && B || fail`: that form is not
# if-then-else (shellcheck SC2015 — the fail arm also runs when A holds and B
# does not), and shellcheck 0.9.0 on the CI image rejects it at info severity
# while 0.11.0 locally does not.
if [ ! -f "$TMP/out-collide/eval-suite-a-0/with_skill/run-1/grading.json" ] \
   || [ ! -f "$TMP/out-collide/eval-suite-b-0/with_skill/run-1/grading.json" ]; then
  fail "two case files sharing eval_id 0 did not both produce results"
fi
pass

# Mutation: revert to the flat eval-<id> key and the collision must return,
# proving the suite qualifier is what prevents it rather than some incidental
# property of the run. The runner resolves REPO from its own location and
# fixtures relative to it, so the mutant needs a shadow root with evals/.
mkdir -p "$TMP/mut/scripts"
ln -s "$REPO/evals" "$TMP/mut/evals"
ln -s "$REPO/.claude-plugin" "$TMP/mut/.claude-plugin"
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

# ---------------------------------------------------------------------------
# 9. The model recorded is the one that ANSWERED, not the one requested.
# ---------------------------------------------------------------------------
# `--model` is a workflow_dispatch input and is blank on most runs, meaning
# "the CLI default". Recording the request therefore records nothing on exactly
# the runs whose model a reader most needs to name — and run 31053788703
# shipped a benchmark whose executor_model was the literal string
# "<model-name>" (#203). Without it, #173's regression alarm cannot tell a
# model upgrade from a skill regression: it would misattribute the cause.
#
# The fake reports models that deliberately differ from what --model asks for,
# so "observed" and "requested" cannot be confused by coincidence.
mkdir -p "$TMP/case-model"
cat > "$TMP/case-model/evals.json" <<EOF
{ "evals": [ { "eval_id": 0, "eval_name": "judged", "fixture": "$FIXTURE",
  "prompt": "p", "ground_truth": "g",
  "assertions": [ { "text": "a judged claim", "discriminating": true } ] } ] }
EOF
cat > "$TMP/plan-model.json" <<EOF
{ "with_skill": { "calls": [
    { "tool": "glassfrog_create_tension",
      "args": { "role_id": "$SEC_ROLE", "body": "any write at all" } } ] },
  "grader": [ { "passed": true, "evidence": "fixture" } ] }
EOF

record_models() {  # $1 = runner path, $2 = out dir
  rm -rf "$2"
  FAKE_PLAN="$TMP/plan-model.json" BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
    python3 "$1" --case "$TMP/case-model/evals.json" --out "$2" \
      --configs with_skill --model requested-model-not-used >/dev/null 2>&1
}

record_models "$RUNNER" "$TMP/out-model"
python3 -c "
import json
g=json.load(open('$TMP/out-model/eval-case-model-0/with_skill/run-1/grading.json'))
m=g['models']
assert m['requested']=='requested-model-not-used', m
assert m['executor']=='fake-executor-model', m
assert m['analyzer']=='fake-analyzer-model', m
r=json.load(open('$TMP/out-model/run_metadata.json'))
assert r['executor_models']==['fake-executor-model'], r
assert r['analyzer_models']==['fake-analyzer-model'], r
assert r['model']=='requested-model-not-used', r
" || fail "the runner did not record the models that actually answered"
pass

# Mutation: record the REQUESTED model instead of the observed one. This is the
# defect the assertion above exists to catch, and it is invisible on any run
# where --model happens to be set to what actually answers -- which is why the
# fake reports a different name. Nothing else in this suite touches the models
# block, so without this case the recording could regress to echoing the
# request and every other section would stay green.
mkdir -p "$TMP/mut-model/scripts"
ln -s "$REPO/evals" "$TMP/mut-model/evals"
ln -s "$REPO/.claude-plugin" "$TMP/mut-model/.claude-plugin"
python3 - "$RUNNER" "$TMP/mut-model/scripts/run-behavioural-eval.py" <<'PY'
import pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = src.read_text()
mutated = text.replace('"executor": observed_model(outcome["events"]),',
                       '"executor": model,')
assert mutated != text, "mutation target not found: the executor model recording moved"
dst.write_text(mutated)
PY
record_models "$TMP/mut-model/scripts/run-behavioural-eval.py" "$TMP/out-model-mut"
python3 -c "
import json
g=json.load(open('$TMP/out-model-mut/eval-case-model-0/with_skill/run-1/grading.json'))
assert g['models']['executor']=='requested-model-not-used', g['models']
" || fail "the request-echoing mutant did not reproduce the defect, so § 9 no longer proves the recording reads the stream"
pass

# ---------------------------------------------------------------------------
# 10. THE SESSION HAD THE SHAPE ITS CONFIGURATION CLAIMS.
# ---------------------------------------------------------------------------
# The defect these catch is the one this suite could not previously see: a
# with_skill leg that never loaded the plugin still produces a well-formed
# stream, makes tool calls, and scores. Four graded runs reported deltas between
# two configurations that were both the base model (#226), and nothing here went
# red, because "the plugin did not load" and "the plugin loaded and changed
# nothing" were indistinguishable to the runner.
#
# Each check gets a seeded defect AND a mutant runner with only that check
# removed, so a check that some other check incidentally covers cannot pass for
# load-bearing.

# A shadow root the runner will resolve REPO to. It needs evals/ for the
# fixtures and .claude-plugin/ because PLUGIN_NAME is read from the manifest.
make_mutant() {  # $1 = name, $2 = literal to replace, $3 = replacement
  local d="$TMP/mut-$1"
  rm -rf "$d"; mkdir -p "$d/scripts"
  ln -s "$REPO/evals" "$d/evals"
  ln -s "$REPO/.claude-plugin" "$d/.claude-plugin"
  MUT_OLD="$2" MUT_NEW="$3" python3 - "$RUNNER" "$d/scripts/run-behavioural-eval.py" <<'PY'
import os, pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = src.read_text()
mutated = text.replace(os.environ["MUT_OLD"], os.environ["MUT_NEW"])
# If the code is refactored the mutation stops reproducing the defect, and the
# case would pass while testing nothing. Fail loudly instead.
assert mutated != text, f"mutation target not found: {os.environ['MUT_OLD'][:70]!r}"
dst.write_text(mutated)
PY
  echo "$d/scripts/run-behavioural-eval.py"
}

# Print the execution_error of one leg (empty string when the run was accepted).
exec_error() {  # $1 = runner, $2 = plan, $3 = out dir, $4 = config
  rm -rf "$3"
  FAKE_PLAN="$2" BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
    python3 "$1" --case "$TMP/case/evals.json" --out "$3" \
      --configs "$4" --no-grade >/dev/null 2>&1
  python3 -c "
import json
g=json.load(open('$3/eval-case-0/$4/run-1/grading.json'))
print(g['execution_error'] or '')
assert g['execution_error'] is None or g['summary']['pass_rate']==0.0, g['summary']"
}

# A plan whose control leg behaves identically to its treatment leg — the exact
# null result the checks have to tell apart from a broken harness.
cat > "$TMP/plan-both-legs.json" <<EOF
{ "with_skill":    { "calls": [ { "tool": "glassfrog_create_tension",
      "args": { "role_id": "$SEC_ROLE", "body": "successor" } } ] },
  "without_skill": { "calls": [ { "tool": "glassfrog_create_tension",
      "args": { "role_id": "$SEC_ROLE", "body": "successor" } } ] } }
EOF

# Baseline: a well-shaped run of either leg is accepted.
for leg in with_skill without_skill; do
  E="$(exec_error "$RUNNER" "$TMP/plan-both-legs.json" "$TMP/out-shape-$leg" "$leg")"
  [ -z "$E" ] || fail "a well-shaped $leg run was rejected: $E"
done
pass

# 10a. No Skill tool — what `--bare` produced, and the whole of #226. The run
#      otherwise looks perfect: real tool calls, real writes, a scoreable
#      transcript. Only the init event says no skill could ever have fired.
export FAKE_NO_SKILL_TOOL=1
E="$(exec_error "$RUNNER" "$TMP/plan-both-legs.json" "$TMP/out-noskill" with_skill)"
case "$E" in
  *"no Skill tool"*) : ;;
  *) fail "a session with no Skill tool was accepted (error was: '$E')" ;;
esac
MUT="$(make_mutant noskill 'if "Skill" not in set(init.get("tools") or []):' 'if False:')"
E="$(exec_error "$MUT" "$TMP/plan-both-legs.json" "$TMP/out-noskill-mut" with_skill)"
[ -z "$E" ] || fail "the no-Skill-tool defect was caught by something other than its own check: $E"
unset FAKE_NO_SKILL_TOOL
pass

# 10b. --plugin-dir was passed and registered nothing. This is what makes
#      with_skill the base model while every artifact still looks healthy.
export FAKE_PLUGIN_NOT_LOADED=1
E="$(exec_error "$RUNNER" "$TMP/plan-both-legs.json" "$TMP/out-noload" with_skill)"
case "$E" in
  *"registered no ${PLUGIN_NS}:"*) : ;;
  *) fail "a with_skill run that loaded no plugin was accepted (error was: '$E')" ;;
esac
MUT="$(make_mutant noload '        if not registered:' '        if False:')"
E="$(exec_error "$MUT" "$TMP/plan-both-legs.json" "$TMP/out-noload-mut" with_skill)"
[ -z "$E" ] || fail "the plugin-not-loaded defect was caught by another check: $E"
unset FAKE_PLUGIN_NOT_LOADED
pass

# 10c. The mirror: the plugin present in a leg that is supposed to be without it.
#      An operator's globally-installed copy is the live route for this, which is
#      what --bare was originally protecting against and CLAUDE_CONFIG_DIR now does.
export FAKE_PLUGIN_LEAK=1
E="$(exec_error "$RUNNER" "$TMP/plan-both-legs.json" "$TMP/out-leak" without_skill)"
case "$E" in
  *"leaked into without_skill"*) : ;;
  *) fail "a control leg carrying the plugin was accepted (error was: '$E')" ;;
esac
MUT="$(make_mutant leak '    elif registered:' '    elif False:')"
E="$(exec_error "$MUT" "$TMP/plan-both-legs.json" "$TMP/out-leak-mut" without_skill)"
[ -z "$E" ] || fail "the plugin-leak defect was caught by another check: $E"
unset FAKE_PLUGIN_LEAK
pass

# 10d. No init event at all. Unlike the three above this one IS caught by 10a's
#      check as a side effect — an absent init has no tools either — so the
#      mutation proves something narrower and worth stating plainly: without
#      this branch the run still fails, but it is misdiagnosed as a missing
#      Skill tool rather than as an unverifiable session.
export FAKE_NO_INIT=1
E="$(exec_error "$RUNNER" "$TMP/plan-both-legs.json" "$TMP/out-noinit" with_skill)"
case "$E" in
  *"no init event"*) : ;;
  *) fail "a session with no init event was accepted (error was: '$E')" ;;
esac
MUT="$(make_mutant noinit '    if init is None:
        return ("the session emitted no init event' '    init = init or {}
    if False:
        return ("the session emitted no init event')"
E="$(exec_error "$MUT" "$TMP/plan-both-legs.json" "$TMP/out-noinit-mut" with_skill)"
case "$E" in
  *"no init event"*) fail "the no-init branch was removed but its message survived; the mutation is not reproducing the defect" ;;
  "") fail "with the no-init branch removed the run was accepted, so the message assertion above is the only thing standing between an unverifiable session and a green score" ;;
  *) : ;;
esac
unset FAKE_NO_INIT
pass

# 10e. The control reached the checkout on disk. Run-1 of graded run
#      31058151548 did exactly this — `find /` then `cat` — and scored 3/5 on
#      content it read off the filesystem rather than received from the plugin.
#      FAKE_READ_PATH is the runner's OWN repo root, so the mutant (whose REPO
#      is its shadow root) is tested against its own path, not this one.
export FAKE_READ_PATH="$REPO"
E="$(exec_error "$RUNNER" "$TMP/plan-both-legs.json" "$TMP/out-reach" without_skill)"
case "$E" in
  *"reached the plugin checkout on disk"*) : ;;
  *) fail "a control leg that read the checkout was accepted (error was: '$E')" ;;
esac
# Reading it in with_skill is how a skill loads its own references/ — legitimate.
E="$(exec_error "$RUNNER" "$TMP/plan-both-legs.json" "$TMP/out-reach-ok" with_skill)"
[ -z "$E" ] || fail "with_skill was penalised for reading the plugin's own files: $E"
MUT="$(make_mutant reach '    reached = contamination_error(events, config)' '    reached = None')"
# Point the fake at the MUTANT's own root: its REPO is the shadow dir, so a read
# of this checkout would not be contamination from its point of view anyway.
export FAKE_READ_PATH="$TMP/mut-reach"
E="$(exec_error "$MUT" "$TMP/plan-both-legs.json" "$TMP/out-reach-mut" without_skill)"
[ -z "$E" ] || fail "the filesystem-reach defect was caught by another check: $E"
unset FAKE_READ_PATH
pass

# ---------------------------------------------------------------------------
# 11. THE SESSION-SHAPE PREFLIGHT, under --validate-only.
# ---------------------------------------------------------------------------
# § 10's checks only fire once a graded run is under way. The preflight moves
# the same three questions to the cheapest tier there is: the CLI emits its init
# event BEFORE it authenticates, so an operator with no API key still learns
# whether a Skill tool exists and whether --plugin-dir registered anything.
# #226 cost four graded runs and an artifact download to notice, and every fact
# needed to spot it was available for free, at session start, on any laptop.
validate() {  # $1 = runner, rest = extra args; prints the session-shape lines
  FAKE_PLAN="$TMP/plan-both-legs.json" BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
    python3 "$1" --case "$TMP/case/evals.json" --out "$TMP/out-validate" \
      --validate-only "${@:2}" 2>&1 | grep "session shape" || true
}
validate_rc() {  # $1 = runner, rest = extra args; prints the exit code
  FAKE_PLAN="$TMP/plan-both-legs.json" BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
    python3 "$1" --case "$TMP/case/evals.json" --out "$TMP/out-validate" \
      --validate-only "${@:2}" >/dev/null 2>&1
  echo $?
}

V="$(validate "$RUNNER")"
echo "$V" | grep -q "ok   session shape \[with_skill\]" \
  || { echo "$V"; fail "the preflight did not report a healthy with_skill session"; }
echo "$V" | grep -q "ok   session shape \[without_skill\]" \
  || { echo "$V"; fail "the preflight did not report a healthy without_skill session"; }
[ "$(validate_rc "$RUNNER")" = "0" ] || fail "a healthy preflight did not exit 0"
pass

# 11a. The #226 configuration itself. This is the assertion that would have
#      stopped the whole defect at the preflight, for free.
export FAKE_NO_SKILL_TOOL=1
V="$(validate "$RUNNER")"
echo "$V" | grep -q "FAIL session shape" \
  || { echo "$V"; fail "the preflight passed a session with no Skill tool"; }
[ "$(validate_rc "$RUNNER")" = "1" ] || fail "a failed preflight did not exit non-zero"
# Mutation: drop the preflight and the defect is invisible until a graded run.
MUT="$(make_mutant preflight '    if args.validate_only and not args.no_session_probe:' '    if False:')"
[ "$(validate_rc "$MUT")" = "0" ] \
  || fail "the no-Skill-tool defect was caught under --validate-only by something other than the preflight"
unset FAKE_NO_SKILL_TOOL
pass

# 11b. --plugin-dir registering nothing is the preflight's other question, and
#      it is asymmetric: only the treatment leg can fail it.
export FAKE_PLUGIN_NOT_LOADED=1
V="$(validate "$RUNNER")"
echo "$V" | grep -q "FAIL session shape \[with_skill\]" \
  || { echo "$V"; fail "the preflight passed a with_skill session that loaded no plugin"; }
echo "$V" | grep -q "ok   session shape \[without_skill\]" \
  || { echo "$V"; fail "the control leg was failed for an absence that is its whole point"; }
unset FAKE_PLUGIN_NOT_LOADED
pass

# 11c. The escape hatch has to actually skip it — a preflight that cannot be
#      turned off is one that gets deleted the first time `claude` is not on PATH.
export FAKE_NO_SKILL_TOOL=1
V="$(validate "$RUNNER" --no-session-probe)"
[ -z "$V" ] || { echo "$V"; fail "--no-session-probe still ran the session probe"; }
[ "$(validate_rc "$RUNNER" --no-session-probe)" = "0" ] \
  || fail "--no-session-probe did not skip the failing probe"
unset FAKE_NO_SKILL_TOOL
pass

# ---------------------------------------------------------------------------
# 12. THE TWO ARMS MUST HAVE RUN ON THE SAME EXECUTOR MODEL.
# ---------------------------------------------------------------------------
# A delta between arms that ran on different models is a fact about the models.
# Graded run 31229964963 answered all 12 with_skill executions with
# claude-opus-5[1m] and all 12 without_skill executions with claude-haiku-4-5,
# reported +0.13 in the plugin's favour, and every artifact looked healthy —
# benchmark.json records executor_model as a comma-joined string, so even a
# careful reader sees "two models" only if they think to ask. The loop runs
# with_skill first for every eval, so the bias has a fixed direction.
both_configs() {  # $1 = runner, $2 = out dir; prints the exit code
  rm -rf "$2"
  FAKE_PLAN="$TMP/plan-both-legs.json" BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude" \
    python3 "$1" --case "$TMP/case/evals.json" --out "$2" \
      --configs with_skill,without_skill --no-grade >/dev/null 2>"$TMP/both.err"
  echo $?
}

# One model across both arms is the healthy case.
[ "$(both_configs "$RUNNER" "$TMP/out-samemodel")" = "0" ] \
  || { cat "$TMP/both.err"; fail "a run whose arms shared an executor model was rejected"; }
python3 -c "
import json
m=json.load(open('$TMP/out-samemodel/run_metadata.json'))['executor_models_by_config']
assert sorted(m)==['with_skill','without_skill'], m
assert m['with_skill']==m['without_skill']==['fake-executor-model'], m
" || fail "run_metadata did not record the per-config executor models"
pass

# Mutation: split the model along the configuration, exactly as the live run did.
export FAKE_SPLIT_MODEL=1
# Spelled as an explicit `if`: `A && B || C` is not if-then-else (SC2015), and C
# would also run when A holds and B does not — the same shellcheck note § 8
# already carries a comment about.
SPLIT_RC="$(both_configs "$RUNNER" "$TMP/out-splitmodel")"
if [ "$SPLIT_RC" = "0" ] \
   || ! grep -q "did not run on the same executor model" "$TMP/both.err"; then
  cat "$TMP/both.err"
  fail "a run whose arms used different executor models was accepted (exit $SPLIT_RC)"
fi
# The evidence has to survive the failure — a run that fails here has still done
# all of its work, and the record is what makes the failure actionable.
python3 -c "
import json
m=json.load(open('$TMP/out-splitmodel/run_metadata.json'))['executor_models_by_config']
assert m['with_skill']==['fake-executor-model'], m
assert m['without_skill']==['fake-control-model'], m
" || fail "run_metadata was not written for a run that failed the same-model check"
MUT="$(make_mutant samemodel '        if len(distinct) > 1:' '        if False:')"
[ "$(both_configs "$MUT" "$TMP/out-splitmodel-mut")" = "0" ] \
  || fail "the split-model defect was caught by something other than its own check"
unset FAKE_SPLIT_MODEL
pass

# ---------------------------------------------------------------------------
# 13. CACHE KEY COMPUTATION (U1) -- compute_cache_key hashes exactly R1's nine
#     declared inputs and nothing else silently.
#
# This runs entirely against a SYNTHETIC mini-repo under $TMP, not against
# this checkout, so each of the nine inputs can be mutated one at a time
# without touching (or restoring) a real file. discover_shared_references is
# exercised through two citing files -- the skill's SKILL.md and a
# references/ file one level deeper -- because that asymmetry is the exact
# failure mode skills-lint.sh check 1 exists to catch (CLAUDE.md: nine broken
# shared-file load paths shipped to main once already under a looser
# resolver); a cache key that only discovered SKILL.md's own citations would
# silently under-hash a skill whose references/ file cites shared content the
# version-bump check (check 4) cannot see either.
# ---------------------------------------------------------------------------
python3 - "$RUNNER" <<'PY' || fail "compute_cache_key did not behave as required"
import pathlib, shutil, sys, tempfile

spec_path = sys.argv[1]
import importlib.util
spec = importlib.util.spec_from_file_location("runner", spec_path)
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

# KTD2: this is the ONE canonical enumeration a later completeness check (R7,
# not built in this unit) will assert against. Fixed exactly, in this order
# by convention -- a drift here is a drift in the contract itself, not a
# behavioural finding this suite should silently absorb.
assert list(runner.CACHE_KEY_INPUT_CLASSES) == [
    "skills/**", "skills/shared/**", "evals/cases/**", "evals/stub/**",
    "scripts/run-behavioural-eval.py",
], runner.CACHE_KEY_INPUT_CLASSES

def build_repo(root):
    """One skill, two shared files -- one cited from SKILL.md, one cited only
    from a references/ file one level deeper -- a stub, a runner script and a
    fixture: every file compute_cache_key reads."""
    skill_dir = root / "skills" / "my-skill"
    (skill_dir / "references").mkdir(parents=True)
    (root / "skills" / "shared").mkdir(parents=True)
    (root / "evals" / "stub").mkdir(parents=True)
    (root / "evals" / "fixtures" / "glassfrog").mkdir(parents=True)
    (root / "scripts").mkdir(parents=True)

    (root / "skills" / "shared" / "shared-a.md").write_text("shared A v1\n")
    (root / "skills" / "shared" / "shared-b.md").write_text("shared B v1\n")
    (skill_dir / "SKILL.md").write_text(
        "---\nname: my-skill\ndescription: d\nstatus: active\nversion: 1.0.0\n---\n"
        "Loads `../shared/shared-a.md` directly.\n")
    (skill_dir / "references" / "deep.md").write_text(
        "Loads `../../shared/shared-b.md`, one level deeper than SKILL.md.\n")
    (root / "evals" / "stub" / "glassfrog_stub.py").write_text("# stub v1\n")
    (root / "scripts" / "run-behavioural-eval.py").write_text("# runner v1\n")
    (root / "evals" / "fixtures" / "glassfrog" / "fixture.json").write_text('{"v":1}\n')
    return skill_dir

def key_for(root, skill_dir, **overrides):
    case = overrides.pop("case", {"eval_id": 0, "prompt": "p"})
    kwargs = dict(
        case=case,
        skill_dirs=[skill_dir],
        fixture_path=root / "evals" / "fixtures" / "glassfrog" / "fixture.json",
        stub_path=root / "evals" / "stub" / "glassfrog_stub.py",
        runner_path=root / "scripts" / "run-behavioural-eval.py",
        repo=root,
        runs=1,
        model="claude-model-x",
        cli_version="2.1.0",
    )
    kwargs.update(overrides)
    return runner.compute_cache_key(**kwargs)

base = pathlib.Path(tempfile.mkdtemp(prefix="cachekey-"))
try:
    skill_dir = build_repo(base)

    baseline = key_for(base, skill_dir)
    assert key_for(base, skill_dir) == baseline, "identical inputs produced different keys"

    # 1. case file content
    assert key_for(base, skill_dir, case={"eval_id": 0, "prompt": "DIFFERENT"}) != baseline, \
        "changing the case content did not change the key"

    # 2. the skill's declared version: field
    skill_md = skill_dir / "SKILL.md"
    skill_md.write_text(skill_md.read_text().replace("version: 1.0.0", "version: 1.0.1"))
    assert key_for(base, skill_dir) != baseline, \
        "changing the skill's declared version did not change the key"
    skill_md.write_text(skill_md.read_text().replace("version: 1.0.1", "version: 1.0.0"))
    assert key_for(base, skill_dir) == baseline, "restoring the version did not restore the key"

    # 3. a skills/shared/ file cited directly from SKILL.md, version: UNCHANGED
    #    -- the whole point of R1: check 4 excludes skills/shared/ from its
    #    diff, so the version field alone is not a proxy for shared-file drift.
    shared_a = base / "skills" / "shared" / "shared-a.md"
    shared_a.write_text("shared A v2 -- EDITED\n")
    assert key_for(base, skill_dir) != baseline, \
        "editing a skills/shared/ file did not change the key even though " \
        "the skill's version: field was left untouched"
    shared_a.write_text("shared A v1\n")
    assert key_for(base, skill_dir) == baseline, "restoring the shared file did not restore the key"

    # 3b. the file cited only from references/deep.md, one level deeper than
    #     SKILL.md -- the historical failure mode skills-lint.sh check 1 was
    #     built to catch.
    shared_b = base / "skills" / "shared" / "shared-b.md"
    shared_b.write_text("shared B v2 -- EDITED\n")
    assert key_for(base, skill_dir) != baseline, \
        "editing a shared file cited only from a references/ file (one " \
        "level deeper than SKILL.md) did not change the key -- discovery " \
        "is not walking references/"
    shared_b.write_text("shared B v1\n")
    assert key_for(base, skill_dir) == baseline

    # 4. fixture hash
    fixture = base / "evals" / "fixtures" / "glassfrog" / "fixture.json"
    fixture.write_text('{"v":2}\n')
    assert key_for(base, skill_dir) != baseline, "changing the fixture did not change the key"
    fixture.write_text('{"v":1}\n')
    assert key_for(base, skill_dir) == baseline

    # 5. the harness's own execution/grading script
    runner_file = base / "scripts" / "run-behavioural-eval.py"
    runner_file.write_text("# runner v2 -- EDITED\n")
    assert key_for(base, skill_dir) != baseline, \
        "editing run-behavioural-eval.py did not change the key"
    runner_file.write_text("# runner v1\n")
    assert key_for(base, skill_dir) == baseline

    # 5b. eval-report.py is a post-hoc renderer that never runs during
    #     execution or grading, so it must play NO part in the key -- an edit
    #     to a same-directory file by that name must not move it.
    (base / "scripts" / "eval-report.py").write_text("# report v2 -- irrelevant\n")
    assert key_for(base, skill_dir) == baseline, \
        "an eval-report.py-only edit changed the key, but that script " \
        "never runs during execution or grading"

    # 6. runs
    assert key_for(base, skill_dir, runs=2) != baseline, "changing runs did not change the key"

    # 7. model id
    assert key_for(base, skill_dir, model="claude-model-y") != baseline, \
        "changing the model id did not change the key"
    assert key_for(base, skill_dir, model=None) != baseline, \
        "a None model produced the same key as a named model"

    # 8. stub hash
    stub = base / "evals" / "stub" / "glassfrog_stub.py"
    stub.write_text("# stub v2 -- EDITED\n")
    assert key_for(base, skill_dir) != baseline, "changing the stub did not change the key"
    stub.write_text("# stub v1\n")
    assert key_for(base, skill_dir) == baseline

    # 9. the invoked CLI binary's version
    assert key_for(base, skill_dir, cli_version="2.2.0") != baseline, \
        "changing the CLI version did not change the key"

    # A leg with no relevant skill (e.g. a without_skill control leg) is a
    # valid input, not an error -- it just contributes no skill_versions or
    # shared_refs to the key.
    empty_skill_key = runner.compute_cache_key(
        case={"eval_id": 0, "prompt": "p"}, skill_dirs=[],
        fixture_path=base / "evals" / "fixtures" / "glassfrog" / "fixture.json",
        stub_path=base / "evals" / "stub" / "glassfrog_stub.py",
        runner_path=base / "scripts" / "run-behavioural-eval.py",
        repo=base, runs=1, model=None, cli_version="2.1.0")
    assert empty_skill_key != baseline, \
        "a leg with no skill_dirs produced the same key as one with a skill"
finally:
    shutil.rmtree(base, ignore_errors=True)

print("compute_cache_key: all nine inputs independently discriminating; "
      "shared-file discovery walks references/; CACHE_KEY_INPUT_CLASSES intact")
PY
pass

# ---------------------------------------------------------------------------
# 14. CACHE INDEX SKIP/EXECUTE DECISION (U2 + U3) -- the change-aware skip
#     wrapped around the per-config loop in main(), and its bounded lifetime.
#
# These run the REAL main() loop (not just compute_cache_key in isolation)
# against a "cache root" that mirrors this checkout closely enough for
# resolve_skill_dirs_for_leg and discover_shared_references to see the real
# shipped skills, but with its OWN copy of skills/ so one skill's version can
# be bumped without touching this checkout's actual files. evals/ and
# .claude-plugin/ are symlinked (their content does not need to be mutated),
# and scripts/run-behavioural-eval.py is a plain copy of $RUNNER so its own
# REPO constant resolves inside the cache root -- the same technique § 10's
# make_mutant uses, extended to also copy skills/ rather than leave it absent.
# ---------------------------------------------------------------------------
CACHE_ROOT="$TMP/cache-root"
mkdir -p "$CACHE_ROOT/scripts"
cp "$RUNNER" "$CACHE_ROOT/scripts/run-behavioural-eval.py"
ln -s "$REPO/evals" "$CACHE_ROOT/evals"
ln -s "$REPO/.claude-plugin" "$CACHE_ROOT/.claude-plugin"
cp -R "$REPO/skills" "$CACHE_ROOT/skills"
CACHE_RUNNER="$CACHE_ROOT/scripts/run-behavioural-eval.py"
# Fixed and matched by the "--version" branch added to fake-claude.py above --
# claude_cli_version() is one of the nine inputs compute_cache_key hashes, so
# the test's own key computation and the runner's must agree on it exactly.
CLI_VERSION="2.5.0 (Claude Code)"

# Computes the SAME key main() will compute for (case, config) in a cache
# root, using the runner's own resolve_skill_dirs_for_leg + compute_cache_key
# rather than recomputing the logic by hand -- the whole point is to prove
# the runner's internal decision, not a parallel guess at it.
cache_key_for() {  # $1=cache_root $2=case_file $3=eval_id $4=config $5=runs $6=model(or "") $7=cli_version
  python3 - "$@" <<'PY'
import importlib.util, json, pathlib, sys
cache_root, case_file, eval_id, config, runs, model, cli_version = sys.argv[1:8]
spec = importlib.util.spec_from_file_location(
    "cache_runner", pathlib.Path(cache_root) / "scripts" / "run-behavioural-eval.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
doc = json.load(open(case_file))
case = next(c for c in doc["evals"] if str(c["eval_id"]) == str(eval_id))
skill_dirs = runner.resolve_skill_dirs_for_leg(config, repo=pathlib.Path(cache_root))
fixture_path = pathlib.Path(cache_root) / case["fixture"]
print(runner.compute_cache_key(
    case=case, skill_dirs=skill_dirs, fixture_path=fixture_path,
    runs=int(runs), model=(model or None), cli_version=cli_version))
PY
}

# Seeds one entry into a cache index file, creating it if absent. The stored
# "grading" is deliberately minimal -- only the fields cache_entry_is_usable
# and record_leg_bookkeeping actually read (summary, models, execution_error)
# -- matching the plan's "keep it simple" instruction for the index schema.
seed_cache_index() {  # $1=index_path $2=key $3=last_executed $4=successful(true|false) $5=eval_name $6=config $7=executor_model $8=passed $9=total
  python3 - "$@" <<'PY'
import json, sys
path, key, last_executed, successful, eval_name, config, executor_model, passed, total = sys.argv[1:10]
try:
    idx = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError):
    idx = {}
passed_i, total_i = int(passed), int(total)
idx[key] = {
    "last_executed": last_executed,
    "successful": successful == "true",
    "grading": {
        "eval_name": eval_name,
        "config": config,
        "models": {"requested": None, "executor": executor_model, "analyzer": None},
        "expectations": [],
        "summary": {"passed": passed_i, "failed": total_i - passed_i, "total": total_i,
                    "pass_rate": (passed_i / total_i) if total_i else 0.0},
        "execution_metrics": {}, "timing": {}, "execution_error": None,
        "cache_hit": True,
    },
    "case": eval_name,
    "config": config,
}
with open(path, "w") as f:
    json.dump(idx, f, indent=2)
PY
}

# Runs the cache root's runner over the clean plan (§ 1's plan-clean.json --
# it satisfies every mechanical check, so a leg that DOES execute is a leg
# that passes cleanly rather than one whose result is incidentally a fresh
# defect). Logs every CLI invocation to $TMP/cache-invoke.log and captures
# stdout/stderr for the caller to inspect; prints the exit code.
run_cache() {  # $1=out_dir $2=index_path $3=now rest=extra args
  local out="$1" idx="$2" now="$3"; shift 3
  rm -rf "$out"
  : > "$TMP/cache-invoke.log"
  CACHE_INVOKE_LOG="$TMP/cache-invoke.log" FAKE_PLAN="$TMP/plan-clean.json" \
    BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/fake-claude-logged" \
    python3 "$CACHE_RUNNER" --case "$TMP/case/evals.json" --out "$out" \
      --configs with_skill --no-grade --cache-index "$idx" --now "$now" "$@" \
      >"$TMP/cache-run.out" 2>"$TMP/cache-run.err"
  echo $?
}

NOW="2026-08-17T00:00:00+00:00"
CACHE_KEY_WS="$(cache_key_for "$CACHE_ROOT" "$TMP/case/evals.json" 0 with_skill 1 "" "$CLI_VERSION")"

# 14a (AE1). A fresh, successful entry under the leg's CURRENT key is reused:
#     the CLI is invoked exactly once (the --version probe used to compute
#     the key -- never a real session or grading call), run_dir is never
#     created, and the stored result feeds run_metadata.json exactly as a
#     fresh execution's would.
seed_cache_index "$TMP/idx-hit.json" "$CACHE_KEY_WS" \
  "2026-08-16T00:00:00+00:00" true "mechanical-checks" with_skill \
  "stored-executor-model" 4 4
RC="$(run_cache "$TMP/out-cache-hit" "$TMP/idx-hit.json" "$NOW")"
[ "$RC" = "0" ] || { cat "$TMP/cache-run.err"; fail "a cache-hit run did not exit 0"; }
[ -d "$TMP/out-cache-hit/eval-case-0/with_skill" ] \
  && fail "a skipped leg created its run_dir"
grep -q "cache hit" "$TMP/cache-run.out" \
  || { cat "$TMP/cache-run.out"; fail "a cache-hit run did not report a cache hit"; }
INVOCATIONS="$(wc -l < "$TMP/cache-invoke.log" | tr -d ' ')"
[ "$INVOCATIONS" = "1" ] \
  || { cat "$TMP/cache-invoke.log"; fail "expected exactly one CLI invocation (the --version probe) on a cache hit, got $INVOCATIONS"; }
grep -q -- "--version" "$TMP/cache-invoke.log" \
  || { cat "$TMP/cache-invoke.log"; fail "the one invocation on a cache hit was not the --version probe"; }
python3 -c "
import json
m = json.load(open('$TMP/out-cache-hit/run_metadata.json'))
assert m['executor_models'] == ['stored-executor-model'], m
assert m['executor_models_by_config']['with_skill'] == ['stored-executor-model'], m
" || fail "a cache-hit leg's stored result did not feed run_metadata.json"
pass

# 14b (AE2). Bumping a shipped skill's version: changes the computed key
#     (proving the leg's cache key really is sensitive to it, same as § 13's
#     unit-level proof, but now observed through the whole main() loop), so
#     an entry seeded under the OLD (pre-bump) key is a miss under the new
#     one. The leg executes fresh, and a new entry lands under the CURRENT
#     key; the superseded old entry is left in place rather than deleted --
#     only the key that matters now is the one main() looks up.
FACILITATOR_SKILL_MD="$CACHE_ROOT/skills/holacracy-facilitator/SKILL.md"
cp "$FACILITATOR_SKILL_MD" "$TMP/facilitator-SKILL.md.orig"
python3 - "$FACILITATOR_SKILL_MD" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
bumped = re.sub(r'^version:\s*[0-9]+\.[0-9]+\.[0-9]+\s*$', 'version: 99.0.0',
                text, count=1, flags=re.MULTILINE)
assert bumped != text, "no version: field found to bump"
open(path, "w").write(bumped)
PY
CACHE_KEY_WS_BUMPED="$(cache_key_for "$CACHE_ROOT" "$TMP/case/evals.json" 0 with_skill 1 "" "$CLI_VERSION")"
[ "$CACHE_KEY_WS_BUMPED" != "$CACHE_KEY_WS" ] \
  || fail "bumping a shipped skill's version did not change the computed cache key"

seed_cache_index "$TMP/idx-bumped.json" "$CACHE_KEY_WS" \
  "2026-08-16T00:00:00+00:00" true "mechanical-checks" with_skill \
  "stale-executor-model" 4 4
RC="$(run_cache "$TMP/out-cache-bumped" "$TMP/idx-bumped.json" "$NOW")"
[ "$RC" = "0" ] || { cat "$TMP/cache-run.err"; fail "a post-bump execution did not exit 0"; }
grep -q "cache hit" "$TMP/cache-run.out" \
  && { cat "$TMP/cache-run.out"; fail "a leg whose skill version bumped was skipped as a cache hit"; }
[ -f "$TMP/out-cache-bumped/eval-case-0/with_skill/run-1/grading.json" ] \
  || fail "a leg whose cache key changed did not execute (no grading.json written)"
python3 -c "
import json
g = json.load(open('$TMP/out-cache-bumped/eval-case-0/with_skill/run-1/grading.json'))
assert g['cache_hit'] is False, g
idx = json.load(open('$TMP/idx-bumped.json'))
assert idx['$CACHE_KEY_WS_BUMPED']['successful'] is True, idx.get('$CACHE_KEY_WS_BUMPED')
assert '$CACHE_KEY_WS' in idx, 'the superseded entry under the old key should not be deleted'
" || fail "the cache index was not updated correctly after a key-changing execution"
cp "$TMP/facilitator-SKILL.md.orig" "$FACILITATOR_SKILL_MD"
CACHE_KEY_WS_RESTORED="$(cache_key_for "$CACHE_ROOT" "$TMP/case/evals.json" 0 with_skill 1 "" "$CLI_VERSION")"
[ "$CACHE_KEY_WS_RESTORED" = "$CACHE_KEY_WS" ] \
  || fail "restoring the bumped skill's version did not restore the original cache key"
pass

# 14c (AE6). An entry under the CURRENT key whose stored result was NOT
#     successful is not reused, however fresh it is -- the leg executes
#     again, and the index is updated with the new (successful) outcome.
seed_cache_index "$TMP/idx-unsuccessful.json" "$CACHE_KEY_WS" \
  "$NOW" false "mechanical-checks" with_skill "stale-executor-model" 0 4
RC="$(run_cache "$TMP/out-cache-unsuccessful" "$TMP/idx-unsuccessful.json" "$NOW")"
[ "$RC" = "0" ] || { cat "$TMP/cache-run.err"; fail "execution of an unsuccessful-entry leg did not exit 0"; }
grep -q "cache hit" "$TMP/cache-run.out" \
  && { cat "$TMP/cache-run.out"; fail "a leg with an unsuccessful stored entry was skipped as a cache hit"; }
[ -f "$TMP/out-cache-unsuccessful/eval-case-0/with_skill/run-1/grading.json" ] \
  || fail "a leg with an unsuccessful stored entry did not execute"
python3 -c "
import json
idx = json.load(open('$TMP/idx-unsuccessful.json'))
assert idx['$CACHE_KEY_WS']['successful'] is True, idx['$CACHE_KEY_WS']
" || fail "the unsuccessful entry was not replaced with a successful one after re-execution"
pass

# 14d (AE5 / U3's bounded lifetime). An entry under the CURRENT key that IS
#     successful but 8 nights old is stale and executes again -- the ceiling
#     a static key alone would never enforce.
seed_cache_index "$TMP/idx-stale.json" "$CACHE_KEY_WS" \
  "2026-08-09T00:00:00+00:00" true "mechanical-checks" with_skill \
  "stale-executor-model" 4 4
RC="$(run_cache "$TMP/out-cache-stale" "$TMP/idx-stale.json" "$NOW")"
[ "$RC" = "0" ] || { cat "$TMP/cache-run.err"; fail "execution of a stale-entry leg did not exit 0"; }
grep -q "cache hit" "$TMP/cache-run.out" \
  && { cat "$TMP/cache-run.out"; fail "an 8-night-old entry was reused as a cache hit"; }
[ -f "$TMP/out-cache-stale/eval-case-0/with_skill/run-1/grading.json" ] \
  || fail "a leg with a stale stored entry did not execute"
pass

# 14e. The mirror of 14d: an entry only 3 nights old, well inside the
#     7-night default, still skips.
seed_cache_index "$TMP/idx-fresh3.json" "$CACHE_KEY_WS" \
  "2026-08-14T00:00:00+00:00" true "mechanical-checks" with_skill \
  "stored-executor-model" 4 4
RC="$(run_cache "$TMP/out-cache-fresh3" "$TMP/idx-fresh3.json" "$NOW")"
[ "$RC" = "0" ] || { cat "$TMP/cache-run.err"; fail "a 3-night-old cache hit did not exit 0"; }
grep -q "cache hit" "$TMP/cache-run.out" \
  || { cat "$TMP/cache-run.out"; fail "a 3-night-old entry was not reused"; }
[ -d "$TMP/out-cache-fresh3/eval-case-0/with_skill" ] \
  && fail "a skipped (3-night-old) leg created its run_dir"
pass

# 14f. cache_entry_is_usable itself, at the boundary --the CLI-level tests
#     above prove the loop wires it in correctly; this proves the ceiling is
#     exactly 7 days rather than "roughly a week", including the exact-7
#     boundary none of the CLI-level cases above exercises.
python3 - "$CACHE_RUNNER" <<'PY' || fail "cache_entry_is_usable did not behave as required"
import importlib.util, sys
from datetime import datetime, timedelta, timezone

spec = importlib.util.spec_from_file_location("cache_runner_unit", sys.argv[1])
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

now = datetime(2026, 8, 17, tzinfo=timezone.utc)

def usable(**overrides):
    entry = {"successful": True,
             "last_executed": (now - timedelta(days=1)).isoformat()}
    entry.update(overrides)
    return runner.cache_entry_is_usable(entry, now=now, max_age_days=7)

assert runner.cache_entry_is_usable(None, now=now, max_age_days=7) is False, \
    "no entry must never be usable"
assert usable(successful=False) is False, "an unsuccessful entry must never be usable"
assert usable(last_executed=None) is False, "a missing last_executed must not be usable"
assert usable(last_executed="not-a-timestamp") is False, \
    "an unparseable last_executed must not be usable (and must not raise)"
assert usable(last_executed=(now - timedelta(days=6, hours=23)).isoformat()) is True, \
    "an entry just under 7 days old must be usable"
assert usable(last_executed=(now - timedelta(days=7)).isoformat()) is False, \
    "an entry exactly 7 days old must force re-execution (R8: at least once every 7 nights)"
assert usable(last_executed=(now - timedelta(days=8)).isoformat()) is False, \
    "an entry 8 days old must not be usable"
# A naive (timezone-unaware) ISO string, as a hand-edited index might carry,
# must be treated as UTC rather than raising or comparing wrong.
naive = (now - timedelta(days=1)).replace(tzinfo=None).isoformat()
assert usable(last_executed=naive) is True, \
    "a timezone-naive last_executed must be treated as UTC, not rejected"

print("cache_entry_is_usable: R3-R6 and R8's 7-day boundary all hold")
PY
pass

# 14g. --validate-only stays entirely independent of the cache index -- even
#     one pointed at a bogus, nonexistent `claude` binary must not make
#     --validate-only fail, because claude_cli_version() (the only thing that
#     would invoke it) is gated on `not args.validate_only` and so is never
#     reached from this path (R5).
rm -f "$TMP/idx-should-not-be-touched.json"
V_RC=0
BEHAVIOURAL_EVAL_CLAUDE_BIN="$TMP/does-not-exist-claude" python3 "$CACHE_RUNNER" \
  --case "$TMP/case/evals.json" --out "$TMP/out-cache-validate" \
  --validate-only --no-session-probe \
  --cache-index "$TMP/idx-should-not-be-touched.json" \
  >"$TMP/cache-validate.out" 2>&1 || V_RC=$?
[ "$V_RC" = "0" ] \
  || { cat "$TMP/cache-validate.out"; fail "--validate-only with --cache-index failed, even though the cache path should never be reached"; }
[ -f "$TMP/idx-should-not-be-touched.json" ] \
  && fail "--validate-only wrote to the cache index; it must never touch it"
pass

echo "run-behavioural-eval.test.sh: $CASES cases passed"
