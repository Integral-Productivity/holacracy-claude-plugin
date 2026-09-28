#!/usr/bin/env bash
#
# release-pr-age-check.sh — alarm when a release PR sits open too long.
#
# WHY THIS EXISTS
# ---------------
# "Shipped" means two different things to two different audiences:
#
#   - to the author, it means MERGED TO MAIN;
#   - to every consumer, it means RELEASED, PROMOTED TO `stable`, AND LOADED.
#
# Those two meanings drift apart for exactly as long as the release PR sits
# open, because the marketplace installs from the `stable` branch and `stable`
# only advances when `promote-stable.yml` fires on a `vX.Y.Z` tag — which only
# exists once the release PR merges.
#
# They drifted 34 days once. v0.6.0 was tagged 2026-06-23; PR #70 merged the
# SessionStart role-grounding directive on 2026-07-20; the next tag was v0.10.0
# on 2026-07-27. Every session in that window ran pre-directive code no matter
# what, which invalidated the Check phase of the PDCA-1 grounding experiment.
# Nothing anywhere reported that. See issue #129 (this script) and #122 (the
# failure it was extracted from).
#
# `version-authority.yml` guards that the version files are CORRECT. This
# guards that a correct version actually SHIPS.
#
# WHAT IT REPORTS
# ---------------
# Age alone is not actionable. The report also names, from live state:
#
#   - the version waiting to ship  (the release PR's `.release-please-manifest.json`)
#   - the version consumers run    (`.claude-plugin/plugin.json` $.version on `stable`)
#   - how many merged commits are frozen behind it (`compare/stable...main`)
#   - the subject lines of those commits
#
# It reads `stable` rather than `git tag --list` deliberately: a tag can exist
# while promotion has failed (that is issue #108), and in that state consumers
# are still on the older version. `stable` is what they actually install.
#
# THE RELEASE PR THAT NEVER CAME (issue #145)
# -------------------------------------------
# An old release PR is one way to stop shipping. Having NO release PR while a
# releasable change waits is the other, and it is worse: nothing is old, so
# nothing looks wrong. Three causes lead there, and the no-release-PR path
# tells them apart, in this order:
#
#   tag-missing       main's `.release-please-manifest.json` names a version
#                     with no `vX.Y.Z` tag. The release PR merged but did not
#                     release: release-please hard-failed at its tag or
#                     GitHub-release step. This is #310 — `stable` sat on
#                     0.19.1 for about 15 hours while this script said
#                     "cleared".
#   promotion-failed  the tag exists but `stable` still carries an older
#                     version: `promote-stable.yml` did not fast-forward it
#                     (issue #108). This one is checked whether or not a
#                     release PR is open: the next releasable merge makes
#                     release-please open a new PR, and a young PR must not
#                     hide it.
#   no-release-pr     a releasable commit (feat, fix, perf, revert, deps, or
#                     any breaking change) is on `main` but not on `stable`,
#                     and release-please never opened a PR for it. That is its
#                     documented soft-failure path: missing credentials exit 0.
#
# A docs-, ci- or chore-only delta is NOT a stall. release-please does not open
# a PR for those, so "stable behind main, no release PR" is the normal steady
# state after such a merge.
#
# Each stall alarms only once it is older than a grace window, measured from
# the manifest change (the first two causes) or the oldest waiting releasable
# commit (the third). release-please normally acts within a minute or two of a
# push, so the window only absorbs a scheduled run that lands mid-release. While
# a stall is inside the window, the run neither alarms nor closes the tracking
# issue: "cleared" is never reported while a releasable change is waiting.
#
# Nor is it reported when a read the stall check needs has failed (`stable`,
# the compare, main's manifest, the tag list). The run warns that the check was
# inconclusive and leaves the tracking issue open.
#
# EXIT CODES
# ----------
#   0  no release PR open and nothing releasable waiting (or still inside the
#      grace window), or the release PR is younger than the threshold
#   1  ALARM — a release PR is at or past the threshold, or a release has
#      stalled (notifications sent)
#   2  usage error or an operational failure (gh/network/parse)
#
# Exit 1 is deliberate: it turns the scheduled run red in the Actions tab, which
# is the third notification layer behind the PR comment and the tracking issue.
# Notifications are always sent BEFORE the non-zero exit.
#
# VERIFICATION AFFORDANCES
# ------------------------
# `--now` and `--pr-json` exist so the alarm path can be demonstrated without
# waiting for a real release PR to go stale — issue #129's acceptance criteria
# call for "a dry run against a synthetic date". Neither is used by the
# workflow; both are inert in production. Shipping an alarm nobody has ever
# seen fire is the same fail-silent shape this script exists to catch.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

# Three days, not seven. The observed failure was 34 days, but the harm
# threshold is much lower than that: PR #70 was unshippable for 7 days and that
# alone was enough to invalidate an experiment. Three days lets a Friday merge
# survive the weekend and alarm on Monday, which is the shortest window that
# does not manufacture noise for normal working rhythm.
DEFAULT_MAX_AGE_DAYS=3

# Two hours for a release with no release PR (issue #145). release-please opens
# its PR, and tags on merge, within a minute or two of a push to main. Two
# hours covers a queued runner and a slow retry. It is still short enough that
# the daily run catches a stall the same day it starts.
DEFAULT_GRACE_HOURS=2

# The commit types release-please treats as releasable: the ones in its default
# visible changelog sections. docs/ci/chore/test/style/refactor/build do not
# open a release PR. Any type with `!`, or a BREAKING CHANGE footer, also counts.
RELEASABLE_TYPES='feat|fix|perf|revert|deps'

# release-please derives its branch name from release-please-config.json
# (branch + package-name), so it changes if that config changes. Today it is
# `release-please--branches--main--components--holacracy`. Prefix-match, never
# exact-match — this is the same precedent version-authority.yml sets.
RELEASE_BRANCH_PREFIX='release-please--'

# Idempotency marker. Both the PR comment and the tracking issue carry it, and
# both are found by matching it rather than by title, so the title is free to
# change on every run (it carries the age, which is the point).
MARKER='<!-- release-pr-age-check:v1 -->'

ISSUE_LABELS='["ci","main-health"]'

MAX_AGE_DAYS="${RELEASE_PR_MAX_AGE_DAYS:-$DEFAULT_MAX_AGE_DAYS}"
GRACE_HOURS="${RELEASE_STALL_GRACE_HOURS:-$DEFAULT_GRACE_HOURS}"
REPO="${GITHUB_REPOSITORY:-}"
NOW_ISO=''
PR_JSON_FILE=''
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/release-pr-age-check.sh [options]

  --repo OWNER/NAME     Repository to inspect. Default: $GITHUB_REPOSITORY,
                        else the repo `gh` resolves from the working directory.
  --max-age-days N      Alarm at or past N days old.
                        Default: $RELEASE_PR_MAX_AGE_DAYS, else 3.
  --grace-hours N       Alarm once a stalled release has waited N hours or
                        more (issue #145).
                        Default: $RELEASE_STALL_GRACE_HOURS, else 2.
  --dry-run             Print the report; make no writes to GitHub.
  --now ISO8601         Treat this instant as "now" (e.g. 2026-08-20T00:00:00Z).
                        Verification affordance; unused in CI.
  --pr-json PATH        Read the open-PR list from this file instead of calling
                        `gh pr list`. Same shape as:
                          gh pr list --state open \
                            --json number,title,headRefName,createdAt,url
                        Substitutes PR METADATA only — reads of `stable`, of
                        the PR's head branch, of main's release manifest, of
                        the tag list and of the manifest's last-change date
                        still hit the live repo, so a fixture naming a branch
                        that exists will report that branch's real pending
                        version, not the fixture's title.
                        Verification affordance; unused in CI.
  -h, --help            This text.

Exit: 0 = clear or under threshold, 1 = alarm raised, 2 = usage/operational error.
EOF
}

die() {
  echo "::error title=release-pr-age-check::$*" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)          REPO="${2:-}";          shift 2 ;;
    --max-age-days)  MAX_AGE_DAYS="${2:-}";  shift 2 ;;
    --grace-hours)   GRACE_HOURS="${2:-}";   shift 2 ;;
    --now)           NOW_ISO="${2:-}";       shift 2 ;;
    --pr-json)       PR_JSON_FILE="${2:-}";  shift 2 ;;
    --dry-run)       DRY_RUN=true;           shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage >&2; die "unknown argument: $1" ;;
  esac
done

case "$MAX_AGE_DAYS" in
  ''|*[!0-9]*) die "--max-age-days must be a non-negative integer, got '$MAX_AGE_DAYS'" ;;
esac
case "$GRACE_HOURS" in
  ''|*[!0-9]*) die "--grace-hours must be a non-negative integer, got '$GRACE_HOURS'" ;;
esac

command -v gh >/dev/null 2>&1 || die "the GitHub CLI (gh) is required and was not found on PATH"
command -v jq >/dev/null 2>&1 || die "jq is required and was not found on PATH"

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
  [ -n "$REPO" ] || die "could not determine the repository; pass --repo OWNER/NAME"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Parse an ISO-8601 Zulu timestamp to a Unix epoch, on either BSD or GNU date.
#
# BSD is tried FIRST and with an explicit format string, because it is strict:
# it fails cleanly on input it cannot parse, and it has no GNU-style
# `-d "<datestring>"` parsing mode. What BSD does with `-d` instead differs by
# variant, and both are why the ordering is load-bearing:
#
#   macOS        `-d` is not an option at all. Probed on macOS 27 (2026-08-05),
#                `date -u -d '2026-08-01T00:00:00Z' +%s` is
#                `date: illegal option -- d`, rc 1. A GNU-shaped call fails
#                cleanly here, so the damage from a wrong order would be a
#                false alarm, not a silent one.
#
#   FreeBSD-style  `-d` sets daylight-saving time rather than parsing a
#                datestring, so `date -d "<iso>"` is accepted-and-WRONG: it
#                answers "now". Try GNU first on such a platform and every PR
#                silently reads as zero days old and this alarm never fires
#                again.
#
# GNU has no `-j`, so the BSD attempt fails there and the GNU form runs. Never
# collapse these into one call. Both BSD variants are pinned by the `bsd-bin`
# and `bsd-legacy-bin` stubs in scripts/release-pr-age-check.test.sh, so the
# behaviour above is enforced rather than merely asserted here.
iso_to_epoch() {
  local iso="$1" out
  if out="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null)"; then
    printf '%s\n' "$out"; return 0
  fi
  if out="$(date -u -d "$iso" +%s 2>/dev/null)"; then
    printf '%s\n' "$out"; return 0
  fi
  return 1
}

# Whole hours from an ISO instant to NOW_EPOCH (set before any call). Returns non-zero when it cannot parse.
hours_since() {
  local epoch
  epoch="$(iso_to_epoch "$1")" || return 1
  local h=$(( (NOW_EPOCH - epoch) / 3600 ))
  [ "$h" -ge 0 ] || h=0
  printf '%s\n' "$h"
}

# Read one JSON file from a git ref via the contents API. Prints nothing and
# returns non-zero when the ref or path is absent (e.g. `stable` does not exist
# yet), so callers can substitute an explicit "unknown" rather than an empty
# string that reads like a real value.
file_at_ref() {
  local path="$1" ref="$2" b64
  b64="$(gh api "repos/$REPO/contents/$path?ref=$ref" --jq '.content' 2>/dev/null)" || return 1
  [ -n "$b64" ] || return 1
  printf '%s' "$b64" | tr -d '\n' | base64 --decode 2>/dev/null || return 1
}

# POST/PATCH a JSON body built by jq. Routing the body through `--input -`
# rather than `-f body=...` keeps markdown (backticks, quotes, newlines, pipes)
# out of shell-quoting range entirely.
api_write() {
  local method="$1" endpoint="$2"
  gh api -X "$method" "$endpoint" --input - >/dev/null
}

# ---------------------------------------------------------------------------
# 1. Find the open release PR
# ---------------------------------------------------------------------------

if [ -n "$NOW_ISO" ]; then
  NOW_EPOCH="$(iso_to_epoch "$NOW_ISO")" || die "could not parse --now '$NOW_ISO' (expected e.g. 2026-08-20T00:00:00Z)"
  echo "note: using synthetic clock --now=$NOW_ISO"
else
  NOW_EPOCH="$(date -u +%s)"
fi

if [ -n "$PR_JSON_FILE" ]; then
  [ -f "$PR_JSON_FILE" ] || die "--pr-json file not found: $PR_JSON_FILE"
  echo "note: reading the open-PR list from $PR_JSON_FILE instead of the GitHub API"
  open_prs="$(cat "$PR_JSON_FILE")"
else
  open_prs="$(gh pr list --repo "$REPO" --state open --limit 100 \
    --json number,title,headRefName,createdAt,url)" \
    || die "gh pr list failed against $REPO"
fi

# Oldest first: if release-please ever has more than one open PR, the oldest is
# the one that has been blocking releases the longest.
release_pr="$(printf '%s' "$open_prs" | jq -c --arg p "$RELEASE_BRANCH_PREFIX" \
  '[.[] | select(.headRefName | startswith($p))] | sort_by(.createdAt) | .[0] // empty')" \
  || die "could not parse the open-PR list as JSON"

# ---------------------------------------------------------------------------
# 2. Locate any existing tracking issue (used by both the clear and alarm paths)
# ---------------------------------------------------------------------------

find_tracking_issue() {
  gh issue list --repo "$REPO" --state open --label main-health --limit 100 \
    --json number,body 2>/dev/null \
    | jq -r --arg m "$MARKER" '[.[] | select((.body // "") | contains($m))] | .[0].number // empty'
}

tracking_issue="$(find_tracking_issue || true)"

close_tracking_issue() {
  local reason="$1"
  [ -n "$tracking_issue" ] || return 0
  if [ "$DRY_RUN" = true ]; then
    echo "dry-run: would close tracking issue #$tracking_issue"
    return 0
  fi
  jq -n --arg b "$reason" '{body:$b}' \
    | api_write POST "repos/$REPO/issues/$tracking_issue/comments" \
    || echo "::warning::could not comment on tracking issue #$tracking_issue before closing it"
  if jq -n '{state:"closed"}' | api_write PATCH "repos/$REPO/issues/$tracking_issue"; then
    echo "Closed tracking issue #$tracking_issue."
  else
    echo "::error title=release-pr-age-check::failed to close tracking issue #$tracking_issue. The alarm has cleared but the issue is still open; close it by hand." >&2
  fi
}

# Open the tracking issue, or update it in place when one already carries the
# marker. Both alarm paths share it, so a stall that turns into a stale release
# PR (or the reverse) stays on ONE issue. Returns non-zero on a failed write.
upsert_tracking_issue() {
  local title="$1" body="$2"
  if [ -n "$tracking_issue" ]; then
    if jq -n --arg t "$title" --arg b "$body" '{title:$t,body:$b}' \
         | api_write PATCH "repos/$REPO/issues/$tracking_issue"; then
      echo "Updated tracking issue #$tracking_issue."
    else
      echo "::error title=release-pr-age-check::failed to update tracking issue #$tracking_issue." >&2
      return 1
    fi
  elif jq -n --arg t "$title" --arg b "$body" --argjson l "$ISSUE_LABELS" \
         '{title:$t,body:$b,labels:$l}' | api_write POST "repos/$REPO/issues"; then
    echo "Opened a tracking issue."
  else
    echo "::error title=release-pr-age-check::failed to open a tracking issue. Check that the workflow grants 'issues: write' and that the 'ci' and 'main-health' labels exist." >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 3. Gather the state the report needs
# ---------------------------------------------------------------------------
# A failed read is recorded as a gap. A run with a gap never closes the tracking
# issue: it cannot tell "nothing has stalled" from "could not look", and closing
# on absent evidence is the #122 failure.
evidence_gaps=''     # every unreadable input the stall causes depend on
promotion_gaps=''    # the ones the promotion-failed check depends on
note_gap() {  # note_gap WHAT [promotion]
  evidence_gaps="${evidence_gaps:+$evidence_gaps, }$1"
  if [ "${2:-}" = promotion ]; then
    promotion_gaps="${promotion_gaps:+$promotion_gaps, }$1"
  fi
}

stable_version='<unknown>'
if stable_plugin_json="$(file_at_ref '.claude-plugin/plugin.json' 'stable')"; then
  stable_version="$(printf '%s' "$stable_plugin_json" | jq -r '.version // "<unparseable>"')"
else
  echo "::warning::could not read .claude-plugin/plugin.json from the 'stable' branch of $REPO — reporting the consumer-facing version as <unknown>."
fi
case "$stable_version" in
  '<unknown>'|'<unparseable>') stable_known=false; note_gap "the version on 'stable'" promotion ;;
  *) stable_known=true ;;
esac

unshipped_count='<unknown>'
unshipped_subjects=''
compare_json=''
if compare_json="$(gh api "repos/$REPO/compare/stable...main" 2>/dev/null)" \
   && printf '%s' "$compare_json" | jq -e '(.commits | type == "array") and (.ahead_by | type == "number")' >/dev/null 2>&1; then
  unshipped_count="$(printf '%s' "$compare_json" | jq -r '.ahead_by')"
  unshipped_subjects="$(printf '%s' "$compare_json" \
    | jq -r '[.commits[] | .commit.message | split("\n")[0]] | reverse | .[0:10] | .[] | "  - " + .')"
else
  # gh prints the HTTP error body to stdout, so a failed call still leaves
  # text in compare_json. Drop it, or later reads parse the error as a result.
  compare_json=''
  echo "::warning::could not compare 'stable...main' on $REPO — reporting the frozen-commit count as <unknown>."
  note_gap "the 'stable...main' comparison"
fi

# ---------------------------------------------------------------------------
# 4. The release state on main (issue #145)
# ---------------------------------------------------------------------------
# Read on both paths. promotion-failed is checked whether or not a release PR
# is open: after a failed promotion the next releasable merge makes
# release-please open a new PR, and a young PR must not hide the stall.

# Main's manifest is the version the last merged release PR wrote. Cheap, and
# no commit-type parsing to get wrong.
main_version='<unknown>'
tag_state='<unknown>'      # present | absent | <unknown>
manifest_changed_at=''
if main_manifest="$(file_at_ref '.release-please-manifest.json' 'main')"; then
  main_version="$(printf '%s' "$main_manifest" | jq -r '.["."] // "<unparseable>"')"
else
  echo "::warning::could not read .release-please-manifest.json from 'main' — cannot check for a merged release that was never tagged."
fi
case "$main_version" in
  '<unknown>'|'<unparseable>') note_gap "main's .release-please-manifest.json" promotion ;;
  *)
    # matching-refs answers [] for "no such tag", so an absent tag and an
    # unreadable API are different results here, not both a failed call.
    if tag_refs="$(gh api "repos/$REPO/git/matching-refs/tags/v$main_version" 2>/dev/null)" \
       && printf '%s' "$tag_refs" | jq -e 'type == "array"' >/dev/null 2>&1; then
      if printf '%s' "$tag_refs" | jq -e --arg r "refs/tags/v$main_version" 'any(.[]; .ref == $r)' >/dev/null; then
        tag_state=present
      else
        tag_state=absent
      fi
    else
      echo "::warning::could not list tags on $REPO — cannot tell whether v$main_version was released."
      note_gap "the tag list" promotion
    fi
    manifest_changed_at="$(gh api "repos/$REPO/commits?sha=main&path=.release-please-manifest.json&per_page=1" 2>/dev/null \
      | jq -r '.[0].commit.committer.date // empty' 2>/dev/null || true)"
    ;;
esac

promotion_failed=false
if [ "$tag_state" = present ] && [ "$stable_known" = true ] && [ "$stable_version" != "$main_version" ]; then
  promotion_failed=true
fi

# The delta: which commits on main would release-please turn into a release?
releasable_json='[]'
releasable_subjects=''
releasable_count=0
if [ -n "$compare_json" ] && printf '%s' "$compare_json" | jq -e '.commits | type == "array"' >/dev/null 2>&1; then
  releasable_json="$(printf '%s' "$compare_json" | jq -c --arg t "$RELEASABLE_TYPES" '
    [ .commits[]
      | { subject: (.commit.message | split("\n")[0]),
          message: .commit.message,
          date: (.commit.committer.date // .commit.author.date // "") }
      | select( (.subject | test("^(" + $t + ")(\\([^)]*\\))?!?: "))
             or (.subject | test("^[A-Za-z]+(\\([^)]*\\))?!: "))
             or (.message | test("(^|\n)BREAKING[ -]CHANGE: ")) ) ]')"
  releasable_count="$(printf '%s' "$releasable_json" | jq 'length')"
  releasable_subjects="$(printf '%s' "$releasable_json" \
    | jq -r 'reverse | .[0:10] | .[] | "  - " + .subject')"
fi

# Sets stall_hours and age_text from an ISO instant, and returns 0 while the
# stall is still inside the grace window. Unknown age counts as past the
# window: a stall we cannot date is still a stall, and reporting health from
# absent evidence is the #122 failure.
stall_hours=''
age_text=''
stall_inside_grace() {  # stall_inside_grace SINCE_ISO
  stall_hours=''
  if [ -n "$1" ]; then stall_hours="$(hours_since "$1" || true)"; fi
  if [ -n "$stall_hours" ]; then age_text="${stall_hours}h"; else age_text='an unknown time'; fi
  [ -n "$stall_hours" ] && [ "$stall_hours" -lt "$GRACE_HOURS" ]
}

# Print the stall report, open or update the tracking issue, and exit 1. Both
# paths share it, so a stall stays on the ONE tracking issue whether or not a
# release PR is open. Call stall_inside_grace first; it sets age_text.
emit_stall_alarm() {  # emit_stall_alarm CAUSE WHERE
  local stall_cause="$1" where="$2" issue_title cause_text report
  [ -n "$releasable_subjects" ] || releasable_subjects='  (none, or the list could not be read)'

  case "$stall_cause" in
    tag-missing)
      issue_title="Release stalled — v${main_version} merged but never tagged; consumers on ${stable_version}"
      cause_text="$(cat <<EOF
**Likely cause: release-please failed AFTER the release PR merged.** \`main\`'s
\`.release-please-manifest.json\` says \`${main_version}\`, but there is no tag
\`v${main_version}\`. With no tag, \`promote-stable.yml\` never runs and \`stable\`
never moves. One known cause is #310: there, for example, the release App had
no \`workflows\` permission, so the GitHub-release step failed with *Resource not
accessible by integration*.

**Where to look:** the most recent **failed** \`release-please.yml\` run on
\`main\` (the failure is in its log, not in any PR), and
\`docs/solutions/build-errors/release-please-fails-when-release-app-lacks-workflows-permission.md\`.
Fix the cause, then re-run that workflow; it tags the release it missed.
EOF
)"
      ;;
    promotion-failed)
      issue_title="Release stalled — v${main_version} tagged but stable still on ${stable_version}"
      cause_text="$(cat <<EOF
**Likely cause: promotion failed.** Tag \`v${main_version}\` exists, but \`stable\`
still carries \`${stable_version}\`. \`promote-stable.yml\` did not fast-forward
\`stable\` to the tag (issue #108).

**Where to look:** the **Promote to stable** run for tag \`v${main_version}\`.
Re-run it once its cause is fixed. A re-run is not always enough: a
tag-triggered run uses the workflow file as it was at the tag. If the caller
file itself was broken, a re-run replays the broken file, and recovery needs a
new patch release. See
\`docs/solutions/build-errors/promote-stable-startup-failure-missing-caller-permissions.md\`.
EOF
)"
      ;;
    no-release-pr)
      issue_title="Release stalled — ${releasable_count} releasable commit(s) on main with no release PR; consumers on ${stable_version}"
      cause_text="$(cat <<EOF
**Likely cause: release-please did not open a release PR.** ${releasable_count}
releasable commit(s) are on \`main\` but not on \`stable\`. \`release-please.yml\`
exits 0 by design when its org variables are missing, the PEM cannot be read,
or the token mint fails, so its run can be green while it did nothing.

**Where to look:** the annotations on the most recent \`release-please.yml\` run
on \`main\`. Fix the cause, then re-run it; it opens the release PR.
EOF
)"
      ;;
    *) die "unhandled stall cause '$stall_cause' -- this is a bug in the script" ;;
  esac

  report="$(cat <<EOF
$MARKER
**A release has stalled ${where}** (waiting ${age_text}; grace window: ${GRACE_HOURS}h).

${cause_text}

|  |  |
| --- | --- |
| Version on \`main\` (\`.release-please-manifest.json\`) | \`${main_version}\` |
| Tag \`v${main_version}\` | ${tag_state} |
| **Version consumers actually run** (\`stable\`) | \`${stable_version}\` |
| Commits merged to \`main\` but not on \`stable\` | **${unshipped_count}** |
| Of those, releasable | **${releasable_count}** |

Releasable commits waiting (most recent first, up to 10):

\`\`\`
${releasable_subjects}
\`\`\`

**To clear this:** get the release out. The next run of this check closes this
report automatically once the stall has cleared.

<sub>Posted by \`.github/workflows/release-latency-alarm.yml\` via
\`scripts/release-pr-age-check.sh\` (issue #145). Grace window is
\`RELEASE_STALL_GRACE_HOURS\`.</sub>
EOF
)"

  echo "::error title=Release stalled (${stall_cause})::${issue_title}"
  echo
  printf '%s\n' "$report"
  echo

  if [ "$DRY_RUN" = true ]; then
    if [ -n "$tracking_issue" ]; then
      echo "dry-run: would update tracking issue #$tracking_issue (title: $issue_title)"
    else
      echo "dry-run: would open a tracking issue (title: $issue_title)"
    fi
    exit 1
  fi

  # The stall alarm does not comment on a release PR: on the no-PR path there is
  # none, and on the PR path the PR is not what is stuck. The tracking issue and
  # the red run are the two layers here.
  upsert_tracking_issue "$issue_title" "$report" \
    || echo "::warning::the tracking-issue write failed. The alarm still fails this run, which is the remaining layer of the signal."
  exit 1
}

# ---------------------------------------------------------------------------
# 5. No release PR open — is a release stalled? (issue #145)
# ---------------------------------------------------------------------------
# See "THE RELEASE PR THAT NEVER CAME" in the header for the three causes and
# why they are checked in this order.

if [ -z "$release_pr" ]; then
  echo "No open release PR on $REPO (searched open PRs for a '${RELEASE_BRANCH_PREFIX}*' head branch)."
  echo "  Consumers on 'stable': $stable_version"
  echo "  Commits on main not yet on stable: $unshipped_count"

  stall_cause=''   # tag-missing | promotion-failed | no-release-pr
  stall_since=''   # ISO instant the stall is measured from; empty = unknown

  if [ "$tag_state" = absent ]; then
    stall_cause=tag-missing
    stall_since="$manifest_changed_at"
  elif [ "$promotion_failed" = true ]; then
    stall_cause=promotion-failed
    stall_since="$manifest_changed_at"
  elif [ "$releasable_count" -gt 0 ]; then
    stall_cause=no-release-pr
    # compare lists commits oldest first; the oldest one has waited longest.
    stall_since="$(printf '%s' "$releasable_json" | jq -r '.[0].date')"
  fi

  if [ -z "$stall_cause" ]; then
    if [ "$unshipped_count" != "<unknown>" ] && [ "$unshipped_count" -gt 0 ]; then
      echo "  None of them is releasable (no feat/fix/perf/revert/deps or breaking change), so no release PR is expected. This is the normal state after a docs-, ci- or chore-only merge."
    fi
    if [ -n "$evidence_gaps" ]; then
      echo "::warning::the release-stall check was inconclusive: could not read ${evidence_gaps}. No stall was found, but the tracking issue is left open rather than closed on missing evidence."
      exit 0
    fi
    close_tracking_issue "Cleared — there is no longer an open release PR on \`$REPO\`, and no releasable change is waiting. Consumers on \`stable\` are now at **$stable_version**. Closed automatically by \`scripts/release-pr-age-check.sh\`."
    exit 0
  fi

  if stall_inside_grace "$stall_since"; then
    echo "Release stall suspected ($stall_cause), but it is ${stall_hours}h old — inside the ${GRACE_HOURS}h grace window. No alarm yet."
    echo "  The tracking issue is left as it is: a waiting releasable change is never reported as cleared."
    exit 0
  fi

  emit_stall_alarm "$stall_cause" "with no release PR open"
fi

# ---------------------------------------------------------------------------
# 6. Compute age
# ---------------------------------------------------------------------------

pr_number="$(printf '%s' "$release_pr"  | jq -r '.number')"
pr_title="$(printf '%s' "$release_pr"   | jq -r '.title')"
pr_url="$(printf '%s' "$release_pr"     | jq -r '.url')"
pr_created="$(printf '%s' "$release_pr" | jq -r '.createdAt')"
pr_branch="$(printf '%s' "$release_pr"  | jq -r '.headRefName')"

created_epoch="$(iso_to_epoch "$pr_created")" \
  || die "could not parse the PR's createdAt '$pr_created' on either BSD or GNU date"

age_days=$(( (NOW_EPOCH - created_epoch) / 86400 ))
[ "$age_days" -ge 0 ] || age_days=0

# The version waiting to ship is what the release PR writes into the manifest.
# Read it from the PR's own head branch rather than parsing the title — the
# manifest is the file release-please actually authors, and it is what
# promote-stable.yml asserts against at promotion time.
pending_version='<unknown>'
if pending_manifest="$(file_at_ref '.release-please-manifest.json' "$pr_branch")"; then
  pending_version="$(printf '%s' "$pending_manifest" | jq -r '.["."] // "<unparseable>"')"
else
  echo "::warning::could not read .release-please-manifest.json from '$pr_branch' — falling back to the PR title for the pending version."
  pending_version="$(printf '%s' "$pr_title" | sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p')"
  [ -n "$pending_version" ] || pending_version='<unknown>'
fi

# ---------------------------------------------------------------------------
# 7. Under threshold — report and clear, unless an earlier promotion failed
# ---------------------------------------------------------------------------
# tag-missing and no-release-pr are not checked here. A young release PR
# explains unreleased commits, and release-please does not open a new PR while a
# merged one is still untagged. A failed promotion is different: the tag exists,
# so release-please moves on and opens the next PR while `stable` stays behind.

if [ "$age_days" -lt "$MAX_AGE_DAYS" ]; then
  if [ "$promotion_failed" = true ] && ! stall_inside_grace "$manifest_changed_at"; then
    echo "Release PR #$pr_number is ${age_days}d old — under the ${MAX_AGE_DAYS}d threshold, but an earlier release never reached 'stable'."
    emit_stall_alarm promotion-failed "while release PR #${pr_number} is open"
  fi
  echo "Release PR #$pr_number is ${age_days}d old — under the ${MAX_AGE_DAYS}d threshold. No alarm."
  echo "  Waiting to ship: $pending_version"
  echo "  Consumers on 'stable': $stable_version"
  echo "  Commits frozen behind it: $unshipped_count"
  if [ "$promotion_failed" = true ]; then
    echo "  Promotion of v$main_version to 'stable' looks failed, but it is ${stall_hours}h old — inside the ${GRACE_HOURS}h grace window. No alarm yet."
    echo "  The tracking issue is left as it is: a failed promotion is never reported as cleared."
    exit 0
  fi
  if [ -n "$promotion_gaps" ]; then
    echo "::warning::the promotion check was inconclusive: could not read ${promotion_gaps}. The tracking issue is left open rather than closed on missing evidence."
    exit 0
  fi
  close_tracking_issue "Cleared — release PR #$pr_number is back under the ${MAX_AGE_DAYS}-day threshold (now ${age_days}d old). Closed automatically by \`scripts/release-pr-age-check.sh\`."
  exit 0
fi

# ---------------------------------------------------------------------------
# 8. ALARM
# ---------------------------------------------------------------------------

[ -n "$unshipped_subjects" ] || unshipped_subjects='  (could not list commits)'

issue_title="Release PR #${pr_number} open ${age_days}d — ${pending_version} unshipped, consumers on ${stable_version}"

report="$(cat <<EOF
$MARKER
**Release PR [#${pr_number}](${pr_url}) has been open for ${age_days} days** (threshold: ${MAX_AGE_DAYS} days).

Merging that PR *is* the release act. Until it merges, nothing reaches anyone:
release-please tags \`v${pending_version}\` on merge, and \`promote-stable.yml\`
fast-forwards the \`stable\` branch that the marketplace installs from. Everything
merged to \`main\` in the meantime is written but **unshipped**.

|  |  |
| --- | --- |
| Release PR | [#${pr_number}](${pr_url}) — \`${pr_title}\` |
| Open since | \`${pr_created}\` (${age_days} days) |
| Version waiting to ship | \`${pending_version}\` |
| **Version consumers actually run** (\`stable\`) | \`${stable_version}\` |
| Commits merged to \`main\` but not on \`stable\` | **${unshipped_count}** |

Frozen behind this PR (most recent first, up to 10):

\`\`\`
${unshipped_subjects}
\`\`\`

**To clear this:** merge ${pr_url}. The next run of this check closes this
report automatically.

**If the release is being held deliberately**, say so on the PR — the hold is
then a decision on the record rather than a silent freeze, which is the whole
failure this check exists to make visible (issues #129, #122).

<sub>Posted by \`.github/workflows/release-latency-alarm.yml\` via
\`scripts/release-pr-age-check.sh\`. Threshold is the \`RELEASE_PR_MAX_AGE_DAYS\`
\`env:\` in that workflow.</sub>
EOF
)"

# Console form, so a `workflow_dispatch` run is readable in the Actions tab even
# if both write paths fail.
echo "::error title=Release PR open ${age_days}d::${issue_title}"
echo
printf '%s\n' "$report"
echo

if [ "$DRY_RUN" = true ]; then
  echo "dry-run: would upsert a sticky comment on PR #$pr_number"
  if [ -n "$tracking_issue" ]; then
    echo "dry-run: would update tracking issue #$tracking_issue (title: $issue_title)"
  else
    echo "dry-run: would open a tracking issue (title: $issue_title)"
  fi
  exit 1
fi

write_failures=0

# --- Layer 1: a sticky comment on the release PR, where the merge happens ---
existing_comment="$(gh api "repos/$REPO/issues/$pr_number/comments" --paginate 2>/dev/null \
  | jq -r --arg m "$MARKER" '[.[] | select((.body // "") | contains($m))] | .[0].id // empty' || true)"

if [ -n "$existing_comment" ]; then
  if jq -n --arg b "$report" '{body:$b}' | api_write PATCH "repos/$REPO/issues/comments/$existing_comment"; then
    echo "Updated the sticky comment on PR #$pr_number (comment $existing_comment)."
  else
    echo "::error title=release-pr-age-check::failed to update comment $existing_comment on PR #$pr_number." >&2
    write_failures=$((write_failures + 1))
  fi
elif jq -n --arg b "$report" '{body:$b}' | api_write POST "repos/$REPO/issues/$pr_number/comments"; then
  echo "Commented on PR #$pr_number."
else
  echo "::error title=release-pr-age-check::failed to comment on PR #$pr_number. Check that the workflow grants 'pull-requests: write'." >&2
  write_failures=$((write_failures + 1))
fi

# --- Layer 2: a tracking issue, so the alarm survives outside the PR view ---
upsert_tracking_issue "$issue_title" "$report" || write_failures=$((write_failures + 1))

if [ "$write_failures" -gt 0 ]; then
  echo "::warning::${write_failures} notification path(s) failed. The alarm still fails this run, which is the remaining layer of the signal."
fi

# Layer 3: a red run in the Actions tab. Always last, so the notifications above
# are attempted first — an alarm that exits before it notifies is no alarm.
exit 1
