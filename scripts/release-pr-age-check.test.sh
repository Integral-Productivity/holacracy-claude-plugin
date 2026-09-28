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
# exercised (section 6). A canned `<name>.err` file makes it print that body to
# stdout and exit 1 instead, because that is what real `gh api` does on an HTTP
# error: the error body lands where the script expects the answer. Anything it
# was never taught is recorded in unhandled.log rather than merely failing,
# because the script deliberately absorbs `gh api` failures into `<unknown>` --
# a new call site would otherwise degrade the report in silence, which is the
# defect class, not a test detail.
#
# THE MUTATION PROPERTY (section 10)
# ----------------------------------
# Sections 1-9 could all pass against a script whose defenses do nothing, so
# section 10 asserts both directions the way scripts/skills-lint.test.sh does:
# for each defense there is a one-line mutation, and the suite asserts BOTH that
# the property holds on the real script AND that it FAILS on the mutant. The
# second half is what proves a check is load-bearing rather than incidentally
# covered by another. Every property used there is written as a `p_*` function
# taking the script path, so the same assertion runs against both.

# shellcheck disable=SC2016  # $p / $MAX_AGE_DAYS / $iso inside the section 10 sed
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
serve() {
  if [ -f "$STUB_DIR/$1.err" ]; then cat "$STUB_DIR/$1.err"; exit 1; fi
  [ -f "$STUB_DIR/$1" ] || exit 1; cat "$STUB_DIR/$1"
}
unhandled() { printf '%s\n' "$*" >> "$STUB_DIR/unhandled.log"; exit 1; }
case "${1:-}" in
  api)
    shift
    ep=''; for a in "$@"; do case "$a" in repos/*) ep="$a" ;; esac; done
    case "$ep" in
      */contents/.claude-plugin/plugin.json*)      serve stable-plugin.b64 ;;
      */contents/.release-please-manifest.json?ref=main) serve main-manifest.b64 ;;
      */contents/.release-please-manifest.json*)   serve pending-manifest.b64 ;;
      */compare/stable...main)                     serve compare.json ;;
      */git/matching-refs/tags/*)                  serve tag-refs.json ;;
      */commits\?*path=.release-please-manifest.json*) serve manifest-commits.json ;;
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

# A stub dir preloaded with a world where a release PR is open: `stable` on
# 0.11.1, tagged and promoted, so `main`'s manifest also says 0.11.1; the PR
# would ship 0.13.0; four commits frozen, two of them releasable (they are what
# the PR carries). Sections mutate it from there.
newstub() {  # newstub NAME -> echoes the dir
  local d="$TMP/stub-$1"
  mkdir -p "$d"
  printf '[]' > "$d/issues.json"
  printf '[]' > "$d/pr-comments.json"
  printf '{"nameWithOwner":"o/r"}' > "$d/repo.json"
  printf '{"name":"holacracy","version":"0.11.1"}' | base64 > "$d/stable-plugin.b64"
  printf '{".":"0.13.0"}' | base64 > "$d/pending-manifest.b64"
  printf '{".":"0.11.1"}' | base64 > "$d/main-manifest.b64"
  printf '[{"ref":"refs/tags/v0.11.1"}]' > "$d/tag-refs.json"
  printf '[{"commit":{"committer":{"date":"2026-07-20T00:00:00Z"}}}]' > "$d/manifest-commits.json"
  cat > "$d/compare.json" <<'EOF'
{"ahead_by": 4, "commits": [
 {"commit": {"message": "feat: alpha\n\nbody text", "committer": {"date": "2026-08-01T00:00:00Z"}}},
 {"commit": {"message": "fix: beta", "committer": {"date": "2026-08-02T00:00:00Z"}}},
 {"commit": {"message": "docs: gamma", "committer": {"date": "2026-08-03T00:00:00Z"}}},
 {"commit": {"message": "chore: delta", "committer": {"date": "2026-08-04T00:00:00Z"}}}]}
EOF
  printf '%s\n' "$d"
}

# Replace the delta with commits release-please would never release. With no
# release PR open this is the normal steady state after a docs-only merge, and
# must not alarm (issue #145).
docsonly() {  # docsonly STUBDIR
  cat > "$1/compare.json" <<'EOF'
{"ahead_by": 3, "commits": [
 {"commit": {"message": "docs: gamma", "committer": {"date": "2026-08-01T00:00:00Z"}}},
 {"commit": {"message": "ci(deps): bump action", "committer": {"date": "2026-08-02T00:00:00Z"}}},
 {"commit": {"message": "chore(deps)(deps): bump a reusable workflow", "committer": {"date": "2026-08-03T00:00:00Z"}}}]}
EOF
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
S1d="$(newstub exitcodes-docsonly)"; docsonly "$S1d"
out="$(run "$SCRIPT" "$S1d" --pr-json "$S1/none.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "no open release PR with nothing releasable must exit 0, got $rc: $out"
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

out="$(run "$SCRIPT" "$S1" --grace-hours soon 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || fail "a non-integer --grace-hours must exit 2, got $rc: $out"

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
  docsonly "$s"
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
# alarm that exits before it notifies is no alarm (script section 8).
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
S5d="$(newstub autoclose-docsonly)"; docsonly "$S5d"; cp "$S5/issues.json" "$S5d/issues.json"
out="$(run "$SCRIPT" "$S5d" --pr-json "$S5/none.json" 2>&1)"; rc=$?
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

# `stable` behind `main` with NO open release PR used to be a bare warning on
# exit 0. Section 9 pins what it is now (issue #145). Here: when the reads that
# tell the causes apart all fail, the run warns rather than inventing a verdict.
S6b="$(newstub nopr-degraded)"
rm -f "$S6b/main-manifest.b64" "$S6b/compare.json"
printf '[]' > "$S6b/none.json"
out="$(run "$SCRIPT" "$S6b" --pr-json "$S6b/none.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "no release PR with nothing readable must exit 0, got $rc: $out"
echo "$out" | grep -q "could not read .release-please-manifest.json from 'main'" \
  || fail "an unreadable main manifest must warn; got: $out"

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
# 9. A release stalled with NO release PR open (issue #145). Three causes, each
#    told apart and named, and a docs-only delta that must stay quiet. #310 is
#    the case that motivated it: the release PR merged, release-please failed
#    at the tag step, and this script said "cleared" for about 15 hours.
# ---------------------------------------------------------------------------
NONE="$TMP/none.json"; printf '[]' > "$NONE"

p_docs_only_quiet() {  # a docs/ci/chore-only delta is the steady state: exit 0
  local script="$1" s out rc; s="$(newstub "docs-$$-$RANDOM")"; docsonly "$s"
  out="$(run "$script" "$s" --pr-json "$NONE" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || return 1
  printf '%s' "$out" | grep -q 'None of them is releasable' || return 1
  return 0
}
p_docs_only_quiet "$SCRIPT" || fail "a docs/ci/chore-only delta with no release PR must not alarm"

p_releasable_alarms() {  # feat/fix waiting, no PR, past grace: exit 1, cause named
  local script="$1" s out rc; s="$(newstub "rel-$$-$RANDOM")"
  out="$(run "$script" "$s" --pr-json "$NONE" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || return 1
  printf '%s' "$out" | grep -q 'release-please did not open a release PR' || return 1
  return 0
}
p_releasable_alarms "$SCRIPT" || fail "a releasable commit with no release PR past the grace window must alarm"

S9="$(newstub stall-report)"
out="$(run "$SCRIPT" "$S9" --pr-json "$NONE" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "the stall fixture should alarm, got $rc: $out"
echo "$out" | grep -q 'release-pr-age-check:v1' || fail "the stall report must carry the shared marker; got: $out"
echo "$out" | grep -q '| Of those, releasable | \*\*2\*\* |' || fail "expected 2 releasable commits; got: $out"
echo "$out" | grep -q -- '- feat: alpha' || fail "expected the releasable subjects; got: $out"
echo "$out" | grep -q -- '- docs: gamma' && fail "a docs commit must not be listed as releasable: $out"
echo "$out" | grep -q 'release-please.yml' || fail "the report must say where to look; got: $out"
echo "$out" | grep -q 'would open a tracking issue' || fail "expected the tracking-issue layer; got: $out"
echo "$out" | grep -q 'sticky comment' && fail "there is no release PR to comment on: $out"
[ -s "$S9/unhandled.log" ] && fail "the gh stub saw an unhandled call: $(cat "$S9/unhandled.log")"

# Which commit types count. Breaking changes of any type count; `chore(deps)`
# (Dependabot's prefix here) does not, and neither does `ci:`.
S9t="$(newstub stall-types)"
cat > "$S9t/compare.json" <<'EOF'
{"ahead_by": 4, "commits": [
 {"commit": {"message": "chore(deps)(deps): bump x", "committer": {"date": "2026-08-01T00:00:00Z"}}},
 {"commit": {"message": "refactor!: drop the old flag", "committer": {"date": "2026-08-01T00:00:00Z"}}},
 {"commit": {"message": "docs: explain\n\nBREAKING CHANGE: the path moved", "committer": {"date": "2026-08-01T00:00:00Z"}}},
 {"commit": {"message": "perf(lint): faster", "committer": {"date": "2026-08-01T00:00:00Z"}}}]}
EOF
out="$(run "$SCRIPT" "$S9t" --pr-json "$NONE" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "breaking changes and perf must count as releasable, got $rc: $out"
echo "$out" | grep -q '| Of those, releasable | \*\*3\*\* |' \
  || fail "expected exactly 3 releasable (not chore(deps)); got: $out"

# The grace window, pinned in BOTH directions like the age threshold. Default 2h.
p_grace_boundary() {
  local script="$1" s rc; s="$(newstub "grace-$$-$RANDOM")"
  cat > "$s/compare.json" <<'EOF'
{"ahead_by": 1, "commits": [
 {"commit": {"message": "feat: new", "committer": {"date": "2026-08-05T22:00:00Z"}}}]}
EOF
  run "$script" "$s" --pr-json "$NONE" >/dev/null 2>&1; rc=$?     # exactly 2h
  [ "$rc" -eq 1 ] || return 1
  sed -i.bak 's/2026-08-05T22:00:00Z/2026-08-05T23:00:00Z/' "$s/compare.json"
  run "$script" "$s" --pr-json "$NONE" >/dev/null 2>&1; rc=$?     # exactly 1h
  [ "$rc" -eq 0 ] || return 1
  return 0
}
p_grace_boundary "$SCRIPT" || fail "stall age == grace must alarm and grace-1 must not"

S9g="$(newstub grace-knob)"
out="$(RELEASE_STALL_GRACE_HOURS=1000 run "$SCRIPT" "$S9g" --pr-json "$NONE" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "RELEASE_STALL_GRACE_HOURS should widen the window, got $rc: $out"
out="$(run "$SCRIPT" "$S9g" --pr-json "$NONE" --grace-hours 1000 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "--grace-hours should widen the window, got $rc: $out"

# Acceptance criterion from #310: while a releasable change waits, the run
# must NOT report "cleared" -- inside the grace window included.
p_no_close_while_waiting() {
  local script="$1" s out; s="$(newstub "noclose-$$-$RANDOM")"
  cat > "$s/issues.json" <<'EOF'
[{"number": 999, "body": "<!-- release-pr-age-check:v1 -->\nA release has stalled..."}]
EOF
  cat > "$s/compare.json" <<'EOF'
{"ahead_by": 1, "commits": [
 {"commit": {"message": "fix: new", "committer": {"date": "2026-08-05T23:30:00Z"}}}]}
EOF
  out="$(run "$script" "$s" --pr-json "$NONE" 2>&1)"
  printf '%s' "$out" | grep -q 'inside the 2h grace window' || return 1
  printf '%s' "$out" | grep -q 'would close tracking issue' && return 1
  out="$(run "$script" "$s" --pr-json "$NONE" --grace-hours 0 2>&1)"
  printf '%s' "$out" | grep -q 'would update tracking issue #999' || return 1
  printf '%s' "$out" | grep -q 'would close tracking issue' && return 1
  return 0
}
p_no_close_while_waiting "$SCRIPT" || fail "a waiting releasable change must never close the tracking issue"

# A stall that cannot be dated is still a stall: unknown age alarms.
p_undated_alarms() {
  local script="$1" s rc; s="$(newstub "undated-$$-$RANDOM")"
  printf '{"ahead_by": 1, "commits": [{"commit": {"message": "feat: x"}}]}' > "$s/compare.json"
  run "$script" "$s" --pr-json "$NONE" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] || return 1
  return 0
}
p_undated_alarms "$SCRIPT" || fail "a stall with no readable date must alarm, not read as fresh"

# Cause 1 (#310): the manifest on main names a version with no tag. Caught even
# with a docs-only delta, because it needs no commit-type parsing at all.
p_tag_missing() {
  local script="$1" s out rc; s="$(newstub "tagmiss-$$-$RANDOM")"; docsonly "$s"
  printf '{".":"0.20.0"}' | base64 > "$s/main-manifest.b64"
  printf '[]' > "$s/tag-refs.json"
  out="$(run "$script" "$s" --pr-json "$NONE" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || return 1
  printf '%s' "$out" | grep -q 'failed AFTER the release PR merged' || return 1
  printf '%s' "$out" | grep -q 'release-please-fails-when-release-app-lacks-workflows-permission' || return 1
  return 0
}
p_tag_missing "$SCRIPT" || fail "a merged release with no tag must alarm and name the #310 cause"

# The tag match is exact. matching-refs is a PREFIX match, so v0.2.0 would also
# return v0.2.01; a near-miss tag must not count as the release.
p_tag_exact() {
  local script="$1" s out rc; s="$(newstub "tagexact-$$-$RANDOM")"; docsonly "$s"
  # stable matches main, so a wrongly "present" tag leaves no other cause to
  # fall into -- the promotion check must not mask this property.
  printf '{"name":"holacracy","version":"0.2.0"}' | base64 > "$s/stable-plugin.b64"
  printf '{".":"0.2.0"}' | base64 > "$s/main-manifest.b64"
  printf '[{"ref":"refs/tags/v0.2.01"}]' > "$s/tag-refs.json"
  out="$(run "$script" "$s" --pr-json "$NONE" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || return 1
  printf '%s' "$out" | grep -q 'failed AFTER the release PR merged' || return 1
  return 0
}
p_tag_exact "$SCRIPT" || fail "a prefix-only tag match must not count as the release being tagged"

# Cause 2 (#108): tagged, but stable was not promoted.
S9p="$(newstub promotion)"; docsonly "$S9p"
printf '{".":"0.12.0"}' | base64 > "$S9p/main-manifest.b64"
printf '[{"ref":"refs/tags/v0.12.0"}]' > "$S9p/tag-refs.json"
out="$(run "$SCRIPT" "$S9p" --pr-json "$NONE" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "a tag that never reached stable must alarm, got $rc: $out"
echo "$out" | grep -q 'promotion failed' || fail "expected the promotion cause; got: $out"
echo "$out" | grep -q 'Promote to stable' || fail "expected where to look; got: $out"

# The manifest-change date also gates causes 1 and 2: a release merged an hour
# ago may simply not be tagged yet.
S9f="$(newstub tag-fresh)"; docsonly "$S9f"
printf '{".":"0.20.0"}' | base64 > "$S9f/main-manifest.b64"
printf '[]' > "$S9f/tag-refs.json"
printf '[{"commit":{"committer":{"date":"2026-08-05T23:00:00Z"}}}]' > "$S9f/manifest-commits.json"
out="$(run "$SCRIPT" "$S9f" --pr-json "$NONE" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "a release merged inside the grace window must not alarm yet, got $rc: $out"

# An unreadable tag list warns and falls through to the commit-type rule.
S9u="$(newstub tag-unreadable)"
rm -f "$S9u/tag-refs.json"
out="$(run "$SCRIPT" "$S9u" --pr-json "$NONE" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "an unreadable tag list must still reach the commit-type rule, got $rc: $out"
echo "$out" | grep -q 'could not list tags' || fail "an unreadable tag list must warn; got: $out"

# The stall is dated from the OLDEST waiting releasable commit. Here the oldest
# is past the window and the newest is inside it, so it must alarm.
p_oldest_commit_dates() {
  local script="$1" s rc; s="$(newstub "oldest-$$-$RANDOM")"
  cat > "$s/compare.json" <<'EOF'
{"ahead_by": 2, "commits": [
 {"commit": {"message": "feat: older", "committer": {"date": "2026-08-05T20:00:00Z"}}},
 {"commit": {"message": "fix: newer", "committer": {"date": "2026-08-05T23:30:00Z"}}}]}
EOF
  run "$script" "$s" --pr-json "$NONE" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] || return 1
  return 0
}
p_oldest_commit_dates "$SCRIPT" || fail "a stall must be dated from its oldest releasable commit"

# A failed compare. Real `gh api` prints the error body to stdout, so the
# script must not parse that body as a comparison. It used to, and died in jq
# with exit 5: no report, no stall check, outside the 0/1/2 contract.
S9e="$(newstub compare-error)"
rm -f "$S9e/compare.json"
printf '{"message":"Not Found","documentation_url":"https://docs.github.com/rest"}' > "$S9e/compare.json.err"
out="$(run "$SCRIPT" "$S9e" --pr-json "$NONE" 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; } || fail "a compare error body must give exit 0 or 1, got $rc: $out"
echo "$out" | grep -q 'No open release PR' || fail "a compare error body must still print the report; got: $out"
echo "$out" | grep -q "could not compare 'stable...main'" || fail "a compare error body must warn; got: $out"
echo "$out" | grep -q 'Commits on main not yet on stable: <unknown>' \
  || fail "a compare error body must report the count as <unknown>; got: $out"
# The tag-missing cause needs no compare data, so it must still fire.
printf '{".":"0.20.0"}' | base64 > "$S9e/main-manifest.b64"
printf '[]' > "$S9e/tag-refs.json"
out="$(run "$SCRIPT" "$S9e" --pr-json "$NONE" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "tag-missing must still alarm when the compare fails, got $rc: $out"
# Same on the release-PR path, which reads the compare too.
S9e2="$(newstub compare-error-pr)"
rm -f "$S9e2/compare.json"
printf '{"message":"Server Error"}' > "$S9e2/compare.json.err"
mkprs "$S9e2/prs.json" "$RELEASE_BRANCH" 2026-08-01T00:00:00Z
out="$(run "$SCRIPT" "$S9e2" --pr-json "$S9e2/prs.json" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || fail "a stale PR with a compare error body must still alarm, got $rc: $out"

# Missing evidence is not "cleared". When a read the stall check depends on
# fails and no stall is found, the run warns and leaves the tracking issue open.
p_gap_keeps_issue_open() {
  local script="$1" s out
  s="$(newstub "gap-compare-$$-$RANDOM")"
  cat > "$s/issues.json" <<'EOF'
[{"number": 999, "body": "<!-- release-pr-age-check:v1 -->\nA release has stalled..."}]
EOF
  rm -f "$s/compare.json"
  out="$(run "$script" "$s" --pr-json "$NONE" 2>&1)" || return 1
  printf '%s' "$out" | grep -q 'would close tracking issue' && return 1
  printf '%s' "$out" | grep -q 'inconclusive' || return 1

  s="$(newstub "gap-manifest-$$-$RANDOM")"; docsonly "$s"
  cat > "$s/issues.json" <<'EOF'
[{"number": 999, "body": "<!-- release-pr-age-check:v1 -->\nA release has stalled..."}]
EOF
  rm -f "$s/main-manifest.b64"
  out="$(run "$script" "$s" --pr-json "$NONE" 2>&1)" || return 1
  printf '%s' "$out" | grep -q 'would close tracking issue' && return 1
  printf '%s' "$out" | grep -q 'inconclusive' || return 1
  return 0
}
p_gap_keeps_issue_open "$SCRIPT" || fail "an unreadable input must leave the tracking issue open, not close it"

# The same on the release-PR path: a young PR with `stable` unreadable cannot
# rule out a failed promotion, so it must not close the issue either.
S9gp="$(newstub gap-pr)"
cp "$S5/issues.json" "$S9gp/issues.json"
rm -f "$S9gp/stable-plugin.b64"
mkprs "$S9gp/prs.json" "$RELEASE_BRANCH" 2026-08-05T00:00:00Z
out="$(run "$SCRIPT" "$S9gp" --pr-json "$S9gp/prs.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "a young PR with stable unreadable must exit 0, got $rc: $out"
echo "$out" | grep -q 'would close tracking issue' && fail "an unreadable stable must not close the tracking issue: $out"

# promotion-failed while a release PR IS open. After a failed promotion the
# next releasable merge makes release-please open a new PR. A young PR must not
# hide the stall, and must not close the tracking issue that reports it.
promotion_with_pr() {  # promotion_with_pr NAME MANIFEST_DATE -> echoes the stub dir
  local s; s="$(newstub "$1")"
  cp "$S5/issues.json" "$s/issues.json"
  printf '{".":"0.12.0"}' | base64 > "$s/main-manifest.b64"
  printf '[{"ref":"refs/tags/v0.12.0"}]' > "$s/tag-refs.json"
  printf '[{"commit":{"committer":{"date":"%s"}}}]' "$2" > "$s/manifest-commits.json"
  mkprs "$s/prs.json" "$RELEASE_BRANCH" 2026-08-05T00:00:00Z       # 1 day old
  printf '%s\n' "$s"
}
p_promotion_with_pr() {
  local script="$1" s out rc; s="$(promotion_with_pr "promopr-$$-$RANDOM" 2026-07-20T00:00:00Z)"
  out="$(run "$script" "$s" --pr-json "$s/prs.json" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || return 1
  printf '%s' "$out" | grep -q 'promotion failed' || return 1
  printf '%s' "$out" | grep -q 'while release PR #165 is open' || return 1
  printf '%s' "$out" | grep -q 'would update tracking issue #999' || return 1
  printf '%s' "$out" | grep -q 'would close tracking issue' && return 1
  return 0
}
p_promotion_with_pr "$SCRIPT" || fail "a failed promotion must alarm even while a young release PR is open"

S9pg="$(promotion_with_pr promotion-pr-grace 2026-08-05T23:00:00Z)"
out="$(run "$SCRIPT" "$S9pg" --pr-json "$S9pg/prs.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "a failed promotion inside the grace window must not alarm yet, got $rc: $out"
echo "$out" | grep -q 'inside the 2h grace window' || fail "expected the grace-window line; got: $out"
echo "$out" | grep -q 'would close tracking issue' && fail "a failed promotion inside the window must not close the issue: $out"
[ -s "$S9pg/unhandled.log" ] && fail "the gh stub saw an unhandled call: $(cat "$S9pg/unhandled.log")"

# ---------------------------------------------------------------------------
# 10. THE MUTATION PROPERTY. Each case seeds ONE defect and asserts the matching
#    property FLIPS. Without this, every section above could be green against a
#    script whose defenses had been deleted.
# ---------------------------------------------------------------------------
# mutate runs inside `$(...)`, so a `fail` in it would only end the subshell.
# It returns non-zero instead, and every call site checks that. Without the
# check, a sed that stopped matching would hand back an unchanged copy (or no
# file at all), the property would "fail" on it, and the case would pass while
# testing nothing.
mutate() {  # mutate NAME SED_EXPR -> echoes the mutant's path
  local expr="$2" out="$TMP/mutant-$1.sh"
  sed "$expr" "$SCRIPT" > "$out" || return 1
  cmp -s "$SCRIPT" "$out" && return 1
  printf '%s\n' "$out"
}

# Self-test: a sed that matches nothing must make mutate fail, or every
# "could not be built" check below is unreachable.
if mutate selftest 's/this text is deliberately absent from the script/x/' >/dev/null 2>&1; then
  fail "mutate accepted a sed that matches nothing; every mutation case below is vacuous"
fi

# 10a. Break the prefix filter: every open PR becomes a "release PR", so a
#      human branch impersonates a release and the alarm fires on noise.
m="$(mutate prefix 's/startswith($p)/startswith("")/')" || fail "mutation prefix could not be built"
p_prefix "$m" && fail "mutation: breaking the branch prefix match did not fail the suite"

# 10b. Break the age arithmetic: dividing by 10x the seconds-per-day deflates
#      every age toward 0, which is the alarm going permanently silent.
m="$(mutate age 's|/ 86400 ))|/ 864000 ))|')" || fail "mutation age could not be built"
p_age "$m"      && fail "mutation: breaking the age arithmetic did not fail the suite"
p_boundary "$m" && fail "mutation: breaking the age arithmetic did not fail the boundary check"

# 10c. Break the threshold comparison by one: `-le` clears at exactly the
#      threshold, so the alarm fires a day later than documented, forever.
m="$(mutate threshold 's/-lt "$MAX_AGE_DAYS"/-le "$MAX_AGE_DAYS"/')" || fail "mutation threshold could not be built"
p_boundary "$m" && fail "mutation: off-by-one in the threshold comparison did not fail the suite"

# 10d/10e. Collapse `iso_to_epoch` to a single platform. Each mutant still passes
#          on the platform it kept, which is exactly why this would go unnoticed:
#          a GNU-only script is green on every CI runner we have and wrong on the
#          operator's Mac, where the check is also run by hand.
#
#          The BSD-removal mutant is also the closest one-line stand-in for a
#          REORDER. On the legacy platform, "BSD attempt no longer succeeds" and
#          "GNU attempt runs first" have the same consequence: the GNU form
#          answers `now` and every PR reads as zero days old.
m="$(mutate nobsd 's/date -u -j -f/false -u -j -f/')" || fail "mutation nobsd could not be built"
p_bsd "$m"        && fail "mutation: removing the BSD date branch did not fail the suite"
p_bsd_legacy "$m" && fail "mutation: removing the BSD date branch did not fail on legacy BSD"
p_gnu "$m"        || fail "the BSD-removal mutant should still work on GNU -- otherwise 10d proves nothing"

m="$(mutate nognu 's/date -u -d "$iso"/false -u -d "$iso"/')" || fail "mutation nognu could not be built"
p_gnu "$m" && fail "mutation: removing the GNU date branch did not fail the suite"
p_bsd "$m" || fail "the GNU-removal mutant should still work on BSD -- otherwise 10e proves nothing"

# 10f-10o. The issue #145 stall detection (section 9).

# 10f. Treat every commit type as releasable: a docs-only merge alarms.
m="$(mutate alltypes "s/^RELEASABLE_TYPES='feat|fix|perf|revert|deps'/RELEASABLE_TYPES='[a-z]+'/")" || fail "mutation alltypes could not be built"
p_docs_only_quiet "$m" && fail "mutation: counting every commit type as releasable did not fail the suite"

# 10g. Treat no commit type as releasable: the soft-failure stall goes silent.
m="$(mutate notypes "s/^RELEASABLE_TYPES='feat|fix|perf|revert|deps'/RELEASABLE_TYPES='none'/")" || fail "mutation notypes could not be built"
p_releasable_alarms "$m" && fail "mutation: counting no commit type as releasable did not fail the suite"

# 10h. Off-by-one in the grace comparison.
m="$(mutate grace 's/-lt "$GRACE_HOURS"/-le "$GRACE_HOURS"/')" || fail "mutation grace could not be built"
p_grace_boundary "$m" && fail "mutation: off-by-one in the grace comparison did not fail the suite"

# 10i. Close the tracking issue from inside the grace window -- the #310
#      acceptance criterion, broken on the one path where it is easy to break.
m="$(mutate closewaiting 's/^    echo "  The tracking issue is left as it is/    close_tracking_issue x; echo "  The tracking issue is left as it is/')" || fail "mutation closewaiting could not be built"
p_no_close_while_waiting "$m" && fail "mutation: closing the issue while a change waits did not fail the suite"

# 10j. Read an undated stall as fresh.
m="$(mutate undated 's/\[ -n "$stall_hours" \] \&\& \[ "$stall_hours" -lt/[ -z "$stall_hours" ] || [ "$stall_hours" -lt/')" || fail "mutation undated could not be built"
p_undated_alarms "$m" && fail "mutation: reading an undated stall as fresh did not fail the suite"

# 10k. Drop the tag-missing cause entirely.
m="$(mutate notagcheck 's/if \[ "$tag_state" = absent \]; then/if false; then/')" || fail "mutation notagcheck could not be built"
p_tag_missing "$m" && fail "mutation: dropping the tag-missing check did not fail the suite"

# 10l. Accept a prefix-only tag match.
m="$(mutate tagprefix 's/any(.\[\]; .ref == $r)/any(.[]; .ref | startswith($r))/')" || fail "mutation tagprefix could not be built"
p_tag_exact "$m" && fail "mutation: accepting a prefix-only tag match did not fail the suite"

# 10m. Close the tracking issue even when a read the stall check needs failed.
m="$(mutate gapclose 's/    if \[ -n "$evidence_gaps" \]; then/    if false; then/')" || fail "mutation gapclose could not be built"
p_gap_keeps_issue_open "$m" && fail "mutation: closing the issue on missing evidence did not fail the suite"

# 10n. Skip the promotion check while a release PR is open: a young PR hides
#      the stall and closes its tracking issue.
m="$(mutate promopr 's/if \[ "$promotion_failed" = true \] \&\& ! stall_inside_grace/if false \&\& ! stall_inside_grace/')" || fail "mutation promopr could not be built"
p_promotion_with_pr "$m" && fail "mutation: skipping the promotion check on the release-PR path did not fail the suite"

# 10o. Date the stall from the NEWEST releasable commit instead of the oldest.
m="$(mutate newestdate "s/jq -r '.\[0\].date'/jq -r '.[-1].date'/")" || fail "mutation newestdate could not be built"
p_oldest_commit_dates "$m" && fail "mutation: dating the stall from the newest commit did not fail the suite"

echo "PASS: all release-pr-age-check tests"
