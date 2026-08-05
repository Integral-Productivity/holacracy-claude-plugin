#!/usr/bin/env bash
#
# grounding-fire-rate-check.sh — alarm when the role-grounding directive stops
# reaching sessions.
#
# WHY THIS EXISTS
# ---------------
# Issue #122: the SessionStart directive fired in 1 of 301 sessions for two
# weeks and nothing anywhere reported it. The handler was fine; a v0.6.0 copy
# was being loaded while 0.10.2 was recorded as installed, and v0.6.0 had no
# directive in it. A hook that exits 0 with empty stdout leaves no transcript
# record at all, so "running two-week-old code" and "no hook installed" were
# byte-for-byte identical on disk.
#
# Three independent signals all read healthy while the feature was dead: the
# recorded install was correct, the handler's own tests passed (against the copy
# in the repo, not the copy that runs), and the hook exited 0 every time.
#
# #153 made the data observable — every payload now carries the plugin version,
# and a quiet session emits a marker instead of nothing. This is the piece that
# READS that data and fails loudly. Without it the transcripts hold the evidence
# and nobody looks.
#
# WHY IT IS NOT A CI CHECK
# ------------------------
# Session transcripts live in ~/.claude/projects on the operator's machine. A
# GitHub Actions runner cannot see them, so this runs operator-local — on the
# same schedule as the weekly grounding-pdca1-readout. Its TEST SUITE runs in
# CI, fixture-driven, via --readout-json.
#
# COUNT HOOK RECORDS, NOT TEXT MATCHES
# ------------------------------------
# This shells scripts/grounding-readout.sh rather than scanning transcripts
# itself. That is deliberate and load-bearing. The obvious one-liner —
#
#     grep -l "Holacracy plugin: role-grounding" ~/.claude/projects/*/*.jsonl
#
# — returned 10 files on 2026-08-03 against a true 3, because whole-file grep
# cannot tell "the hook injected this" from "the session read or quoted it".
# That error produced the false 2.2% in #122 and the 23 false positives in #123.
# The readout counts only hook-output records and buckets sessions by start
# time; re-deriving either here would reintroduce the exact defect this script
# exists to catch. See CLAUDE.md § "Measuring whether the grounding directive
# fired".
#
# WHY --include-self
# ------------------
# The readout holds this repo's own sessions out of its headline by default,
# because sessions working on the directive would score themselves on the
# BEHAVIOR signals. Delivery is different: whether the hook fired is a property
# of the installed plugin, not of the repo the session ran in. Excluding them
# here would blind the check exactly where the treatment is most observable —
# which is what #149 was filed for.
#
# EXIT CODES
# ----------
#   0  clear, or too few sessions in the window to judge
#   1  ALARM — the fire rate is below the floor (notifications sent)
#   2  usage error, an operational failure, or NOTHING TO MEASURE
#
# Exit 2 on an empty window is not pedantry. A zero-session corpus reporting
# "clear" is a silent pass on no evidence, which is the failure mode of this
# entire issue wearing a different hat.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

HERE="$(cd "$(dirname "$0")" && pwd)"
READOUT="$HERE/grounding-readout.sh"

# The directive is always-on by default (ADR-0008 A2), so in a healthy
# deployment this rate is ~100%. The floor sits at 0.9 rather than 1.0 to
# absorb the legitimate misses: a session started before a re-install, or one
# in a directory matched by HOLACRACY_GROUNDING_EXCLUDE. It is far above the
# observed failure (0.3%), which is what it has to separate.
DEFAULT_MIN_RATE=0.9

# Below this many sessions the rate is noise: 1 miss in 3 is 67%, which would
# alarm on a quiet weekend. The window reports "no verdict" instead of
# guessing — and says so out loud rather than exiting 0 in silence.
DEFAULT_MIN_SESSIONS=10

# A rolling window, because the question is "has it collapsed?", not "what has
# the rate been since the beginning of time". Scanning all history would keep
# the pre-fix corpus in the denominator forever and never recover.
DEFAULT_DAYS=7

MARKER='<!-- grounding-fire-rate-check:v1 -->'
ISSUE_LABELS='["area:fitness","main-health"]'

MIN_RATE="${GROUNDING_MIN_FIRE_RATE:-$DEFAULT_MIN_RATE}"
MIN_SESSIONS="${GROUNDING_MIN_SESSIONS:-$DEFAULT_MIN_SESSIONS}"
DAYS="${GROUNDING_WINDOW_DAYS:-$DEFAULT_DAYS}"
SINCE_START="${GROUNDING_WINDOW_START:-}"
REPO="${GITHUB_REPOSITORY:-}"
READOUT_JSON_FILE=''
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/grounding-fire-rate-check.sh [options]

  --min-rate R          Alarm when the fire rate is strictly below R (0..1).
                        Default: $GROUNDING_MIN_FIRE_RATE, else 0.9.
  --min-sessions N      Report "no verdict" below N sessions in the window.
                        Default: $GROUNDING_MIN_SESSIONS, else 10.
  --days N              Rolling window width in days. Default: 7.
  --since-start WHEN    Fixed window start (YYYY-MM-DD or YYYY-MM-DDTHH:MM),
                        overriding --days. Buckets by SESSION START, never
                        file mtime.
  --repo OWNER/NAME     Repository for the tracking issue. Default:
                        $GITHUB_REPOSITORY, else whatever `gh` resolves.
  --dry-run             Print the report; make no writes to GitHub. Does not
                        require gh or jq.
  --readout-json PATH   Read grounding-readout.sh --json output from this file
                        instead of running it. Verification affordance; unused
                        in production.
  -h, --help            This text.

Exit: 0 = clear or no verdict, 1 = alarm raised, 2 = usage/operational error
      or an empty window (nothing to measure).
EOF
}

die() {
  echo "::error title=grounding-fire-rate-check::$*" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --min-rate)      MIN_RATE="${2:-}";           shift 2 ;;
    --min-sessions)  MIN_SESSIONS="${2:-}";       shift 2 ;;
    --days)          DAYS="${2:-}";               shift 2 ;;
    --since-start)   SINCE_START="${2:-}";        shift 2 ;;
    --repo)          REPO="${2:-}";               shift 2 ;;
    --readout-json)  READOUT_JSON_FILE="${2:-}";  shift 2 ;;
    --dry-run)       DRY_RUN=true;                shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage >&2; die "unknown argument: $1" ;;
  esac
done

case "$MIN_SESSIONS" in
  ''|*[!0-9]*) die "--min-sessions must be a non-negative integer, got '$MIN_SESSIONS'" ;;
esac
case "$DAYS" in
  ''|*[!0-9]*) die "--days must be a non-negative integer, got '$DAYS'" ;;
esac

command -v python3 >/dev/null 2>&1 \
  || die "python3 is required (JSON parsing); not found on PATH"

python3 -c "
import sys
try:
    r = float('$MIN_RATE')
except ValueError:
    sys.exit(1)
sys.exit(0 if 0.0 <= r <= 1.0 else 1)
" 2>/dev/null || die "--min-rate must be a number between 0 and 1, got '$MIN_RATE'"

# gh/jq are needed only to WRITE. Checking them up front would make --dry-run
# unrunnable in CI, and an alarm path nobody can exercise is the same
# fail-silent shape this script exists to catch.
if [ "$DRY_RUN" = false ]; then
  command -v gh >/dev/null 2>&1 || die "the GitHub CLI (gh) is required and was not found on PATH"
  command -v jq >/dev/null 2>&1 || die "jq is required and was not found on PATH"
  if [ -z "$REPO" ]; then
    REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
    [ -n "$REPO" ] || die "could not determine the repository; pass --repo OWNER/NAME"
  fi
fi

# ---------------------------------------------------------------------------
# 1. Resolve the window
# ---------------------------------------------------------------------------

# BSD first with explicit flags, then GNU — same reasoning as
# release-pr-age-check.sh's iso_to_epoch, and the same two BSD variants. On
# macOS `-d` is not an option at all: probed on macOS 27 (2026-08-05),
# `date -u -d '2026-08-01T00:00:00Z' +%s` is `date: illegal option -- d`, rc 1,
# so a GNU-shaped call fails cleanly there. On FreeBSD-style BSD `-d` sets
# daylight-saving time instead of parsing a datestring, so the same call is
# accepted-and-wrong — it answers "now", and a window computed GNU-first would
# silently collapse to zero days. BSD-first is correct on both; that is why the
# ordering is load-bearing rather than incidental. Both variants are pinned by
# the `bsd-bin` and `bsd-legacy-bin` stubs in
# scripts/release-pr-age-check.test.sh.
days_ago() {
  local n="$1" out
  if out="$(date -v-"${n}"d '+%Y-%m-%dT%H:%M' 2>/dev/null)"; then
    printf '%s\n' "$out"; return 0
  fi
  if out="$(date -d "$n days ago" '+%Y-%m-%dT%H:%M' 2>/dev/null)"; then
    printf '%s\n' "$out"; return 0
  fi
  return 1
}

if [ -z "$SINCE_START" ]; then
  SINCE_START="$(days_ago "$DAYS")" \
    || die "could not compute a ${DAYS}-day window on either BSD or GNU date"
  WINDOW_DESC="rolling ${DAYS}-day window (sessions started on/after $SINCE_START)"
else
  WINDOW_DESC="sessions started on/after $SINCE_START"
fi

# ---------------------------------------------------------------------------
# 2. Get the readout
# ---------------------------------------------------------------------------

if [ -n "$READOUT_JSON_FILE" ]; then
  [ -f "$READOUT_JSON_FILE" ] || die "--readout-json file not found: $READOUT_JSON_FILE"
  echo "note: reading the readout from $READOUT_JSON_FILE instead of running it"
  readout_json="$(cat "$READOUT_JSON_FILE")"
else
  [ -x "$READOUT" ] || [ -f "$READOUT" ] \
    || die "scripts/grounding-readout.sh not found next to this script ($READOUT)"
  # A readout failure must never be read as a clean window. It exits 2 when it
  # cannot derive its own marker, which means the directive was reworded and
  # the count would be an unjustifiable zero.
  readout_json="$(bash "$READOUT" --json --include-self --since-start "$SINCE_START")" \
    || die "grounding-readout.sh failed; refusing to report a rate it could not measure"
fi

# ---------------------------------------------------------------------------
# 3. Derive the verdict
# ---------------------------------------------------------------------------

# One python3 pass emits shell-assignable values. Doing the comparison here
# rather than in bash keeps the floor an honest float comparison; bash has no
# float arithmetic and the usual workarounds silently truncate.
#
# Captured and status-checked BEFORE eval, never `eval "$(...)"` directly:
# eval reports its own exit status, so a parser failure would sail through and
# leave the counters unset. A check that cannot read its input must fail, not
# proceed with whatever happens to be in scope.
if ! verdict_vars="$(printf '%s' "$readout_json" | python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
except ValueError as exc:
    sys.stderr.write("could not parse the readout as JSON: %s\n" % exc)
    sys.exit(2)

sessions = int(d.get("sessions") or 0)
fired = int((d.get("directive_fired") or {}).get("count") or 0)
seen = d.get("plugin_versions_seen") or {}
unstamped = int(d.get("sessions_without_plugin_version") or 0)

parts = ["%s (%d)" % (v, n) for v, n in sorted(seen.items(), reverse=True)]
if unstamped:
    # Named explicitly. A session whose loaded version cannot be determined is
    # the #122 condition itself -- v0.6.0 predated the stamp entirely -- so it
    # must never be quietly folded in with the stamped ones.
    parts.append("no version stamp (%d)" % unstamped)
versions = ", ".join(parts) if parts else "none"

rate = (fired / sessions) if sessions else 0.0

print("SESSIONS=%d" % sessions)
print("FIRED=%d" % fired)
print("RATE=%.4f" % rate)
print("RATE_PCT=%s" % ("n/a" if not sessions else "%.0f%%" % (rate * 100)))
print("VERSIONS=%s" % json.dumps(versions))
' )"; then
  die "could not read the readout output as JSON; refusing to report a rate from input it could not parse"
fi
eval "$verdict_vars"

# ---------------------------------------------------------------------------
# 4. Nothing to measure — never a silent pass
# ---------------------------------------------------------------------------

if [ "$SESSIONS" -eq 0 ]; then
  die "no sessions found in the window ($WINDOW_DESC). Nothing to measure, so this is NOT a pass. Check CLAUDE_PROJECTS_DIR and the window."
fi

summary="$FIRED of $SESSIONS session(s) ($RATE_PCT) — $WINDOW_DESC"

# ---------------------------------------------------------------------------
# 5. Tracking-issue plumbing (shared by the clear and alarm paths)
# ---------------------------------------------------------------------------

tracking_issue=''
if [ "$DRY_RUN" = false ]; then
  tracking_issue="$(gh issue list --repo "$REPO" --state open --label main-health --limit 100 \
    --json number,body 2>/dev/null \
    | jq -r --arg m "$MARKER" '[.[] | select((.body // "") | contains($m))] | .[0].number // empty' || true)"
fi

close_tracking_issue() {
  local reason="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "dry-run: would close any open tracking issue"
    return 0
  fi
  [ -n "$tracking_issue" ] || return 0
  jq -n --arg b "$reason" '{body:$b}' \
    | gh api -X POST "repos/$REPO/issues/$tracking_issue/comments" --input - >/dev/null \
    || echo "::warning::could not comment on tracking issue #$tracking_issue before closing it"
  if jq -n '{state:"closed"}' | gh api -X PATCH "repos/$REPO/issues/$tracking_issue" --input - >/dev/null; then
    echo "Closed tracking issue #$tracking_issue."
  else
    echo "::error title=grounding-fire-rate-check::failed to close tracking issue #$tracking_issue. The alarm has cleared but the issue is still open; close it by hand." >&2
  fi
}

# ---------------------------------------------------------------------------
# 6. Under-powered — a stated non-verdict, not a pass
# ---------------------------------------------------------------------------

if [ "$SESSIONS" -lt "$MIN_SESSIONS" ]; then
  echo "NO VERDICT — under-powered: $summary"
  echo "  n=$SESSIONS is below the --min-sessions floor of $MIN_SESSIONS; the rate is not decidable yet."
  echo "  plugin versions seen: $VERSIONS"
  exit 0
fi

# ---------------------------------------------------------------------------
# 7. Clear
# ---------------------------------------------------------------------------

# Strictly below the floor alarms; exactly at it is clear. Stated once, here,
# so the boundary is not re-derived (and re-decided) in two places.
below_floor="$(python3 -c "print('yes' if float('$RATE') < float('$MIN_RATE') else 'no')")"

if [ "$below_floor" = "no" ]; then
  echo "Clear — directive fired in $summary (floor: $MIN_RATE)."
  echo "  plugin versions seen: $VERSIONS"
  close_tracking_issue "Cleared — the role-grounding directive fired in **$summary**, back at or above the floor of \`$MIN_RATE\`. Plugin versions seen: $VERSIONS. Closed automatically by \`scripts/grounding-fire-rate-check.sh\`."
  exit 0
fi

# ---------------------------------------------------------------------------
# 8. ALARM
# ---------------------------------------------------------------------------

issue_title="Role-grounding directive fired in only $RATE_PCT of sessions ($FIRED/$SESSIONS)"

report="$(cat <<EOF
$MARKER
**The role-grounding directive is not reaching sessions.** It fired in
**$FIRED of $SESSIONS** session(s) — **$RATE_PCT** — against a floor of \`$MIN_RATE\`.

|  |  |
| --- | --- |
| Window | $WINDOW_DESC |
| Sessions measured | $SESSIONS |
| Directive fired in | $FIRED ($RATE_PCT) |
| Floor | $MIN_RATE |
| **Plugin versions seen** | $VERSIONS |

**Read the versions row first.** A collapsed fire rate and a stale loaded copy
are usually the same story: in issue #122 the app had materialized **v0.6.0**,
which predates the directive, while \`installed_plugins.json\` reported 0.10.2.
A large "no version stamp" count means copies too old to carry the stamp at all
— that is the #122 condition exactly.

Things to check, cheapest first:

1. \`scripts/plugin-version-skew-check.sh\` — is the loaded version behind \`stable\`?
2. Is a release PR sitting open? Merging it *is* the release act; until then
   nothing reaches anyone (\`scripts/release-pr-age-check.sh\`).
3. Is \`HOLACRACY_GROUNDING_EXCLUDE\` or \`HOLACRACY_GROUNDING_DIRECTIVE=off\` set
   more broadly than intended?

**Do not diagnose this with \`grep\` over transcripts.** Whole-file grep cannot
tell "the hook injected this" from "the session read it", and reported 10 files
against a true 3 on 2026-08-03. Use \`scripts/grounding-readout.sh --since-start\`.

<sub>Posted by \`scripts/grounding-fire-rate-check.sh\`. Threshold:
\`GROUNDING_MIN_FIRE_RATE\` / \`--min-rate\`.</sub>
EOF
)"

echo "::error title=Grounding fire rate below floor::${issue_title}"
echo
printf '%s\n' "$report"
echo

if [ "$DRY_RUN" = true ]; then
  echo "dry-run: would upsert a tracking issue (title: $issue_title)"
  exit 1
fi

if [ -n "$tracking_issue" ]; then
  if jq -n --arg t "$issue_title" --arg b "$report" '{title:$t,body:$b}' \
       | gh api -X PATCH "repos/$REPO/issues/$tracking_issue" --input - >/dev/null; then
    echo "Updated tracking issue #$tracking_issue."
  else
    echo "::error title=grounding-fire-rate-check::failed to update tracking issue #$tracking_issue." >&2
  fi
elif jq -n --arg t "$issue_title" --arg b "$report" --argjson l "$ISSUE_LABELS" \
       '{title:$t,body:$b,labels:$l}' \
       | gh api -X POST "repos/$REPO/issues" --input - >/dev/null; then
  echo "Opened a tracking issue."
else
  echo "::error title=grounding-fire-rate-check::failed to open a tracking issue. Check that gh has 'issues: write' and that the 'area:fitness' and 'main-health' labels exist." >&2
fi

# Last, so the notification above is always attempted first. An alarm that
# exits before it notifies is no alarm.
exit 1
