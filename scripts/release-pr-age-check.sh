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
# EXIT CODES
# ----------
#   0  no release PR open, or it is younger than the threshold
#   1  ALARM — a release PR is at or past the threshold (notifications sent)
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
  --dry-run             Print the report; make no writes to GitHub.
  --now ISO8601         Treat this instant as "now" (e.g. 2026-08-20T00:00:00Z).
                        Verification affordance; unused in CI.
  --pr-json PATH        Read the open-PR list from this file instead of calling
                        `gh pr list`. Same shape as:
                          gh pr list --state open \
                            --json number,title,headRefName,createdAt,url
                        Substitutes PR METADATA only — reads of `stable` and of
                        the PR's head branch still hit the live repo, so a
                        fixture naming a branch that exists will report that
                        branch's real pending version, not the fixture's title.
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

# ---------------------------------------------------------------------------
# 3. Gather the state the report needs
# ---------------------------------------------------------------------------

stable_version='<unknown>'
if stable_plugin_json="$(file_at_ref '.claude-plugin/plugin.json' 'stable')"; then
  stable_version="$(printf '%s' "$stable_plugin_json" | jq -r '.version // "<unparseable>"')"
else
  echo "::warning::could not read .claude-plugin/plugin.json from the 'stable' branch of $REPO — reporting the consumer-facing version as <unknown>."
fi

unshipped_count='<unknown>'
unshipped_subjects=''
if compare_json="$(gh api "repos/$REPO/compare/stable...main" 2>/dev/null)"; then
  unshipped_count="$(printf '%s' "$compare_json" | jq -r '.ahead_by')"
  unshipped_subjects="$(printf '%s' "$compare_json" \
    | jq -r '[.commits[] | .commit.message | split("\n")[0]] | reverse | .[0:10] | .[] | "  - " + .')"
else
  echo "::warning::could not compare 'stable...main' on $REPO — reporting the frozen-commit count as <unknown>."
fi

# ---------------------------------------------------------------------------
# 4. Clear path — no release PR open
# ---------------------------------------------------------------------------

if [ -z "$release_pr" ]; then
  echo "No open release PR on $REPO (searched open PRs for a '${RELEASE_BRANCH_PREFIX}*' head branch)."
  echo "  Consumers on 'stable': $stable_version"
  echo "  Commits on main not yet on stable: $unshipped_count"
  if [ "$unshipped_count" != "<unknown>" ] && [ "$unshipped_count" -gt 0 ]; then
    # release-please.yml opens its PR within ~a minute of a push to main, so on
    # the daily cadence this state is not the normal post-merge transient — it
    # means release-please took its documented soft-failure path (absent org
    # vars, unreadable 1P PEM, or failed token mint all exit 0), or a tag was
    # cut without promote-stable.yml succeeding (issue #108). Either way nothing
    # else reports it.
    echo "::warning::'stable' is $unshipped_count commit(s) behind 'main' with NO open release PR. Expected causes: release-please.yml soft-failed (it exits 0 on missing credentials by design), or a tag was cut but promote-stable.yml did not fast-forward 'stable' (issue #108). Check the most recent release-please and Promote to stable runs."
  fi
  close_tracking_issue "Cleared — there is no longer an open release PR on \`$REPO\`. Consumers on \`stable\` are now at **$stable_version**. Closed automatically by \`scripts/release-pr-age-check.sh\`."
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Compute age
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
# 6. Under threshold — report and clear
# ---------------------------------------------------------------------------

if [ "$age_days" -lt "$MAX_AGE_DAYS" ]; then
  echo "Release PR #$pr_number is ${age_days}d old — under the ${MAX_AGE_DAYS}d threshold. No alarm."
  echo "  Waiting to ship: $pending_version"
  echo "  Consumers on 'stable': $stable_version"
  echo "  Commits frozen behind it: $unshipped_count"
  close_tracking_issue "Cleared — release PR #$pr_number is back under the ${MAX_AGE_DAYS}-day threshold (now ${age_days}d old). Closed automatically by \`scripts/release-pr-age-check.sh\`."
  exit 0
fi

# ---------------------------------------------------------------------------
# 7. ALARM
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
if [ -n "$tracking_issue" ]; then
  if jq -n --arg t "$issue_title" --arg b "$report" '{title:$t,body:$b}' \
       | api_write PATCH "repos/$REPO/issues/$tracking_issue"; then
    echo "Updated tracking issue #$tracking_issue."
  else
    echo "::error title=release-pr-age-check::failed to update tracking issue #$tracking_issue." >&2
    write_failures=$((write_failures + 1))
  fi
elif jq -n --arg t "$issue_title" --arg b "$report" --argjson l "$ISSUE_LABELS" \
       '{title:$t,body:$b,labels:$l}' | api_write POST "repos/$REPO/issues"; then
  echo "Opened a tracking issue."
else
  echo "::error title=release-pr-age-check::failed to open a tracking issue. Check that the workflow grants 'issues: write' and that the 'ci' and 'main-health' labels exist." >&2
  write_failures=$((write_failures + 1))
fi

if [ "$write_failures" -gt 0 ]; then
  echo "::warning::${write_failures} notification path(s) failed. The alarm still fails this run, which is the remaining layer of the signal."
fi

# Layer 3: a red run in the Actions tab. Always last, so the notifications above
# are attempted first — an alarm that exits before it notifies is no alarm.
exit 1
