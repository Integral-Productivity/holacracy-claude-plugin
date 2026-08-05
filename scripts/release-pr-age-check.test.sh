#!/usr/bin/env bash
# Regression tests for scripts/release-pr-age-check.sh.
#
# Run: bash scripts/release-pr-age-check.test.sh
# No framework -- plain asserts. Exits non-zero on first failure.
#
# WHY THIS SUITE EXISTS
# ---------------------
# The check is an alarm, so its failure mode is SILENCE: a regression that makes
# it always report "no alarm" merges green and nobody learns anything until the
# next 34-day release freeze. That is the same fail-silent shape issue #129
# exists to catch, one level up. Until this file existed, `shellcheck
# scripts/*.sh` was the whole of its coverage -- and shellcheck has no opinion
# about whether the threshold comparison is the right way round. See issue #143.
#
# HOW IT IS HERMETIC
# ------------------
# `--now` (synthetic clock) and `--pr-json` (substitute the open-PR list) are
# already in the script. They are not sufficient on their own: `gh` and `jq` are
# demanded unconditionally at startup, and the report's other three numbers --
# the consumer-facing version, the pending version, the frozen-commit count --
# all come from `gh api` regardless of `--pr-json`. So this suite puts a STUB
# `gh` on PATH that serves canned responses out of a per-section fixture dir.
# The script under test is never modified or sourced; it runs exactly as CI and
# the scheduled task run it.
#
# The stub serves a response only when the canned file exists and exits 1
# otherwise, which is also how the "GitHub said no" degradation paths get
# exercised (section 6). Anything it was never taught is recorded in
# unhandled.log rather than merely failing, because the script deliberately
# absorbs `gh api` failures into `<unknown>` -- a new call site would otherwise
# degrade the report in silence, which is the defect class, not a test detail.
#
# THE MUTATION PROPERTY (section 9)
# ---------------------------------
# Sections 1-8 could all pass against a script whose defenses do nothing, so
# section 9 asserts both directions the way scripts/skills-lint.test.sh does:
# for each defense there is a one-line mutation, and the suite asserts BOTH that
# the property holds on the real script AND that it FAILS on the mutant. The
# second half is what proves a check is load-bearing rather than incidentally
# covered by another. Every property used there is written as a `p_*` function
# taking the script path, so the same assertion runs against both.

# shellcheck disable=SC2016  # $p / $MAX_AGE_DAYS / $iso inside the section 9 sed
# expressions are literal text matched IN the script under test, not expansions.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/release-pr-age-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

[ -f "$SCRIPT" ] || fail "script under test not found at $SCRIPT"
command -v python3 >/dev/null 2>&1 || fail "python3 is required by the date stubs"

# ---------------------------------------------------------------------------
# The `gh` stub
# ---------------------------------------------------------------------------
# Canned files are the POST-`--jq` value, because that is what the script
# consumes: `file_at_ref` calls `gh api ... --jq '.content'` and pipes the
# result straight into base64, so the fixture is the base64 blob itself.

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >> "$STUB_DIR/calls.log"
serve() { [ -f "$STUB_DIR/$1" ] || exit 1; cat "$STUB_DIR/$1"; }
unhandled() { printf '%s\n' "$*" >> "$STUB_DIR/unhandled.log"; exit 1; }
case "${1:-}" in
  api)
    shift
    ep=''; for a in "$@"; do case "$a" in repos/*) ep="$a" ;; esac; done
    case "$ep" in
      */contents/.claude-plugin/plugin.json*)      serve stable-plugin.b64 ;;
      */contents/.release-please-manifest.json*)   serve pending-manifest.b64 ;;
      */compare/stable...main)                     serve compare.json ;;
      */issues/*/comments)                         serve pr-comments.json ;;
      *) unhandled "api $ep" ;;
    esac ;;
  issue) serve issues.json ;;
  pr)    serve prs.json ;;
  repo)  serve repo.json ;;
  *)     unhandled "$*" ;;
esac
STUB
chmod +x "$TMP/bin/gh"

# ---------------------------------------------------------------------------
# The two `date` stubs
# ---------------------------------------------------------------------------
# `iso_to_epoch` tries the BSD form first and the GNU form second, and the
# script's own comment says the two must never be collapsed. Nothing enforced
# that, so these stubs do: each implements exactly one platform's contract.
#
# There are TWO BSD variants here, because `-d` differs between them and that
# difference is what decides whether ORDER matters:
#
#   bsd-bin         macOS. Probed on macOS 27 (2026-08-05): `date -u -d <iso>`
#                   is `illegal option -- d`, rc 1 -- `-d` does not merely
#                   misbehave there, it does not exist. This is the operator's
#                   machine, and it is why an unparseable --now really does
#                   exit 2 on it.
#
#   bsd-legacy-bin  FreeBSD-style, and the hazard `iso_to_epoch`'s own comment
#                   names: `-d` sets daylight-saving time instead of parsing a
#                   datestring, so `date -d <iso>` is ACCEPTED AND WRONG -- it
#                   answers "now". Emulating that rather than making it fail is
#                   what makes ORDER observable: with GNU tried first on such a
#                   platform, every PR silently becomes zero days old and the
#                   alarm never fires again.
#
# Worth flagging for whoever next edits `iso_to_epoch`: its comment presents the
# accepted-and-wrong behaviour as current BSD, and on macOS that is no longer
# so. Both variants are pinned here either way.

_parse='import sys,datetime as d;print(int(d.datetime.strptime(sys.argv[1],"%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=d.timezone.utc).timestamp()))'

mkdir -p "$TMP/bsd-bin" "$TMP/bsd-legacy-bin" "$TMP/gnu-bin"

cat > "$TMP/bsd-bin/date" <<STUB
#!/usr/bin/env bash
# macOS date: supports -j -f FMT; -d is not an option at all.
set -uo pipefail
iso=''
while [ \$# -gt 0 ]; do
  case "\$1" in
    -d) echo "date: illegal option -- d" >&2; exit 1 ;;
    -u|-j) shift ;;
    -f) shift 2 ;;
    +%s) shift ;;
    *) iso="\$1"; shift ;;
  esac
done
[ -n "\$iso" ] || exec /bin/date -u +%s
exec python3 -c '$_parse' "\$iso"
STUB

cat > "$TMP/bsd-legacy-bin/date" <<STUB
#!/usr/bin/env bash
# FreeBSD-style date: supports -j -f FMT; -d sets DST and silently yields "now".
set -uo pipefail
iso=''; saw_j=false; saw_d=false
while [ \$# -gt 0 ]; do
  case "\$1" in
    -u|-j) [ "\$1" = -j ] && saw_j=true; shift ;;
    -f) shift 2 ;;
    -d) saw_d=true; shift 2 ;;
    +%s) shift ;;
    *) iso="\$1"; shift ;;
  esac
done
if [ "\$saw_d" = true ] && [ "\$saw_j" = false ]; then exec /bin/date -u +%s; fi
[ -n "\$iso" ] || exec /bin/date -u +%s
exec python3 -c '$_parse' "\$iso"
STUB

cat > "$TMP/gnu-bin/date" <<STUB
#!/usr/bin/env bash
# GNU date: supports -d DATESTRING; has no -j at all.
set -uo pipefail
iso=''
while [ \$# -gt 0 ]; do
  case "\$1" in
    -j) echo "date: invalid option -- 'j'" >&2; exit 1 ;;
    -u) shift ;;
    -f) echo "date: invalid option -- 'f'" >&2; exit 1 ;;
    -d) iso="\$2"; shift 2 ;;
    +%s) shift ;;
    *) shift ;;
  esac
done
[ -n "\$iso" ] || exec /bin/date -u +%s
exec python3 -c '$_parse' "\$iso"
STUB

chmod +x "$TMP/bsd-bin/date" "$TMP/bsd-legacy-bin/date" "$TMP/gnu-bin/date"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A stub dir preloaded with a healthy world: one release PR, a `stable` two
# minor versions behind, four commits frozen. Sections mutate it from there.
newstub() {  # newstub NAME -> echoes the dir
  local d="$TMP/stub-$1"
  mkdir -p "$d"
  printf '[]' > "$d/issues.json"
  printf '[]' > "$d/pr-comments.json"
  printf '{"nameWithOwner":"o/r"}' > "$d/repo.json"
  printf '{"name":"holacracy","version":"0.11.1"}' | base64 > "$d/stable-plugin.b64"
  printf '{".":"0.13.0"}' | base64 > "$d/pending-manifest.b64"
  cat > "$d/compare.json" <<'EOF'
{"ahead_by": 4, "commits": [
 {"commit": {"message": "feat: alpha\n\nbody text"}},
 {"commit": {"message": "fix: beta"}},
 {"commit": {"message": "docs: gamma"}},
 {"commit": {"message": "chore: delta"}}]}
EOF
  printf '%s\n' "$d"
}

# A one-PR open-PR list in the shape `gh pr list --json ...` returns.
mkprs() {  # mkprs PATH BRANCH CREATED_ISO [NUMBER]
  cat > "$1" <<EOF
[{"number": ${4:-165}, "title": "chore(main): release 0.13.0",
  "headRefName": "$2", "createdAt": "$3",
  "url": "https://github.com/o/r/pull/${4:-165}"}]
EOF
}

RELEASE_BRANCH='release-please--branches--main--components--holacracy'
NOW='2026-08-06T00:00:00Z'          # fixtures date PRs relative to this instant

# run SCRIPT STUBDIR [args...] -- always --dry-run, always a synthetic clock.
run() {
  local script="$1" stub="$2"; shift 2
  PATH="$TMP/bin:$PATH" STUB_DIR="$stub" \
    bash "$script" --repo o/r --dry-run --now "$NOW" "$@"
}

# ---------------------------------------------------------------------------
# 1. The exit-code contract. Verified by hand when #129 landed; never pinned.
#    All four codes, because the difference between "under threshold" and
#    "operational failure" is the difference between health and no evidence.
# ---------------------------------------------------------------------------
S1="$(newstub exitcodes)"

mkprs "$S1/prs.json" "$RELEASE_BRANCH" 2026-08-05T00:00:00Z       # 1 day old
out="$(run "$SCRIPT" "$S1" --pr-json "$S1/prs.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "a PR under the threshold must exit 0, got $rc: $out"
echo "$out" | grep -q 'No alarm' || fail "expected an explicit no-alarm line; got: $out"

printf '[]' > "$S1/none.json"                                     # no release PR
out="$(run "$SCRIPT" "$S1" --pr-json "$S1/none.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "no open release PR must exit 0, got $rc: $out"
echo "$out" | grep -q 'No open release PR' || fail "expected the no-release-PR line; got: $out"

mkprs "$S1/stale.json" "$RELEASE_BRANCH" 2026-08-01T00:00:00Z     # 5 days old
out="$(run "$SCRIPT" "$S1" --pr-json "$S1/stale.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "a PR past the threshold must exit 1, got $rc: $out"

# Exit 2 is usage or operational failure, never a quiet pass.
out="$(run "$SCRIPT" "$S1" --nonsense 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "an unknown argument must exit 2, got $rc: $out"

out="$(run "$SCRIPT" "$S1" --max-age-days abc 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a non-integer --max-age-days must exit 2, got $rc: $out"

out="$(run "$SCRIPT" "$S1" --max-age-days -1 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a negative --max-age-days must exit 2, got $rc: $out"

out="$(run "$SCRIPT" "$S1" --pr-json "$TMP/no-such-file.json" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a missing --pr-json file must exit 2, got $rc: $out"

echo '{not json' > "$S1/garbage.json"
out="$(run "$SCRIPT" "$S1" --pr-json "$S1/garbage.json" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "an unparseable --pr-json file must exit 2, got $rc: $out"

# An unparseable --now is exit 2, asserted under BOTH date stubs rather than
# under whichever `date` the machine happens to have. The fixture string has to
# be one NEITHER platform accepts, and that is easy to get wrong: this assertion
# first shipped with `last tuesday`, which BSD rejects and GNU cheerfully parses
# -- so it passed on the operator's Mac and failed on the Linux runner. The
# script's tolerance for `--now` is its platform's tolerance, so pin the case on
# both platforms explicitly instead of inheriting the runner's.
for datebin in "$TMP/bsd-bin" "$TMP/gnu-bin"; do
  out="$(PATH="$datebin:$TMP/bin:$PATH" STUB_DIR="$S1" bash "$SCRIPT" --repo o/r \
          --dry-run --now 'definitely-not-a-timestamp' 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || fail "an unparseable --now must exit 2 under $datebin, got $rc: $out"
done

# ---------------------------------------------------------------------------
# 2. The threshold boundary, pinned in BOTH directions. An off-by-one here is
#    invisible: `-le` cries wolf a day early forever, and the alarm firing at
#    all looks like proof it works. Only the pair of assertions distinguishes
#    them. Default threshold is 3 days.
# ---------------------------------------------------------------------------
p_boundary() {  # p_boundary SCRIPT -> 0 when the boundary is exactly right
  local script="$1" s rc; s="$(newstub "boundary-$$-$RANDOM")"
  mkprs "$s/at.json"    "$RELEASE_BRANCH" 2026-08-03T00:00:00Z   # exactly 3d
  mkprs "$s/under.json" "$RELEASE_BRANCH" 2026-08-04T00:00:00Z   # exactly 2d
  run "$script" "$s" --pr-json "$s/at.json"    >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] || return 1
  run "$script" "$s" --pr-json "$s/under.json" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || return 1
  return 0
}
p_boundary "$SCRIPT" || fail "age == threshold must alarm and threshold-1 must not"

# The threshold is configurable by env as well as by flag, so the scheduled
# workflow can set it once via `env:` rather than on every invocation.
S2="$(newstub envthreshold)"
mkprs "$S2/prs.json" "$RELEASE_BRANCH" 2026-08-01T00:00:00Z       # 5 days old
out="$(RELEASE_PR_MAX_AGE_DAYS=30 run "$SCRIPT" "$S2" --pr-json "$S2/prs.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "RELEASE_PR_MAX_AGE_DAYS should raise the threshold, got $rc: $out"
out="$(run "$SCRIPT" "$S2" --pr-json "$S2/prs.json" --max-age-days 30 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "--max-age-days should raise the threshold, got $rc: $out"

# ---------------------------------------------------------------------------
# 3. Branch matching. release-please derives its branch name from
#    release-please-config.json, so the script prefix-matches rather than
#    naming the branch -- which means the prefix has to be tight enough that a
#    human branch cannot impersonate a release. `release-please--` carries two
#    dashes deliberately; a single-dash near-miss must not match.
# ---------------------------------------------------------------------------
p_prefix() {  # p_prefix SCRIPT -> 0 when near-miss branches are NOT release PRs
  local script="$1" s; s="$(newstub "prefix-$$-$RANDOM")"
  cat > "$s/nearmiss.json" <<'EOF'
[{"number": 1, "title": "fix release notes", "headRefName": "release-notes-fix",
  "createdAt": "2026-01-01T00:00:00Z", "url": "https://github.com/o/r/pull/1"},
 {"number": 2, "title": "release-please tweak", "headRefName": "release-please-notes",
  "createdAt": "2026-01-01T00:00:00Z", "url": "https://github.com/o/r/pull/2"},
 {"number": 3, "title": "bump dep", "headRefName": "dependabot/npm/foo",
  "createdAt": "2026-01-01T00:00:00Z", "url": "https://github.com/o/r/pull/3"}]
EOF
  local out rc
  out="$(run "$script" "$s" --pr-json "$s/nearmiss.json" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || return 1
  printf '%s' "$out" | grep -q 'No open release PR' || return 1
  return 0
}
p_prefix "$SCRIPT" || fail "a near-miss branch must not be treated as a release PR"

# The real branch does match.
S3="$(newstub prefixmatch)"
mkprs "$S3/prs.json" "$RELEASE_BRANCH" 2026-08-01T00:00:00Z
out="$(run "$SCRIPT" "$S3" --pr-json "$S3/prs.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "the real release branch must match, got $rc: $out"

# Oldest wins. If release-please ever has two PRs open, the one that has been
# blocking releases longest is the one to report -- picking the newest would
# under-report the freeze, which is the exact quantity this alarm exists for.
cat > "$S3/two.json" <<'EOF'
[{"number": 200, "title": "chore(main): release 0.14.0",
  "headRefName": "release-please--branches--main--components--holacracy",
  "createdAt": "2026-08-04T00:00:00Z", "url": "https://github.com/o/r/pull/200"},
 {"number": 100, "title": "chore(main): release 0.13.0",
  "headRefName": "release-please--branches--next--components--holacracy",
  "createdAt": "2026-07-01T00:00:00Z", "url": "https://github.com/o/r/pull/100"}]
EOF
out="$(run "$SCRIPT" "$S3" --pr-json "$S3/two.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "two open release PRs should still alarm, got $rc: $out"
echo "$out" | grep -q '#100' || fail "the OLDEST release PR must be reported; got: $out"
echo "$out" | grep -q '#200' && fail "the newer release PR must not be the one reported: $out"

# ---------------------------------------------------------------------------
# 4. Report content -- the #129 acceptance criteria. Age alone is not
#    actionable; the alarm is only useful if it names what is stuck, what
#    consumers actually run, and how much is frozen behind it.
# ---------------------------------------------------------------------------
p_age() {  # p_age SCRIPT -> 0 when a 5-day-old PR is reported as 5 days
  local script="$1" s out; s="$(newstub "age-$$-$RANDOM")"
  mkprs "$s/prs.json" "$RELEASE_BRANCH" 2026-08-01T00:00:00Z     # 5d before NOW
  out="$(run "$script" "$s" --pr-json "$s/prs.json" 2>&1)"
  printf '%s' "$out" | grep -q 'open for 5 days' || return 1
  return 0
}
p_age "$SCRIPT" || fail "a 5-day-old PR must be reported as 5 days old"

S4="$(newstub report)"
mkprs "$S4/prs.json" "$RELEASE_BRANCH" 2026-08-01T00:00:00Z
out="$(run "$SCRIPT" "$S4" --pr-json "$S4/prs.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "the report fixture should alarm, got $rc: $out"

echo "$out" | grep -q 'release-pr-age-check:v1' || fail "expected the idempotency marker; got: $out"
echo "$out" | grep -q '0.13.0' || fail "expected the pending version in the report; got: $out"
echo "$out" | grep -q '0.11.1' || fail "expected the consumer-facing version in the report; got: $out"
echo "$out" | grep -q '\*\*4\*\*'  || fail "expected the frozen-commit count in the report; got: $out"
echo "$out" | grep -q 'chore: delta' || fail "expected the frozen commit subjects; got: $out"
# Subjects are first-line only -- a commit body must not leak into the table.
echo "$out" | grep -q 'body text' && fail "commit bodies must not appear in the report: $out"
# Both notification layers are announced before the non-zero exit, because an
# alarm that exits before it notifies is no alarm (script section 7).
echo "$out" | grep -q 'would upsert a sticky comment' || fail "expected the PR-comment layer; got: $out"
echo "$out" | grep -q 'would open a tracking issue' || fail "expected the tracking-issue layer; got: $out"

# Nothing reached the stub that it had not been taught. The script absorbs
# `gh api` failures into `<unknown>`, so a NEW call site would otherwise quietly
# degrade the report rather than fail anything.
[ -s "$S4/unhandled.log" ] && fail "the gh stub saw an unhandled call: $(cat "$S4/unhandled.log")"

# ---------------------------------------------------------------------------
# 5. The tracking issue auto-closes when the alarm clears. Issue #143's sibling
#    concern: an alarm that opens issues and never closes them trains everyone
#    to ignore it.
# ---------------------------------------------------------------------------
S5="$(newstub autoclose)"
cat > "$S5/issues.json" <<'EOF'
[{"number": 999, "body": "<!-- release-pr-age-check:v1 -->\nRelease PR #165 has been open..."}]
EOF
printf '[]' > "$S5/none.json"
out="$(run "$SCRIPT" "$S5" --pr-json "$S5/none.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "a cleared alarm must exit 0, got $rc: $out"
echo "$out" | grep -q 'would close tracking issue #999' \
  || fail "an open tracking issue must be closed once the release PR is gone; got: $out"

# Same, via the under-threshold path rather than the no-PR path.
mkprs "$S5/fresh.json" "$RELEASE_BRANCH" 2026-08-05T00:00:00Z
out="$(run "$SCRIPT" "$S5" --pr-json "$S5/fresh.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "an under-threshold PR must exit 0, got $rc: $out"
echo "$out" | grep -q 'would close tracking issue #999' \
  || fail "dropping back under the threshold must close the tracking issue; got: $out"

# ---------------------------------------------------------------------------
# 6. Degradation. When GitHub cannot answer, the report must say `<unknown>`
#    and warn -- never print an empty string that reads like a real version,
#    and never crash instead of alarming. The alarm's job survives a partial
#    outage.
# ---------------------------------------------------------------------------
S6="$(newstub degraded)"
rm -f "$S6/stable-plugin.b64" "$S6/compare.json" "$S6/pending-manifest.b64"
mkprs "$S6/prs.json" "$RELEASE_BRANCH" 2026-08-01T00:00:00Z
out="$(run "$SCRIPT" "$S6" --pr-json "$S6/prs.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "a degraded read must still alarm, got $rc: $out"
echo "$out" | grep -q '<unknown>' || fail "an unreadable value must render as <unknown>; got: $out"
echo "$out" | grep -q '::warning::' || fail "a degraded read must warn; got: $out"
# With the manifest unreadable the pending version falls back to the PR title,
# which is the only other place release-please writes it.
echo "$out" | grep -q '0.13.0' || fail "expected the title fallback for the pending version; got: $out"

# `stable` behind `main` with NO open release PR is its own warning: it means
# release-please soft-failed or promote-stable did not run (issue #108).
S6b="$(newstub nopr-behind)"
printf '[]' > "$S6b/none.json"
out="$(run "$SCRIPT" "$S6b" --pr-json "$S6b/none.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "no release PR must exit 0 even when stable is behind, got $rc: $out"
echo "$out" | grep -q '::warning::' || fail "stable behind main with no release PR must warn; got: $out"

# ---------------------------------------------------------------------------
# 7. `iso_to_epoch` on BOTH platforms. The script's comment says the BSD and GNU
#    calls must never be collapsed and that BSD must be tried first; nothing
#    enforced either claim. These stubs do, by implementing exactly one
#    platform's contract each. See the stub definitions above for why there are
#    two BSD variants; in short, only the legacy one makes ORDER observable.
# ---------------------------------------------------------------------------
p_on_date() {  # p_on_date SCRIPT DATEBIN -> 0 when the 5-day age is right there
  local script="$1" datebin="$2" s out; s="$(newstub "date-$$-$RANDOM")"
  mkprs "$s/prs.json" "$RELEASE_BRANCH" 2026-08-01T00:00:00Z
  out="$(PATH="$datebin:$TMP/bin:$PATH" STUB_DIR="$s" bash "$script" \
          --repo o/r --dry-run --now "$NOW" --pr-json "$s/prs.json" 2>&1)"
  printf '%s' "$out" | grep -q 'open for 5 days' || return 1
  return 0
}
p_bsd()        { p_on_date "$1" "$TMP/bsd-bin"; }
p_bsd_legacy() { p_on_date "$1" "$TMP/bsd-legacy-bin"; }
p_gnu()        { p_on_date "$1" "$TMP/gnu-bin"; }

p_bsd "$SCRIPT"        || fail "the age must be correct on macOS-style date (BSD branch)"
p_bsd_legacy "$SCRIPT" || fail "the age must be correct on FreeBSD-style date (BSD branch, tried FIRST)"
p_gnu "$SCRIPT"        || fail "the age must be correct on a GNU-only date (GNU fallback branch)"

# ---------------------------------------------------------------------------
# 8. A clock that runs backwards clamps to 0 rather than reporting a negative
#    age, which would compare as under-threshold and read as healthy.
# ---------------------------------------------------------------------------
S8="$(newstub future)"
mkprs "$S8/prs.json" "$RELEASE_BRANCH" 2026-12-01T00:00:00Z       # after NOW
out="$(run "$SCRIPT" "$S8" --pr-json "$S8/prs.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "a PR created after now must clamp to 0d and exit 0, got $rc: $out"
echo "$out" | grep -q 'is 0d old' || fail "a future-dated PR must report 0d; got: $out"

# ---------------------------------------------------------------------------
# 9. THE MUTATION PROPERTY. Each case seeds ONE defect and asserts the matching
#    property FLIPS. Without this, every section above could be green against a
#    script whose defenses had been deleted.
# ---------------------------------------------------------------------------
mutate() {  # mutate NAME SED_EXPR -> echoes the mutant's path
  local name="$1" expr="$2" out="$TMP/mutant-$1.sh"
  sed "$expr" "$SCRIPT" > "$out"
  cmp -s "$SCRIPT" "$out" \
    && fail "mutation '$name' changed nothing -- its sed no longer matches the script"
  printf '%s\n' "$out"
}

# 9a. Break the prefix filter: every open PR becomes a "release PR", so a
#     human branch impersonates a release and the alarm fires on noise.
m="$(mutate prefix 's/startswith($p)/startswith("")/')"
p_prefix "$m" && fail "mutation: breaking the branch prefix match did not fail the suite"

# 9b. Break the age arithmetic: dividing by 10x the seconds-per-day deflates
#     every age toward 0, which is the alarm going permanently silent.
m="$(mutate age 's|/ 86400 ))|/ 864000 ))|')"
p_age "$m"      && fail "mutation: breaking the age arithmetic did not fail the suite"
p_boundary "$m" && fail "mutation: breaking the age arithmetic did not fail the boundary check"

# 9c. Break the threshold comparison by one: `-le` clears at exactly the
#     threshold, so the alarm fires a day later than documented, forever.
m="$(mutate threshold 's/-lt "$MAX_AGE_DAYS"/-le "$MAX_AGE_DAYS"/')"
p_boundary "$m" && fail "mutation: off-by-one in the threshold comparison did not fail the suite"

# 9d/9e. Collapse `iso_to_epoch` to a single platform. Each mutant still passes
#        on the platform it kept, which is exactly why this would go unnoticed:
#        a GNU-only script is green on every CI runner we have and wrong on the
#        operator's Mac, where the check is also run by hand.
#
#        The BSD-removal mutant is also the closest one-line stand-in for a
#        REORDER. On the legacy platform, "BSD attempt no longer succeeds" and
#        "GNU attempt runs first" have the same consequence: the GNU form
#        answers `now` and every PR reads as zero days old.
m="$(mutate nobsd 's/date -u -j -f/false -u -j -f/')"
p_bsd "$m"        && fail "mutation: removing the BSD date branch did not fail the suite"
p_bsd_legacy "$m" && fail "mutation: removing the BSD date branch did not fail on legacy BSD"
p_gnu "$m"        || fail "the BSD-removal mutant should still work on GNU -- otherwise 9d proves nothing"

m="$(mutate nognu 's/date -u -d "$iso"/false -u -d "$iso"/')"
p_gnu "$m" && fail "mutation: removing the GNU date branch did not fail the suite"
p_bsd "$m" || fail "the GNU-removal mutant should still work on BSD -- otherwise 9e proves nothing"

echo "PASS: all release-pr-age-check tests"
