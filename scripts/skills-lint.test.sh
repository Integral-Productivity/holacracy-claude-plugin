#!/usr/bin/env bash
# Regression tests for scripts/skills-lint.sh.
#
# Run: bash scripts/skills-lint.test.sh
# No framework — plain asserts. Exits non-zero on first failure.
#
# HOW THIS SUITE IS BUILT
# -----------------------
# Every case builds a THROWAWAY GIT REPO in a temp dir, seeds exactly one defect,
# and points the lint at it via SKILLS_LINT_ROOT. Fixtures rather than the live
# repo, because a suite that asserts against real content has to be rewritten
# every time the content changes, and stops being run shortly after.
#
# THE MUTATION PROPERTY
# ---------------------
# For each check N there is a fixture violating ONLY check N, and the suite
# asserts BOTH directions:
#
#   full lint on that fixture            -> FAILS   (the check does its job)
#   lint with SKILLS_LINT_SKIP=N         -> PASSES  (nothing else covers it)
#
# The second assertion is the one that matters. Without it, a check could be
# dead weight — some other check incidentally catching the same defect — and the
# suite would still be green. This is the property that makes
# grounding-readout.test.sh trustworthy (see scripts-test.yml's header) and it
# is the reason to write a lint suite at all rather than eyeballing the output.
#
# A final case asserts the REAL repo is clean, so a genuine regression in the
# plugin's own markdown fails here too, not just in the fixtures.

# shellcheck disable=SC2016  # backticks in single quotes are literal markdown, not substitution
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/skills-lint.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
CASES=0

# Portable in-place edit. `sed -i` is NOT portable: GNU takes the suffix as an
# optional attached argument, BSD/macOS takes it as a mandatory separate one, so
# `sed -i 's/a/b/' f` on BSD reads 's/a/b/' as the backup suffix and `f` as the
# program. Writing to a temp file and moving it uses only the `sed` both agree
# on (issue #185). Do not "simplify" this back to -i, and do not branch on
# `uname` — the branch is what rots.
#
# It also FAILS LOUDLY when the expression matched nothing. Every caller here is
# seeding a fixture defect, and a seeding step that silently no-ops leaves the
# fixture pristine while the assertions still run — the mutation property would
# report green having measured nothing. That is a worse defect than the
# portability bug this helper fixes, so the no-op is an error, not a shrug.
sedi() {  # sedi EXPR FILE
  local expr="$1" f="$2"
  sed "$expr" "$f" > "$f.sedi" || fail "sedi: sed failed on $f"
  if cmp -s "$f" "$f.sedi"; then
    rm -f "$f.sedi"
    fail "sedi: '$expr' changed nothing in $f — the fixture defect was never seeded"
  fi
  mv "$f.sedi" "$f" || fail "sedi: could not replace $f"
}

# A fixture repo that passes every check. Each case copies it and breaks one
# thing, so a case can only fail for the reason it is named after.
_fixture() {  # $1 = destination dir
  local d="$1"
  mkdir -p "$d"/{commands,agents,skills/demo,skills/shared,evals}
  cat > "$d/commands/demo-cmd.md" <<'EOF'
---
description: A demo command.
argument-hint: [thing, optional]
---
# /holacracy:demo-cmd
Loads `skills/shared/thing.md` Step 2 and links to [the skill](../skills/demo/SKILL.md).
EOF
  cat > "$d/agents/demo-agent.md" <<'EOF'
---
name: demo-agent
description: A demo agent.
model: inherit
---
Body.
EOF
  cat > "$d/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: A demo skill.
status: draft
version: 1.0.0
---
Loads `../shared/thing.md`.
EOF
  cat > "$d/skills/shared/thing.md" <<'EOF'
# Thing
## Step 1 -- first
## Step 2 -- second
EOF
  cat > "$d/README.md" <<'EOF'
# Demo
See `skills/shared/thing.md` and `commands/demo-cmd.md`.
EOF
  printf '# allowlist\n' > "$d/evals/lint-allow-paths.txt"
  printf '# forward references\n' > "$d/evals/forward-references.txt"
  git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t
  git -C "$d" add -A && git -C "$d" commit -qm init
}

# Assert: the fixture fails the full lint, and passes with check N skipped.
_assert_load_bearing() {  # $1 = check number, $2 = fixture dir, $3 = label
  SKILLS_LINT_ROOT="$2" bash "$LINT" >/dev/null 2>&1 \
    && fail "check $1 ($3): lint passed but the fixture is broken"
  SKILLS_LINT_SKIP="$1" SKILLS_LINT_ROOT="$2" bash "$LINT" >/dev/null 2>&1 \
    || fail "check $1 ($3): still fails with check $1 skipped — the defect is caught by something else, so check $1 is not load-bearing"
  CASES=$((CASES + 1))
}

# 0. The pristine fixture is clean. If this fails, every case below is meaningless.
_fixture "$TMP/clean"
SKILLS_LINT_ROOT="$TMP/clean" bash "$LINT" >/dev/null 2>&1 \
  || { SKILLS_LINT_ROOT="$TMP/clean" bash "$LINT"; fail "the pristine fixture is not clean"; }

# 1. A backticked path that does not resolve from the citing file.
#    This is the nine-instances-on-main defect: `../shared/x.md` written inside a
#    role skill's references/ dir, where the correct path is `../../shared/x.md`.
_fixture "$TMP/c1"
mkdir -p "$TMP/c1/skills/demo/references"
cat > "$TMP/c1/skills/demo/references/deep.md" <<'EOF'
# Deep
Loads `../shared/thing.md`, which does not resolve from here.
EOF
git -C "$TMP/c1" add -A && git -C "$TMP/c1" commit -qm c1
_assert_load_bearing 1 "$TMP/c1" "unresolvable backticked path"

# 1b. The allowlist must be keyed on the PAIR. The same path allowlisted for a
#     DIFFERENT citing file must not excuse this one.
printf 'README.md ../shared/thing.md wrong file\n' >> "$TMP/c1/evals/lint-allow-paths.txt"
SKILLS_LINT_ROOT="$TMP/c1" bash "$LINT" >/dev/null 2>&1 \
  && fail "check 1: an allowlist entry for another file excused this finding"
printf 'skills/demo/references/deep.md ../shared/thing.md deliberate\n' >> "$TMP/c1/evals/lint-allow-paths.txt"
SKILLS_LINT_ROOT="$TMP/c1" bash "$LINT" >/dev/null 2>&1 \
  || fail "check 1: a correctly-keyed allowlist entry did not silence the finding"
CASES=$((CASES + 1))

# 2. A step citation naming a heading the target does not have. This is #166's
#    renumber hazard: thing.md has Steps 1-2, the citation says Step 5.
_fixture "$TMP/c2"
sedi 's|`skills/shared/thing.md` Step 2|`skills/shared/thing.md` Step 5|' "$TMP/c2/commands/demo-cmd.md"
git -C "$TMP/c2" add -A && git -C "$TMP/c2" commit -qm c2
_assert_load_bearing 2 "$TMP/c2" "citation to a nonexistent step"

# 2b. The three narrowings that first-run false positives forced. Each of these
#     must NOT be a finding, or the check is unusable on real prose.
_fixture "$TMP/c2b"
cat >> "$TMP/c2b/README.md" <<'EOF'
Row: | `skills/shared/thing.md` | At the start of every session (Step 0.5). |
Row: Runs `skills/shared/thing.md` Step 2 (thing). Then reads the cache at Step 9.
Row: `commands/demo-cmd.md` step 4 — a numbered list item, not a heading.
EOF
git -C "$TMP/c2b" add -A && git -C "$TMP/c2b" commit -qm c2b
SKILLS_LINT_ROOT="$TMP/c2b" bash "$LINT" >/dev/null 2>&1 \
  || { SKILLS_LINT_ROOT="$TMP/c2b" bash "$LINT"; fail "check 2 false-positives on a phase label, a same-line self-reference, or a numbered-list citation"; }
CASES=$((CASES + 1))

# 3. Frontmatter contract. A skill without `version` cannot be version-checked,
#    and a non-semver version is how a hand-maintained number drifts to nonsense.
_fixture "$TMP/c3"
sedi '/^version:/d' "$TMP/c3/skills/demo/SKILL.md"
git -C "$TMP/c3" add -A && git -C "$TMP/c3" commit -qm c3
_assert_load_bearing 3 "$TMP/c3" "skill missing version"

_fixture "$TMP/c3b"
sedi 's/^version: 1.0.0/version: v1.0/' "$TMP/c3b/skills/demo/SKILL.md"
git -C "$TMP/c3b" add -A && git -C "$TMP/c3b" commit -qm c3b
_assert_load_bearing 3 "$TMP/c3b" "skill version not semver"

_fixture "$TMP/c3c"
sedi '/^argument-hint:/d' "$TMP/c3c/commands/demo-cmd.md"
git -C "$TMP/c3c" add -A && git -C "$TMP/c3c" commit -qm c3c
_assert_load_bearing 3 "$TMP/c3c" "command missing argument-hint"

# 4. Content changed without a version bump — diff-aware, so it needs --base.
_fixture "$TMP/c4"
BASE4="$(git -C "$TMP/c4" rev-parse HEAD)"
printf '\nNew paragraph, no version bump.\n' >> "$TMP/c4/skills/demo/SKILL.md"
git -C "$TMP/c4" add -A && git -C "$TMP/c4" commit -qm c4
SKILLS_LINT_ROOT="$TMP/c4" bash "$LINT" --base "$BASE4" >/dev/null 2>&1 \
  && fail "check 4: body changed with no version bump but lint passed"
SKILLS_LINT_SKIP=4 SKILLS_LINT_ROOT="$TMP/c4" bash "$LINT" --base "$BASE4" >/dev/null 2>&1 \
  || fail "check 4 is not load-bearing"
CASES=$((CASES + 1))

# 4b. Bumping the version clears it. And 4c: a frontmatter-only change (the bump
#     itself) must not demand a further bump, or the rule would never terminate.
sedi 's/^version: 1.0.0/version: 1.1.0/' "$TMP/c4/skills/demo/SKILL.md"
git -C "$TMP/c4" add -A && git -C "$TMP/c4" commit -qm c4b
SKILLS_LINT_ROOT="$TMP/c4" bash "$LINT" --base "$BASE4" >/dev/null 2>&1 \
  || fail "check 4: a bumped version did not clear the finding"
_fixture "$TMP/c4c"
BASE4C="$(git -C "$TMP/c4c" rev-parse HEAD)"
sedi 's/^version: 1.0.0/version: 1.0.1/' "$TMP/c4c/skills/demo/SKILL.md"
git -C "$TMP/c4c" add -A && git -C "$TMP/c4c" commit -qm c4c
SKILLS_LINT_ROOT="$TMP/c4c" bash "$LINT" --base "$BASE4C" >/dev/null 2>&1 \
  || fail "check 4: a frontmatter-only bump demanded a further bump"
CASES=$((CASES + 1))

# 4d. A skill is its whole DIRECTORY. Changing references/ without touching
#     SKILL.md still changes what the skill does at runtime, and must still
#     demand a bump. Scoping the check to SKILL.md alone would have let the very
#     PR that introduced this lint edit four references/ files version-free.
_fixture "$TMP/c4d"
mkdir -p "$TMP/c4d/skills/demo/references"
printf '# Ref\nInitial.\n' > "$TMP/c4d/skills/demo/references/ref.md"
git -C "$TMP/c4d" add -A && git -C "$TMP/c4d" commit -qm c4d-base
BASE4D="$(git -C "$TMP/c4d" rev-parse HEAD)"
printf 'A materially different instruction.\n' >> "$TMP/c4d/skills/demo/references/ref.md"
git -C "$TMP/c4d" add -A && git -C "$TMP/c4d" commit -qm c4d
SKILLS_LINT_ROOT="$TMP/c4d" bash "$LINT" --base "$BASE4D" >/dev/null 2>&1 \
  && fail "check 4: a references/ change with no version bump was accepted"
sedi 's/^version: 1.0.0/version: 1.0.1/' "$TMP/c4d/skills/demo/SKILL.md"
git -C "$TMP/c4d" add -A && git -C "$TMP/c4d" commit -qm c4d-bump
SKILLS_LINT_ROOT="$TMP/c4d" bash "$LINT" --base "$BASE4D" >/dev/null 2>&1 \
  || fail "check 4: bumping SKILL.md did not clear a references/ change"
CASES=$((CASES + 1))

# 5. A slash command referenced in prose that neither exists nor is declared.
_fixture "$TMP/c5"
printf '\nSee `/holacracy:ghost-command` for details.\n' >> "$TMP/c5/README.md"
git -C "$TMP/c5" add -A && git -C "$TMP/c5" commit -qm c5
_assert_load_bearing 5 "$TMP/c5" "reference to a nonexistent command"

# 5b. Declaring it WITH a tracking issue clears it; declaring it WITHOUT one
#     does not. An undated forward reference is indistinguishable from a stale
#     one six months later, which is the whole point of requiring the issue.
printf '/holacracy:ghost-command planned\n' >> "$TMP/c5/evals/forward-references.txt"
SKILLS_LINT_ROOT="$TMP/c5" bash "$LINT" >/dev/null 2>&1 \
  && fail "check 5: a forward reference with no tracking issue was accepted"
sedi 's|/holacracy:ghost-command planned|/holacracy:ghost-command #999 planned|' "$TMP/c5/evals/forward-references.txt"
SKILLS_LINT_ROOT="$TMP/c5" bash "$LINT" >/dev/null 2>&1 \
  || fail "check 5: a forward reference declared against an issue was still flagged"
CASES=$((CASES + 1))

# 6. A shared reference nothing loads.
_fixture "$TMP/c6"
printf '# Orphan\n' > "$TMP/c6/skills/shared/orphan.md"
git -C "$TMP/c6" add -A && git -C "$TMP/c6" commit -qm c6
_assert_load_bearing 6 "$TMP/c6" "orphaned shared reference"

# 7. The real repository is clean. Fixtures prove the checks work; this proves
#    they are actually pointed at the plugin.
bash "$LINT" >/dev/null 2>&1 || { bash "$LINT"; fail "the live repository does not pass its own lint"; }
CASES=$((CASES + 1))

echo "skills-lint.test.sh: $CASES cases passed"
