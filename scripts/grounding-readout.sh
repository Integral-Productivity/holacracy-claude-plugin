#!/usr/bin/env bash
# scripts/grounding-readout.sh
#
# Check instrument for the role-grounding experiment (issue #62, Track A
# PDCA-1; ADR-0008). Scans Claude Code session transcripts for the grounding
# signals and prints per-signal session counts + rates over a run window,
# against the pre-experiment baseline ("Operating as ..." seen in 0 of 40
# sessions).
#
# WHAT IT COUNTS
#
#   directive-fired  : the session-start hook actually injected the grounding
#                      directive. Detected by a marker DERIVED AT RUNTIME from
#                      hooks-handlers/session-start.sh (see MARKER below) --
#                      never a hard-coded copy of the directive text.
#   resolve+announce : the assistant ITSELF emitted an announcement naming a
#                      real role and circle, in the bold form
#                      "Operating as **<role> of <circle>**".
#   remit-crossing   : the assistant itself named a cross-role remit boundary.
#   chapter-mark     : the session made a mark_chapter tool call.
#
# Announce / remit are counted only from assistant-emitted text. Transcript
# content the session merely *read* (file reads, tool results, the injected
# directive itself, user messages) never scores. This is the repair for issue
# #123: the previous version grepped whole files for the bare phrase
# "operating as", which matched the directive's own example text, the plugin's
# own documentation being read, and ordinary English -- 23 hits in the
# 2026-07-20 window, all 23 false positives.
#
# DELIVERY VS BEHAVIOR. The headline number the Act decision needs is
# announce / directive-fired, not announce / all-sessions. A directive that
# never fires produces a zero rate that says nothing about behavior. Both
# denominators are reported.
#
# MARKER DERIVATION. The directive text lives in hooks-handlers/session-start.sh
# and is owned by a separate effort (#122) that may reword it. Copying a
# literal from it here would break silently -- the same fail-silent class of
# bug this instrument exists to detect. So the marker is read out of the hook
# source at run time: the first non-empty line of the `DIRECTIVE` heredoc
# (today: "**Holacracy plugin: role-grounding directive**"). If the heredoc or
# a usable marker cannot be found, this script FAILS LOUDLY (exit 2) rather
# than reporting a zero it cannot justify. Same principle as ADR-0007: derive
# from live source, never a hard-coded table.
#
#   Known limit: the marker is derived from the CURRENT hook source, so
#   re-running over a window recorded before a reword will under-count
#   directive-fired. Compare windows only within one directive revision.
#
# SELF-EXCLUSION. Sessions working on this plugin see the directive text, the
# docs, and this script, and would score themselves -- including the weekly
# `grounding-pdca1-readout` scheduled task, which writes every search pattern
# into its own transcript on every run (issue #123 defect 3). This repo's own
# project slugs, worktrees included, are excluded by default. Pass
# --include-self to count them.
#
# HONEST BY CONSTRUCTION: this counts only what the model literally emitted in
# transcripts. It infers nothing and claims no grounding beyond the text found.
# It remains a proxy -- an assistant that verbatim-quotes a documentation
# example still scores. The structured session log (#71) is the durable
# higher-fidelity successor.
#
# Usage:
#   scripts/grounding-readout.sh [--since YYYY-MM-DD] [--project <slug>]
#                                [--json] [--include-self] [--hook PATH]
#                                [DIR ...]
#   --since        only count transcripts modified on/after this date
#   --project      restrict to $CLAUDE_PROJECTS_DIR/<slug>
#   --json         emit machine-readable JSON instead of the table
#   --include-self include this repo's own sessions (off by default)
#   --hook PATH    read the directive from PATH instead of the plugin's hook
#   DIR ...        scan these dirs instead of the default projects dir
#
# Env:
#   CLAUDE_PROJECTS_DIR   transcript root (default: ~/.claude/projects)
#   HOLACRACY_HOOK_SOURCE directive source (default: the plugin's hook)

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"

PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
HOOK_SOURCE="${HOLACRACY_HOOK_SOURCE:-$REPO_ROOT/hooks-handlers/session-start.sh}"
BASELINE_NOTE="baseline: 0 of 40 pre-experiment sessions had 'Operating as ...'"

since=""
project=""
json=0
include_self=0
dirs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)        since="${2:-}"; shift 2 ;;
    --project)      project="${2:-}"; shift 2 ;;
    --json)         json=1; shift ;;
    --include-self) include_self=1; shift ;;
    --hook)         HOOK_SOURCE="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,75p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do dirs+=("$1"); shift; done ;;
    *)  dirs+=("$1"); shift ;;
  esac
done

# python3 is required: the scan parses JSONL to tell assistant-emitted text
# from text the session merely read. There is no grep-only fallback that can
# make that distinction, and a degraded fallback would silently reintroduce
# the very defect this repair removes.
if ! command -v python3 >/dev/null 2>&1; then
  echo "grounding-readout: python3 is required (JSONL parsing); not found on PATH" >&2
  exit 2
fi

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

# This repo's own project slug(s), for self-exclusion. Claude Code names a
# project directory after its cwd with every non-alphanumeric character
# replaced by '-', so /Users/me/GitHub/holacracy-claude-plugin becomes
# -Users-me-GitHub-holacracy-claude-plugin and its worktrees extend that with
# '--claude-worktrees-<name>'. Derive from the MAIN worktree (git-common-dir),
# so running from inside a worktree still excludes the whole family.
self_slug=""
if [[ "$include_self" -eq 0 ]]; then
  common_git="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [[ -n "$common_git" ]]; then
    main_worktree="$(cd "$(dirname "$common_git")" && pwd)"
  else
    main_worktree="$REPO_ROOT"
  fi
  self_slug="$(printf '%s' "$main_worktree" | sed 's/[^A-Za-z0-9]/-/g')"
fi

# Gather transcript files. Subagent transcripts are not sessions: in the
# 2026-07-20 window they were 295 of 513 files, overstating the denominator
# ~2.4x and deflating every rate (issue #123 defect 2).
files=()
subagent_excluded=0
self_excluded=0
while IFS= read -r -d '' f; do
  case "$f" in
    */subagents/*) subagent_excluded=$((subagent_excluded + 1)); continue ;;
  esac
  if [[ -n "$self_slug" ]]; then
    parent="$(basename "$(dirname "$f")")"
    if [[ "$parent" == "$self_slug" || "$parent" == "$self_slug-"* ]]; then
      self_excluded=$((self_excluded + 1)); continue
    fi
  fi
  files+=("$f")
done < <(find "${roots[@]}" -type f -name '*.jsonl' "${newer_pred[@]+"${newer_pred[@]}"}" -print0 2>/dev/null)

[[ -n "$ref" ]] && rm -f "$ref"

# Hand the file list to the scanner via a NUL-separated list file, so paths
# with spaces or newlines survive and stdin stays free for the script heredoc.
list="$(mktemp)"
trap 'rm -f "$list"' EXIT
if [[ ${#files[@]} -gt 0 ]]; then
  printf '%s\0' "${files[@]}" > "$list"
fi

python3 - "$list" "$HOOK_SOURCE" "$since" "$subagent_excluded" "$self_excluded" "$json" "$BASELINE_NOTE" <<'PY'
import json as _json
import os
import re
import sys

list_path, hook_path, since, sub_excl, self_excl, want_json, baseline = sys.argv[1:8]
sub_excl, self_excl, want_json = int(sub_excl), int(self_excl), int(want_json)


def die(msg):
    """Fail loudly. A readout that cannot locate its own marker must not
    report a zero -- a silent zero is indistinguishable from 'nobody
    complied', which is exactly the misreading issue #123 exists to end."""
    sys.stderr.write("grounding-readout: %s\n" % msg)
    sys.exit(2)


# --- Marker derivation (see the header note) -------------------------------

MIN_MARKER_LEN = 20


def derive_marker(path):
    if not os.path.isfile(path):
        die("directive source not found: %s\n"
            "  Pass --hook PATH or set HOLACRACY_HOOK_SOURCE." % path)
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError as exc:
        die("cannot read directive source %s: %s" % (path, exc))

    start = delim = None
    for i, line in enumerate(lines):
        m = re.search(r"<<-?'(DIRECTIVE)'", line)
        if m:
            start, delim = i + 1, m.group(1)
            break
    if start is None:
        die("no quoted `DIRECTIVE` heredoc in %s\n"
            "  The hook's directive block was renamed or removed; this readout\n"
            "  cannot tell whether the directive fired. Update the heredoc name\n"
            "  here and in the hook together." % path)

    body = []
    for line in lines[start:]:
        if line.strip() == delim:
            break
        body.append(line)
    else:
        die("unterminated `DIRECTIVE` heredoc in %s" % path)

    marker = next((s for s in (l.strip() for l in body) if s), "")
    if len(marker) < MIN_MARKER_LEN:
        die("directive marker from %s is too short to be distinctive: %r\n"
            "  Expected the directive's leading header line." % (path, marker))
    return marker


MARKER = derive_marker(hook_path)

# The directive reaches a transcript nested inside JSON (a hook envelope inside
# an attachment record), so the marker may appear raw, escaped once, or escaped
# twice. Check all three rather than assuming plain ASCII survives.
_e1 = _json.dumps(MARKER)[1:-1]
MARKER_FORMS = tuple(dict.fromkeys((MARKER, _e1, _json.dumps(_e1)[1:-1])))


# --- Signal patterns -------------------------------------------------------

# Anchored to the bold announcement form with a real role AND circle, not the
# bare phrase "operating as" anywhere in the file.
ANNOUNCE_RE = re.compile(r"operating as \*\*([^*\n]+?) of ([^*\n]+?)\*\*", re.I)
REMIT_RE = re.compile(r"remit|crosses into|role boundary", re.I)
CHAPTER_RE = re.compile(r"mark_chapter")

# Template metavariables that must never score. These are what the 2026-07-20
# window's only assistant-emitted bold announcements actually were.
PLACEHOLDERS = {
    "role", "circle", "sub-circle", "enclosing circle",
    "role name", "circle name", "rolename", "circlename",
    "x", "y", "z", "foo", "bar",
    "your role", "the role", "some role", "target role",
    "your circle", "the circle", "some circle", "target circle",
}


def is_placeholder(role, circle):
    for part in (role, circle):
        p = part.strip()
        if not p:
            return True
        # <role>, [Circle Name], {circle} -- metavariable brackets of any kind.
        if any(ch in p for ch in "<>[]{}"):
            return True
        if p.lower() in PLACEHOLDERS:
            return True
    return False


def has_marker(text):
    return any(form in text for form in MARKER_FORMS)


def emitted_by_assistant(rec):
    """Return (texts, tool_names) the ASSISTANT produced in this record.

    Handles the real transcript shape (message.content[] blocks) and the flat
    {"type":"assistant","text":...} shape used by the test fixtures. Anything
    the session merely read -- user turns, tool results, file reads, the
    injected directive -- is deliberately not here.
    """
    texts, tools = [], []
    rtype = rec.get("type")

    # Sidechain records are subagent turns inlined into a parent transcript;
    # same reason */subagents/* files are excluded from the denominator.
    if rec.get("isSidechain") is True:
        return texts, tools

    if rtype == "tool_use" and isinstance(rec.get("name"), str):
        tools.append(rec["name"])
        return texts, tools

    if rtype != "assistant":
        return texts, tools

    if isinstance(rec.get("text"), str):
        texts.append(rec["text"])

    msg = rec.get("message")
    content = msg.get("content") if isinstance(msg, dict) else None
    if isinstance(content, str):
        texts.append(content)
    elif isinstance(content, list):
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "text" and isinstance(block.get("text"), str):
                texts.append(block["text"])
            elif btype == "tool_use" and isinstance(block.get("name"), str):
                tools.append(block["name"])
    return texts, tools


def scan(path):
    fired = announce = remit = chapter = False
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return fired, announce, remit, chapter
    with fh:
        for line in fh:
            if not line.strip():
                continue
            if not fired and has_marker(line):
                fired = True
            try:
                rec = _json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue

            texts, tools = emitted_by_assistant(rec)

            if not chapter and any(CHAPTER_RE.search(t) for t in tools):
                chapter = True

            for text in texts:
                # An assistant quoting the directive back is echoing the
                # treatment, not grounding itself.
                if has_marker(text):
                    continue
                if not announce:
                    for role, circle in ANNOUNCE_RE.findall(text):
                        if not is_placeholder(role, circle):
                            announce = True
                            break
                if not remit and REMIT_RE.search(text):
                    remit = True
            if fired and announce and remit and chapter:
                break
    return fired, announce, remit, chapter


# --- Run -------------------------------------------------------------------

with open(list_path, "rb") as fh:
    raw = fh.read()
paths = [p.decode("utf-8", "replace") for p in raw.split(b"\0") if p]

total = len(paths)
n_fired = n_announce = n_remit = n_chapter = 0
# Signal counts restricted to sessions that actually got the treatment. The
# "of directive-fired" column must be compliance-among-treated, not a global
# count over a smaller denominator -- that produces rates above 100%.
f_announce = f_remit = f_chapter = 0
for p in paths:
    fired, announce, remit, chapter = scan(p)
    n_fired += fired
    n_announce += announce
    n_remit += remit
    n_chapter += chapter
    if fired:
        f_announce += announce
        f_remit += remit
        f_chapter += chapter


def rate(n, d):
    return None if d == 0 else round(n / d, 4)


def pct(n, d):
    return "n/a" if d == 0 else "%.0f%%" % (n / d * 100)


if want_json:
    print(_json.dumps({
        "sessions": total,
        "since": since or None,
        "baseline_note": baseline,
        "directive_marker": MARKER,
        "directive_marker_source": hook_path,
        "excluded": {"subagent_files": sub_excl, "self_sessions": self_excl},
        "directive_fired": {"count": n_fired, "rate": rate(n_fired, total)},
        "resolve_announce": {
            "count": n_announce,
            "rate_of_sessions": rate(n_announce, total),
            "count_when_directive_fired": f_announce,
            "rate_of_directive_fired": rate(f_announce, n_fired),
        },
        "remit_crossing": {
            "count": n_remit,
            "rate_of_sessions": rate(n_remit, total),
            "count_when_directive_fired": f_remit,
            "rate_of_directive_fired": rate(f_remit, n_fired),
        },
        "chapter_mark": {
            "count": n_chapter,
            "rate_of_sessions": rate(n_chapter, total),
            "count_when_directive_fired": f_chapter,
            "rate_of_directive_fired": rate(f_chapter, n_fired),
        },
    }, indent=2))
    sys.exit(0)

out = []
out.append("Grounding readout (issue #62; instrument repaired per #123)")
if since:
    out.append("  window: transcripts modified on/after %s" % since)
out.append("  directive marker (derived from %s):" % hook_path)
out.append("    %s" % MARKER)
out.append("  scanned: %d session transcript(s)  "
           "[excluded: %d subagent file(s), %d self session(s)]"
           % (total, sub_excl, self_excl))
out.append("  directive fired in: %d session(s)  (%s)"
           % (n_fired, pct(n_fired, total)))
out.append("  %s" % baseline)
out.append("")
out.append("  %-22s %6s   %-13s %s"
           % ("signal", "count", "of sessions", "when directive fired"))
out.append("  %-22s %6s   %-13s %s" % ("-" * 22, "-" * 5, "-" * 11, "-" * 20))
for label, n, f in (("resolve+announce", n_announce, f_announce),
                    ("remit-crossing flag", n_remit, f_remit),
                    ("chapter-mark", n_chapter, f_chapter)):
    out.append("  %-22s %6d   %-13s %d / %d  %s"
               % (label, n, pct(n, total), f, n_fired, pct(f, n_fired)))
print("\n".join(out))
PY
exit $?
