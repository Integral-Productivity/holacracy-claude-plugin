#!/usr/bin/env bash
# Regression tests for hooks-handlers/session-start.sh.
#
# Run: bash hooks-handlers/session-start.test.sh
# No framework — plain asserts. Exits non-zero on first failure.
#
# Covers the surfacing window, the heredoc-injection safety fix, legacy-entry
# rendering, the anomaly path, the fail-silent contract, and the role-grounding
# directive (issue #62) with its honesty and gating behavior.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/session-start.sh"
# LOCAL date, deliberately. The hook windows routines against the user's local
# "today" (see _date() in session-start.sh). Building fixtures from `date -u`
# instead made this suite fail for the ~7h/day that the UTC and Pacific dates
# disagree, while passing on a UTC CI runner -- issue #132.
TODAY="$(date +%Y-%m-%d)"

# Windowing fixtures need instants whose LOCAL date is today in EVERY timezone.
# A hand-written "...T18:00:00Z" does not qualify: at Asia/Tokyo (+09) or
# Pacific/Kiritimati (+14) it lands on tomorrow, so such fixtures only worked
# near UTC. Derive each instant from a local wall-clock time instead.
_utc_for_local() {  # $1 = HH:MM:SS local today -> UTC ISO-8601 "...Z" instant
  python3 -c '
import datetime as dt, sys
h, m, s = (int(x) for x in sys.argv[1].split(":"))
local = dt.datetime.now().astimezone().replace(
    hour=h, minute=m, second=s, microsecond=0)
print(local.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
' "$1"
}
WIN_FROM="$(_utc_for_local 00:00:00)"    # local start of today
WIN_UNTIL="$(_utc_for_local 23:59:59)"   # local end of today
FIRE_TODAY="$(_utc_for_local 12:00:00)"  # local midday today
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# Routine-briefing tests (1-5) run with the grounding directive OFF so they
# exercise the briefing path in isolation and prove it is unchanged from before
# issue #62. Grounding-specific tests (G1-G8) set their own env explicitly.
export HOLACRACY_GROUNDING_DIRECTIVE=off

# 1. A windowed entry whose packet_summary contains a triple-quote and a
#    trailing backslash must still produce VALID JSON (heredoc-injection fix).
cat > "$TMP/l1.jsonl" <<JSONL
{"id":"a","title":"holacracy/secretary/pre-tactical-prep/ops","last_status":"ok","surface_from":"${WIN_FROM}","surface_until":"${WIN_UNTIL}","built_at":"${TODAY}T08:00:00Z","packet_summary":"weird \"\"\" tail\\\\","packet_path":"~/p/ops.md"}
JSONL
out="$(HOLACRACY_ROUTINE_LEDGER="$TMP/l1.jsonl" bash "$HOOK")"
echo "$out" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' || fail "envelope is not valid JSON for adversarial packet_summary"
echo "$out" | grep -q "as of ${TODAY}T08:00:00Z" || fail "missing 'as of' freshness marker"
echo "$out" | grep -q "full draft: ~/p/ops.md" || fail "missing full-draft pointer"

# 2. A legacy metadata-only entry (no window/summary) firing today renders as before.
cat > "$TMP/l2.jsonl" <<JSONL
{"id":"b","title":"holacracy/secretary/pre-tactical-prep/legacy","next_fire":"${FIRE_TODAY}","last_fire":"2026-06-11T18:00:00Z","last_status":"ok"}
JSONL
out="$(HOLACRACY_ROUTINE_LEDGER="$TMP/l2.jsonl" bash "$HOOK")"
echo "$out" | grep -q "holacracy/secretary/pre-tactical-prep/legacy" || fail "legacy entry did not surface"

# 3. An error-status entry surfaces under anomalies; a malformed line is ignored.
cat > "$TMP/l3.jsonl" <<JSONL
not-json
{"id":"c","title":"holacracy/lead-link/audit/ops","last_status":"error","last_fire":"2026-06-17T09:00:00Z"}
JSONL
out="$(HOLACRACY_ROUTINE_LEDGER="$TMP/l3.jsonl" bash "$HOOK")"
echo "$out" | grep -q "last fire FAILED" || fail "error entry did not surface as anomaly"

# 4. Unreadable ledger -> silent, exit 0.
out="$(HOLACRACY_ROUTINE_LEDGER="$TMP/missing.jsonl" bash "$HOOK")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] || fail "unreadable ledger was not silent/exit-0"

# 5. Out-of-window entry -> silent.
cat > "$TMP/l5.jsonl" <<JSONL
{"id":"d","title":"holacracy/secretary/pre-tactical-prep/x","surface_from":"2026-07-01T00:00:00Z","surface_until":"2026-07-01T23:59:59Z","last_status":"ok","packet_summary":"future"}
JSONL
out="$(HOLACRACY_ROUTINE_LEDGER="$TMP/l5.jsonl" bash "$HOOK")"
[ -z "$out" ] || fail "out-of-window entry should not surface"

# 6. Timezone semantics (issue #132). A routine whose next_fire is today in
#    LOCAL time but a DIFFERENT calendar day in UTC must still surface. This is
#    the regression guard for _date()'s local normalization: a hook that takes
#    .date() straight off the UTC value compares a UTC date against a local
#    today and silently drops the entry.
#
#    Both edges are exercised because which one straddles midnight depends on
#    the sign of the UTC offset -- 23:30 local is tomorrow-UTC at negative
#    offsets, 00:30 local is yesterday-UTC at positive ones. At offset 0
#    NEITHER straddles, so this assertion is vacuous under a UTC runner. That
#    is why scripts-test.yml runs this suite under a non-UTC timezone as well;
#    the two halves are load-bearing together, not redundantly.
for _hms in 00:30:00 23:30:00; do
  _inst="$(_utc_for_local "$_hms")"
  cat > "$TMP/l6.jsonl" <<JSONL
{"id":"e","title":"holacracy/secretary/tz-edge/${_hms}","next_fire":"${_inst}","last_status":"ok"}
JSONL
  out="$(HOLACRACY_ROUTINE_LEDGER="$TMP/l6.jsonl" bash "$HOOK")"
  echo "$out" | grep -q "holacracy/secretary/tz-edge/${_hms}" \
    || fail "routine due today LOCAL at ${_hms} (UTC instant ${_inst}) did not surface -- _date() is comparing a UTC date against a local today"
done

# --- Role-grounding directive (issue #62) ---------------------------------
# From here on grounding is exercised directly; run each from $TMP (no
# glassfrog-declaring .mcp.json in cwd) so gate tests are deterministic.
MISSING="$TMP/missing.jsonl"

# G1. Default is always-on: with the toggle unset and no ledger, the hook still
#     emits a valid-JSON envelope carrying the grounding directive.
out="$(cd "$TMP" && env -u HOLACRACY_GROUNDING_DIRECTIVE HOLACRACY_ROUTINE_LEDGER="$MISSING" bash "$HOOK")"
[ -n "$out" ] || fail "grounding directive should inject by default (always-on)"
echo "$out" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' || fail "grounding envelope is not valid JSON"
echo "$out" | grep -q "role-grounding directive" || fail "grounding directive marker missing"
echo "$out" | grep -q "actor-and-role-resolution.md" || fail "grounding directive should point at the resolution procedure"

# G2. Honest by construction: it DEMANDS the load and does NOT claim grounding
#     already happened.
echo "$out" | grep -q "NOT yet been performed" || fail "directive must demand the load, not claim it happened"
echo "$out" | grep -q "does not assert it happened" || fail "directive must disclaim asserting grounding occurred"
echo "$out" | grep -qi "grounding complete" && fail "directive must never claim grounding is complete"

# G3. Grounding + briefing combine: both surface, leading with the directive,
#     as a single valid-JSON envelope.
cat > "$TMP/g3.jsonl" <<JSONL
{"id":"g3","title":"holacracy/secretary/pre-tactical-prep/ops","next_fire":"${FIRE_TODAY}","last_status":"ok"}
JSONL
out="$(cd "$TMP" && env -u HOLACRACY_GROUNDING_DIRECTIVE HOLACRACY_ROUTINE_LEDGER="$TMP/g3.jsonl" bash "$HOOK")"
echo "$out" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' || fail "combined envelope is not valid JSON"
echo "$out" | grep -q "role-grounding directive" || fail "combined output missing grounding directive"
echo "$out" | grep -q "holacracy/secretary/pre-tactical-prep/ops" || fail "combined output missing routine briefing"

# G4. Explicit off + no ledger -> silent (toggle works; existing behavior).
out="$(cd "$TMP" && HOLACRACY_GROUNDING_DIRECTIVE=off HOLACRACY_ROUTINE_LEDGER="$MISSING" bash "$HOOK")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] || fail "grounding off + no ledger should be silent/exit-0"

# G5. GlassFrog gate ON, no connector declared in cwd -> no injection (silent).
out="$(cd "$TMP" && HOLACRACY_GROUNDING_DIRECTIVE=on HOLACRACY_GROUNDING_REQUIRE_GLASSFROG=on HOLACRACY_ROUTINE_LEDGER="$MISSING" bash "$HOOK")"
[ -z "$out" ] || fail "glassfrog gate should suppress injection when no connector is declared"

# G6. GlassFrog gate ON, a .mcp.json naming glassfrog present in cwd -> injects.
mkdir -p "$TMP/gf"
cat > "$TMP/gf/.mcp.json" <<'JSON'
{ "mcpServers": { "glassfrog": { "url": "https://example/mcp" } } }
JSON
out="$(cd "$TMP/gf" && HOLACRACY_GROUNDING_DIRECTIVE=on HOLACRACY_GROUNDING_REQUIRE_GLASSFROG=on HOLACRACY_ROUTINE_LEDGER="$MISSING" bash "$HOOK")"
echo "$out" | grep -q "role-grounding directive" || fail "glassfrog gate should allow injection when connector is declared"

# G7. Path gate: a regex that does not match $PWD -> no injection.
out="$(cd "$TMP" && HOLACRACY_GROUNDING_DIRECTIVE=on HOLACRACY_GROUNDING_REQUIRE_PATH='this-path-does-not-exist-xyz' HOLACRACY_ROUTINE_LEDGER="$MISSING" bash "$HOOK")"
[ -z "$out" ] || fail "path gate should suppress injection when \$PWD does not match"

# G8. Path gate: a regex that matches $PWD -> injects.
out="$(cd "$TMP" && HOLACRACY_GROUNDING_DIRECTIVE=on HOLACRACY_GROUNDING_REQUIRE_PATH="$(basename "$TMP")" HOLACRACY_ROUTINE_LEDGER="$MISSING" bash "$HOOK")"
echo "$out" | grep -q "role-grounding directive" || fail "path gate should allow injection when \$PWD matches"

echo "PASS: all session-start hook tests"
