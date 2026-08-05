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
#                      never a hard-coded copy of the directive text -- and
#                      counted ONLY from hook-output records. Reading the hook
#                      source, or quoting the directive, is not receiving it
#                      (issue #149); the bare text match this replaces is the
#                      same mistake that produced the false 2.2% in #122.
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
# project slugs, worktrees included, are held out of every headline figure by
# default. Pass --include-self to fold them into the main figures.
#
# They are NOT discarded. They are scanned and reported on their own line
# (issue #149). Dropping them made this instrument blind exactly where the
# treatment was observable: after the 2026-08-03 delivery fix every session
# that received the directive was in this repo, so the readout reported 0
# announcements where the transcripts showed 2 -- a silent zero, which is the
# failure mode this instrument exists to end. Read that line as corroboration,
# never as the experiment's result: those sessions work on the directive.
#
# HONEST BY CONSTRUCTION: this counts only what the model literally emitted in
# transcripts. It infers nothing and claims no grounding beyond the text found.
# It remains a proxy -- an assistant that verbatim-quotes a documentation
# example still scores. The structured session log (#71) is the durable
# higher-fidelity successor.
#
# Usage:
#   scripts/grounding-readout.sh [--since YYYY-MM-DD] [--since-start WHEN]
#                                [--project <slug>] [--json] [--include-self]
#                                [--hook PATH] [DIR ...]
#   --since        only count transcripts MODIFIED on/after this date
#   --since-start  only count sessions that STARTED on/after this instant
#                  (YYYY-MM-DD or YYYY-MM-DDTHH:MM, local unless offset given).
#                  Prefer this for "did the directive fire after <fix>?": mtime
#                  misfiles any session that began before the cutoff and was
#                  appended to afterwards -- five of them in the 2026-08-03
#                  window. Sessions with an unreadable start time are dropped,
#                  never guessed into the window.
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
since_start=""
project=""
json=0
include_self=0
dirs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)        since="${2:-}"; shift 2 ;;
    --since-start)  since_start="${2:-}"; shift 2 ;;
    --project)      project="${2:-}"; shift 2 ;;
    --json)         json=1; shift ;;
    --include-self) include_self=1; shift ;;
    --hook)         HOOK_SOURCE="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
self_files=()
subagent_files=()
subagent_excluded=0
self_excluded=0
while IFS= read -r -d '' f; do
  case "$f" in
    # Kept, not merely counted, so the reported exclusion figure can be
    # narrowed to the window like every other number in the report.
    */subagents/*) subagent_excluded=$((subagent_excluded + 1)); subagent_files+=("$f"); continue ;;
  esac
  if [[ -n "$self_slug" ]]; then
    parent="$(basename "$(dirname "$f")")"
    if [[ "$parent" == "$self_slug" || "$parent" == "$self_slug-"* ]]; then
      # Held back from the headline denominator, but KEPT and scanned so they
      # can be reported on their own line (issue #149). Dropping them outright
      # made the instrument blind exactly where the treatment was observable:
      # after the 2026-08-03 delivery fix every session that received the
      # directive was in this repo, so the readout reported 0 announcements
      # where the transcripts showed 2. A silent zero is the failure mode this
      # instrument exists to end -- it must not produce one itself.
      self_excluded=$((self_excluded + 1)); self_files+=("$f"); continue
    fi
  fi
  files+=("$f")
done < <(find "${roots[@]}" -type f -name '*.jsonl' "${newer_pred[@]+"${newer_pred[@]}"}" -print0 2>/dev/null)

[[ -n "$ref" ]] && rm -f "$ref"

# Hand the file list to the scanner via a NUL-separated list file, so paths
# with spaces or newlines survive and stdin stays free for the script heredoc.
list="$(mktemp)"
self_list="$(mktemp)"
sub_list="$(mktemp)"
trap 'rm -f "$list" "$self_list" "$sub_list"' EXIT
if [[ ${#files[@]} -gt 0 ]]; then
  printf '%s\0' "${files[@]}" > "$list"
fi
if [[ ${#self_files[@]} -gt 0 ]]; then
  printf '%s\0' "${self_files[@]}" > "$self_list"
fi
if [[ ${#subagent_files[@]} -gt 0 ]]; then
  printf '%s\0' "${subagent_files[@]}" > "$sub_list"
fi

python3 - "$list" "$HOOK_SOURCE" "$since" "$subagent_excluded" "$self_excluded" "$json" "$BASELINE_NOTE" "$self_list" "$since_start" "$sub_list" <<'PY'
import datetime as _dt
import json as _json
import os
import re
import sys

list_path, hook_path, since, sub_excl, self_excl, want_json, baseline = sys.argv[1:8]
self_list_path = sys.argv[8] if len(sys.argv) > 8 else ""
since_start = sys.argv[9] if len(sys.argv) > 9 else ""
sub_list_path = sys.argv[10] if len(sys.argv) > 10 else ""
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

# The version the hook stamps into every payload it emits -- both the directive
# ("_Directive emitted by holacracy-claude-plugin vX.Y.Z._") and the quiet
# marker. Counted ONLY from hook records, for the same reason every other
# signal here is provenance-scoped: a session that reads the hook source or
# quotes a release note must not be reported as having run that version.
#
# This is the first consumer of that stamp. It exists because #122's root cause
# -- a v0.6.0 copy loading while 0.10.2 was recorded as installed -- was
# invisible in the data and took archaeology across three install channels to
# find. With this line, a stale deployment is a glance at the readout.
#
# Anchored to a semver core so the trailing "._" of the markdown italics stops
# the match cleanly; "unknown" is what the hook emits when version.txt is
# unreadable, and must be reported rather than dropped.
VERSION_RE = re.compile(
    r"holacracy-claude-plugin v(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?|unknown)")

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


def is_hook_record(rec):
    """True if this record is hook OUTPUT, the only honest evidence that the
    directive was actually injected.

    Before this check, `directive-fired` was a text match on any line, so a
    session that merely READ hooks-handlers/session-start.sh, or quoted the
    directive in a prompt, scored as having received it -- the identical
    mistake that produced the false 2.2% in #122 and that #123 repaired for
    the announce signal but not for this one. Slug self-exclusion hid it,
    because the sessions most likely to read the hook source are this repo's
    own; surfacing the in-repo cohort (#149) made it visible.
    """
    if rec.get("type") != "attachment":
        return False
    att = rec.get("attachment")
    if isinstance(att, dict):
        return att.get("type") == "hook_success"
    # Flat shape used by the fixtures and by older transcript versions.
    return "stdout" in rec or "hookName" in rec


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
    version = None
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return fired, announce, remit, chapter, version
    with fh:
        for line in fh:
            if not line.strip():
                continue
            try:
                rec = _json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue

            # Scoped to hook-output records: reading the hook source is not
            # the same as receiving its output. See is_hook_record().
            if is_hook_record(rec):
                if not fired and has_marker(line):
                    fired = True
                # Checked on EVERY hook record, not only the one carrying the
                # directive: a session the hook stayed quiet in still emits the
                # quiet marker, and that marker's version is exactly the
                # evidence that distinguishes "ran and had nothing to say" from
                # "never ran". Dropping it would reintroduce the blind spot.
                if version is None:
                    m = VERSION_RE.search(line)
                    if m:
                        version = m.group(1)

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
            if fired and announce and remit and chapter and version is not None:
                break
    return fired, announce, remit, chapter, version


# --- Run -------------------------------------------------------------------

# How far into a transcript to look for the session's start time. Bounded so a
# huge transcript is not read end-to-end just to date it, but far enough past
# the leading metadata records that carry no timestamp.
_START_SCAN_LIMIT = 50


def _session_start(path):
    """Timestamp of the first record that CARRIES one, i.e. when the session
    began. Returns None if no dated record is found in the opening records.

    Scans forward rather than reading only record #1. Claude Code transcripts
    routinely open with a summary or meta record that has no `timestamp`, and
    giving up on it dropped the whole session from every windowed run --
    silently, because a dropped session is simply absent from the denominator.

    Measured on 2026-08-04: a 2-hour window holding seven sessions reported
    ONE. The six it dropped were exactly the sessions carrying the v0.12.0
    stamp that proved a delivery fix had landed, so the readout showed
    `plugin versions seen: no version stamp` while the fix was working. That is
    the #122 failure shape in the instrument rather than the hook: absence of
    evidence rendered as evidence of absence.

    A malformed line is skipped rather than fatal, for the same reason -- one
    unparseable record must not disqualify a session from being counted.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh):
                if i >= _START_SCAN_LIMIT:
                    break
                if not line.strip():
                    continue
                try:
                    ts = _json.loads(line).get("timestamp")
                except ValueError:
                    continue
                if not ts:
                    continue
                try:
                    return _dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
                except (TypeError, ValueError):
                    continue
    except OSError:
        return None
    return None


def _parse_cutoff(text):
    """Accept YYYY-MM-DD or YYYY-MM-DDTHH:MM[:SS][+ZZ:ZZ]. Naive values are
    read as LOCAL time, matching how an operator states a wall-clock cutoff."""
    try:
        d = _dt.datetime.fromisoformat(text)
    except ValueError:
        die("cannot parse --since-start %r; expected YYYY-MM-DD or "
            "YYYY-MM-DDTHH:MM" % text)
    if d.tzinfo is None:
        d = d.astimezone()
    return d


CUTOFF = _parse_cutoff(since_start) if since_start else None


def read_list(path):
    if not path or not os.path.isfile(path):
        return []
    with open(path, "rb") as fh:
        raw = fh.read()
    paths = [p.decode("utf-8", "replace") for p in raw.split(b"\0") if p]
    if CUTOFF is None:
        return paths
    # Bucket by when the session STARTED, not by file mtime. --since uses
    # find -newer, which misfiles any session that began before the cutoff and
    # was merely appended to afterwards -- five of them in the 2026-08-03
    # window. Sessions whose start time cannot be read are dropped rather than
    # guessed at: an unknown start must not silently land in the window.
    kept = []
    for p in paths:
        st = _session_start(p)
        if st is not None and st >= CUTOFF:
            kept.append(p)
    return kept


def tally(paths):
    """Scan a set of transcripts and return the counts for one cohort.

    Signal counts restricted to sessions that actually got the treatment are
    tracked separately: the "of directive-fired" column must be
    compliance-among-treated, not a global count over a smaller denominator --
    that produces rates above 100%.
    """
    t = dict(total=len(paths), fired=0, announce=0, remit=0, chapter=0,
             f_announce=0, f_remit=0, f_chapter=0,
             versions={}, no_version=0)
    for p in paths:
        fired, announce, remit, chapter, version = scan(p)
        t["fired"] += fired
        t["announce"] += announce
        t["remit"] += remit
        t["chapter"] += chapter
        if fired:
            t["f_announce"] += announce
            t["f_remit"] += remit
            t["f_chapter"] += chapter
        if version is None:
            # Counted, never omitted. A session whose loaded version cannot be
            # determined is the #122 condition itself -- v0.6.0 predated the
            # stamp and so emitted nothing at all. Silence here must read as
            # "unknown", not as "fine".
            t["no_version"] += 1
        else:
            t["versions"][version] = t["versions"].get(version, 0) + 1
    return t


def versions_line(t):
    """One-line human summary of which plugin versions actually ran."""
    parts = ["%s (%d)" % (v, n)
             for v, n in sorted(t["versions"].items(), reverse=True)]
    if t["no_version"]:
        parts.append("no version stamp (%d)" % t["no_version"])
    return ", ".join(parts) if parts else "none"


paths = read_list(list_path)
main = tally(paths)

# This repo's own sessions are held out of the headline denominator but still
# scanned and reported (issue #149). They are NOT contaminated by construction:
# the scanner already counts only assistant-emitted text, skips sidechain
# records, and skips assistant text that echoes the directive marker -- those
# provenance defenses, not the slug filter, are what stop a session from
# scoring itself. Reporting them separately keeps the cross-repo headline
# clean while making the in-repo evidence visible instead of silently zero.
self_paths = read_list(self_list_path)
selfies = tally(self_paths)

# Narrow the reported exclusions to the window, like every other figure here.
# They were counted while gathering files, BEFORE --since-start was applied, so
# a 2-hour report could announce "excluded: 705 subagent file(s), 27 self
# session(s)" when the window held none of them -- numbers that invite exactly
# the misreading they caused on 2026-08-04, where "27 self sessions excluded"
# was taken as "27 in-repo sessions we are not showing you" and the true
# windowed figure was zero.
sub_excl = len(read_list(sub_list_path))
self_excl = len(self_paths)

total = main["total"]
n_fired, n_announce = main["fired"], main["announce"]
n_remit, n_chapter = main["remit"], main["chapter"]
f_announce, f_remit = main["f_announce"], main["f_remit"]
f_chapter = main["f_chapter"]


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
        # Which plugin version actually ran, per session, read from the stamp
        # the hook writes into every payload. `sessions_without_plugin_version`
        # is the count that matters most: a copy old enough to predate the
        # stamp emits nothing, which is precisely the #122 failure.
        "plugin_versions_seen": main["versions"],
        "sessions_without_plugin_version": main["no_version"],
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
        # Held out of every figure above. Present so an in-repo-only window is
        # visible rather than reported as a bare zero (issue #149).
        "in_repo": {
            "sessions": selfies["total"],
            "directive_fired": selfies["fired"],
            "resolve_announce": selfies["announce"],
            "remit_crossing": selfies["remit"],
            "chapter_mark": selfies["chapter"],
            "resolve_announce_when_directive_fired": selfies["f_announce"],
            "plugin_versions_seen": selfies["versions"],
            "sessions_without_plugin_version": selfies["no_version"],
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
# Which version actually ran. Skew between this and the released version is the
# #122 root cause; naming it here turns that diagnosis into a glance.
out.append("  plugin versions seen: %s" % versions_line(main))
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

# In-repo cohort, reported but never folded into the figures above. Without
# this line a window in which every treated session happened to be in this
# repo reads as a flat zero -- which is what #149 was filed for.
if selfies["total"]:
    out.append("")
    out.append("  in-repo (this plugin's own sessions; excluded from every figure above)")
    out.append("    %d session(s), directive fired in %d"
               % (selfies["total"], selfies["fired"]))
    out.append("    resolve+announce %d  (%d of %d when directive fired)"
               % (selfies["announce"], selfies["f_announce"], selfies["fired"]))
    out.append("    remit-crossing %d   chapter-mark %d"
               % (selfies["remit"], selfies["chapter"]))
    out.append("    plugin versions seen: %s" % versions_line(selfies))
    out.append("    Read as corroboration, not as the experiment's result:"
               " these sessions work on the directive itself.")
print("\n".join(out))
PY
exit $?
