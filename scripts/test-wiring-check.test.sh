#!/usr/bin/env bash
# Regression tests for scripts/test-wiring-check.sh.
#
# Run: bash scripts/test-wiring-check.test.sh
# No framework -- plain asserts. Exits non-zero on first failure.
#
# HERMETIC
# --------
# Every case builds a throwaway git repository under a temp dir and points the
# guard at it with --root. Two places read the live repo on purpose, because a
# guard whose only proof is fixtures drifts away from the thing it guards: the
# tail of section 4 seeds a deleted step into a COPY of this repo (a fixture
# cannot carry the real workflow's real prose), and section 8 runs the guard
# against the repo as it stands.
#
# THE MUTATION PROPERTY
# ---------------------
# For each defense there is a fixture violating ONLY that defense, and the
# suite asserts BOTH directions:
#
#   the guard as shipped        -> FAILS  (the defense does its job)
#   TEST_WIRING_SKIP=<defense>  -> PASSES (nothing else covers it)
#
# The second is the load-bearing half, and the same contract skills-lint.test.sh
# gets from SKILLS_LINT_SKIP: a defense some other defense incidentally covers
# would pass a naive suite while buying nothing.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
CHECK="$HERE/test-wiring-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
CASES=0
pass() { CASES=$((CASES + 1)); }

# ---------------------------------------------------------------------------
# Fixture plumbing. A fixture is a real git repo, because the guard reads its
# corpora with `git ls-files` -- tracked-ness is part of the contract, not an
# implementation detail to be stubbed around.
# ---------------------------------------------------------------------------
new_repo() {  # $1 = name -> prints the path
  local d="$TMP/$1"
  mkdir -p "$d/scripts" "$d/hooks-handlers" "$d/.github/workflows"
  git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  printf '%s' "$d"
}

commit() { git -C "$1" add -A && git -C "$1" commit -qm fixture; }

# The baseline workflow, exercising all four invocation shapes the guard
# accepts -- plain, env-prefixed inside a loop, flagged, and bare `./`.
write_workflow() {  # $1 = repo dir
  cat > "$1/.github/workflows/scripts-test.yml" <<'YML'
name: Scripts tests
# scripts/a.test.sh is named HERE, in prose, as well as run below.
on: [pull_request]
jobs:
  scripts-test:
    runs-on: ubuntu-latest
    steps:
      - name: a
        run: bash scripts/a.test.sh
      - name: b
        run: |
          for tz in UTC America/Los_Angeles; do
            TZ="$tz" bash hooks-handlers/b.test.sh
          done
      - name: c
        run: bash -x ./scripts/c.test.sh
      - name: d
        run: ./scripts/d.test.sh
YML
}

# A repo that should be clean: four tracked suites, four invocations.
baseline() {  # $1 = name -> prints the path
  local d; d="$(new_repo "$1")"
  write_workflow "$d"
  for f in scripts/a.test.sh scripts/c.test.sh scripts/d.test.sh hooks-handlers/b.test.sh; do
    echo '#!/usr/bin/env bash' > "$d/$f"
  done
  commit "$d" >/dev/null
  printf '%s' "$d"
}

run_check() {  # $1 = repo dir, rest = env assignments already applied by caller
  bash "$CHECK" --root "$1" >/dev/null 2>&1
}

assert_clean() {  # $1 = repo dir, $2 = message
  run_check "$1" || { bash "$CHECK" --root "$1"; fail "$2"; }
}

assert_finds() {  # $1 = repo dir, $2 = message
  run_check "$1" && { bash "$CHECK" --root "$1"; fail "$2"; }
}

# The mutation pair: shipped guard must fail, guard with that defense off must
# pass. Both halves, or the defense is not proven load-bearing.
assert_mutation() {  # $1 = repo dir, $2 = defense, $3 = what was seeded
  assert_finds "$1" "the guard did not catch $3"
  TEST_WIRING_SKIP="$2" run_check "$1" \
    || { TEST_WIRING_SKIP="$2" bash "$CHECK" --root "$1"
         fail "$3 still fails with the '$2' defense disabled; that defense is not what caught it"; }
}

# ---------------------------------------------------------------------------
# 1. The baseline is clean, and every accepted invocation shape is accepted.
# ---------------------------------------------------------------------------
BASE="$(baseline base)"
assert_clean "$BASE" "the pristine fixture is not clean"
bash "$CHECK" --root "$BASE" | grep -q "4 suite(s) wired" \
  || { bash "$CHECK" --root "$BASE"; fail "expected all 4 shapes to be recognised as wired"; }
pass

# Each shape on its own, so a regression naming one of them cannot hide behind
# the other three passing.
for shape in "bash scripts/a.test.sh" \
             "TZ=\"\$tz\" bash hooks-handlers/b.test.sh" \
             "bash -x ./scripts/c.test.sh" \
             "./scripts/d.test.sh"; do
  d="$(new_repo "shape-$(echo "$shape" | tr -cd '[:lower:]')")"
  path="$(echo "$shape" | tr ' ' '\n' | grep 'test\.sh$' | sed 's#^\./##')"
  mkdir -p "$d/$(dirname "$path")"
  echo '#!/usr/bin/env bash' > "$d/$path"
  printf 'jobs:\n  x:\n    steps:\n      - run: %s\n' "$shape" \
    > "$d/.github/workflows/scripts-test.yml"
  commit "$d" >/dev/null
  assert_clean "$d" "invocation shape not recognised: $shape"
done
pass

# ---------------------------------------------------------------------------
# 2. MUTATION -- 'wiring': a tracked suite nothing invokes.
#    This is issue #186's acceptance criterion, stated as a fixture.
# ---------------------------------------------------------------------------
UNWIRED="$(baseline unwired)"
echo '#!/usr/bin/env bash' > "$UNWIRED/scripts/orphan.test.sh"
commit "$UNWIRED" >/dev/null
assert_mutation "$UNWIRED" wiring "a tracked *.test.sh with no invocation"
# Captured rather than piped: the guard exits 1 here, and `set -o pipefail`
# would attribute that to grep.
REPORT="$(bash "$CHECK" --root "$UNWIRED" 2>&1)"
case "$REPORT" in
  *scripts/orphan.test.sh*) ;;
  *) echo "$REPORT"; fail "the finding does not name the unwired file" ;;
esac
pass

# ---------------------------------------------------------------------------
# 3. MUTATION -- 'verb': a path MENTIONED on a live line is not a path that
#    runs. The step name naming the file is the realistic shape, and it is what
#    every step in the real scripts-test.yml looks like.
# ---------------------------------------------------------------------------
NAMED="$(baseline named)"
echo '#!/usr/bin/env bash' > "$NAMED/scripts/orphan.test.sh"
cat >> "$NAMED/.github/workflows/scripts-test.yml" <<'YML'
      - name: scripts/orphan.test.sh regression suite
        run: echo "the run line lost its invocation in a rebase"
YML
commit "$NAMED" >/dev/null
assert_mutation "$NAMED" verb "a suite named by a step but never invoked"
pass

# ---------------------------------------------------------------------------
# 4. MUTATION -- 'comments': a commented-out step is not a step. This one
#    satisfies the verb defense perfectly well, which is why it needs its own.
# ---------------------------------------------------------------------------
DISABLED="$(baseline disabled)"
echo '#!/usr/bin/env bash' > "$DISABLED/scripts/orphan.test.sh"
cat >> "$DISABLED/.github/workflows/scripts-test.yml" <<'YML'
      - name: orphan
      # run: bash scripts/orphan.test.sh
        run: echo "disabled while debugging, never restored"
YML
commit "$DISABLED" >/dev/null
assert_mutation "$DISABLED" comments "a suite whose only invocation is commented out"
pass

# Both defenses at once, against the LIVE workflow rather than a fixture.
# Deleting the grounding-readout step leaves that path named in the header
# prose and in its own step name; the guard must still call it unwired. A
# fixture cannot prove this -- only the real file's real prose can.
LIVE="$TMP/live"
mkdir -p "$LIVE"
(cd "$REPO" && git ls-files -z | xargs -0 tar cf - 2>/dev/null) | tar xf - -C "$LIVE"
WF="$LIVE/.github/workflows/scripts-test.yml"
[ -f "$WF" ] || fail "could not materialise a copy of the live repo"
grep -v 'run: bash scripts/grounding-readout.test.sh' "$WF" > "$WF.tmp" && mv "$WF.tmp" "$WF"
grep -q 'scripts/grounding-readout.test.sh' "$WF" \
  || fail "the live workflow no longer mentions grounding-readout.test.sh outside its run line; this case is stale"
git -C "$LIVE" init -q 2>/dev/null
git -C "$LIVE" config user.email t@t.t
git -C "$LIVE" config user.name t
commit "$LIVE" >/dev/null
assert_finds "$LIVE" "a real suite whose step was deleted while its prose remained"
REPORT="$(bash "$CHECK" --root "$LIVE" 2>&1)"
case "$REPORT" in
  *scripts/grounding-readout.test.sh*) ;;
  *) echo "$REPORT"; fail "the finding does not name the suite whose step was deleted" ;;
esac
pass

# ---------------------------------------------------------------------------
# 5. MUTATION -- 'boundary': a longer path is not this path.
#    `bash scripts/a.test.sh.disabled` must not wire scripts/a.test.sh.
# ---------------------------------------------------------------------------
PREFIX="$(new_repo prefix)"
echo '#!/usr/bin/env bash' > "$PREFIX/scripts/a.test.sh"
echo '#!/usr/bin/env bash' > "$PREFIX/scripts/a.test.sh.disabled"
printf 'jobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh.disabled\n' \
  > "$PREFIX/.github/workflows/scripts-test.yml"
commit "$PREFIX" >/dev/null
assert_mutation "$PREFIX" boundary "a suite wired only by a longer, similarly-named path"
pass

# ---------------------------------------------------------------------------
# 6. Scope: tracked-ness, and every workflow rather than one.
# ---------------------------------------------------------------------------
# An untracked scratch file is not shipped coverage.
UNTRACKED="$(baseline untracked)"
echo '#!/usr/bin/env bash' > "$UNTRACKED/scripts/scratch.test.sh"
assert_clean "$UNTRACKED" "an untracked *.test.sh raised a finding"
pass

# A suite wired by a DIFFERENT workflow is wired. skills-eval.yml really does
# run scripts/run-behavioural-eval.test.sh, so scoping to scripts-test.yml
# alone would turn a legitimate wiring into a false alarm.
OTHER="$(baseline other-workflow)"
echo '#!/usr/bin/env bash' > "$OTHER/scripts/nightly.test.sh"
printf 'jobs:\n  x:\n    steps:\n      - run: bash scripts/nightly.test.sh\n' \
  > "$OTHER/.github/workflows/skills-eval.yml"
commit "$OTHER" >/dev/null
assert_clean "$OTHER" "a suite wired by a second workflow was reported unwired"
pass

# ---------------------------------------------------------------------------
# 7. Operational failures exit 2 -- never a quiet pass.
# ---------------------------------------------------------------------------
NOTREPO="$TMP/not-a-repo"; mkdir -p "$NOTREPO"
bash "$CHECK" --root "$NOTREPO" >/dev/null 2>&1
[ "$?" = "2" ] || fail "a non-git root did not exit 2"

NOTESTS="$(new_repo no-tests)"
write_workflow "$NOTESTS"; commit "$NOTESTS" >/dev/null
bash "$CHECK" --root "$NOTESTS" >/dev/null 2>&1
[ "$?" = "2" ] || fail "a repo with no tracked *.test.sh did not exit 2"

NOWF="$(new_repo no-workflows)"
echo '#!/usr/bin/env bash' > "$NOWF/scripts/a.test.sh"; commit "$NOWF" >/dev/null
bash "$CHECK" --root "$NOWF" >/dev/null 2>&1
[ "$?" = "2" ] || fail "a repo with no tracked workflows did not exit 2"

bash "$CHECK" --nonsense >/dev/null 2>&1
[ "$?" = "2" ] || fail "an unknown argument did not exit 2"

bash "$CHECK" --root "$TMP/does-not-exist" >/dev/null 2>&1
[ "$?" = "2" ] || fail "a missing --root directory did not exit 2"
pass

# ---------------------------------------------------------------------------
# 8. The live repo. The fixtures prove the guard works; this proves it holds
#    against the thing it guards, which is the point of shipping it.
# ---------------------------------------------------------------------------
bash "$CHECK" --root "$REPO" >/dev/null 2>&1 \
  || { bash "$CHECK" --root "$REPO"; fail "the live repo has an unwired *.test.sh"; }

# And the guard's own suite is one of the files it enumerates -- a guard that
# exempts itself is the failure it exists to prevent.
git -C "$REPO" ls-files '*.test.sh' | grep -qx 'scripts/test-wiring-check.test.sh' \
  || fail "this suite is not tracked, so the guard is not checking itself"
pass

echo "test-wiring-check.test.sh: $CASES sections passed"
