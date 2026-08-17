#!/usr/bin/env bash
# Static assertion that CACHE_KEY_INPUT_CLASSES (scripts/run-behavioural-eval.py)
# and compute_cache_key's own source agree about which file-tree input classes
# participate in the nightly eval's cache key.
#
# Run:  bash scripts/cache-key-completeness-check.sh [--root <dir>]
# Exit: 0 clean, 1 findings, 2 usage/environment error.
#
# WHY THIS EXISTS (R4, R7)
# ------------------------
# CACHE_KEY_INPUT_CLASSES is documented, in run-behavioural-eval.py itself, as
# treated-exhaustive BY DESIGN: adding a new input that could move a leg's
# result is a required edit to that constant, not an optional enhancement, so
# a cache hit never masks an actual change (R4). A documentation comment
# saying so is exactly the enforcement mechanism this repo's own CLAUDE.md
# warns against -- "a paragraph is the weakest enforcement mechanism that
# exists" is the whole argument skills-lint.sh's header makes about the
# ../../shared/ convention, and the same failure mode applies here: nothing
# stops CACHE_KEY_INPUT_CLASSES and compute_cache_key's actual body from
# drifting apart the same way.
#
# This is that enforcement, parallel to skills-lint.sh check 4 (a skill's
# frontmatter `version:` must move when its content does) -- a static ratchet
# against ONE known drift, not a general "did anything change" scanner.
#
# WHAT THIS DOES NOT DO
# ----------------------
# This is NOT a git-diff scan. skills-lint.sh check 4 answers "did the skill's
# content change since <base> without a version bump" -- an inherently
# diff-aware question. This check answers a different, base-independent
# question: "does compute_cache_key's CURRENT source actually cover every
# class CACHE_KEY_INPUT_CLASSES currently claims, and vice versa." It runs
# clean against a single tree with no --base needed.
#
# Nor is this a general "which files can move this leg's result" detector --
# KTD2 settled that such a detector is unimplementable in general. What is
# checkable, and what this checks, is narrower and mechanical: does the
# enumerated list and the function's own source AGREE. Discovering a wholly
# new sensitive input class nobody has enumerated yet is explicitly out of
# scope -- that still depends on a human noticing during review.
#
# HOW "does the code cover the class" IS VERIFIED
# ------------------------------------------------
# Each class name is not itself executable, so this hand-maintains a small,
# explicit mapping (see _class_markers below) from each CURRENT
# CACHE_KEY_INPUT_CLASSES entry to (a) a source-text marker proving
# compute_cache_key's body actually reads that input, and (b) the
# `components` dict key that input's hash lands under. Two checks fall out:
#
#   check 1 (enumeration -> code)   every enumerated class has both markers
#                                    present in compute_cache_key's body
#   check 2 (code -> enumeration)   every components dict key is either
#                                    mapped from an enumerated class, or is
#                                    one of the three runtime values the
#                                    module docstring explicitly excludes
#                                    from CACHE_KEY_INPUT_CLASSES on purpose
#                                    (runs, model, cli_version) plus `fixture`
#                                    (the case's own fixture path, likewise
#                                    excluded by design, not a file-tree glob)
#
# Check 2 is what catches a new hashed input added to the function without a
# matching enumeration entry: an unrecognised dict key has nowhere to map
# from, and is a finding regardless of whether it happens to be spelled like
# a file-tree glob.
#
# WHY BOTH DIRECTIONS ARE SEPARATE CHECKS
# -----------------------------------------
# So each can be proven load-bearing independently (see the mutation suite,
# cache-key-completeness-check.test.sh): a class named but not referenced in
# code must trip check 1 and ONLY check 1; an unenumerated dict key added to
# the function must trip check 2 and ONLY check 2. If either direction were
# folded into the other, a defect in one could hide behind a coincidental
# finding from the other, and the mutation suite's isolation assertion is
# what would catch that regression, not eyeballing the output.
#
# ON THE SKIP FLAG
# -----------------
# CACHE_KEY_CHECK_SKIP exists for the mutation suite, same role as
# SKILLS_LINT_SKIP in skills-lint.sh: it proves each check is load-bearing by
# disabling it and asserting the seeded defect goes unreported. Not a
# documented user-facing knob -- the way to clear a finding is to fix the
# drift it names.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CACHE_KEY_CHECK_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SKIP="${CACHE_KEY_CHECK_SKIP:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 || { echo "--root needs a directory" >&2; exit 2; } ;;
    --help|-h) sed -n '2,6p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "not a directory: $ROOT" >&2; exit 2; }
TARGET="$ROOT/scripts/run-behavioural-eval.py"
[ -f "$TARGET" ] || { echo "not found: $TARGET" >&2; exit 2; }

# shellcheck source=lib/check-common.sh
source "$SCRIPT_DIR/lib/check-common.sh"

# ---------------------------------------------------------------------------
# Extraction: the two source-of-truth blocks, read from the target file as
# plain text. This is intentionally NOT a Python parse -- a regex-based read
# of the exact shapes the real code uses (a module-level tuple literal, a
# `components = { ... }` dict literal) is enough to catch the drift this
# check exists for, and staying out of Python keeps this check runnable with
# nothing but bash, matching the rest of scripts/*.sh.
# ---------------------------------------------------------------------------

# The CACHE_KEY_INPUT_CLASSES tuple body, one quoted string per line.
_enum_classes() {
  awk '/^CACHE_KEY_INPUT_CLASSES = \(/{f=1} f{print} f&&/^\)$/{exit}' "$TARGET" \
    | grep -oE '"[^"]+"' | tr -d '"'
}

# compute_cache_key's full source, from its `def` line up to (not including)
# the next top-level `def `. Indented lines never match `^def `, so a nested
# helper cannot end the capture early -- only another top-level function can.
_fn_body() {
  awk '
    /^def compute_cache_key\(/ { f=1 }
    f && /^def / && !/^def compute_cache_key\(/ { exit }
    f { print }
  ' "$TARGET"
}

# The keys of the `components = { ... }` dict literal inside compute_cache_key.
_components_keys() {
  _fn_body | awk '/components = \{/{f=1;next} f&&/^    \}$/{exit} f{print}' \
    | grep -oE '"[A-Za-z_]+"' | tr -d '"'
}

# ---------------------------------------------------------------------------
# The mapping. Each CACHE_KEY_INPUT_CLASSES entry that has ever existed in
# this file gets one case here: a source-text marker proving
# compute_cache_key actually reads that input, and the components dict key
# its hash lands under. A class with no case here is itself a finding (see
# check 1) rather than silently passing -- the mapping is meant to track the
# enumeration, not the other way around.
# ---------------------------------------------------------------------------
_class_markers() {  # $1 = class string; sets MARKER_CALL, MARKER_KEY; 1 if unknown
  case "$1" in
    "skills/**")
      MARKER_CALL='skill_declared_version\('
      MARKER_KEY='skill_versions'
      ;;
    "skills/shared/**")
      MARKER_CALL='discover_shared_references\('
      MARKER_KEY='shared_refs'
      ;;
    "commands/**")
      MARKER_CALL='commands_paths = sorted\(\(repo / "commands"\)\.glob'
      MARKER_KEY='commands'
      ;;
    "agents/**")
      MARKER_CALL='agents_paths = sorted\(\(repo / "agents"\)\.glob'
      MARKER_KEY='agents'
      ;;
    "evals/cases/**")
      MARKER_CALL='json\.dumps\(case,'
      MARKER_KEY='case'
      ;;
    "evals/stub/**")
      MARKER_CALL='stub_path = stub_path or STUB'
      MARKER_KEY='stub'
      ;;
    "scripts/run-behavioural-eval.py")
      MARKER_CALL='runner_path = runner_path or Path\(__file__\)\.resolve\(\)'
      MARKER_KEY='runner'
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

# Components dict keys that are deliberately NOT file-tree classes -- the
# module docstring in run-behavioural-eval.py names these explicitly as
# excluded from CACHE_KEY_INPUT_CLASSES on purpose: `runs`/`model`/
# `cli_version` are runtime values, and `fixture` is a per-case path rather
# than a static input class. check 2 must not flag them as unenumerated.
_is_exempt_key() {
  case "$1" in
    fixture | runs | model | cli_version) return 0 ;;
    *) return 1 ;;
  esac
}

_known_component_keys_from_enum() {
  local class
  while IFS= read -r class; do
    [ -n "$class" ] || continue
    _class_markers "$class" || continue
    printf '%s\n' "$MARKER_KEY"
  done < <(_enum_classes)
}

ENUM_CLASSES="$(_enum_classes)"
[ -n "$ENUM_CLASSES" ] \
  || { echo "no CACHE_KEY_INPUT_CLASSES tuple found in $TARGET -- nothing to measure" >&2; exit 2; }
FN_BODY="$(_fn_body)"
[ -n "$FN_BODY" ] \
  || { echo "no compute_cache_key function found in $TARGET -- nothing to measure" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Check 1 -- every enumerated class is actually referenced by the code.
# ---------------------------------------------------------------------------
check_enum_to_code() {
  skipped 1 && return 0
  local class components_keys
  components_keys="$(_components_keys)"
  while IFS= read -r class; do
    [ -n "$class" ] || continue
    if ! _class_markers "$class"; then
      finding 1 "$TARGET" \
        "CACHE_KEY_INPUT_CLASSES names '$class' but this checker has no known verification marker for it -- add one to scripts/cache-key-completeness-check.sh's _class_markers()"
      continue
    fi
    printf '%s\n' "$FN_BODY" | grep -qE "$MARKER_CALL" \
      || finding 1 "$TARGET" \
        "CACHE_KEY_INPUT_CLASSES names '$class' but compute_cache_key's source does not reference it"
    printf '%s\n' "$components_keys" | grep -qxF "$MARKER_KEY" \
      || finding 1 "$TARGET" \
        "CACHE_KEY_INPUT_CLASSES names '$class' but compute_cache_key's components dict has no '$MARKER_KEY' entry"
  done <<< "$ENUM_CLASSES"
}

# ---------------------------------------------------------------------------
# Check 2 -- every hashed component the code produces is accounted for by
# the enumeration (or is one of the three declared-exempt runtime values).
# ---------------------------------------------------------------------------
check_code_to_enum() {
  skipped 2 && return 0
  local key known
  known="$(_known_component_keys_from_enum)"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    _is_exempt_key "$key" && continue
    printf '%s\n' "$known" | grep -qxF "$key" \
      || finding 2 "$TARGET" \
        "compute_cache_key's components dict hashes '$key' but no class in CACHE_KEY_INPUT_CLASSES accounts for it"
  done < <(_components_keys)
}

check_enum_to_code
check_code_to_enum

check_common_summarize "cache-key-completeness-check"
