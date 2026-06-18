#!/usr/bin/env bash
# Holacracy plugin -- SessionStart hook handler.
#
# Surfaces scheduled-task routines tagged with the `holacracy/` prefix that
# either fire today or have anomalies (e.g., last fire failed). Silent when
# there's nothing to report. Fail-silent on error so a broken hook never
# blocks the user's session.
#
# Routine discovery currently relies on the user's scheduled tasks being
# tagged with titles that start with `holacracy/<role>/<routine>/<scope>`.
# That convention is set by the agentic-routines mechanism in v0.3+.
#
# In v0.2, before any routines exist, this hook is effectively always
# silent -- which is the right default. It becomes useful once routines
# are created in v0.3.
#
# The hook output format is the Claude Code hook JSON envelope with
# `hookSpecificOutput.additionalContext` (per the SessionStart convention
# demonstrated by learning-output-style).

set -uo pipefail

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

if [[ ! -r "$LEDGER_FILE" ]]; then
  # No ledger yet (expected in v0.2). Silent exit.
  exit 0
fi

# Parse the ledger. Each line is a JSON object with at least:
#   { "id": "...", "title": "holacracy/secretary/pre-tactical-prep/operations",
#     "next_fire": "2026-05-23T18:00:00Z",
#     "last_fire": "2026-05-16T18:00:00Z",
#     "last_status": "ok" | "error" | "skipped" }
#
# We surface routines whose next_fire is today, or whose last_status is
# "error". Anything else is omitted.

# Use python3 if available for reliable JSON parsing; fall back silently
# if it's not. (macOS ships Python by default; this should be safe.)
if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

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

# If python emitted nothing, exit silent.
if [[ -z "$briefing" ]]; then
  exit 0
fi

# Emit the SessionStart envelope.
#
# Pass the briefing as an argv argument (not interpolated into the Python
# source) so arbitrary packet-summary text -- including triple-quotes or a
# trailing backslash from GlassFrog data -- cannot break the heredoc and
# silently drop the envelope. The quoted heredoc delimiter prevents shell
# expansion inside the script. Fail-silent.
python3 - "$briefing" <<'PY' 2>/dev/null
import json, sys
briefing = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": briefing
    }
}))
PY

exit 0
