#!/usr/bin/env bash
# Holacracy plugin -- SessionStart hook handler.
#
# Emits (via the Claude Code hook JSON envelope's
# `hookSpecificOutput.additionalContext`) up to two things, in order:
#
#   1. A role-grounding directive (issue #62, Track A PDCA-1) that DEMANDS
#      the session resolve + announce its active Holacratic role/circle before
#      its first substantive action. On by default; gate-able (see below).
#   2. A routine briefing: scheduled-task routines tagged with the `holacracy/`
#      prefix that fire today or have anomalies (e.g., last fire failed).
#
# Silent when there's nothing to report. Fail-silent on error so a broken hook
# never blocks the user's session.
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
# CONFIG (all optional; default is always-on so the first experiment gets
# maximal, honest signal):
#   HOLACRACY_GROUNDING_DIRECTIVE          on|off  (default on)  master toggle
#   HOLACRACY_GROUNDING_REQUIRE_GLASSFROG  on|off  (default off) only inject
#       when a GlassFrog connector is declared (a `.mcp.json` naming glassfrog
#       in the plugin root or cwd). This is a shell-detectable proxy for "the
#       connector is wired" -- it does not, and cannot, assert a live session.
#   HOLACRACY_GROUNDING_REQUIRE_PATH       <regex> (default unset) only inject
#       when $PWD matches this extended-regex (e.g. a governed-work worktree).
# When both gates are set they AND together (both must pass to inject).

# Portable lowercase (avoids ${var,,} for older bash).
_lc() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }

# Truthy test for on|1|true|yes.
_truthy() {
  case "$(_lc "${1:-}")" in
    on|1|true|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Honest proxy for "GlassFrog connector declared": a readable .mcp.json naming
# glassfrog in the plugin root or the session cwd.
_glassfrog_declared() {
  local f
  for f in "${CLAUDE_PLUGIN_ROOT:-}/.mcp.json" "${PWD:-}/.mcp.json" "${PWD:-}/.claude/.mcp.json"; do
    [[ "$f" != "/.mcp.json" && "$f" != "/.claude/.mcp.json" && -r "$f" ]] \
      && grep -qi 'glassfrog' "$f" 2>/dev/null && return 0
  done
  return 1
}

grounding=""
if _truthy "${HOLACRACY_GROUNDING_DIRECTIVE:-on}"; then
  inject=1
  if _truthy "${HOLACRACY_GROUNDING_REQUIRE_GLASSFROG:-off}"; then
    _glassfrog_declared || inject=0
  fi
  if [[ -n "${HOLACRACY_GROUNDING_REQUIRE_PATH:-}" ]]; then
    printf '%s' "${PWD:-}" | grep -Eq -- "${HOLACRACY_GROUNDING_REQUIRE_PATH}" 2>/dev/null || inject=0
  fi
  if [[ "$inject" -eq 1 ]]; then
    grounding=$(cat <<'DIRECTIVE'
**Holacracy plugin: role-grounding directive**

Before your first substantive action this session, resolve and announce the active Holacratic role/circle per the procedure in `skills/shared/actor-and-role-resolution.md`: call `glassfrog_get_me` + `glassfrog_list_my_roles`, resolve to a single role + circle, then announce it in your opening lines (e.g. "Operating as **Role of Circle**").

This grounding has NOT yet been performed -- this directive only requests it and does not assert it happened (the hook has no GlassFrog access at fire time). If work crosses into another role's remit, name the boundary and mark a chapter. If GlassFrog isn't connected, name that limitation and ask which role/circle to treat as primary rather than assuming one.
DIRECTIVE
)
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
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).date()
    except Exception:
        return None


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
if [[ -n "$grounding" && -n "$briefing" ]]; then
  additional_context="${grounding}"$'\n\n---\n\n'"${briefing}"
elif [[ -n "$grounding" ]]; then
  additional_context="$grounding"
elif [[ -n "$briefing" ]]; then
  additional_context="$briefing"
else
  exit 0
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
