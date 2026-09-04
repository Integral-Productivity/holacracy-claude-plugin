#!/usr/bin/env bash
# Holacracy plugin -- SessionStart hook handler.
#
# Emits (via the Claude Code hook JSON envelope's
# `hookSpecificOutput.additionalContext`) up to two things, in order:
#
#   1. A role-grounding directive (issue #62, Track A PDCA-1) that DEMANDS
#      the session resolve + announce its active Holacratic role/circle before
#      its first substantive action -- emitted ONLY when an authenticated
#      GlassFrog connector is detected (issue #283), and gate-able besides.
#      When the connector is not authenticated the directive is withheld and
#      one informational line says so instead.
#   2. A routine briefing: scheduled-task routines tagged with the `holacracy/`
#      prefix that fire today or have anomalies (e.g., last fire failed).
#
# NEVER POSES A QUESTION. Nothing this hook emits may require an answer before
# work can start: a SessionStart payload reaches unattended sessions as readily
# as interactive ones, and a blocking question there has nobody to answer it
# (issue #283).
#
# NEVER writes nothing: when there is nothing to surface it emits a one-line
# quiet marker carrying the plugin version, so a transcript can always tell
# "ran with nothing to say" from "never ran" (issue #122 -- a stale copy that
# emitted nothing left no trace and went undetected for two weeks). Still
# fail-silent on *error*, so a broken hook never blocks the user's session.
#
# Routine discovery relies on the user's scheduled tasks being tagged with
# titles that start with `holacracy/<role>/<routine>/<scope>` -- a convention
# set by the agentic-routines mechanism in v0.3+. In v0.2, before any routines
# exist, the routine half is effectively always silent (the right default);
# it becomes useful once routines are created in v0.3.
#
# The hook output format is the Claude Code hook JSON envelope with
# `hookSpecificOutput.additionalContext` (per the SessionStart convention
# demonstrated by learning-output-style).

set -uo pipefail

# ---------------------------------------------------------------------------
# Which version is actually running (issue #122).
#
# The outage #122 documents was a v0.6.0 copy being loaded while 0.10.2 was
# recorded as installed. It stayed invisible for two weeks precisely because
# nothing the hook emitted said which version produced it -- diagnosing it took
# archaeology across three install channels. Stamping the version into every
# payload turns that into a grep over transcripts.
#
# "unknown" when version.txt cannot be read, never blank: a missing version must
# read as missing, not as an empty string that looks like an absent field.
_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || _hook_dir=""
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${_hook_dir%/hooks-handlers}}"
PLUGIN_VERSION="unknown"
if [[ -r "$PLUGIN_ROOT/version.txt" ]]; then
  PLUGIN_VERSION="$(tr -d '[:space:]' < "$PLUGIN_ROOT/version.txt")"
  [[ -n "$PLUGIN_VERSION" ]] || PLUGIN_VERSION="unknown"
fi

# ---------------------------------------------------------------------------
# Part 1 -- Role-grounding directive (issue #62, Track A PDCA-1).
#
# The plugin *documents* the grounding standard (skills/shared/actor-and-role-
# resolution.md: resolve + announce the active role/circle, re-validate on
# pivot) but has no system mechanism that makes it hold. This injects a
# one-line, system-fired directive so grounding no longer depends on operator
# vigilance.
#
# HONEST BY CONSTRUCTION: a hook has NO MCP access at fire time (same scar as
# the routine half below -- see the note before LEDGER_FILE, and ADR-0004's
# "Strategy on file says..." narration scar). This directive therefore *demands
# the load*; it never *claims* grounding already happened. The wording says so
# explicitly.
#
# CONFIG (all optional). The default is on wherever the directive CAN be
# satisfied -- see the capability gate below, which is not optional and is the
# one condition #283 made non-negotiable:
#   HOLACRACY_GROUNDING_DIRECTIVE          on|off  (default on)  master toggle
#   HOLACRACY_GROUNDING_REQUIRE_GLASSFROG  on|off  (default off) only inject
#       when a GlassFrog connector is declared (a `.mcp.json` naming glassfrog
#       in the plugin root or cwd). This is a shell-detectable proxy for "the
#       connector is wired" -- it does not, and cannot, assert a live session.
#   HOLACRACY_GROUNDING_REQUIRE_PATH       <regex> (default unset) only inject
#       when $PWD matches this extended-regex (e.g. a governed-work worktree).
#   HOLACRACY_GROUNDING_EXCLUDE            <regex> (default unset) do NOT inject
#       when $PWD matches this extended-regex.
# When several gates are set they AND together, and EXCLUDE always wins.
#
# Why the scoping knob is an exclusion and not a positive gate (issue #122):
# every opt-in form shares one property -- a misconfiguration makes the
# directive silently absent, which is byte-for-byte the two-week outage this
# hook is recovering from. An opt-out inverts the failure mode: forgetting to
# configure it means the directive shows up somewhere unwanted, which is
# visible, mildly annoying, and one edit to fix. Given that this whole effort
# exists because a silent zero went undetected, the default belongs to the
# option whose failure announces itself.

# Portable lowercase (avoids ${var,,} for older bash).
_lc() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }

# Truthy test for on|1|true|yes.
_truthy() {
  case "$(_lc "${1:-}")" in
    on|1|true|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Capability gate: is the GlassFrog connector actually AUTHENTICATED? (#283)
#
# The directive tells the session to call `glassfrog_get_me` before its first
# substantive action. When the connector is unauthenticated -- which includes
# EVERY non-interactive session, because the OAuth flow cannot run there -- that
# instruction cannot be carried out. What the session got instead was a failed
# tool call and, from the directive's own fallback, a question with nobody
# present to answer it. An Administration-tier control placed on a path where
# compliance is impossible reads as governance and functions as noise.
#
# WHAT SIGNAL, AND WHY THIS ONE
#
# A SessionStart hook is on the hot path of every session in every repo, so the
# check has to be local and fast. Four candidates were evaluated:
#
#   * The hook's own stdin/env. Carries session_id, transcript_path, cwd,
#     permission_mode, hook_event_name, source -- and no MCP state at all. The
#     harness documents no field and no environment variable that exposes MCP
#     connection or authentication status to a hook.
#   * `claude mcp list`, or any probe of the server URL. Both are network round
#     trips on the hot path. Disqualified on speed, not on accuracy.
#   * `~/.claude/mcp-needs-auth-cache.json`. Negative-only, and observably
#     stale: on the machine this was written on, glassfrog was unauthenticated
#     and absent from that cache. Absence there proves nothing.
#   * The harness's own MCP OAuth store. Local, small, and the very record the
#     harness consults to attach a bearer token to the server. This one.
#
# So: an entry under `mcpOAuth` whose server name contains "glassfrog" AND whose
# `accessToken` is a non-empty string. The empty-string case is not theoretical
# -- it is exactly what an OAuth flow that was started and never completed
# leaves behind, and it is why "an entry exists" is not the test.
#
# FAIL CLOSED, BUT NEVER SILENTLY. If the store is missing, unreadable, or holds
# no authenticated glassfrog entry, the directive is withheld. That inverts the
# default ADR-0008 A2 argued for, and A2's objection still stands: an opt-in
# gate that misfires makes the directive silently absent, which is byte-for-byte
# the #122 outage. Two things answer it, and neither is optional:
#   1. A withheld directive announces itself in the payload (see the withheld
#      marker below). Absence is visible in the transcript, not inferred.
#   2. HOLACRACY_GROUNDING_ASSUME_GLASSFROG=on forces the gate open, for any
#      deployment whose token lives somewhere this check cannot see (an OS
#      keychain, a managed enterprise store). A false negative is then one
#      environment variable from fixed rather than an unfixable silent zero.
#
# CONFIG:
#   HOLACRACY_GROUNDING_ASSUME_GLASSFROG   on|off  (default off) treat the
#       connector as authenticated without consulting the store.
#   HOLACRACY_GROUNDING_CREDENTIALS_FILE   <path>  (default
#       ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json) which store to
#       read. Exists so both sides of this gate are exercisable in tests.
_glassfrog_authenticated() {
  _truthy "${HOLACRACY_GROUNDING_ASSUME_GLASSFROG:-off}" && return 0

  local cred="${HOLACRACY_GROUNDING_CREDENTIALS_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json}"
  [[ -r "$cred" ]] || return 1
  # Cheap pre-filter before paying for a python3 start-up: a store that does not
  # contain the string at all cannot contain an authenticated entry.
  grep -qi 'glassfrog' "$cred" 2>/dev/null || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - "$cred" <<'PY' 2>/dev/null
import json, sys, time

try:
    with open(sys.argv[1]) as fh:
        store = json.load(fh)
except Exception:
    sys.exit(1)

entries = store.get("mcpOAuth")
if not isinstance(entries, dict):
    sys.exit(1)

for key, entry in entries.items():
    if not isinstance(entry, dict):
        continue
    # serverName is authoritative; the map key ("<server>|<hash>") is the
    # fallback for any record written without one.
    name = entry.get("serverName") or str(key).split("|", 1)[0]
    if "glassfrog" not in str(name).lower():
        continue

    token = entry.get("accessToken")
    if not isinstance(token, str) or not token.strip():
        # A discovery record with an empty token is an OAuth flow that was
        # begun and never finished. That is the unauthenticated state.
        continue

    # An expiry, when present, is only disqualifying with no refresh token --
    # otherwise the harness refreshes on first use. Epoch seconds and
    # milliseconds are both accepted; the threshold separates them.
    exp = entry.get("expiresAt")
    if isinstance(exp, (int, float)) and not entry.get("refreshToken"):
        seconds = exp / 1000.0 if exp > 1e11 else float(exp)
        if seconds <= time.time():
            continue

    sys.exit(0)

sys.exit(1)
PY
}

# Honest proxy for "a GlassFrog connector is declared in the WORKING TREE": a
# readable .mcp.json naming glassfrog at $PWD, at $PWD/.claude, or anywhere up
# to and including the enclosing git root.
#
# This deliberately does NOT consult $CLAUDE_PLUGIN_ROOT. The plugin ships its
# own .mcp.json naming glassfrog, so probing there made the gate return true in
# every directory on the machine -- dead configuration that read as a working
# check (issue #122). The old form appeared to behave in the test suite only
# because CLAUDE_PLUGIN_ROOT is unset there; in production it is always set, so
# the gate was true everywhere it mattered. See G9.
#
# The walk to the git root fixes a second defect: the old check tested the exact
# $PWD only, so a session started in a subdirectory of a connector-declaring
# repo did not match.
_glassfrog_declared() {
  local dir="${PWD:-}" f
  [[ -n "$dir" ]] || return 1
  while [[ -n "$dir" ]]; do
    for f in "$dir/.mcp.json" "$dir/.claude/.mcp.json"; do
      [[ -r "$f" ]] && grep -qi 'glassfrog' "$f" 2>/dev/null && return 0
    done
    # Stop at the repo root (.git is a dir in a normal clone, a file in a
    # worktree) and at the filesystem root.
    [[ -e "$dir/.git" || "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

grounding=""
withheld=""
if _truthy "${HOLACRACY_GROUNDING_DIRECTIVE:-on}"; then
  inject=1
  if _truthy "${HOLACRACY_GROUNDING_REQUIRE_GLASSFROG:-off}"; then
    _glassfrog_declared || inject=0
  fi
  if [[ -n "${HOLACRACY_GROUNDING_REQUIRE_PATH:-}" ]]; then
    printf '%s' "${PWD:-}" | grep -Eq -- "${HOLACRACY_GROUNDING_REQUIRE_PATH}" 2>/dev/null || inject=0
  fi
  # Exclusion is evaluated last and wins over every positive gate.
  if [[ -n "${HOLACRACY_GROUNDING_EXCLUDE:-}" ]]; then
    printf '%s' "${PWD:-}" | grep -Eq -- "${HOLACRACY_GROUNDING_EXCLUDE}" 2>/dev/null && inject=0
  fi
  # The capability gate (#283) is evaluated last of all, and only for a
  # directive the operator's own configuration would otherwise have allowed
  # through. The ordering carries meaning in the output: operator-configured
  # suppression stays quiet, because the operator already knows they set it;
  # capability suppression ANNOUNCES ITSELF, because a missing connector is a
  # diagnosable condition the operator may not know about, and an absence
  # nobody can see is the #122 failure shape.
  if [[ "$inject" -eq 1 ]] && ! _glassfrog_authenticated; then
    inject=0
    withheld="_holacracy-claude-plugin v${PLUGIN_VERSION}: role-grounding directive withheld -- no authenticated GlassFrog connector detected, so role resolution is unavailable this session._"
  fi
  if [[ "$inject" -eq 1 ]]; then
    grounding=$(cat <<'DIRECTIVE'
**Holacracy plugin: role-grounding directive**

Before your first substantive action this session, resolve and announce the active Holacratic role/circle per the procedure in `skills/shared/actor-and-role-resolution.md` -- follow its Step 2 call shape, which is bounded: do NOT pass `include_roles: true` to `glassfrog_get_me`, and do NOT call `glassfrog_list_my_roles` unpaged. For a Partner who fills many roles both overflow the tool-result limit and cost you the turn. Then announce the result in your opening lines (e.g. "Operating as **Role of Circle**").

This grounding has NOT yet been performed -- this directive only requests it and does not assert it happened (the hook has no GlassFrog access at fire time). If work crosses into another role's remit, name the boundary and mark a chapter.
DIRECTIVE
)
    # Stamp the running version. Appended AFTER the heredoc and never inside it:
    # scripts/grounding-readout.sh derives its detection marker from the first
    # non-empty line of this `DIRECTIVE` heredoc at run time, and its header
    # warns that windows are only comparable within one directive revision. A
    # version string inside the block would change every release and silently
    # break that comparison.
    grounding="${grounding}"$'\n\n'"_Directive emitted by holacracy-claude-plugin v${PLUGIN_VERSION}._"
  fi
fi

# Discover today's holacracy routines.
#
# Why not call `mcp__scheduled-tasks__list_scheduled_tasks` from the hook?
# Hooks run as plain shell commands without access to MCP tooling at
# session-start time. The honest answer for v0.2 is: there's no shell-level
# way to query the scheduled-tasks MCP from a hook script. The agentic-
# routines mechanism in v0.3 will write a per-actor routine ledger file
# (e.g., `${HOME}/.claude/holacracy/routines.jsonl`) that the hook can read
# without needing MCP at hook time.
#
# Until that ledger exists, we exit silently. This is the documented
# "silent when nothing to report" behaviour.

LEDGER_FILE="${HOLACRACY_ROUTINE_LEDGER:-${HOME}/.claude/holacracy/routines.jsonl}"

# The routine briefing (Part 2) is optional. If there's no readable ledger
# (expected in v0.2) or no python3 for JSON parsing, leave the briefing empty
# and fall through to the combine step -- the grounding directive (Part 1) may
# still need to emit. We must NOT exit the whole hook here.
#
# Ledger line shape. Each line is a JSON object with at least:
#   { "id": "...", "title": "holacracy/secretary/pre-tactical-prep/operations",
#     "next_fire": "2026-05-23T18:00:00Z",
#     "last_fire": "2026-05-16T18:00:00Z",
#     "last_status": "ok" | "error" | "skipped" }
# We surface routines whose next_fire is today, or whose last_status is
# "error". Anything else is omitted.
briefing=""
if [[ -r "$LEDGER_FILE" ]] && command -v python3 >/dev/null 2>&1; then
briefing=$(python3 - <<'PY' "$LEDGER_FILE" 2>/dev/null || true
import datetime as dt
import json
import os
import sys

ledger_path = sys.argv[1]
today = dt.date.today()


def _date(s):
    """Local calendar date for an ISO-8601 instant.

    Ledger timestamps are UTC (`...Z`), but a routine's "today" means today in
    the user's timezone -- so tz-aware values are converted to local before the
    date is taken. Taking .date() straight off the UTC value and comparing it
    against dt.date.today() (which is local) mixes timezones: for the hours the
    two calendar dates disagree -- ~7h/day in Pacific -- a routine genuinely due
    today does not surface, and windows are off by one. Issue #132; that
    mismatch also made the test suite pass under a UTC CI runner while failing
    locally, so it would have been wired in green and stayed broken.
    """
    try:
        d = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None
    if d.tzinfo is not None:
        d = d.astimezone()
    return d.date()


due = []
anomalies = []

try:
    with open(ledger_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            title = entry.get("title", "")
            if not title.startswith("holacracy/"):
                continue

            # Anomaly check
            if entry.get("last_status") == "error":
                anomalies.append(
                    f"- {title}: last fire FAILED ({entry.get('last_fire', 'unknown time')})"
                )

            # Surfacing window. Prefer surface_from/surface_until; fall back to
            # next_fire's day for legacy entries that carry no window. A window
            # match (not exact day) is correct because a routine may fire late
            # -- on next app launch -- so the packet should show across the
            # prep-to-meeting window.
            sf = _date(entry["surface_from"]) if entry.get("surface_from") else None
            su = _date(entry["surface_until"]) if entry.get("surface_until") else None
            if sf or su:
                in_window = (sf or today) <= today <= (su or today)
            else:
                nxt = _date(entry["next_fire"]) if entry.get("next_fire") else None
                in_window = (nxt == today)

            if not in_window:
                continue

            summary = entry.get("packet_summary")
            if summary:
                # New-style entry with a built packet: surface the sanitized
                # summary, the freshness marker, and a pointer to the full draft.
                item = f"- {title}\n  {summary}\n  (as of {entry.get('built_at', 'unknown')}"
                if entry.get("packet_path"):
                    item += f"; full draft: {entry['packet_path']}"
                item += ")"
                due.append(item)
            else:
                # Legacy / metadata-only entry: render exactly as before.
                nxt = entry.get("next_fire")
                when = ""
                if nxt:
                    try:
                        when = dt.datetime.fromisoformat(nxt.replace("Z", "+00:00")).strftime("%H:%M %Z").strip()
                    except ValueError:
                        when = ""
                due.append(f"- {title}" + (f" (fires {when})" if when else ""))
except Exception:
    # Fail-silent.
    sys.exit(0)

if not due and not anomalies:
    sys.exit(0)

lines = ["**Holacracy plugin: routine briefing**", ""]
if due:
    lines.append("Routines ready / firing today:")
    lines.extend(due)
    lines.append("")
if anomalies:
    lines.append("Anomalies (review needed):")
    lines.extend(anomalies)
    lines.append("")
lines.append("Run `/holacracy:routines` for full inventory.")

print("\n".join(lines))
PY
)
fi

# Combine the grounding directive (Part 1) and the routine briefing (Part 2)
# into a single additionalContext payload. Either may be empty; if both are,
# exit silent. When both are present the grounding directive leads, separated
# by a horizontal rule.
#
# `$withheld` stands in for `$grounding` when the capability gate suppressed the
# directive (#283). It is ONE informational line: it asks nothing, requires no
# answer, and instructs the session to do nothing before its first substantive
# action. That is the whole contract -- a SessionStart payload has no guarantee
# of a human at the other end, so it must never pose a question.
lead="${grounding:-$withheld}"
if [[ -n "$lead" && -n "$briefing" ]]; then
  additional_context="${lead}"$'\n\n---\n\n'"${briefing}"
elif [[ -n "$lead" ]]; then
  additional_context="$lead"
elif [[ -n "$briefing" ]]; then
  additional_context="$briefing"
else
  # NEVER exit silent (issue #122).
  #
  # A hook that writes nothing to stdout leaves no record in the transcript at
  # all, so "ran and had nothing to surface" is indistinguishable from "never
  # ran" -- which is exactly how a stale copy emitting nothing went undetected
  # for two weeks. This marker is the smallest thing that makes the difference
  # observable, and it carries the version for the same reason.
  #
  # It deliberately does NOT contain the directive's marker line, so
  # scripts/grounding-readout.sh will not miscount a quiet session as a
  # directive firing.
  additional_context="_holacracy-claude-plugin v${PLUGIN_VERSION}: session-start hook ran; nothing to surface._"
fi

# Emit the SessionStart envelope.
#
# Pass the payload as an argv argument (not interpolated into the Python
# source) so arbitrary packet-summary text -- including triple-quotes or a
# trailing backslash from GlassFrog data -- cannot break the heredoc and
# silently drop the envelope. The quoted heredoc delimiter prevents shell
# expansion inside the script. Fail-silent.
python3 - "$additional_context" <<'PY' 2>/dev/null
import json, sys
additional_context = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": additional_context
    }
}))
PY

exit 0
