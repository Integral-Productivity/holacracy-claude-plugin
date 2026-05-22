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

fires_today = []
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

            # Today check
            nxt = entry.get("next_fire")
            if nxt:
                try:
                    nxt_dt = dt.datetime.fromisoformat(nxt.replace("Z", "+00:00"))
                    if nxt_dt.date() == today:
                        fires_today.append(f"- {title} (fires {nxt_dt.strftime('%H:%M %Z').strip()})")
                except ValueError:
                    pass
except Exception:
    # Fail-silent.
    sys.exit(0)

if not fires_today and not anomalies:
    sys.exit(0)

lines = ["**Holacracy plugin: routine briefing**", ""]
if fires_today:
    lines.append("Routines firing today:")
    lines.extend(fires_today)
    lines.append("")
if anomalies:
    lines.append("Anomalies (review needed):")
    lines.extend(anomalies)
    lines.append("")
lines.append("Run `/holacracy:routines:list` for full inventory (v0.3+).")

print("\n".join(lines))
PY
)

# If python emitted nothing, exit silent.
if [[ -z "$briefing" ]]; then
  exit 0
fi

# Emit the SessionStart envelope.
#
# Use python to JSON-encode the briefing so newlines and quotes don't break
# the envelope. Again, fail-silent.
python3 - <<PY 2>/dev/null
import json, sys
briefing = """$briefing"""
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": briefing
    }
}))
PY

exit 0
