#!/usr/bin/env bash
# Regression tests for hooks-handlers/session-start.sh.
#
# Run: bash hooks-handlers/session-start.test.sh
# No framework — plain asserts. Exits non-zero on first failure.
#
# Covers the surfacing window, the heredoc-injection safety fix, legacy-entry
# rendering, the anomaly path, and the fail-silent contract.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/session-start.sh"
TODAY="$(date -u +%Y-%m-%d)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# 1. A windowed entry whose packet_summary contains a triple-quote and a
#    trailing backslash must still produce VALID JSON (heredoc-injection fix).
cat > "$TMP/l1.jsonl" <<JSONL
{"id":"a","title":"holacracy/secretary/pre-tactical-prep/ops","last_status":"ok","surface_from":"${TODAY}T00:00:00Z","surface_until":"${TODAY}T23:59:59Z","built_at":"${TODAY}T08:00:00Z","packet_summary":"weird \"\"\" tail\\\\","packet_path":"~/p/ops.md"}
JSONL
out="$(HOLACRACY_ROUTINE_LEDGER="$TMP/l1.jsonl" bash "$HOOK")"
echo "$out" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' || fail "envelope is not valid JSON for adversarial packet_summary"
echo "$out" | grep -q "as of ${TODAY}T08:00:00Z" || fail "missing 'as of' freshness marker"
echo "$out" | grep -q "full draft: ~/p/ops.md" || fail "missing full-draft pointer"

# 2. A legacy metadata-only entry (no window/summary) firing today renders as before.
cat > "$TMP/l2.jsonl" <<JSONL
{"id":"b","title":"holacracy/secretary/pre-tactical-prep/legacy","next_fire":"${TODAY}T18:00:00Z","last_fire":"2026-06-11T18:00:00Z","last_status":"ok"}
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

echo "PASS: all session-start hook tests"
