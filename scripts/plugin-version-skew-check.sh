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


# Files that together identify a copy of THIS plugin when no manifest names it.
# Chosen because both are ours and neither is generic enough to match another
# plugin that happens to ship skills or hooks.
FINGERPRINT = (
    os.path.join("hooks-handlers", "session-start.sh"),
    os.path.join("skills", "holacracy-facilitator"),
)

NO_VERSION = "<unreadable>"


def read_version_txt(d):
    try:
        with open(os.path.join(d, "version.txt"), encoding="utf-8") as fh:
            return fh.read().strip() or None
    except OSError:
        return None


def plugin_version_at(d):
    """Version of a materialized plugin copy at `d`, or None if it is not ours.

    Ordered strategies, first hit wins. The previous single-strategy form
    demanded a `.claude-plugin/plugin.json` naming us, with a `version.txt`
    fallback gated on the PATH containing the plugin name -- which a
    `rpm/plugin_<opaque-ID>/` directory never does. That made the fallback dead
    for the one surface it was written to cover, and the desktop-app copies
    invisible. Per ADR-0007: derive identity from what is on disk, not from a
    single assumed shape.
    """
    # 1. A manifest that names a plugin is authoritative in both directions --
    #    it identifies ours AND positively rules out someone else's.
    meta = read_json(os.path.join(d, ".claude-plugin", "plugin.json"))
    if isinstance(meta, dict) and meta.get("name") is not None:
        if str(meta.get("name", "")).strip().lower() != NAME:
            return None
        v = str(meta.get("version", "")).strip()
        return v or read_version_txt(d) or NO_VERSION

    # 2. No usable manifest: identify structurally. A copy carrying both of our
    #    fingerprint paths is ours whatever the directory is called.
    if all(os.path.exists(os.path.join(d, p)) for p in FINGERPRINT):
        return read_version_txt(d) or NO_VERSION

    # 3. Last resort: the path names us.
    if NAME in d.lower():
        return read_version_txt(d)

    return None


# (label, version_or_None, note, is_na)
#
# `is_na` marks a channel that is legitimately not in use here -- reported as a
# row, never as an alarm. The distinction that decides it:
#
#   Does absence PROVE the channel is unused, or only that we could not read it?
#
# Where the plugin name appears in the path (the cache) or in a key (the install
# record), absence is proof: the plugin is not installed through that channel,
# and saying so is honest. Where identity is opaque (`rpm/plugin_<ID>/`),
# absence among copies that DO exist means we could not tell what is there --
# which is the #122 condition, and alarms.
#
# What is never acceptable is an omitted row. The first live run reported five
# skewed channels and silently said nothing about the two that caused #122;
# `channels_found` was 6, so the "nothing compared" guard did not trip either.
# That is the quiet-marker principle from ADR-0008 A1, missed here: a channel
# with nothing to say must still say so.
channels = []

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
        channels.append(("loaded (session transcripts)", worst, note, False))
    elif sessions:
        channels.append((
            "loaded (session transcripts)", None,
            "%d session(s) in the last %s day(s), NONE carrying a version stamp"
            % (sessions, DAYS), False))
    else:
        channels.append((
            "loaded (session transcripts)", None,
            "no sessions in the last %s day(s)" % DAYS, False))

# --- desktop app materialized copies --------------------------------------
#
# The channel that was stale in #122, and the one whose identity is opaque:
# copies live in `rpm/plugin_<ID>/`, so the plugin name is nowhere in the path.
# That is exactly why absence here cannot be read as "not installed".
app_roots = [
    os.path.join(ROOT, "Library", "Application Support", "Claude",
                 "local-agent-mode-sessions"),
    os.path.join(ROOT, ".config", "Claude", "local-agent-mode-sessions"),
]
present_roots = [r for r in app_roots if os.path.isdir(r)]
app_rows, app_copies_seen = [], 0
for r in present_roots:
    for d in sorted(glob.glob(os.path.join(r, "*", "rpm", "plugin_*"))):
        # `*.bak-YYYY-MM-DD-HHMM` app-session directories are backups nothing
        # loads from. In #122 one such copy reported 0.2.0 and was inert
        # clutter; alarming on it would train the reader to ignore this check.
        if ".bak-" in d:
            continue
        app_copies_seen += 1
        v = plugin_version_at(d)
        if v:
            app_rows.append(("desktop app copy", v, os.path.relpath(d, ROOT), False))

if app_rows:
    channels.extend(app_rows)
elif not present_roots:
    channels.append(("desktop app copy", None,
                     "surface not present under %s" % ROOT, True))
elif app_copies_seen == 0:
    channels.append(("desktop app copy", None,
                     "surface present, no plugins materialized into it", True))
else:
    # Copies exist and none is identifiable as ours. We cannot say what this
    # surface is running -- the #122 condition, so it alarms.
    channels.append((
        "desktop app copy", None,
        "%d plugin copies present, NONE identifiable as %s -- cannot tell what "
        "this surface runs" % (app_copies_seen, NAME), False))

# --- plugin cache ----------------------------------------------------------
#
# The cache retains EVERY version ever installed, one directory per version, so
# a row per directory reports history as skew. The first live run showed a cache
# holding 0.6.0/0.10.2/0.10.3 alongside 0.12.0 and called four of them BEHIND --
# four false alarms about archived copies nothing loads. The effective version
# of a marketplace's cache is the NEWEST one present; the rest are detail.
cache_root = os.path.join(ROOT, ".claude", "plugins", "cache")
by_market = {}
for d in sorted(glob.glob(os.path.join(cache_root, "*", NAME, "*"))):
    if not os.path.isdir(d):
        continue
    v = plugin_version_at(d) or os.path.basename(d)
    if not v:
        continue
    market = os.path.basename(os.path.dirname(os.path.dirname(d)))
    by_market.setdefault(market, {})[v] = d

for market in sorted(by_market):
    versions = by_market[market]
    comparable = [v for v in versions if key(v)]
    effective = max(comparable, key=key) if comparable else sorted(versions)[0]
    archived = sorted((v for v in versions if v != effective),
                      key=lambda x: key(x) or (0, 0, 0), reverse=True)
    note = "%s (effective)" % market
    if archived:
        note += "; also cached: %s" % ", ".join(archived)
    channels.append(("plugin cache", effective, note, False))

if not by_market:
    # The plugin name is a path component here, so its absence is proof of
    # "not cached", not an inability to read. Reporting that as UNKNOWN would
    # be crying wolf; omitting the row entirely is the bug being fixed.
    where = "no plugin cache under %s" % ROOT
    if os.path.isdir(cache_root):
        where = "cache present, no %s entry in any marketplace" % NAME
    channels.append(("plugin cache", None, where, True))

# --- recorded install ------------------------------------------------------
installed_path = os.path.join(ROOT, ".claude", "plugins",
                              "installed_plugins.json")
installed = read_json(installed_path)
install_rows = []
if isinstance(installed, dict):
    for k, val in sorted(installed.items()):
        if NAME not in str(k).lower():
            continue
        v = None
        if isinstance(val, dict):
            v = str(val.get("version") or "").strip() or None
        elif isinstance(val, str):
            v = val.strip() or None
        install_rows.append(("recorded install", v or NO_VERSION, str(k), False))

if install_rows:
    channels.extend(install_rows)
elif not os.path.exists(installed_path):
    channels.append(("recorded install", None,
                     "no installed_plugins.json under %s" % ROOT, True))
elif installed is None:
    # The file is there and we could not parse it. That is unreadability, not
    # absence, so it alarms.
    channels.append(("recorded install", None,
                     "installed_plugins.json present but unparseable", False))
else:
    # Parsed cleanly and we are simply not in it. The plugin name would be in
    # the key, so this is proof of "not recorded", not a failure to read.
    channels.append(("recorded install", None,
                     "installed_plugins.json has no %s entry" % NAME, True))

# --- verdict ---------------------------------------------------------------
stable_key = key(STABLE)
rows, skewed = [], []
comparable_channels = 0
for label, v, note, is_na in channels:
    k = key(v)
    if is_na:
        status = "n/a"
    elif k is None:
        status = "UNKNOWN"
    elif stable_key is None:
        status = "?"
    elif k < stable_key:
        status = "BEHIND"
    elif k > stable_key:
        status = "AHEAD"
    else:
        status = "ok"
    if status in ("ok", "BEHIND", "AHEAD"):
        comparable_channels += 1
    # AHEAD is reported but never alarms: a local dev checkout legitimately
    # runs ahead of `stable`. n/a never alarms either -- it means the channel
    # is provably not in use here, which is a fact, not a fault. BEHIND and
    # UNKNOWN are the #122 conditions.
    if status in ("BEHIND", "UNKNOWN"):
        skewed.append((label, v, note, status))
    if is_na:
        shown = "—"
    else:
        shown = v or "<undetermined>"
    rows.append((label, shown, status, note))

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
    # Rows whose version could actually be compared against `stable`. This, not
    # the row count, is what "did we measure anything" means now that absent
    # channels report themselves instead of vanishing -- a run of four honest
    # `n/a` rows has compared nothing and must not read as clear.
    "comparable_channels": comparable_channels,
}
print(json.dumps(out))
PY
)" || die "channel probe failed"

table="$(printf '%s' "$report" | python3 -c 'import json,sys; print(json.load(sys.stdin)["table"])')"
skew_count="$(printf '%s' "$report" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["skew"]))')"
comparable="$(printf '%s' "$report" | python3 -c 'import json,sys; print(json.load(sys.stdin)["comparable_channels"])')"

echo "Plugin version skew check"
printf '%s\n' "$table"
echo

# Comparing nothing is not health -- it means the probe looked in the wrong
# place, or every channel is legitimately absent and there is no deployment to
# judge. Either way, saying "clear" would be a pass on no evidence.
#
# Anchored on COMPARABLE channels, not on row count. Every channel now emits a
# row even when it has nothing to report, so counting rows would let a run of
# four honest `n/a` rows look like four successful comparisons.
if [ "$comparable" -eq 0 ]; then
  die "no channel under $PROBE_ROOT yielded a version that could be compared against stable. Nothing was measured, so this is NOT a pass — check the probe root."
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

# shellcheck disable=SC2016  # the backticks are literal markdown code spans in
# the issue body, inside single-quoted Python -- nothing here should expand.
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
