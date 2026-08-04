#!/usr/bin/env bash
# Regression tests for scripts/plugin-version-skew-check.sh.
#
# Run: bash scripts/plugin-version-skew-check.test.sh
# No framework -- plain asserts. Exits non-zero on first failure.
#
# Section 1 builds a REPRODUCTION of the exact issue #122 condition -- a v0.6.0
# copy materialized by the desktop app while installed_plugins.json reports
# 0.10.2 -- because #150 asks for the alarm to be demonstrated against a
# reproduction rather than asserted. Section 2 does the same for the softer
# cache-behind-stable case that had already recurred unnoticed.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/plugin-version-skew-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# Materialize a plugin copy with a manifest, the way a real install looks.
mkcopy() {  # mkcopy DIR VERSION [NAME]
  local dir="$1" version="$2" name="${3:-holacracy}"
  mkdir -p "$dir/.claude-plugin"
  printf '%s\n' "$version" > "$dir/version.txt"
  cat > "$dir/.claude-plugin/plugin.json" <<EOF
{"name": "$name", "version": "$version"}
EOF
}

mkloaded() {  # mkloaded PATH VERSIONS_JSON SESSIONS UNSTAMPED
  cat > "$1" <<EOF
{"sessions": $3, "directive_fired": {"count": $3},
 "plugin_versions_seen": $2, "sessions_without_plugin_version": $4}
EOF
}

APP='Library/Application Support/Claude/local-agent-mode-sessions'

# ---------------------------------------------------------------------------
# 1. The #122 reproduction: desktop app pinned at 0.6.0, install record 0.10.2,
#    stable 0.10.3. Every config file read plausible; the loaded code was two
#    weeks stale. This must alarm, and must name the desktop copy.
# ---------------------------------------------------------------------------
R1="$TMP/issue122"
mkcopy "$R1/$APP/abc123/rpm/plugin_011Gxk9EXCkyRyB192A1AxeZ" 0.6.0
mkcopy "$R1/.claude/plugins/cache/integral-productivity-internal/holacracy/0.10.2" 0.10.2
mkdir -p "$R1/.claude/plugins"
cat > "$R1/.claude/plugins/installed_plugins.json" <<'EOF'
{"holacracy@integral-productivity-internal": {"version": "0.10.2", "lastUpdated": "2026-07-29T21:54:00Z"}}
EOF
mkloaded "$TMP/loaded-0.6.0.json" '{}' 8 8   # v0.6.0 emitted no stamp at all

out="$(bash "$SCRIPT" --dry-run --fixture-root "$R1" --stable-version 0.10.3 \
        --loaded-json "$TMP/loaded-0.6.0.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "the #122 condition must alarm, got $rc: $out"
echo "$out" | grep -q 'desktop app copy' || fail "expected the desktop app channel named; got: $out"
echo "$out" | grep -q '0.6.0' || fail "expected the stale 0.6.0 version reported; got: $out"
echo "$out" | grep -q 'BEHIND' || fail "expected a BEHIND status; got: $out"
echo "$out" | grep -q 'plugin-version-skew-check:v1' || fail "expected the idempotency marker; got: $out"
# The install record was ALSO behind stable -- both must surface, because in
# #122 believing the "correct" channel is what delayed the diagnosis.
echo "$out" | grep -q 'recorded install' || fail "expected the recorded install channel; got: $out"

# 1b. And the loaded channel must read UNKNOWN, not be quietly omitted. v0.6.0
#     predates the version stamp, so it emits nothing -- the single most
#     important case this check has to get right (#150 criterion 3).
echo "$out" | grep -q 'UNKNOWN' || fail "an undeterminable loaded version must read UNKNOWN; got: $out"
echo "$out" | grep -q 'NONE carrying a version stamp' || fail "expected the unstamped-sessions detail; got: $out"

# ---------------------------------------------------------------------------
# 2. The softer case that had already recurred unnoticed: cache at 0.10.2 while
#    stable is 0.10.3. Nothing was obviously broken, and nobody saw it.
# ---------------------------------------------------------------------------
R2="$TMP/cachebehind"
mkcopy "$R2/$APP/abc123/rpm/plugin_x" 0.10.3
mkcopy "$R2/.claude/plugins/cache/mkt/holacracy/0.10.2" 0.10.2
mkloaded "$TMP/loaded-0.10.3.json" '{"0.10.3": 5}' 5 0

out="$(bash "$SCRIPT" --dry-run --fixture-root "$R2" --stable-version 0.10.3 \
        --loaded-json "$TMP/loaded-0.10.3.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "cache behind stable must alarm, got $rc: $out"
echo "$out" | grep -q 'plugin cache' || fail "expected the cache channel named; got: $out"

# ---------------------------------------------------------------------------
# 3. Clear path: every channel at stable, loaded confirmed by transcript stamp.
# ---------------------------------------------------------------------------
R3="$TMP/healthy"
mkcopy "$R3/$APP/abc123/rpm/plugin_x" 0.12.0
mkcopy "$R3/.claude/plugins/cache/mkt/holacracy/0.12.0" 0.12.0
mkdir -p "$R3/.claude/plugins"
cat > "$R3/.claude/plugins/installed_plugins.json" <<'EOF'
{"holacracy@mkt": {"version": "0.12.0"}}
EOF
mkloaded "$TMP/loaded-0.12.0.json" '{"0.12.0": 6}' 6 0

out="$(bash "$SCRIPT" --dry-run --fixture-root "$R3" --stable-version 0.12.0 \
        --loaded-json "$TMP/loaded-0.12.0.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "an all-current deployment should exit 0, got $rc: $out"
echo "$out" | grep -q '^Clear' || fail "expected a Clear line; got: $out"

# ---------------------------------------------------------------------------
# 4. A single stale session alarms even when others are current. One session on
#    a stale copy IS the failure; averaging it away would hide it.
# ---------------------------------------------------------------------------
mkloaded "$TMP/loaded-mixed.json" '{"0.12.0": 5, "0.6.0": 1}' 6 0
out="$(bash "$SCRIPT" --dry-run --fixture-root "$R3" --stable-version 0.12.0 \
        --loaded-json "$TMP/loaded-mixed.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "a mixed window containing a stale version must alarm, got $rc: $out"
echo "$out" | grep -q '0.6.0 (1)' || fail "expected the stale version and its session count; got: $out"

# ---------------------------------------------------------------------------
# 5. AHEAD is reported but does not alarm. A local dev checkout legitimately
#    runs ahead of stable; alarming on it would train the reader to ignore this
#    check, which is how a real alarm gets missed.
# ---------------------------------------------------------------------------
mkloaded "$TMP/loaded-ahead.json" '{"0.13.0": 3}' 3 0
R5="$TMP/ahead"
mkcopy "$R5/.claude/plugins/cache/mkt/holacracy/0.13.0" 0.13.0
out="$(bash "$SCRIPT" --dry-run --fixture-root "$R5" --stable-version 0.12.0 \
        --loaded-json "$TMP/loaded-ahead.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "running ahead of stable should not alarm, got $rc: $out"
echo "$out" | grep -q 'AHEAD' || fail "AHEAD should still be reported; got: $out"

# ---------------------------------------------------------------------------
# 6. Backup app-session directories are inert clutter, not a second deployment.
#    #122 found a 0.2.0 copy under a `.bak-2026-06-02-1620` directory that
#    nothing loads from. Alarming on it would be a permanent false positive.
# ---------------------------------------------------------------------------
R6="$TMP/withbak"
mkcopy "$R6/$APP/abc123/rpm/plugin_x" 0.12.0
mkcopy "$R6/$APP/old.bak-2026-06-02-1620/rpm/plugin_y" 0.2.0
out="$(bash "$SCRIPT" --dry-run --fixture-root "$R6" --stable-version 0.12.0 \
        --loaded-json "$TMP/loaded-0.12.0.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "a .bak- app-session copy must be ignored, got $rc: $out"
echo "$out" | grep -q '0.2.0' && fail "the .bak- copy must not appear at all: $out"

# ---------------------------------------------------------------------------
# 7. Other plugins' copies are not ours. The app materializes ~40 plugins into
#    the same tree; matching on path shape alone would report every one.
# ---------------------------------------------------------------------------
R7="$TMP/otherplugins"
mkcopy "$R7/$APP/abc123/rpm/plugin_other" 0.1.0 reclaim-assistant
mkcopy "$R7/$APP/abc123/rpm/plugin_ours" 0.12.0
out="$(bash "$SCRIPT" --dry-run --fixture-root "$R7" --stable-version 0.12.0 \
        --loaded-json "$TMP/loaded-0.12.0.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "another plugin's copy must not count as ours, got $rc: $out"
echo "$out" | grep -q '0.1.0' && fail "another plugin's version must not be reported: $out"

# ---------------------------------------------------------------------------
# 8. Finding NOTHING is an error, not health. If the probe looks in the wrong
#    place it has compared nothing, and reporting "clear" would be a pass on no
#    evidence -- the failure mode this whole check exists to end.
# ---------------------------------------------------------------------------
R8="$TMP/empty"; mkdir -p "$R8"
out="$(bash "$SCRIPT" --dry-run --fixture-root "$R8" --stable-version 0.12.0 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "an empty probe root must exit 2, got $rc: $out"
echo "$out" | grep -qi 'NOT a pass' || fail "expected an explicit not-a-pass message; got: $out"

# ---------------------------------------------------------------------------
# 9. An unparseable version is UNKNOWN, hence skew -- never silently equal.
# ---------------------------------------------------------------------------
R9="$TMP/garbled"
mkcopy "$R9/.claude/plugins/cache/mkt/holacracy/latest" "not-a-version"
out="$(bash "$SCRIPT" --dry-run --fixture-root "$R9" --stable-version 0.12.0 \
        --loaded-json "$TMP/loaded-0.12.0.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "an unparseable channel version must alarm, got $rc: $out"

# ---------------------------------------------------------------------------
# 10. Usage errors.
# ---------------------------------------------------------------------------
out="$(bash "$SCRIPT" --dry-run --fixture-root "$TMP/nope" --stable-version 0.12.0 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a nonexistent fixture root should exit 2, got $rc: $out"

out="$(bash "$SCRIPT" --dry-run --days -1 --stable-version 0.12.0 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a negative --days should exit 2, got $rc: $out"

out="$(bash "$SCRIPT" --nonsense 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "an unknown argument should exit 2, got $rc: $out"

out="$(bash "$SCRIPT" --dry-run --fixture-root "$R3" --stable-version 0.12.0 \
        --loaded-json "$TMP/no-such-file.json" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a missing --loaded-json file should exit 2, got $rc: $out"

echo "PASS: all plugin-version-skew-check tests"
