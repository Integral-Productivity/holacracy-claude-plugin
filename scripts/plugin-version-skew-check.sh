#!/usr/bin/env bash
#
# plugin-version-skew-check.sh — alarm when the plugin version a session
# actually LOADS differs from the version consumers are supposed to be running.
#
# WHY THIS EXISTS
# ---------------
# This is the single check that would have caught issue #122 on day one.
#
# The Claude desktop app materializes each enabled plugin into a per-app-session
# directory and loads it from there. In #122 that copy sat at **v0.6.0** —
# which predates the role-grounding directive entirely — while
# `~/.claude/plugins/installed_plugins.json` reported **0.10.2**. The hook ran
# every session and emitted nothing, for two weeks, invisibly. Of the 40 plugins
# materialized into that directory, holacracy was the only stale one, and
# nothing anywhere surfaced it.
#
# Drift had already recurred in a second channel unnoticed: the plugin cache sat
# at 0.10.2 while `stable` was 0.10.3. Even the "correct" channel was a release
# behind.
#
# WHAT IS AUTHORITATIVE
# ---------------------
# `stable`. Not `main`, not the newest tag, not `installed_plugins.json`.
# The marketplace installs from the `stable` branch, so `stable` is what
# consumers actually run. A tag can exist while promotion has failed (issue
# #108), and in that state consumers are still on the older version.
#
# The four channels, and what each one can tell you:
#
#   loaded            the version stamp in recent session transcripts. GROUND
#                     TRUTH — the only channel that reports what a session
#                     really ran, rather than what some file says it should.
#   desktop app copy  …/local-agent-mode-sessions/*/rpm/plugin_*/ — the channel
#                     that was stale in #122.
#   plugin cache      ~/.claude/plugins/cache/…/holacracy/<version>/
#   recorded install  ~/.claude/plugins/installed_plugins.json
#
# AN UNKNOWN LOADED VERSION IS SKEW, NEVER A PASS
# -----------------------------------------------
# A copy old enough to predate the version stamp emits no stamp at all — which
# is exactly how v0.6.0 presented. If no session in the window carries a stamp,
# this alarms. Reporting "clear" because the evidence is missing is the same
# fail-silent shape the whole issue is about (#150 acceptance criterion 3).
#
# WHY THE DEFAULT WINDOW IS ONE DAY
# ---------------------------------
# The question is "what is loaded right now", not "what has ever run". A wider
# window drags pre-upgrade sessions in and cries wolf after every release.
#
# EXIT CODES
# ----------
#   0  every determinable channel matches `stable`
#   1  ALARM — a channel is behind, or the loaded version is undeterminable
#   2  usage error or an operational failure
#
# VERIFICATION AFFORDANCES
# ------------------------
# `--fixture-root` and `--stable-version` exist so the alarm can be demonstrated
# against a reproduction of the #122 condition rather than asserted — #150 asks
# for a demonstration. Neither is used in production.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
READOUT="$HERE/grounding-readout.sh"

DEFAULT_DAYS=1
MARKER='<!-- plugin-version-skew-check:v1 -->'
ISSUE_LABELS='["area:infra","main-health"]'
PLUGIN_NAME='holacracy'

DAYS="${PLUGIN_SKEW_WINDOW_DAYS:-$DEFAULT_DAYS}"
FIXTURE_ROOT=''
STABLE_VERSION=''
LOADED_JSON_FILE=''
REPO="${GITHUB_REPOSITORY:-}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/plugin-version-skew-check.sh [options]

  --days N              Look back N days for loaded-version evidence.
                        Default: 1 ("what is loaded right now").
  --stable-version V    Treat V as the authority instead of reading the
                        `stable` branch. Verification affordance; unused in CI.
  --fixture-root PATH   Probe local channels under PATH instead of $HOME, and
                        skip the transcript scan unless --loaded-json is given.
                        Verification affordance; unused in production.
  --loaded-json PATH    Read grounding-readout.sh --json output from this file
                        instead of running it. Verification affordance.
  --repo OWNER/NAME     Repository to read `stable` from and to file the
                        tracking issue in.
  --dry-run             Print the report; make no writes to GitHub.
  -h, --help            This text.

Exit: 0 = no skew, 1 = skew (alarm raised), 2 = usage/operational error.
EOF
}

die() {
  echo "::error title=plugin-version-skew-check::$*" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --days)            DAYS="${2:-}";            shift 2 ;;
    --stable-version)  STABLE_VERSION="${2:-}";  shift 2 ;;
    --fixture-root)    FIXTURE_ROOT="${2:-}";    shift 2 ;;
    --loaded-json)     LOADED_JSON_FILE="${2:-}";shift 2 ;;
    --repo)            REPO="${2:-}";            shift 2 ;;
    --dry-run)         DRY_RUN=true;             shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 usage >&2; die "unknown argument: $1" ;;
  esac
done

case "$DAYS" in
  ''|*[!0-9]*) die "--days must be a non-negative integer, got '$DAYS'" ;;
esac

command -v python3 >/dev/null 2>&1 \
  || die "python3 is required (JSON parsing); not found on PATH"

PROBE_ROOT="${FIXTURE_ROOT:-$HOME}"
[ -d "$PROBE_ROOT" ] || die "probe root does not exist: $PROBE_ROOT"

# ---------------------------------------------------------------------------
# 1. The authority: what `stable` says consumers run
# ---------------------------------------------------------------------------

if [ -z "$STABLE_VERSION" ]; then
  command -v gh >/dev/null 2>&1 || die "the GitHub CLI (gh) is required to read the 'stable' branch; pass --stable-version to skip that read"
  command -v jq >/dev/null 2>&1 || die "jq is required and was not found on PATH"
  if [ -z "$REPO" ]; then
    REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
    [ -n "$REPO" ] || die "could not determine the repository; pass --repo OWNER/NAME"
  fi
  b64="$(gh api "repos/$REPO/contents/.claude-plugin/plugin.json?ref=stable" --jq '.content' 2>/dev/null)" \
    || die "could not read .claude-plugin/plugin.json from the 'stable' branch of $REPO. Without the authority version there is nothing to compare against, so this is an error, not a pass."
  STABLE_VERSION="$(printf '%s' "$b64" | tr -d '\n' | base64 --decode 2>/dev/null | jq -r '.version // empty')" \
    || STABLE_VERSION=''
  [ -n "$STABLE_VERSION" ] || die "could not parse a version out of .claude-plugin/plugin.json on 'stable'"
fi

# ---------------------------------------------------------------------------
# 2. The loaded version: what sessions actually ran
# ---------------------------------------------------------------------------

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

loaded_json='{}'
if [ -n "$LOADED_JSON_FILE" ]; then
  [ -f "$LOADED_JSON_FILE" ] || die "--loaded-json file not found: $LOADED_JSON_FILE"
  loaded_json="$(cat "$LOADED_JSON_FILE")"
elif [ -n "$FIXTURE_ROOT" ]; then
  # A fixture root with no --loaded-json means the transcript channel is simply
  # not under test; the file-based channels below still are.
  loaded_json=''
else
  since="$(days_ago "$DAYS")" || die "could not compute a ${DAYS}-day window on either BSD or GNU date"
  # --include-self because this measures the INSTALLED PLUGIN, not behavior:
  # which version loaded is a property of the deployment, not of the repo the
  # session happened to run in.
  loaded_json="$(bash "$READOUT" --json --include-self --since-start "$since" 2>/dev/null)" \
    || die "grounding-readout.sh failed; cannot determine the loaded version, and an unknown loaded version is not a pass"
fi

# ---------------------------------------------------------------------------
# 3. Probe the file-based channels and decide
# ---------------------------------------------------------------------------

report="$(
  PLUGIN_NAME="$PLUGIN_NAME" \
  PROBE_ROOT="$PROBE_ROOT" \
  STABLE_VERSION="$STABLE_VERSION" \
  LOADED_JSON="$loaded_json" \
  DAYS="$DAYS" \
  python3 <<'PY'
import glob
import json
import os
import re
import sys

NAME = os.environ["PLUGIN_NAME"]
ROOT = os.environ["PROBE_ROOT"]
STABLE = os.environ["STABLE_VERSION"]
DAYS = os.environ["DAYS"]
LOADED_JSON = os.environ.get("LOADED_JSON") or ""

SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)")


def key(v):
    """Sort key for a semver-ish string, or None if it is not comparable.

    Anything unparseable returns None and is treated as skew rather than as
    equal-by-default -- a version we cannot read is not a version we can clear.
    """
    if not v:
        return None
    m = SEMVER.match(v.strip().lstrip("v"))
    return tuple(int(g) for g in m.groups()) if m else None


def read_json(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def plugin_version_at(d):
    """Version of a materialized plugin copy at directory `d`, if it is ours."""
    meta = read_json(os.path.join(d, ".claude-plugin", "plugin.json"))
    if isinstance(meta, dict):
        if str(meta.get("name", "")).strip().lower() != NAME:
            return None
        v = str(meta.get("version", "")).strip()
        if v:
            return v
    # version.txt is the fallback: `release-type: simple` writes it, and a copy
    # can carry it without a parseable manifest.
    try:
        with open(os.path.join(d, "version.txt"), encoding="utf-8") as fh:
            v = fh.read().strip()
    except OSError:
        return None
    # With no manifest to confirm identity, only trust the path.
    return v if (v and NAME in d.lower()) else None


channels = []   # (label, version_or_None, note)

# --- loaded, from transcripts ---------------------------------------------
if LOADED_JSON:
    d = json.loads(LOADED_JSON) if LOADED_JSON.strip() else {}
    seen = d.get("plugin_versions_seen") or {}
    unstamped = int(d.get("sessions_without_plugin_version") or 0)
    sessions = int(d.get("sessions") or 0)
    if seen:
        # The OLDEST version any session ran is the one that matters: a single
        # session on a stale copy is the #122 failure, even if others are fine.
        comparable = [v for v in seen if key(v)]
        worst = min(comparable, key=key) if comparable else sorted(seen)[0]
        note = ", ".join("%s (%d)" % (v, n) for v, n in sorted(seen.items(), reverse=True))
        if unstamped:
            note += ", no version stamp (%d)" % unstamped
        channels.append(("loaded (session transcripts)", worst, note))
    elif sessions:
        channels.append((
            "loaded (session transcripts)", None,
            "%d session(s) in the last %s day(s), NONE carrying a version stamp"
            % (sessions, DAYS)))
    else:
        channels.append((
            "loaded (session transcripts)", None,
            "no sessions in the last %s day(s)" % DAYS))

# --- desktop app materialized copies --------------------------------------
app_globs = [
    os.path.join(ROOT, "Library", "Application Support", "Claude",
                 "local-agent-mode-sessions", "*", "rpm", "plugin_*"),
    os.path.join(ROOT, ".config", "Claude",
                 "local-agent-mode-sessions", "*", "rpm", "plugin_*"),
]
for pattern in app_globs:
    for d in sorted(glob.glob(pattern)):
        # `*.bak-YYYY-MM-DD-HHMM` app-session directories are backups nothing
        # loads from. In #122 one such copy reported 0.2.0 and was inert
        # clutter; alarming on it would train the reader to ignore this check.
        if ".bak-" in d:
            continue
        v = plugin_version_at(d)
        if v:
            channels.append(("desktop app copy", v, os.path.relpath(d, ROOT)))

# --- plugin cache ----------------------------------------------------------
for d in sorted(glob.glob(os.path.join(ROOT, ".claude", "plugins", "cache",
                                       "*", NAME, "*"))):
    if not os.path.isdir(d):
        continue
    # A manifest-confirmed copy is reported WHATEVER its version string says,
    # including an unparseable one -- that lands as UNKNOWN below, which is
    # skew. Dropping it would make a garbled version look like no version at
    # all, i.e. like health. Only when there is no manifest do we fall back to
    # the directory name, and then it must parse, so stray non-version
    # directories in the cache tree are not mistaken for installs.
    v = plugin_version_at(d)
    if v is None:
        v = os.path.basename(d)
        if not key(v):
            continue
    channels.append(("plugin cache", v, os.path.relpath(d, ROOT)))

# --- recorded install ------------------------------------------------------
installed = read_json(os.path.join(ROOT, ".claude", "plugins",
                                   "installed_plugins.json"))
if isinstance(installed, dict):
    for k, val in sorted(installed.items()):
        if NAME not in str(k).lower():
            continue
        v = None
        if isinstance(val, dict):
            v = str(val.get("version") or "").strip() or None
        elif isinstance(val, str):
            v = val.strip() or None
        if v:
            channels.append(("recorded install", v, str(k)))

# --- verdict ---------------------------------------------------------------
stable_key = key(STABLE)
rows, skewed = [], []
for label, v, note in channels:
    k = key(v)
    if k is None:
        status = "UNKNOWN"
    elif stable_key is None:
        status = "?"
    elif k < stable_key:
        status = "BEHIND"
    elif k > stable_key:
        status = "AHEAD"
    else:
        status = "ok"
    # AHEAD is reported but never alarms: a local dev checkout legitimately
    # runs ahead of `stable`. BEHIND and UNKNOWN are the #122 conditions.
    if status in ("BEHIND", "UNKNOWN"):
        skewed.append((label, v, note, status))
    rows.append((label, v or "<undetermined>", status, note))

lines = []
lines.append("  authority: stable = %s" % STABLE)
lines.append("")
lines.append("  %-30s %-14s %-8s %s" % ("channel", "version", "status", "detail"))
lines.append("  %-30s %-14s %-8s %s" % ("-" * 30, "-" * 14, "-" * 8, "-" * 6))
for label, v, status, note in rows:
    lines.append("  %-30s %-14s %-8s %s" % (label, v, status, note))
if not rows:
    lines.append("  (no channels found under %s)" % ROOT)

out = {
    "stable": STABLE,
    "table": "\n".join(lines),
    "skew": [{"channel": c, "version": v, "detail": n, "status": s}
             for c, v, n, s in skewed],
    "channels_found": len(rows),
}
print(json.dumps(out))
PY
)" || die "channel probe failed"

table="$(printf '%s' "$report" | python3 -c 'import json,sys; print(json.load(sys.stdin)["table"])')"
skew_count="$(printf '%s' "$report" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["skew"]))')"
found="$(printf '%s' "$report" | python3 -c 'import json,sys; print(json.load(sys.stdin)["channels_found"])')"

echo "Plugin version skew check"
printf '%s\n' "$table"
echo

# Finding no channels at all is not health -- it means the probe looked in the
# wrong place. Saying "clear" there would be a pass on no evidence.
if [ "$found" -eq 0 ]; then
  die "no plugin channels found under $PROBE_ROOT. Nothing was compared, so this is NOT a pass — check the probe root."
fi

# ---------------------------------------------------------------------------
# 4. Tracking issue
# ---------------------------------------------------------------------------

tracking_issue=''
if [ "$DRY_RUN" = false ] && command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && [ -n "$REPO" ]; then
  tracking_issue="$(gh issue list --repo "$REPO" --state open --label main-health --limit 100 \
    --json number,body 2>/dev/null \
    | jq -r --arg m "$MARKER" '[.[] | select((.body // "") | contains($m))] | .[0].number // empty' || true)"
fi

if [ "$skew_count" -eq 0 ]; then
  echo "Clear — every determinable channel is at $STABLE_VERSION."
  if [ "$DRY_RUN" = true ]; then
    echo "dry-run: would close any open tracking issue"
  elif [ -n "$tracking_issue" ]; then
    jq -n --arg b "Cleared — every determinable plugin channel is now at \`$STABLE_VERSION\`. Closed automatically by \`scripts/plugin-version-skew-check.sh\`." '{body:$b}' \
      | gh api -X POST "repos/$REPO/issues/$tracking_issue/comments" --input - >/dev/null \
      || echo "::warning::could not comment on tracking issue #$tracking_issue before closing it"
    jq -n '{state:"closed"}' | gh api -X PATCH "repos/$REPO/issues/$tracking_issue" --input - >/dev/null \
      && echo "Closed tracking issue #$tracking_issue." \
      || echo "::error title=plugin-version-skew-check::failed to close tracking issue #$tracking_issue; close it by hand." >&2
  fi
  exit 0
fi

skew_rows="$(printf '%s' "$report" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for s in d["skew"]:
    print("| `%s` | `%s` | **%s** | %s |"
          % (s["channel"], s["version"] or "<undetermined>", s["status"], s["detail"]))
')"

issue_title="Plugin version skew: $skew_count channel(s) not at stable ($STABLE_VERSION)"

body="$(cat <<EOF
$MARKER
**The plugin version being loaded does not match what consumers should run.**
\`stable\` is at **$STABLE_VERSION**; $skew_count channel(s) disagree.

| channel | version | status | detail |
| --- | --- | --- | --- |
$skew_rows

\`\`\`
$table
\`\`\`

**Why this matters.** This is issue #122's root cause, and this check is the one
thing that would have caught it on day one. The desktop app had materialized
**v0.6.0** — which predates the role-grounding directive entirely — while
\`installed_plugins.json\` reported 0.10.2. The hook ran every session and emitted
nothing, for two weeks, and every other signal read healthy.

**\`UNKNOWN\` is not "probably fine".** A copy old enough to predate the version
stamp emits no stamp at all. That is exactly how v0.6.0 presented.

To clear this: update the plugin so every channel reaches \`$STABLE_VERSION\`,
then confirm by **measurement** — start a fresh session and check that its
transcript carries the new version — not by reading a config file. Three
config files said the right thing throughout #122.

<sub>Posted by \`scripts/plugin-version-skew-check.sh\`.</sub>
EOF
)"

echo "::error title=Plugin version skew::${issue_title}"
echo
printf '%s\n' "$body"
echo

if [ "$DRY_RUN" = true ]; then
  echo "dry-run: would upsert a tracking issue (title: $issue_title)"
  exit 1
fi

if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && [ -n "$REPO" ]; then
  if [ -n "$tracking_issue" ]; then
    jq -n --arg t "$issue_title" --arg b "$body" '{title:$t,body:$b}' \
      | gh api -X PATCH "repos/$REPO/issues/$tracking_issue" --input - >/dev/null \
      && echo "Updated tracking issue #$tracking_issue." \
      || echo "::error title=plugin-version-skew-check::failed to update tracking issue #$tracking_issue." >&2
  else
    jq -n --arg t "$issue_title" --arg b "$body" --argjson l "$ISSUE_LABELS" \
      '{title:$t,body:$b,labels:$l}' \
      | gh api -X POST "repos/$REPO/issues" --input - >/dev/null \
      && echo "Opened a tracking issue." \
      || echo "::error title=plugin-version-skew-check::failed to open a tracking issue." >&2
  fi
else
  echo "::warning::gh/jq unavailable or no repo resolved; the alarm was printed but no tracking issue was filed."
fi

exit 1
