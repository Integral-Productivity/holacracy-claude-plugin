#!/usr/bin/env bash
# Regression tests for scripts/grounding-readout.sh.
#
# Run: bash scripts/grounding-readout.test.sh
# No framework -- plain asserts. Exits non-zero on first failure.
#
# Builds a synthetic transcript directory and checks the signal counts, the
# rate math, the --since window filter, and the --json shape. Sections 6+ pin
# the issue #123 repairs: each of the three defects gets a fixture that must
# NOT score, plus one genuine announcement that must.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/grounding-readout.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

PROJ="$TMP/projects"
mkdir -p "$PROJ"

# A stand-in for hooks-handlers/session-start.sh. The readout derives its
# directive marker from this file at run time rather than hard-coding a copy,
# so the tests supply their own source via --hook. The heredoc name and the
# leading header line are what the derivation depends on.
HOOK="$TMP/session-start.sh"
cat > "$HOOK" <<'HOOK_SRC'
#!/usr/bin/env bash
grounding=$(cat <<'DIRECTIVE'
**Test plugin: role-grounding directive**

Resolve and announce the active role/circle, e.g. "Operating as **Role of Circle**".

This grounding has NOT yet been performed -- this directive only requests it.
DIRECTIVE
)
HOOK_SRC

run() { CLAUDE_PROJECTS_DIR="$PROJ" bash "$SCRIPT" --hook "$HOOK" "$@"; }

# Session A: genuine announcement + a chapter mark (no remit language).
cat > "$PROJ/a.jsonl" <<'JSONL'
{"type":"assistant","text":"Operating as **Secretary of Operations Circle**. Pulling the checklist now."}
{"type":"tool_use","name":"mcp__ccd_session__mark_chapter"}
JSONL

# Session B: names a remit boundary; its "operating as" is unbolded prose, so
# it is not an announcement.
cat > "$PROJ/b.jsonl" <<'JSONL'
{"type":"assistant","text":"operating as Lead Link of Product. This crosses into the Secretary's remit, so naming the boundary."}
JSONL

# Session C: no grounding signals at all.
cat > "$PROJ/c.jsonl" <<'JSONL'
{"type":"assistant","text":"Sure, here is the code you asked for."}
JSONL

# 1. Default scan: 3 sessions, 1 genuine announce, 1 remit, 1 chapter.
out="$(run)"
echo "$out" | grep -Eq 'scanned: 3 session' || fail "expected 3 sessions scanned; got: $out"
echo "$out" | grep -Eq 'resolve\+announce +1 +33%' || fail "expected resolve+announce 1 / 33%; got: $out"
echo "$out" | grep -Eq 'remit-crossing flag +1 +33%' || fail "expected remit 1 / 33%; got: $out"
echo "$out" | grep -Eq 'chapter-mark +1 +33%' || fail "expected chapter-mark 1 / 33%; got: $out"

# 2. --json shape carries counts and both denominators.
js="$(run --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["sessions"]==3, d
assert d["resolve_announce"]["count"]==1, d
assert d["remit_crossing"]["count"]==1, d
assert d["chapter_mark"]["count"]==1, d
assert abs(d["resolve_announce"]["rate_of_sessions"]-0.3333)<0.01, d
assert d["directive_fired"]["count"]==0, d
assert d["resolve_announce"]["rate_of_directive_fired"] is None, d
assert d["directive_marker"].startswith("**Test plugin"), d
# Signals here occur in sessions the directive never reached, so the
# treated-population counts must be 0 -- not the global counts carried over.
for k in ("resolve_announce","remit_crossing","chapter_mark"):
    assert d[k]["count_when_directive_fired"]==0, (k, d[k])
' || fail "--json shape/counts wrong: $js"

# 2b. No rate may exceed 100%. "of directive-fired" is compliance among the
#     treated, so dividing a global count by the smaller fired count -- which
#     yielded chapter-mark 1550% on the real corpus -- is a bug, not a rate.
mixed="$TMP/mixed"; mkdir -p "$mixed"
cp "$PROJ/a.jsonl" "$mixed/untreated.jsonl"        # chapter mark, no directive
cat > "$mixed/treated.jsonl" <<'JSONL'
{"type":"attachment","stdout":"{\"additionalContext\":\"**Test plugin: role-grounding directive**\"}"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Nothing to report."}]}}
JSONL
js="$(CLAUDE_PROJECTS_DIR="$mixed" bash "$SCRIPT" --hook "$HOOK" --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["directive_fired"]["count"]==1, d
assert d["chapter_mark"]["count"]==1, d
assert d["chapter_mark"]["count_when_directive_fired"]==0, d
for k in ("resolve_announce","remit_crossing","chapter_mark"):
    r=d[k]["rate_of_directive_fired"]
    assert r is None or 0.0 <= r <= 1.0, (k, r, d[k])
' || fail "rate_of_directive_fired must stay within 0..1: $js"

# 3. --project narrows to a subdir slug.
mkdir -p "$PROJ/only"
cp "$PROJ/c.jsonl" "$PROJ/only/x.jsonl"
out="$(run --project only)"
echo "$out" | grep -Eq 'scanned: 1 session' || fail "expected 1 session under --project only; got: $out"
echo "$out" | grep -Eq 'resolve\+announce +0 +0%' || fail "expected 0 announce under --project only; got: $out"

# 4. --since filters by mtime. Backdate a.jsonl to last year; a later --since
#    should exclude it.
touch -t "202601010000" "$PROJ/a.jsonl"
out="$(run --since 2026-06-01)"
echo "$out" | grep -Eq 'resolve\+announce +0 ' || fail "expected --since to exclude backdated announce; got: $out"
touch "$PROJ/a.jsonl"

# 5. Empty scan dir -> 0 sessions, rates n/a, exit 0.
empty="$TMP/empty"; mkdir -p "$empty"
out="$(CLAUDE_PROJECTS_DIR="$empty" bash "$SCRIPT" --hook "$HOOK")"; rc=$?
[ "$rc" -eq 0 ] || fail "empty scan should exit 0"
echo "$out" | grep -Eq 'scanned: 0 session' || fail "empty scan should report 0 sessions; got: $out"
echo "$out" | grep -Eq 'resolve\+announce +0 +n/a' || fail "empty scan rate should be n/a; got: $out"

# ---------------------------------------------------------------------------
# Issue #123 repairs. Fresh corpus: one fixture per defect, plus one genuine
# announcement. Only the genuine one may score resolve+announce.
# ---------------------------------------------------------------------------

D="$TMP/defects"
mkdir -p "$D"
runD() { CLAUDE_PROJECTS_DIR="$D" bash "$SCRIPT" --hook "$HOOK" "$@"; }

# 6a. Defect 1 -- the plugin's own documentation being READ. The doc text
#     arrives as a tool result, not as assistant-emitted text, and carries a
#     perfectly real-looking role and circle.
cat > "$D/doc-quote.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"| Actor fills the target role in exactly one circle | Announce: \"Operating as **Secretary of Operations Circle**.\" |\n- \"Operating as **Lead Link of Product Circle (Advisor)**\""}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Read the resolution doc; the announcement convention is documented there."}]}}
JSONL

# 6b. Defect 1 -- plain English that is not a Holacratic announcement at all.
#     The real 2026-07-20 false positive, from productboard-mcp-server.
cat > "$D/plain-english.jsonl" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"You are a specialist document reviewer operating as the COHERENCE persona for this pass."}]}}
JSONL

# 6c. Defect 1 -- template placeholders echoed by the assistant. Both of the
#     window's assistant-emitted bold announcements were exactly this.
cat > "$D/placeholder.jsonl" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"The directive tells the session to say Operating as **Role of Circle**, or Operating as **Lead Link of X**, or Operating as **<role> of <circle>**, or Operating as **Secretary of [Circle Name]**."}]}}
JSONL

# 6d. Defect 1 -- the directive fired and the assistant quoted it back, but
#     never announced a real role. This is the treatment, not compliance.
cat > "$D/directive-echo.jsonl" <<'JSONL'
{"type":"attachment","hookName":"SessionStart","stdout":"{\"hookSpecificOutput\":{\"additionalContext\":\"**Test plugin: role-grounding directive**\\n\\nResolve and announce the active role/circle, e.g. \\\"Operating as **Role of Circle**\\\".\"}}"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I see the **Test plugin: role-grounding directive** asking me to announce Operating as **Role of Circle**. GlassFrog is not connected, so I cannot resolve a role."}]}}
JSONL

# 6e. Defect 2 -- a subagent transcript. Announces genuinely, but is not a
#     session and must not enter the denominator or any numerator.
mkdir -p "$D/subagents"
cat > "$D/subagents/sub.jsonl" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Operating as **Facilitator of Engineering Circle**. Starting the sweep."}]}}
JSONL

# 6f. The one genuine announcement: directive fired, and the assistant then
#     announced a real role and circle in its own voice.
cat > "$D/genuine.jsonl" <<'JSONL'
{"type":"attachment","hookName":"SessionStart","stdout":"{\"hookSpecificOutput\":{\"additionalContext\":\"**Test plugin: role-grounding directive**\\n\\nResolve and announce the active role/circle.\"}}"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Operating as **Rep Link of Engineering Circle to General Company Circle**. Checking the agenda."}]}}
JSONL

js="$(runD --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
# 5 top-level transcripts; the subagent file is not one of them.
assert d["sessions"]==5, d
assert d["excluded"]["subagent_files"]==1, d
# Two sessions saw the directive: the echo and the genuine one.
assert d["directive_fired"]["count"]==2, d
# Exactly one genuine announcement, and the denominator that matters is
# directive-fired, not all sessions.
assert d["resolve_announce"]["count"]==1, d
assert abs(d["resolve_announce"]["rate_of_directive_fired"]-0.5)<0.001, d
assert abs(d["resolve_announce"]["rate_of_sessions"]-0.2)<0.001, d
' || fail "issue #123 fixtures scored wrong: $js"

# 6h. The directive-echo guard, isolated. The placeholder rule catches today's
#     directive because its example is literally "Role of Circle". If #122
#     rewords the example to a realistic role, only this guard stops an
#     assistant quoting the directive back from scoring. Same corpus, a hook
#     whose example looks real.
HOOK2="$TMP/session-start-realistic.sh"
cat > "$HOOK2" <<'HOOK_SRC2'
grounding=$(cat <<'DIRECTIVE'
**Test plugin: role-grounding directive (realistic example)**

Announce it in your opening lines, e.g. "Operating as **Secretary of Operations Circle**".
DIRECTIVE
)
HOOK_SRC2
E="$TMP/echo-realistic"; mkdir -p "$E"
# The hook record is deliberately present: this fixture is "the directive
# genuinely fired AND the assistant quoted it back", which is the case the echo
# guard exists for. Before #149 this file had no hook record and still scored
# directive_fired==1, because firing was a bare text match -- the assertion
# encoded the defect it was meant to guard against.
cat > "$E/t.jsonl" <<'JSONL'
{"type":"attachment","hookName":"SessionStart","stdout":"{\"hookSpecificOutput\":{\"additionalContext\":\"**Test plugin: role-grounding directive (realistic example)**\\n\\nAnnounce it in your opening lines.\"}}"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"The **Test plugin: role-grounding directive (realistic example)** says to announce it in my opening lines, e.g. \"Operating as **Secretary of Operations Circle**\" -- but GlassFrog is not connected, so I cannot resolve a role."}]}}
JSONL
js="$(CLAUDE_PROJECTS_DIR="$E" bash "$SCRIPT" --hook "$HOOK2" --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["directive_fired"]["count"]==1, d
assert d["resolve_announce"]["count"]==0, d
' || fail "an assistant quoting the directive back must not score: $js"

# 6g. Name the offender if the count is wrong: scan each fixture alone and
#     assert per-file, so a regression says which defect came back.
for f in doc-quote plain-english placeholder directive-echo; do
  one="$TMP/one-$f"; mkdir -p "$one"
  cp "$D/$f.jsonl" "$one/t.jsonl"
  j="$(CLAUDE_PROJECTS_DIR="$one" bash "$SCRIPT" --hook "$HOOK" --json)"
  echo "$j" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["resolve_announce"]["count"]==0, d
' || fail "$f.jsonl scored an announcement it must not: $j"
done

# 7. Self-exclusion. A project dir named after this repo (and its worktrees)
#    is skipped by default, and counted with --include-self.
SELF_SLUG="$(cd "$HERE/.." && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | xargs dirname | sed 's/[^A-Za-z0-9]/-/g')"
[ -n "$SELF_SLUG" ] || fail "could not derive this repo's project slug"
S="$TMP/selftest"
mkdir -p "$S/$SELF_SLUG" "$S/${SELF_SLUG}--claude-worktrees-somewhere" "$S/other-project"
cp "$D/genuine.jsonl" "$S/$SELF_SLUG/t.jsonl"
cp "$D/genuine.jsonl" "$S/${SELF_SLUG}--claude-worktrees-somewhere/t.jsonl"
cp "$D/genuine.jsonl" "$S/other-project/t.jsonl"

js="$(CLAUDE_PROJECTS_DIR="$S" bash "$SCRIPT" --hook "$HOOK" --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["sessions"]==1, d
assert d["excluded"]["self_sessions"]==2, d
' || fail "self-exclusion should drop this repo and its worktrees: $js"

js="$(CLAUDE_PROJECTS_DIR="$S" bash "$SCRIPT" --hook "$HOOK" --include-self --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["sessions"]==3, d
assert d["excluded"]["self_sessions"]==0, d
' || fail "--include-self should count this repo's sessions: $js"

# 7b. In-repo sessions are REPORTED, not silently dropped (issue #149). Held
#     out of every headline figure, but present on their own line -- otherwise a
#     window in which every treated session happened to be in this repo reads as
#     a flat zero, which is exactly what happened after the 2026-08-03 delivery
#     fix: the readout said 0 announcements where the transcripts showed 2.
js="$(CLAUDE_PROJECTS_DIR="$S" bash "$SCRIPT" --hook "$HOOK" --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["sessions"]==1, d                      # headline stays cross-repo only
assert d["resolve_announce"]["count"]==1, d
assert d["in_repo"]["sessions"]==2, d           # and the held-out cohort is visible
assert d["in_repo"]["resolve_announce"]==2, d
' || fail "in-repo sessions must be reported on their own line, not dropped: $js"

# 7c. Reading the hook source is not receiving its output (issue #149).
#     `directive-fired` used to be a bare text match on any line, so a session
#     that merely READ hooks-handlers/session-start.sh, or quoted the directive
#     in a prompt, scored as having been treated -- the identical mistake that
#     produced the false 2.2% in #122. #123 repaired that for the announce
#     signal but left it in place for this one, and slug self-exclusion hid it,
#     because the sessions most likely to read the hook source are this repo's.
#     Surfacing the in-repo cohort made it visible: 9 reported vs 4 real.
R="$TMP/read-not-fired"; mkdir -p "$R"
cat > "$R/t.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"here is the hook source: **Test plugin: role-grounding directive**"}}
{"type":"attachment","attachment":{"type":"file_read","path":"hooks-handlers/session-start.sh"},"content":"**Test plugin: role-grounding directive**"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I can see the **Test plugin: role-grounding directive** header in that file."}]}}
JSONL
js="$(CLAUDE_PROJECTS_DIR="$R" bash "$SCRIPT" --hook "$HOOK" --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["sessions"]==1, d
assert d["directive_fired"]["count"]==0, d
' || fail "reading or quoting the hook source must not count as directive-fired: $js"

# 7d. --since-start buckets by when the session STARTED, not by file mtime
#     (issue #151). Both fixtures below have a current mtime, so --since would
#     keep both; only the start timestamp separates them. This is the axis that
#     matters for "did the directive fire after <fix>?" -- a session that began
#     before the cutoff and was merely appended to afterwards must not land in
#     the window. Five did in the 2026-08-03 window.
W="$TMP/window"; mkdir -p "$W"
cat > "$W/old.jsonl" <<'JSONL'
{"type":"attachment","hookName":"SessionStart","timestamp":"2026-01-01T00:00:00Z","stdout":"{\"hookSpecificOutput\":{\"additionalContext\":\"**Test plugin: role-grounding directive**\"}}"}
JSONL
cat > "$W/new.jsonl" <<'JSONL'
{"type":"attachment","hookName":"SessionStart","timestamp":"2026-06-01T00:00:00Z","stdout":"{\"hookSpecificOutput\":{\"additionalContext\":\"**Test plugin: role-grounding directive**\"}}"}
JSONL

js="$(CLAUDE_PROJECTS_DIR="$W" bash "$SCRIPT" --hook "$HOOK" --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["sessions"]==2, d
assert d["directive_fired"]["count"]==2, d
' || fail "both window fixtures should count with no --since-start: $js"

js="$(CLAUDE_PROJECTS_DIR="$W" bash "$SCRIPT" --hook "$HOOK" --since-start 2026-03-01 --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["sessions"]==1, d
assert d["directive_fired"]["count"]==1, d
' || fail "--since-start must exclude the session that STARTED before the cutoff: $js"

# 7e. A transcript with no readable start timestamp is dropped under
#     --since-start rather than guessed into the window. An unknown start must
#     never be counted as "after the fix" -- that is how a delivery claim gets
#     inflated by exactly the sessions it cannot account for.
cp "$D/genuine.jsonl" "$W/nostamp.jsonl"
js="$(CLAUDE_PROJECTS_DIR="$W" bash "$SCRIPT" --hook "$HOOK" --since-start 2026-03-01 --json)"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["sessions"]==1, d
' || fail "a transcript with no readable start time must not enter the window: $js"

# 8. Fail loudly when the marker cannot be derived, rather than reporting a
#    zero it cannot justify. This is the guard against #122 rewording or
#    restructuring the directive without this instrument noticing.
missing="$TMP/nope.sh"
out="$(runD --hook "$missing" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "missing hook source should exit 2, got $rc: $out"
echo "$out" | grep -q 'directive source not found' || fail "expected a clear missing-source message; got: $out"

noheredoc="$TMP/noheredoc.sh"
printf '#!/usr/bin/env bash\necho hello\n' > "$noheredoc"
out="$(runD --hook "$noheredoc" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "hook without a DIRECTIVE heredoc should exit 2, got $rc: $out"
# shellcheck disable=SC2016  # matching a literal backtick-quoted message
echo "$out" | grep -q 'no quoted `DIRECTIVE` heredoc' || fail "expected a clear heredoc message; got: $out"

shortmarker="$TMP/short.sh"
cat > "$shortmarker" <<'SHORT'
x=$(cat <<'DIRECTIVE'
Hi.
DIRECTIVE
)
SHORT
out="$(runD --hook "$shortmarker" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "too-short marker should exit 2, got $rc: $out"
echo "$out" | grep -q 'too short to be distinctive' || fail "expected a clear short-marker message; got: $out"

# 9. The real hook still yields a usable marker. This is the live wiring: if
#    #122 reshapes hooks-handlers/session-start.sh, this test fails here
#    instead of the readout silently reporting zero directives.
js="$(CLAUDE_PROJECTS_DIR="$D" bash "$SCRIPT" --json)"; rc=$?
[ "$rc" -eq 0 ] || fail "readout against the real hook should exit 0, got $rc"
echo "$js" | python3 -c '
import json,sys
d=json.load(sys.stdin)
m=d["directive_marker"]
assert len(m)>=20, m
assert "grounding" in m.lower() or "holacracy" in m.lower(), m
' || fail "marker derived from the real hook looks wrong: $js"

echo "PASS: all grounding-readout tests"
