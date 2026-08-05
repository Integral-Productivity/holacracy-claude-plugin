#!/usr/bin/env bash
# Every tracked *.test.sh must actually be invoked by a workflow.
#
# Run:  bash scripts/test-wiring-check.sh [--root <dir>]
# Exit: 0 clean, 1 findings, 2 usage/environment error.
#
# WHY THIS EXISTS
# ---------------
# .github/workflows/scripts-test.yml stated the rule in its own header and
# nothing checked it. An author who adds scripts/foo.test.sh and forgets the
# step gets a green PR and a file that never runs -- indistinguishable, from
# the outside, from real coverage.
#
# That judgement had to be made by hand once already: issue #143 records that a
# test file was deliberately NOT committed in PR #138 because it could not be
# wired up, on the reasoning that "committing an unrun test file would have
# been worse than none: it reads as coverage while providing zero." That was
# the right call and it should not have to be re-derived from memory by every
# author. See issue #186.
#
# WHAT COUNTS AS AN INVOCATION
# ----------------------------
# A `bash <path>` or `./<path>` command on a non-comment line of any tracked
# file under .github/workflows/. Optional `-x`-style flags and a leading `./`
# are accepted, as is an env-assignment prefix (`TZ="$tz" bash ...`), because
# scripts-test.yml already runs one suite that way.
#
# EVERY workflow is scanned, not only scripts-test.yml. The property being
# enforced is "something runs this", and skills-eval.yml legitimately runs
# scripts/run-behavioural-eval.test.sh as well. Scoping to a single file would
# turn a legitimate wiring into a false alarm, and a guard that cries wolf gets
# switched off. The corollary is that a suite wired ONLY into the nightly job
# passes this check while providing no per-PR signal -- this guard measures
# invocation, not tier, and does not claim otherwise.
#
# THE THREE DEFENSES, AND WHY NONE IS DECORATION
# ----------------------------------------------
# verb -- a path MENTIONED is not a path that runs. It has to be the argument of
#   a command. Not hypothetical: scripts-test.yml names
#   scripts/grounding-readout.test.sh several times while explaining why that
#   suite matters, and every step in it carries a `- name:` describing the file
#   it runs. A whole-file grep would report those files as wired with their
#   `run:` lines deleted -- scoring green on exactly the defect this guard
#   exists to catch. It is the same whole-file-grep mistake CLAUDE.md documents
#   for the grounding readout: 10 files reported against a true 3.
# comments -- a COMMENTED-OUT step is not a step. `# run: bash x.test.sh` is
#   the shape of a suite someone disabled while debugging and never restored,
#   and it satisfies the verb defense perfectly well.
# boundary -- `bash scripts/foo.test.sh.disabled` does not wire
#   scripts/foo.test.sh. A prefix match would call a renamed-out suite wired.
#
# WHAT THIS DELIBERATELY DOES NOT CHECK
# -------------------------------------
# The reverse direction -- a step invoking a *.test.sh that does not exist --
# needs no guard, because bash exits 127 and the job goes red on the spot. A
# check for it would be dead weight, and dead weight is what the mutation
# contract in docs/adr/0012-* exists to keep out.
#
# ON THE SKIP FLAG
# ----------------
# TEST_WIRING_SKIP disables a named defense (wiring, verb, comments, boundary)
# for the mutation harness in test-wiring-check.test.sh, which proves each is
# load-bearing by turning it off and asserting the seeded defect goes green.
# Same role as SKILLS_LINT_SKIP in skills-lint.sh, and equally not a
# user-facing knob: the way to clear a finding is to add the step.

set -uo pipefail

ROOT="${TEST_WIRING_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SKIP="${TEST_WIRING_SKIP:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 || { echo "--root needs a directory" >&2; exit 2; } ;;
    --help|-h) sed -n '2,5p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "$ROOT" ] || { echo "not a directory: $ROOT" >&2; exit 2; }

FINDINGS=0
finding() {  # $1 = defense id, $2 = file, $3 = message
  printf '%s  %s: %s\n' "[$1]" "$2" "$3"
  FINDINGS=$((FINDINGS + 1))
}
skipped() { case ",$SKIP," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# Escape the ERE metacharacters that can occur in a path. Over-escaping is
# safe here (a stray backslash yields a false finding, never a false pass).
_esc() { printf '%s' "$1" | sed 's/[.[\*^$+?(){}|]/\\&/g'; }

# The haystack is padded with a leading and trailing space on every line (see
# below), so the pattern can use plain [[:space:]] at both ends instead of
# `(^|[[:space:]])` and `([[:space:]]|$)`. Anchors inside an alternation group
# are the one corner of ERE where BSD and GNU grep have historically differed,
# and this repo runs on a BSD laptop and a GNU runner -- see the
# feedback-verify-under-both-bsd-and-gnu note. Padding sidesteps the question.
_pattern() {  # $1 = escaped path -> the ERE that recognises an invocation
  local verb='((ba)?sh([[:space:]]+-[^[:space:]]+)*[[:space:]]+(\./)?|\./)'
  local tail='[[:space:]]'
  skipped verb && verb='(\./)?'
  skipped boundary && tail=''
  printf '[[:space:]]%s%s%s' "$verb" "$1" "$tail"
}

# ---------------------------------------------------------------------------
# The two corpora. Both are read from git rather than the filesystem: an
# untracked scratch file is not shipped coverage and must not raise a finding,
# and an untracked workflow cannot run.
# ---------------------------------------------------------------------------
TESTS="$(git -C "$ROOT" ls-files '*.test.sh' 2>/dev/null)" \
  || { echo "cannot read tracked files in $ROOT (not a git repository?)" >&2; exit 2; }

# "Nothing to measure" is an error, not a pass. Reporting health from absent
# evidence is the failure mode #122 documents, and a silently-empty corpus --
# a broken pathspec, a checkout with no workflows -- would otherwise render
# this guard permanently, invisibly green.
[ -n "$TESTS" ] \
  || { echo "no tracked *.test.sh under $ROOT -- nothing to measure" >&2; exit 2; }

WORKFLOWS="$(git -C "$ROOT" ls-files '.github/workflows/*' 2>/dev/null)"
[ -n "$WORKFLOWS" ] \
  || { echo "no tracked .github/workflows/ files in $ROOT -- nothing to measure" >&2; exit 2; }

HAYSTACK="$(
  while IFS= read -r wf; do
    # Two guards, not `A && B || continue` -- that shape is not if-then-else
    # and shellcheck 0.9.0 on the runner is right to say so (SC2015).
    [ -n "$wf" ] || continue
    [ -f "$ROOT/$wf" ] || continue
    if skipped comments; then
      cat "$ROOT/$wf"
    else
      grep -v '^[[:space:]]*#' "$ROOT/$wf"
    fi
  done <<EOF
$WORKFLOWS
EOF
)"
# Pad both ends of every line so the pattern needs no ^ or $ anchors.
HAYSTACK="$(printf '%s\n' "$HAYSTACK" | sed 's/^/ /; s/$/ /')"

WIRED=0
if ! skipped wiring; then
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if printf '%s\n' "$HAYSTACK" | grep -qE "$(_pattern "$(_esc "$t")")"; then
      WIRED=$((WIRED + 1))
    else
      finding wiring "$t" \
        "no workflow invokes this suite; add a step to .github/workflows/scripts-test.yml"
    fi
  done <<EOF
$TESTS
EOF
fi

if [ "$FINDINGS" -gt 0 ]; then
  printf '\ntest-wiring: %d unwired suite(s). A committed test file nothing invokes\n' "$FINDINGS"
  printf 'reads as coverage while providing none -- see issue #186.\n'
  exit 1
fi
printf 'test-wiring: clean (%d suite(s) wired)\n' "$WIRED"
