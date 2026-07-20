#!/usr/bin/env bash
# Regression tests for scripts/grounding-readout.sh.
#
# Run: bash scripts/grounding-readout.test.sh
# No framework — plain asserts. Exits non-zero on first failure.
#
# Builds a synthetic transcript directory and checks the three signal counts,
# the rate math, the --since window filter, and the --json shape.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/grounding-readout.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

PROJ="$TMP/projects"
mkdir -p "$PROJ"

# Session A: announces + marks a chapter (no remit language).
cat > "$PROJ/a.jsonl" <<'JSONL'
{"type":"assistant","text":"Operating as **Secretary of Operations Circle**. Pulling the checklist now."}
{"type":"tool_use","name":"mcp__ccd_session__mark_chapter"}
JSONL

# Session B: announces + names a remit boundary (no chapter mark).
cat > "$PROJ/b.jsonl" <<'JSONL'
{"type":"assistant","text":"operating as Lead Link of Product. This crosses into the Secretary's remit, so naming the boundary."}
JSONL

# Session C: no grounding signals at all.
cat > "$PROJ/c.jsonl" <<'JSONL'
{"type":"assistant","text":"Sure, here is the code you asked for."}
JSONL

# 1. Default scan: 3 sessions, 2 announce, 1 remit, 1 chapter.
out="$(CLAUDE_PROJECTS_DIR="$PROJ" bash "$SCRIPT")"
echo "$out" | grep -Eq 'scanned: 3 session' || fail "expected 3 sessions scanned; got: $out"
echo "$out" | grep -Eq 'resolve\+announce +2 +67%' || fail "expected resolve+announce 2 / 67%; got: $out"
echo "$out" | grep -Eq 'remit-crossing flag +1 +33%' || fail "expected remit 1 / 33%; got: $out"
echo "$out" | grep -Eq 'chapter-mark +1 +33%' || fail "expected chapter-mark 1 / 33%; got: $out"

# 2. --json shape carries counts and rates.
js="$(CLAUDE_PROJECTS_DIR="$PROJ" bash "$SCRIPT" --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["sessions"]==3, d
assert d["resolve_announce"]["count"]==2, d
assert d["remit_crossing"]["count"]==1, d
assert d["chapter_mark"]["count"]==1, d
assert abs(d["resolve_announce"]["rate"]-0.6667)<0.01, d
' || fail "--json shape/counts wrong: $js"

# 3. --project narrows to a subdir slug.
mkdir -p "$PROJ/only"
cp "$PROJ/c.jsonl" "$PROJ/only/x.jsonl"
out="$(CLAUDE_PROJECTS_DIR="$PROJ" bash "$SCRIPT" --project only)"
echo "$out" | grep -Eq 'scanned: 1 session' || fail "expected 1 session under --project only; got: $out"
echo "$out" | grep -Eq 'resolve\+announce +0 +0%' || fail "expected 0 announce under --project only; got: $out"

# 4. --since filters by mtime. Backdate a.jsonl to last year; a future --since
#    should exclude it.
touch -t "202601010000" "$PROJ/a.jsonl"
out="$(CLAUDE_PROJECTS_DIR="$PROJ" bash "$SCRIPT" --since 2026-06-01)"
# a.jsonl (backdated) excluded; b and c (fresh) remain plus only/x -> announce=1.
echo "$out" | grep -Eq 'resolve\+announce +1 ' || fail "expected --since to exclude backdated announce; got: $out"

# 5. Empty scan dir -> 0 sessions, rates n/a, exit 0.
empty="$TMP/empty"; mkdir -p "$empty"
out="$(CLAUDE_PROJECTS_DIR="$empty" bash "$SCRIPT")"; rc=$?
[ "$rc" -eq 0 ] || fail "empty scan should exit 0"
echo "$out" | grep -Eq 'scanned: 0 session' || fail "empty scan should report 0 sessions; got: $out"
echo "$out" | grep -Eq 'resolve\+announce +0 +n/a' || fail "empty scan rate should be n/a; got: $out"

echo "PASS: all grounding-readout tests"
