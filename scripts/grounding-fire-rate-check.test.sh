#!/usr/bin/env bash
# Regression tests for scripts/grounding-fire-rate-check.sh.
#
# Run: bash scripts/grounding-fire-rate-check.test.sh
# No framework -- plain asserts. Exits non-zero on first failure.
#
# The check is operator-local (it reads ~/.claude/projects, which no CI runner
# has), so this suite is what runs in CI. Most sections drive it through
# --readout-json fixtures; section 9 exercises the real wiring to
# grounding-readout.sh end to end, because a fixture cannot catch a renamed
# JSON key and that rename would make the check report a permanent zero.
#
# Every section pins a way this alarm could go quietly wrong. An alarm nobody
# has ever seen fire is the same fail-silent shape issue #122 is about.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/grounding-fire-rate-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# Write a readout-shaped fixture. Defaults give a healthy window.
mkfixture() {  # mkfixture PATH SESSIONS FIRED [VERSIONS_JSON] [UNSTAMPED]
  local path="$1" sessions="$2" fired="$3"
  local versions="${4:-{\"0.12.0\": $3\}}" unstamped="${5:-0}"
  cat > "$path" <<EOF
{"sessions": $sessions,
 "directive_fired": {"count": $fired},
 "plugin_versions_seen": $versions,
 "sessions_without_plugin_version": $unstamped}
EOF
}

run() { bash "$SCRIPT" --dry-run "$@"; }

# 1. Clear path: a healthy window exits 0 and says so.
mkfixture "$TMP/healthy.json" 40 40
out="$(run --readout-json "$TMP/healthy.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "a healthy window should exit 0, got $rc: $out"
echo "$out" | grep -q '^Clear' || fail "expected a Clear line; got: $out"
echo "$out" | grep -q '0.12.0 (40)' || fail "expected the versions seen in the clear output; got: $out"

# 2. Below the floor: exits 1 AND prints the report. The non-zero exit alone is
#    not the alarm -- the report is what a human reads.
mkfixture "$TMP/collapsed.json" 100 3 '{"0.6.0": 2}' 98
out="$(run --readout-json "$TMP/collapsed.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "a collapsed rate should exit 1, got $rc: $out"
echo "$out" | grep -q 'grounding-fire-rate-check:v1' || fail "expected the idempotency marker in the report; got: $out"
echo "$out" | grep -q '3 of 100' || fail "expected the counts in the report; got: $out"

# 3. The alarm names which plugin versions ran, including the unstamped count.
#    This is the whole reason #153 stamped the version: in #122 the collapse and
#    the stale copy were the same fact, and finding that took archaeology across
#    three install channels. An alarm that omits it sends the reader back there.
echo "$out" | grep -q '0.6.0 (2)' || fail "expected the stale version in the alarm body; got: $out"
echo "$out" | grep -q 'no version stamp (98)' || fail "expected the unstamped count in the alarm body; got: $out"

# 4. The alarm must steer AWAY from whole-file grep. That one-liner returned 10
#    files against a true 3 on 2026-08-03 and produced the false 2.2% this
#    issue was originally filed on; an alarm that invites it re-runs the bug.
echo "$out" | grep -q 'Do not diagnose this with' || fail "expected the grep warning in the alarm body; got: $out"
echo "$out" | grep -q 'since-start' || fail "expected a pointer to the correct instrument; got: $out"

# 5. The floor boundary is STRICTLY below. Exactly at the floor is clear.
#    Pinned in both directions so a later `<=` cannot slip in unnoticed: an
#    off-by-one here either cries wolf every week or never fires at all.
mkfixture "$TMP/exact.json" 100 90         # rate 0.90 == floor 0.9
out="$(run --readout-json "$TMP/exact.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "a rate exactly at the floor must be clear, got $rc: $out"

mkfixture "$TMP/justunder.json" 100 89     # rate 0.89 < floor 0.9
out="$(run --readout-json "$TMP/justunder.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "a rate just under the floor must alarm, got $rc: $out"

# 6. Under-powered: too few sessions to judge. Exits 0, but SAYS SO. A quiet
#    exit 0 on n=3 would read as "healthy" on evidence that cannot support it
#    -- and n=5 supporting no conclusion is exactly what stalled this PDCA.
mkfixture "$TMP/thin.json" 3 1
out="$(run --readout-json "$TMP/thin.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "an under-powered window should exit 0, got $rc: $out"
echo "$out" | grep -q 'NO VERDICT' || fail "an under-powered window must say so out loud; got: $out"
echo "$out" | grep -q 'not decidable' || fail "expected an explicit non-verdict; got: $out"
# and it must NOT claim to be clear
echo "$out" | grep -q '^Clear' && fail "an under-powered window must not report Clear: $out"

# 7. An EMPTY window exits 2, not 0. Reporting "clear" over zero sessions is a
#    pass on no evidence -- the failure mode of this whole issue wearing a
#    different hat. Nothing to measure is an operational failure, not health.
mkfixture "$TMP/empty.json" 0 0 '{}' 0
out="$(run --readout-json "$TMP/empty.json" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "an empty window must exit 2, got $rc: $out"
echo "$out" | grep -qi 'nothing to measure' || fail "expected an explicit nothing-to-measure error; got: $out"

# 8. --dry-run must run without gh or jq on PATH. If it could not, the alarm
#    path would be unexercisable in CI, and an alarm nobody has ever seen fire
#    is precisely what this script exists to prevent.
bare="$(command -v python3)"; bare="$(dirname "$bare")"
out="$(env -i PATH="$bare:/usr/bin:/bin" HOME="$TMP" bash "$SCRIPT" --dry-run \
        --readout-json "$TMP/collapsed.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "--dry-run must work without gh/jq (exit 1 on alarm), got $rc: $out"
echo "$out" | grep -q 'dry-run: would upsert' || fail "expected the dry-run write notice; got: $out"
echo "$out" | grep -qi 'gh) is required' && fail "--dry-run must not demand gh: $out"

# 9. THE LIVE WIRING. Everything above trusts a fixture to have the shape
#    grounding-readout.sh emits. This section runs the real readout, so a
#    renamed key (sessions, directive_fired.count, plugin_versions_seen) fails
#    here instead of turning the check into a permanent silent zero.
HOOK="$TMP/session-start.sh"
cat > "$HOOK" <<'HOOK_SRC'
#!/usr/bin/env bash
grounding=$(cat <<'DIRECTIVE'
**Test plugin: role-grounding directive**

Resolve and announce the active role/circle before your first substantive action.
DIRECTIVE
)
HOOK_SRC

PROJ="$TMP/projects"; mkdir -p "$PROJ"
# 12 sessions that received the directive, stamped v0.12.0 ...
for i in $(seq 1 12); do
  cat > "$PROJ/fired-$i.jsonl" <<'JSONL'
{"type":"attachment","timestamp":"2020-01-01T00:00:00Z","stdout":"{\"additionalContext\":\"**Test plugin: role-grounding directive**\\n\\n_Directive emitted by holacracy-claude-plugin v0.12.0._\"}"}
JSONL
done
# ... and one that did not.
cat > "$PROJ/silent.jsonl" <<'JSONL'
{"type":"assistant","timestamp":"2020-01-01T00:00:00Z","text":"Sure, here is the code."}
JSONL

live() {
  CLAUDE_PROJECTS_DIR="$PROJ" HOLACRACY_HOOK_SOURCE="$HOOK" \
    bash "$SCRIPT" --dry-run --since-start 2019-01-01 "$@"
}

# 13 sessions, 12 fired = 92.3%, above the 0.9 floor.
out="$(live 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "live wiring: 12/13 should be clear, got $rc: $out"
echo "$out" | grep -q '12 of 13' || fail "live wiring: expected 12 of 13; got: $out"
echo "$out" | grep -q '0.12.0 (12)' || fail "live wiring: expected the version from the real readout; got: $out"

# Same corpus, a floor it cannot meet: proves the alarm path is reachable
# through the real readout, not only through fixtures.
out="$(live --min-rate 0.99 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "live wiring: 12/13 under a 0.99 floor should alarm, got $rc: $out"

# 9b. A session that merely READ the directive text must not count as having
#     received it. This is the #122/#123 defect at the level that matters here:
#     if it counted, a collapse in real delivery would be masked by this repo's
#     own sessions discussing the directive.
cat > "$PROJ/reader.jsonl" <<'JSONL'
{"type":"assistant","timestamp":"2020-01-01T00:00:00Z","text":"The hook emits **Test plugin: role-grounding directive** as its first line."}
JSONL
out="$(live 2>&1)"; rc=$?
echo "$out" | grep -q '12 of 14' || fail "reading the directive must not count as receiving it; got: $out"

# 10. Operational failures are exit 2, never a quiet pass.
out="$(run --readout-json "$TMP/does-not-exist.json" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a missing --readout-json file should exit 2, got $rc: $out"

echo '{not json' > "$TMP/garbage.json"
out="$(run --readout-json "$TMP/garbage.json" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "unparseable readout output should exit 2, got $rc: $out"

out="$(run --readout-json "$TMP/healthy.json" --min-rate 1.5 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "--min-rate above 1 should exit 2, got $rc: $out"

out="$(run --readout-json "$TMP/healthy.json" --min-rate abc 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a non-numeric --min-rate should exit 2, got $rc: $out"

out="$(run --readout-json "$TMP/healthy.json" --min-sessions -3 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a negative --min-sessions should exit 2, got $rc: $out"

out="$(run --nonsense 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "an unknown argument should exit 2, got $rc: $out"

# 11. A readout that ITSELF fails must not be read as a clean window. The
#     readout exits 2 when it cannot derive its marker -- i.e. the directive was
#     reworded -- and a zero from that is unjustifiable, not healthy.
out="$(CLAUDE_PROJECTS_DIR="$PROJ" HOLACRACY_HOOK_SOURCE="$TMP/no-such-hook.sh" \
        bash "$SCRIPT" --dry-run --since-start 2019-01-01 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a failing readout must exit 2, got $rc: $out"
echo "$out" | grep -q 'refusing to report a rate' || fail "expected an explicit refusal; got: $out"

# 12. Thresholds are configurable by env as well as flag, so the scheduled task
#     can set them once without every invocation carrying them.
out="$(GROUNDING_MIN_FIRE_RATE=0.01 run --readout-json "$TMP/collapsed.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "GROUNDING_MIN_FIRE_RATE should lower the floor, got $rc: $out"

out="$(GROUNDING_MIN_SESSIONS=500 run --readout-json "$TMP/collapsed.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "GROUNDING_MIN_SESSIONS should raise the n floor, got $rc: $out"
echo "$out" | grep -q 'NO VERDICT' || fail "expected a non-verdict under a raised n floor; got: $out"

echo "PASS: all grounding-fire-rate-check tests"
