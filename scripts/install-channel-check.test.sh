#!/usr/bin/env bash
# Regression tests for scripts/install-channel-check.sh.
#
# Run: bash scripts/install-channel-check.test.sh
# No framework -- plain asserts. Exits non-zero on first failure.
#
# WHY THIS SUITE EXISTS
# ---------------------
# The check guards a delivery claim, so its failure mode is SILENCE: a
# regression that makes it always pass merges green, and the README drifts back
# to naming a marketplace that serves nothing -- which is issue #234, the defect
# the check was written for. Section 4 replays #234 exactly.
#
# HOW IT IS HERMETIC
# ------------------
# Every README and catalog is synthesised under $TMP. Remote catalogs come from
# `--fixture-dir` in most sections; section 6 instead puts a STUB `gh` on PATH so
# the real GitHub-API read path (base64 decode, 404 handling) is exercised too.
# The script under test is never modified or sourced.
#
# THE MUTATION PROPERTY (section 8)
# ---------------------------------
# Sections 1-7 could all pass against a script whose defenses do nothing, so
# section 8 asserts both directions: each defense has a one-line mutation, and
# the property must hold on the real script AND fail on the mutant. The mutant
# builder checks its own exit status and self-tests against an absent target --
# see scripts/eval-cost.test.sh for the vacuous-pass failure that rule prevents.

# shellcheck disable=SC2016  # $p / $ref / $measured in section 8 are literal
# text matched IN the script under test, not expansions.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/install-channel-check.sh"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
cases=0
pass() { cases=$((cases + 1)); }

[ -f "$SCRIPT" ] || fail "script under test not found at $SCRIPT"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required by the mutant builder"

SELF="Integral-Productivity/holacracy-claude-plugin"
LABS="Integral-Productivity/marketplace-labs"

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------
# entry REPO REF [EXTRA_JSON] -> one holacracy plugin entry
entry() {
  jq -cn --arg repo "$1" --arg ref "$2" --argjson extra "${3:-{\}}" \
    '{name:"holacracy", source:{source:"github", repo:$repo, ref:$ref}} + $extra'
}
# catalog PATH NAME ENTRY_JSON... -> writes a marketplace.json
catalog() {
  local path="$1" name="$2"; shift 2
  printf '%s\n' "$@" | jq -s --arg name "$name" '{name:$name, owner:{name:"t"}, plugins:.}' > "$path"
}
# world NAME -> a healthy two-channel world; echoes its dir
world() {
  local d="$TMP/$1"
  mkdir -p "$d/fx"
  catalog "$d/local.json" integral-productivity-holacracy "$(entry "$SELF" stable)"
  catalog "$d/fx/Integral-Productivity__marketplace-labs.json" integral-productivity-labs \
    "$(jq -cn '{name:"other", source:{source:"github", repo:"o/other"}}')" "$(entry "$SELF" stable)"
  cat > "$d/README.md" <<EOF
# t

## Install

**Anyone**

\`\`\`
/plugin marketplace add $SELF
/plugin install holacracy@integral-productivity-holacracy
\`\`\`

**Members**

\`\`\`
/plugin marketplace add $LABS
/plugin install holacracy@integral-productivity-labs
\`\`\`

## What's included

/plugin marketplace add Not-Install/section-lines-are-ignored
EOF
  printf '%s\n' "$d"
}
run() {  # run SCRIPT WORLD_DIR [ARGS...]
  local script="$1" d="$2"; shift 2
  bash "$script" --readme "$d/README.md" --local-catalog "$d/local.json" \
    --self-repo "$SELF" --fixture-dir "$d/fx" "$@"
}

# ---------------------------------------------------------------------------
# 1. Exit-code contract
# ---------------------------------------------------------------------------
W="$(world s1)"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "healthy two-channel world should exit 0 (rc=$rc): $out"
echo "$out" | grep -q 'measured: 2  not measured: 0  failures: 0' || fail "healthy report wrong: $out"
echo "$out" | grep -q 'Not-Install' && fail "a line outside ## Install was read as a channel: $out"
pass

out="$(bash "$SCRIPT" --bogus 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "unknown argument should exit 2 (rc=$rc)"; pass

out="$(bash "$SCRIPT" --readme "$TMP/nope.md" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "missing README should exit 2 (rc=$rc)"; pass

W="$(world s1b)"; printf '# t\n\n## Usage\n\n/plugin marketplace add %s\n' "$SELF" > "$W/README.md"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "README without ## Install should exit 2 (rc=$rc): $out"; pass

W="$(world s1c)"; printf '# t\n\n## Install\n\nClone it.\n' > "$W/README.md"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "Install section with no channel should exit 2, not pass (rc=$rc): $out"
echo "$out" | grep -q 'nothing to measure' || fail "no-channel message missing: $out"; pass

W="$(world s1d)"; rm "$W/fx/Integral-Productivity__marketplace-labs.json"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "an unreadable remote catalog must be 2 (read failure), never a verdict (rc=$rc): $out"; pass

W="$(world s1e)"; echo 'not json' > "$W/fx/Integral-Productivity__marketplace-labs.json"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a garbage catalog should exit 2 (rc=$rc): $out"; pass

W="$(world s1f)"; rm "$W/local.json"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a missing local catalog should exit 2 (rc=$rc): $out"; pass

# ---------------------------------------------------------------------------
# 2. Catalog judgments -- each defect is a 1 naming the defect
# ---------------------------------------------------------------------------
LABSFX="fx/Integral-Productivity__marketplace-labs.json"
p_judged() {  # p_judged SCRIPT LABEL ENTRY_JSON EXPECTED_TEXT -> 0 when the defect is caught
  local script="$1" label="$2" e="$3" want="$4" d o r
  d="$(world "p-$label-$RANDOM")"
  catalog "$d/$LABSFX" integral-productivity-labs "$e"
  o="$(run "$script" "$d" 2>&1)"; r=$?
  [ "$r" -eq 1 ] && echo "$o" | grep -qF "$want"
}
p_missing()  { local d o r; d="$(world "pm-$RANDOM")"
               catalog "$d/$LABSFX" integral-productivity-labs "$(jq -cn '{name:"x",source:{source:"github",repo:"o/x"}}')"
               o="$(run "$1" "$d" 2>&1)"; r=$?; [ "$r" -eq 1 ] && echo "$o" | grep -q 'no plugin named holacracy'; }
p_wrong_repo()   { p_judged "$1" repo "$(entry o/fork stable)" 'source repo is o/fork'; }
p_wrong_ref()    { p_judged "$1" ref "$(entry "$SELF" main)" 'source ref is main'; }
p_no_ref()       { p_judged "$1" noref "$(jq -cn --arg r "$SELF" '{name:"holacracy",source:{source:"github",repo:$r}}')" 'source ref is <none>'; }
p_version()      { p_judged "$1" ver "$(entry "$SELF" stable '{"version":"0.1.0"}')" 'pins version 0.1.0'; }
p_not_github()   { p_judged "$1" url "$(jq -cn '{name:"holacracy",source:"./"}')" 'not a github source'; }

p_missing "$SCRIPT"    || fail "a catalog without holacracy must exit 1 naming it"; pass
p_wrong_repo "$SCRIPT" || fail "an entry sourced from another repo must exit 1"; pass
p_wrong_ref "$SCRIPT"  || fail "an entry at ref main must exit 1"; pass
p_no_ref "$SCRIPT"     || fail "an entry with no ref must exit 1"; pass
p_version "$SCRIPT"    || fail "a pinned version must exit 1 (ADR-0002)"; pass
p_not_github "$SCRIPT" || fail "a non-github source must exit 1"; pass

W="$(world s2dup)"; catalog "$W/$LABSFX" integral-productivity-labs "$(entry "$SELF" stable)" "$(entry "$SELF" stable)"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && echo "$out" | grep -q 'ambiguous'; } || fail "duplicate entries must exit 1 (rc=$rc): $out"; pass

W="$(world s2case)"; catalog "$W/$LABSFX" integral-productivity-labs "$(entry integral-productivity/HOLACRACY-claude-plugin stable)"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "GitHub repo names are case-insensitive; a case-only difference must pass (rc=$rc): $out"; pass

# ---------------------------------------------------------------------------
# 3. Cross-check between channels and install lines
# ---------------------------------------------------------------------------
p_bare_install() { local d o r; d="$(world "pb-$RANDOM")"
  sed -i.bak 's#^/plugin install holacracy@integral-productivity-labs$#/plugin install holacracy#' "$d/README.md"
  o="$(run "$1" "$d" 2>&1)"; r=$?; [ "$r" -eq 1 ] && echo "$o" | grep -q 'names no catalog'; }
p_undeclared() { local d o r; d="$(world "pu-$RANDOM")"
  sed -i.bak 's#holacracy@integral-productivity-labs#holacracy@integral-productivity-tools#' "$d/README.md"
  o="$(run "$1" "$d" 2>&1)"; r=$?; [ "$r" -eq 1 ] && echo "$o" | grep -q 'no listed channel declares a catalog named integral-productivity-tools'; }
p_orphan_channel() { local d o r; d="$(world "po-$RANDOM")"
  sed -i.bak '/^\/plugin install holacracy@integral-productivity-labs$/d' "$d/README.md"
  o="$(run "$1" "$d" 2>&1)"; r=$?; [ "$r" -eq 1 ] && echo "$o" | grep -q 'catalog integral-productivity-labs is added but no'; }

p_bare_install "$SCRIPT"   || fail "a bare '/plugin install holacracy' must exit 1"; pass
p_undeclared "$SCRIPT"     || fail "an install target no channel declares must exit 1"; pass
p_orphan_channel "$SCRIPT" || fail "a channel with no install line must exit 1"; pass

W="$(world s3none)"; sed -i.bak '/^\/plugin install/d' "$W/README.md"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && echo "$out" | grep -q "no '/plugin install holacracy@<catalog>' line"; } \
  || fail "an Install section with no install line must exit 1 (rc=$rc): $out"; pass

# ---------------------------------------------------------------------------
# 4. Issue #234, replayed: the README pointed at a marketplace whose catalog was []
# ---------------------------------------------------------------------------
W="$(world s4)"
catalog "$W/fx/Integral-Productivity__marketplace.json" integral-productivity-tools
jq '.plugins = []' "$W/fx/Integral-Productivity__marketplace.json" > "$W/t" && mv "$W/t" "$W/fx/Integral-Productivity__marketplace.json"
printf '# t\n\n## Install\n\n```\n/plugin marketplace add Integral-Productivity/marketplace\n/plugin install holacracy\n```\n\nOr add this repo directly to your plugin sources.\n' > "$W/README.md"
out="$(run "$SCRIPT" "$W" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "#234's README must fail the check (rc=$rc): $out"
echo "$out" | grep -q 'no plugin named holacracy in the catalog' || fail "#234 report should name the empty catalog: $out"
pass

# ---------------------------------------------------------------------------
# 5. --local-only
# ---------------------------------------------------------------------------
W="$(world s5)"; rm -r "$W/fx"
out="$(bash "$SCRIPT" --readme "$W/README.md" --local-catalog "$W/local.json" --self-repo "$SELF" --local-only 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "--local-only must not need the remote catalog (rc=$rc): $out"
echo "$out" | grep -q "NOT MEASURED  $LABS" || fail "--local-only must name what it skipped: $out"
pass

p_local_judged() { local d o r; d="$(world "pl-$RANDOM")"
  catalog "$d/local.json" integral-productivity-holacracy "$(entry "$SELF" main)"
  o="$(run "$1" "$d" --local-only 2>&1)"; r=$?; [ "$r" -eq 1 ]; }
p_local_judged "$SCRIPT" || fail "--local-only must still judge the local catalog"; pass

p_nothing_measured() { local d o r; d="$(world "pn-$RANDOM")"
  sed -i.bak "/marketplace add Integral-Productivity\/holacracy-claude-plugin/d; /integral-productivity-holacracy/d" "$d/README.md"
  o="$(run "$1" "$d" --local-only 2>&1)"; r=$?; [ "$r" -eq 2 ] && echo "$o" | grep -q 'no channel was measured'; }
p_nothing_measured "$SCRIPT" || fail "--local-only with no local channel measured nothing and must exit 2, not 0"; pass

# ---------------------------------------------------------------------------
# 6. The GitHub-API read path, through a stub gh
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/calls.log"
case "$2" in
  repos/Integral-Productivity/marketplace-labs/contents/.claude-plugin/marketplace.json)
    [ -f "$STUB_DIR/labs.b64" ] || { echo "HTTP 404" >&2; exit 1; }
    cat "$STUB_DIR/labs.b64" ;;
  *) echo "$*" >> "$STUB_DIR/unhandled.log"; exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gh"

W="$(world s6)"; export STUB_DIR="$W"
base64 < "$W/$LABSFX" | fold -w 60 > "$W/labs.b64"   # the API wraps content lines
out="$(PATH="$TMP/bin:$PATH" bash "$SCRIPT" --readme "$W/README.md" --local-catalog "$W/local.json" --self-repo "$SELF" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "the gh read path should decode a wrapped base64 catalog (rc=$rc): $out"
grep -q 'repos/Integral-Productivity/marketplace-labs/contents/.claude-plugin/marketplace.json' "$W/calls.log" || fail "gh was not asked for the labs catalog"
[ ! -s "$W/unhandled.log" ] || fail "the script made a gh call the stub was never taught: $(cat "$W/unhandled.log")"
pass

rm "$W/labs.b64"
out="$(PATH="$TMP/bin:$PATH" bash "$SCRIPT" --readme "$W/README.md" --local-catalog "$W/local.json" --self-repo "$SELF" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a 404 (missing, or private without access) must be 2, never a verdict (rc=$rc): $out"
echo "$out" | grep -q 'not a verdict' || fail "the read-failure message should say it is not a verdict: $out"
pass

# ---------------------------------------------------------------------------
# 7. This repo, as committed
# ---------------------------------------------------------------------------
out="$(cd "$REPO_ROOT" && bash "$SCRIPT" --local-only 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "the committed README + .claude-plugin/marketplace.json fail --local-only (rc=$rc): $out"
pass

# ---------------------------------------------------------------------------
# 8. Mutations: each defense is load-bearing
# ---------------------------------------------------------------------------
# A mutant builder that CANNOT fail silently: its status is checked, the mutant
# must be non-empty, and a missing target is a hard failure naming the drift.
mutate() {  # $1=label $2=find $3=replace
  local dst="$TMP/mut-$1.sh"
  rm -f "$dst"
  python3 - "$SCRIPT" "$dst" "$2" "$3" <<'PY'
import pathlib, sys
src, dst, find, repl = sys.argv[1:5]
text = pathlib.Path(src).read_text()
mutated = text.replace(find, repl, 1)
if mutated == text:
    sys.stderr.write(f"mutation target not found: {find[:70]}\n")
    raise SystemExit(1)
pathlib.Path(dst).write_text(mutated)
PY
  # shellcheck disable=SC2181  # the heredoc above is the command being tested
  if [ $? -ne 0 ] || [ ! -s "$dst" ]; then
    fail "could not build the '$1' mutant: its target moved. This case would otherwise pass vacuously."
  fi
}

harness_rc=0
( mutate selftest 'this string is deliberately absent from install-channel-check.sh' 'x' ) >/dev/null 2>&1 \
  || harness_rc=$?
[ "$harness_rc" -ne 0 ] || fail "the mutate() helper accepted an absent target; every mutation case below is vacuous"
pass

# mutant_fails LABEL FIND REPLACE PROPERTY -- property holds on the real script
# (checked above) and must NOT hold on the mutant.
mutant_fails() {
  mutate "$1" "$2" "$3"
  "$4" "$TMP/mut-$1.sh" && fail "mutation '$1' did not fail $4 -- that defense is not load-bearing"
  pass
}
mutant_fails ref     '($p.source.ref // "") != $ref'                       'false' p_wrong_ref
mutant_fails repo    '(($p.source.repo // "") | ascii_downcase) != $repo'  'false' p_wrong_repo
mutant_fails version 'if $p | has("version")'                              'if false' p_version
mutant_fails missing 'if ($hits | length) == 0 then'                       'if false then' p_missing
mutant_fails undeclared '! printf '"'"'%s'"'"' "$declared_names" | grep -qxF "$target"' 'false' p_undeclared
mutant_fails orphan  '! printf '"'"'%s'"'"' "$installed_names" | grep -qxF "$name"' 'false' p_orphan_channel
mutant_fails measured '[ "$measured" -gt 0 ] || die'                        'true || die' p_nothing_measured

echo "PASS: all install-channel-check tests ($cases cases)"
