#!/usr/bin/env bash
# Regression tests for scripts/cache-key-completeness-check.sh.
#
# Run: bash scripts/cache-key-completeness-check.test.sh
# No framework — plain asserts. Exits non-zero on first failure.
#
# THE MUTATION PROPERTY (ADR-0012, same contract as skills-lint.test.sh)
# ------------------------------------------------------------------------
# For each check N there is a fixture violating ONLY check N, and the suite
# asserts BOTH directions:
#
#   full check on that fixture              -> FAILS  (the check does its job)
#   check with CACHE_KEY_CHECK_SKIP=N        -> PASSES (nothing else covers it)
#
# The second assertion is the one that matters: without it, a check could be
# dead weight — some other check incidentally catching the same defect — and
# the suite would still be green.
#
# Unlike skills-lint's fixtures, these do NOT need a throwaway git repo: the
# check under test reads one file (scripts/run-behavioural-eval.py) off a
# plain directory via CACHE_KEY_CHECK_ROOT / --root, with no `git ls-files`
# dependency anywhere in it.
#
# A final case asserts the REAL repo's run-behavioural-eval.py is clean, so a
# genuine drift between CACHE_KEY_INPUT_CLASSES and compute_cache_key's own
# body fails here too, not just in the fixtures.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/cache-key-completeness-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
CASES=0

# Portable in-place edit -- see skills-lint.test.sh's sedi() for the full
# rationale (BSD vs GNU `sed -i` disagree on the backup-suffix argument, and a
# no-op sed left a fixture pristine once already, so a no-op here is an error
# rather than a silent pass).
sedi() {  # sedi EXPR FILE
  local expr="$1" f="$2"
  sed "$expr" "$f" > "$f.sedi" || fail "sedi: sed failed on $f"
  if cmp -s "$f" "$f.sedi"; then
    rm -f "$f.sedi"
    fail "sedi: '$expr' changed nothing in $f — the fixture defect was never seeded"
  fi
  mv "$f.sedi" "$f" || fail "sedi: could not replace $f"
}

# A minimal stand-in for run-behavioural-eval.py's cache-key section: the
# real CACHE_KEY_INPUT_CLASSES tuple, and a compute_cache_key body carrying
# every marker the checker looks for. Each case copies this and breaks one
# thing, so a case can only fail for the reason it is named after.
_fixture() {  # $1 = destination dir
  local d="$1"
  mkdir -p "$d/scripts"
  cat > "$d/scripts/run-behavioural-eval.py" <<'EOF'
"""Fixture stand-in for run-behavioural-eval.py's cache-key section."""

STUB = "evals/stub/glassfrog_stub.py"

CACHE_KEY_INPUT_CLASSES = (
    "skills/**",
    "skills/shared/**",
    "evals/cases/**",
    "evals/stub/**",
    "scripts/run-behavioural-eval.py",
)


def skill_declared_version(skill_dir):
    return "1.0.0"


def discover_shared_references(skill_dir, repo):
    return []


def compute_cache_key(case, *, skill_dirs=(), fixture_path, runs, model,
                       cli_version, stub_path=None, runner_path=None, repo=None):
    stub_path = stub_path or STUB
    runner_path = runner_path or Path(__file__).resolve()

    skill_versions = sorted(
        f"{d.name}={skill_declared_version(d)}" for d in skill_dirs)
    shared_paths = sorted({
        p for d in skill_dirs for p in discover_shared_references(d, repo)
    })
    shared_digest = "digest"

    components = {
        "case": _sha256_hex(json.dumps(case, sort_keys=True).encode()),
        "skill_versions": skill_versions,
        "shared_refs": shared_digest,
        "fixture": _sha256_file(fixture_path),
        "runner": _sha256_file(runner_path),
        "runs": runs,
        "model": model,
        "stub": _sha256_file(stub_path),
        "cli_version": cli_version,
    }
    return components


def other_function():
    pass
EOF
}

# Assert: the fixture fails the full check, and passes with check N skipped.
_assert_load_bearing() {  # $1 = check number, $2 = fixture dir, $3 = label
  CACHE_KEY_CHECK_ROOT="$2" bash "$CHECK" >/dev/null 2>&1 \
    && fail "check $1 ($3): check passed but the fixture is broken"
  CACHE_KEY_CHECK_SKIP="$1" CACHE_KEY_CHECK_ROOT="$2" bash "$CHECK" >/dev/null 2>&1 \
    || fail "check $1 ($3): still fails with check $1 skipped — the defect is caught by something else, so check $1 is not load-bearing"
  CASES=$((CASES + 1))
}

# 0. The pristine fixture is clean. If this fails, every case below is
#    meaningless.
_fixture "$TMP/clean"
CACHE_KEY_CHECK_ROOT="$TMP/clean" bash "$CHECK" >/dev/null 2>&1 \
  || { CACHE_KEY_CHECK_ROOT="$TMP/clean" bash "$CHECK"; fail "the pristine fixture is not clean"; }
CASES=$((CASES + 1))

# 1a. Enumeration lists a class the checker (and hence the code) has no
#     marker for: a bogus class appended to CACHE_KEY_INPUT_CLASSES.
_fixture "$TMP/c1a"
sedi 's|"scripts/run-behavioural-eval.py",|"scripts/run-behavioural-eval.py",\n    "nonexistent/**",|' \
  "$TMP/c1a/scripts/run-behavioural-eval.py"
_assert_load_bearing 1 "$TMP/c1a" "enumerated class the checker has no marker for"

# 1b. Enumeration lists a REAL, known class, but the code's handling for it
#     was removed -- the "temporarily remove skills/shared/** handling"
#     mutation named in the unit brief. Both the call and its components-dict
#     entry go, so this is a clean "code doesn't reference it" defect rather
#     than a code-references-something-new one (that is case 2's shape).
_fixture "$TMP/c1b"
sedi '/discover_shared_references(d, repo)/d' "$TMP/c1b/scripts/run-behavioural-eval.py"
sedi '/"shared_refs": shared_digest,/d' "$TMP/c1b/scripts/run-behavioural-eval.py"
_assert_load_bearing 1 "$TMP/c1b" "enumerated class whose code handling was removed"

# 2. Code references something new the enumeration doesn't list: a mutant
#    adds a hashed input to compute_cache_key's components dict with no
#    corresponding CACHE_KEY_INPUT_CLASSES entry.
_fixture "$TMP/c2"
sedi 's|"cli_version": cli_version,|"cli_version": cli_version,\n        "extra_thing": "z",|' \
  "$TMP/c2/scripts/run-behavioural-eval.py"
_assert_load_bearing 2 "$TMP/c2" "unenumerated component hashed by the code"

# 2b. The declared-exempt runtime keys (fixture, runs, model, cli_version)
#     must NOT be flagged by check 2 even though none of them maps to a
#     CACHE_KEY_INPUT_CLASSES entry -- they are excluded from the enumeration
#     by design (module docstring), not an oversight. The clean fixture
#     already carries all four; this asserts check 2 alone (with check 1
#     skipped, since a fresh unmodified fixture trivially passes check 1 too)
#     still reports no findings for them.
CACHE_KEY_CHECK_SKIP=1 CACHE_KEY_CHECK_ROOT="$TMP/clean" bash "$CHECK" >/dev/null 2>&1 \
  || { CACHE_KEY_CHECK_SKIP=1 CACHE_KEY_CHECK_ROOT="$TMP/clean" bash "$CHECK"; fail "check 2 false-positived on a declared-exempt runtime key (fixture/runs/model/cli_version)"; }
CASES=$((CASES + 1))

# 3. Enumeration and implementation in sync -- the real repository's
#    run-behavioural-eval.py -- passes cleanly. Fixtures prove the checks
#    work; this proves they are actually pointed at the real file.
bash "$CHECK" >/dev/null 2>&1 || { bash "$CHECK"; fail "the live run-behavioural-eval.py does not pass its own completeness check"; }
CASES=$((CASES + 1))

# 4. Cross-isolation, stated explicitly rather than left implicit in the
#    _assert_load_bearing calls above: the check-1 mutants must not ALSO trip
#    check 2, and the check-2 mutant must not ALSO trip check 1. Per
#    ADR-0012, a seeded defect failing some check other than the one it
#    targets is exactly the false coverage this suite exists to rule out.
CACHE_KEY_CHECK_SKIP=2 CACHE_KEY_CHECK_ROOT="$TMP/c1a" bash "$CHECK" >/dev/null 2>&1 \
  && fail "isolation: check 1's bogus-class fixture did not fail with check 2 skipped -- check 1 isn't actually catching it"
CACHE_KEY_CHECK_SKIP=2 CACHE_KEY_CHECK_ROOT="$TMP/c1b" bash "$CHECK" >/dev/null 2>&1 \
  && fail "isolation: check 1's removed-handling fixture did not fail with check 2 skipped -- check 1 isn't actually catching it"
CACHE_KEY_CHECK_SKIP=1 CACHE_KEY_CHECK_ROOT="$TMP/c2" bash "$CHECK" >/dev/null 2>&1 \
  && fail "isolation: check 2's extra-component fixture did not fail with check 1 skipped -- check 2 isn't actually catching it"
CASES=$((CASES + 1))

echo "cache-key-completeness-check.test.sh: $CASES cases passed"
