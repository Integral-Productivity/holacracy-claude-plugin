#!/usr/bin/env bash
# scripts/grounding-readout.sh
#
# Lightweight readout for the role-grounding experiment (issue #62, Track A
# PDCA-1). Greps Claude Code session transcripts for the three grounding
# signals and prints per-signal session counts + rates over a run window,
# against the pre-experiment baseline ("Operating as ..." seen in 0 of 40
# sessions).
#
# A session "hits" a signal if its transcript file contains the pattern:
#   resolve+announce : the announcement "Operating as ..." (case-insensitive)
#   remit-crossing   : naming a cross-role remit boundary
#   chapter-mark     : a mark_chapter tool call
#
# HONEST BY CONSTRUCTION: this counts only what the model literally emitted in
# transcripts. It infers nothing and claims no grounding beyond the text found.
# It is deliberately a coarse proxy (a transcript that merely quotes the words
# "operating as" would count) -- adequate for a decisive move-off-zero read,
# not a precise instrument. The post-MVP structured session log (see the issue
# filed alongside this experiment) is the higher-fidelity successor.
#
# Usage:
#   scripts/grounding-readout.sh [--since YYYY-MM-DD] [--project <slug>]
#                                [--json] [DIR ...]
#   --since   only count transcripts modified on/after this date
#   --project restrict to $CLAUDE_PROJECTS_DIR/<slug>
#   --json    emit machine-readable JSON instead of the table
#   DIR ...   scan these dirs instead of the default projects dir
#
# Env:
#   CLAUDE_PROJECTS_DIR  transcript root (default: ~/.claude/projects)

set -uo pipefail

PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
BASELINE_NOTE="baseline: 0 of 40 pre-experiment sessions had 'Operating as ...'"

# Signal patterns (extended regex). resolve+announce and remit are matched
# case-insensitively; chapter-mark is the literal tool name.
ANNOUNCE_RE='operating as'
REMIT_RE='remit|crosses into|role boundary'
CHAPTER_RE='mark_chapter'

since=""
project=""
json=0
dirs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)   since="${2:-}"; shift 2 ;;
    --project) project="${2:-}"; shift 2 ;;
    --json)    json=1; shift ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do dirs+=("$1"); shift; done ;;
    *)  dirs+=("$1"); shift ;;
  esac
done

# Resolve scan roots.
if [[ ${#dirs[@]} -gt 0 ]]; then
  roots=("${dirs[@]}")
elif [[ -n "$project" ]]; then
  roots=("$PROJECTS_DIR/$project")
else
  roots=("$PROJECTS_DIR")
fi

# Optional --since predicate via a reference file (portable across BSD/GNU find:
# -newermt is GNU-only, so we touch a stamp file and use -newer instead).
newer_pred=()
ref=""
if [[ -n "$since" ]]; then
  ref="$(mktemp)"
  stamp="$(printf '%s' "$since" | tr -d '-')0000"   # YYYY-MM-DD -> YYYYMMDD0000
  if touch -t "$stamp" "$ref" 2>/dev/null; then
    newer_pred=(-newer "$ref")
  else
    echo "grounding-readout: warning: could not parse --since '$since'; ignoring" >&2
  fi
fi

# Gather transcript files.
files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find "${roots[@]}" -type f -name '*.jsonl' "${newer_pred[@]+"${newer_pred[@]}"}" -print0 2>/dev/null)

[[ -n "$ref" ]] && rm -f "$ref"

total=0
hit_announce=0
hit_remit=0
hit_chapter=0

for f in "${files[@]+"${files[@]}"}"; do
  total=$((total + 1))
  grep -Eiq -- "$ANNOUNCE_RE" "$f" 2>/dev/null && hit_announce=$((hit_announce + 1))
  grep -Eiq -- "$REMIT_RE"    "$f" 2>/dev/null && hit_remit=$((hit_remit + 1))
  grep -Eq  -- "$CHAPTER_RE"  "$f" 2>/dev/null && hit_chapter=$((hit_chapter + 1))
done

# Integer-percent formatter (awk avoids a bc dependency).
pct() { awk -v n="$1" -v d="$2" 'BEGIN { if (d == 0) print "n/a"; else printf "%.0f%%", (n/d)*100 }'; }

if [[ "$json" -eq 1 ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$total" "$hit_announce" "$hit_remit" "$hit_chapter" "$since" "$BASELINE_NOTE" <<'PY'
import json, sys
total, a, r, c, since, note = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6]
def rate(n):
    return None if total == 0 else round(n / total, 4)
print(json.dumps({
    "sessions": total,
    "since": since or None,
    "baseline_note": note,
    "resolve_announce": {"count": a, "rate": rate(a)},
    "remit_crossing":   {"count": r, "rate": rate(r)},
    "chapter_mark":     {"count": c, "rate": rate(c)},
}, indent=2))
PY
  else
    # Fallback if python3 is unavailable: emit minimal JSON by hand.
    printf '{"sessions":%s,"resolve_announce":%s,"remit_crossing":%s,"chapter_mark":%s}\n' \
      "$total" "$hit_announce" "$hit_remit" "$hit_chapter"
  fi
  exit 0
fi

echo "Grounding readout (issue #62)"
[[ -n "$since" ]] && echo "  window: transcripts modified on/after $since"
echo "  scanned: $total session transcript(s)"
echo "  $BASELINE_NOTE"
echo
printf '  %-22s %6s   %s\n' "signal" "count" "rate"
printf '  %-22s %6s   %s\n' "----------------------" "-----" "----"
printf '  %-22s %6s   %s\n' "resolve+announce" "$hit_announce" "$(pct "$hit_announce" "$total")"
printf '  %-22s %6s   %s\n' "remit-crossing flag" "$hit_remit" "$(pct "$hit_remit" "$total")"
printf '  %-22s %6s   %s\n' "chapter-mark" "$hit_chapter" "$(pct "$hit_chapter" "$total")"
