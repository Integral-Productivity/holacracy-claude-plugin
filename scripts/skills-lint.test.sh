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
  mkdir -p "$d/docs"
  cat > "$d/CONCEPTS.md" <<'EOF'
# Concepts
## Work-item lifecycle
| Work-item type | Meaning |
|---|---|
| **Alpha** | first type |
| **Beta** | second type |

| Lifecycle stage | Meaning |
|---|---|
| **Make** | first stage |
| **Sweep** | second stage |
EOF
  cat > "$d/docs/surface-map.md" <<'EOF'
# Map
| Work-item type | Make | Sweep | Context |
|---|---|---|---|
| **Alpha** | `demo-cmd` | `demo-cmd` | notes |
| **Beta** | `demo-cmd` | #42 | notes |
EOF
  printf '# allowlist\n' > "$d/evals/lint-allow-paths.txt"
  printf '# forward references\n' > "$d/evals/forward-references.txt"
  printf '# inventory\nglassfrog_get_me\tread\nglassfrog_list_my_roles\tread\nglassfrog_get_role\tread\nglassfrog_create_tension\twrite\nglassfrog_set_project_tags\twrite\n' \
    > "$d/evals/glassfrog-tools.tsv"
  printf '# prefixes\nmcp__plugin_holacracy_glassfrog-extended__  plugin\nmcp__GlassFrog_Extended__  cowork\n' \
    > "$d/evals/glassfrog-server-prefixes.txt"
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

# 7. A file that prescribes the role-roster load without citing the procedure.
#    The third recurrence of one pattern -- the bound documented adjacent to
#    where it is needed rather than in it (#148, then twelve files in #155).
_fixture "$TMP/c7"
cat > "$TMP/c7/commands/rogue.md" <<'EOF'
---
description: rogue
argument-hint: [thing, optional]
---
1. Confirm the actor via `glassfrog_get_me`.
2. Load the roster via `glassfrog_list_my_roles`.
EOF
git -C "$TMP/c7" add -A && git -C "$TMP/c7" commit -qm c7
_assert_load_bearing 7 "$TMP/c7" "roster load prescribed with no pointer to the procedure"

# 7b. The house style must NOT trip it. Naming both calls beside a pointer is
#     how commands/review-project.md is written, and that is good prose, not a
#     violation -- a check that flagged it would be reverted within a week.
_fixture "$TMP/c7b"
cat > "$TMP/c7b/commands/wellformed.md" <<'EOF'
---
description: wellformed
argument-hint: [thing, optional]
---
1. **Resolve actor + role roster.** Follow `skills/shared/actor-and-role-resolution.md`
   Steps 1-2: `glassfrog_get_me`, then `glassfrog_list_my_roles`.
EOF
mkdir -p "$TMP/c7b/skills/shared"
printf '# Actor and Role Resolution\n\n## Step 1 -- a\n\n## Step 2 -- b\n' \
  > "$TMP/c7b/skills/shared/actor-and-role-resolution.md"
git -C "$TMP/c7b" add -A && git -C "$TMP/c7b" commit -qm c7b
SKILLS_LINT_ROOT="$TMP/c7b" bash "$LINT" >/dev/null 2>&1 \
  || { SKILLS_LINT_ROOT="$TMP/c7b" bash "$LINT"; fail "check 7 flagged the established house style (pointer + both call names)"; }
CASES=$((CASES + 1))

# 7c. A frontmatter `tools:` grant is a capability, not a call description, and
#     agents/holacracy-coach.md legitimately lists the tool there.
_fixture "$TMP/c7c"
cat > "$TMP/c7c/agents/granted.md" <<'EOF'
---
name: granted
description: agent with a tools grant
model: inherit
tools: Read, mcp__plugin_holacracy_glassfrog-extended__glassfrog_list_my_roles
---
Body that never mentions the roster call.
EOF
git -C "$TMP/c7c" add -A && git -C "$TMP/c7c" commit -qm c7c
SKILLS_LINT_ROOT="$TMP/c7c" bash "$LINT" >/dev/null 2>&1 \
  || { SKILLS_LINT_ROOT="$TMP/c7c" bash "$LINT"; fail "check 7 flagged a frontmatter tools: grant" ; }
CASES=$((CASES + 1))

# 8. A description over Claude's upload limit. The upload validator rejects it
#    silently from our side, and the org copy stays on the last accepted
#    version -- 0.22.0 for a week in #368. Folded (`>`) because that is how
#    five of the six real skills are written, so the parser is tested on it.
_fixture "$TMP/c8"
long="$(printf 'word %.0s' $(seq 1 210))"
sedi "s/^description: A demo skill\\.\$/description: >\\n  $long/" "$TMP/c8/skills/demo/SKILL.md"
git -C "$TMP/c8" add -A && git -C "$TMP/c8" commit -qm c8
_assert_load_bearing 8 "$TMP/c8" "skill description over 1024"

_fixture "$TMP/c8b"
mkdir -p "$TMP/c8b/.claude-plugin"
printf '{"name":"demo","description":"%s"}\n' "$(printf 'x%.0s' $(seq 1 501))" > "$TMP/c8b/.claude-plugin/plugin.json"
git -C "$TMP/c8b" add -A && git -C "$TMP/c8b" commit -qm c8b
_assert_load_bearing 8 "$TMP/c8b" "plugin.json description over 500"

# 8d. Wrapping a plain scalar across lines is valid YAML and does not change
#     its value. Measuring only the first line reads it as a few characters.
_fixture "$TMP/c8d"
wrapped="$(printf '  word word word word word word word word word word\\n%.0s' $(seq 1 25))"
sedi "s/^description: A demo skill\\.\$/description: Start\\n$wrapped/" "$TMP/c8d/skills/demo/SKILL.md"
git -C "$TMP/c8d" add -A && git -C "$TMP/c8d" commit -qm c8d
_assert_load_bearing 8 "$TMP/c8d" "wrapped plain description over 1024"

# 8e. A description the parser cannot read is a finding, not length zero.
_fixture "$TMP/c8e"
printf 'Caf\351\n' >> "$TMP/c8e/skills/demo/SKILL.md"
git -C "$TMP/c8e" add -A && git -C "$TMP/c8e" commit -qm c8e
_assert_load_bearing 8 "$TMP/c8e" "unreadable SKILL.md"

# 8c. At the limit is fine. An off-by-one here would fail a manifest the
#     validator accepts, and the fix would be to trim a correct description.
_fixture "$TMP/c8c"
mkdir -p "$TMP/c8c/.claude-plugin"
printf '{"name":"demo","description":"%s"}\n' "$(printf 'x%.0s' $(seq 1 500))" > "$TMP/c8c/.claude-plugin/plugin.json"
git -C "$TMP/c8c" add -A && git -C "$TMP/c8c" commit -qm c8c
SKILLS_LINT_ROOT="$TMP/c8c" bash "$LINT" >/dev/null 2>&1 \
  || { SKILLS_LINT_ROOT="$TMP/c8c" bash "$LINT"; fail "check 8 flagged a 500-character plugin description"; }
CASES=$((CASES + 1))

# 9. A skill cites a GlassFrog tool that exists on no server. Seven such names,
#    69 citations, shipped in the role skills until #337.
_fixture "$TMP/c9"
printf '\nLoad the circle with `glassfrog_get_circle(circle_id)`.\n' >> "$TMP/c9/skills/demo/SKILL.md"
git -C "$TMP/c9" add -A && git -C "$TMP/c9" commit -qm c9
_assert_load_bearing 9 "$TMP/c9" "nonexistent GlassFrog tool name"

# 9b. Names are cited but the inventory is gone. That is a finding, never a
#     silent pass: an absent inventory would otherwise make every name valid.
_fixture "$TMP/c9b"
printf '\nLoad the role with `glassfrog_get_role(role_id)`.\n' >> "$TMP/c9b/skills/demo/SKILL.md"
git -C "$TMP/c9b" rm -q evals/glassfrog-tools.tsv
git -C "$TMP/c9b" add -A && git -C "$TMP/c9b" commit -qm c9b
_assert_load_bearing 9 "$TMP/c9b" "inventory missing"

# 9c. A real tool name is fine.
_fixture "$TMP/c9c"
printf '\nLoad the role with `glassfrog_get_role(role_id)`.\n' >> "$TMP/c9c/skills/demo/SKILL.md"
git -C "$TMP/c9c" add -A && git -C "$TMP/c9c" commit -qm c9c
SKILLS_LINT_ROOT="$TMP/c9c" bash "$LINT" >/dev/null 2>&1 \
  || { SKILLS_LINT_ROOT="$TMP/c9c" bash "$LINT"; fail "check 9 flagged a tool that is in the inventory"; }
CASES=$((CASES + 1))

# 10. The coach's tool lines. The fixture gets a coach whose lines are exactly
#     what the generator prints; each case below breaks them one way.
_coach_fixture() {  # $1 = destination dir
  _fixture "$1"
  { printf -- '---\nname: holacracy-coach\ndescription: coach\nmodel: inherit\n'
    GLASSFROG_INVENTORY_ROOT="$1" python3 "$HERE/glassfrog-tool-inventory.py" coach-frontmatter \
      || fail "coach fixture: generator failed"
    printf -- '---\nBody.\n'
  } > "$1/agents/holacracy-coach.md"
  git -C "$1" add -A && git -C "$1" commit -qm coach
}

# 10a. A generated coach is clean, and its allowlist holds no write tool.
_coach_fixture "$TMP/c10a"
SKILLS_LINT_ROOT="$TMP/c10a" bash "$LINT" >/dev/null 2>&1 \
  || { SKILLS_LINT_ROOT="$TMP/c10a" bash "$LINT"; fail "check 10 flagged a coach generated from the inventory"; }
grep '^tools:' "$TMP/c10a/agents/holacracy-coach.md" | grep -q 'create_tension\|set_project_tags' \
  && fail "the generator put a write tool in the coach's allowlist"
grep '^tools:' "$TMP/c10a/agents/holacracy-coach.md" | grep -q 'mcp__GlassFrog_Extended__glassfrog_get_role' \
  || fail "the generator did not list reads under every prefix"
CASES=$((CASES + 1))

# 10b. A write tool added to the allowlist -- the one edit that breaks the
#      coach's read-only guarantee.
_coach_fixture "$TMP/c10b"
sedi 's/^tools: Read,/tools: Read, mcp__plugin_holacracy_glassfrog-extended__glassfrog_create_tension,/' "$TMP/c10b/agents/holacracy-coach.md"
git -C "$TMP/c10b" add -A && git -C "$TMP/c10b" commit -qm c10b
_assert_load_bearing 10 "$TMP/c10b" "write tool in the coach allowlist"

# 10c. The deny list misses a write. This is #342: two tag writes were added to
#      the server and never to the hand-kept list.
_coach_fixture "$TMP/c10c"
sedi 's/, mcp__GlassFrog_Extended__glassfrog_set_project_tags//' "$TMP/c10c/agents/holacracy-coach.md"
git -C "$TMP/c10c" add -A && git -C "$TMP/c10c" commit -qm c10c
_assert_load_bearing 10 "$TMP/c10c" "write tool missing from the coach deny list"

# 10d. A skill body names a tool by one server's prefix. That name is wrong on
#      every other surface (#338).
_fixture "$TMP/c10d"
printf '\nCall `mcp__plugin_holacracy_glassfrog-extended__glassfrog_create_tension`.\n' >> "$TMP/c10d/skills/demo/SKILL.md"
git -C "$TMP/c10d" add -A && git -C "$TMP/c10d" commit -qm c10d
_assert_load_bearing 10 "$TMP/c10d" "fully-qualified tool name in prose"

# 10e. An agent grants a tool under a prefix nobody has observed.
_fixture "$TMP/c10e"
sedi 's/^model: inherit$/model: inherit\ntools: Read, mcp__made-up__glassfrog_get_role/' "$TMP/c10e/agents/demo-agent.md"
git -C "$TMP/c10e" add -A && git -C "$TMP/c10e" commit -qm c10e
_assert_load_bearing 10 "$TMP/c10e" "unknown server prefix in a tools: line"

# 11. Triage-state names come from a closed list. GlassFrog creates any tag it
#     is sent, so a misspelled state becomes a tag no queue reads (ADR-0019).
_states_fixture() {  # $1 = destination dir
  _fixture "$1"
  printf '# States\n## Step 1 -- list\n| State | Meaning |\n|---|---|\n| `needs-info` | ask |\n| `ready-for-agent` | go |\n' \
    > "$1/skills/shared/triage-states.md"
  printf '# Rubric\n| State | Meaning |\n|---|---|\n| `needs-outcome` | reframe |\n' \
    > "$1/skills/shared/project-well-formedness.md"
  printf '\nStates: `skills/shared/triage-states.md`; verdicts: `skills/shared/project-well-formedness.md`.\n' >> "$1/README.md"
  git -C "$1" add -A && git -C "$1" commit -qm states
}

# 11a. Names from either list are fine, in prose and in the tables themselves.
_states_fixture "$TMP/c11a"
printf '\nRoute it `ready-for-agent`, or `needs-info`; review may say `needs-outcome`.\n' >> "$TMP/c11a/skills/demo/SKILL.md"
git -C "$TMP/c11a" add -A && git -C "$TMP/c11a" commit -qm c11a
SKILLS_LINT_ROOT="$TMP/c11a" bash "$LINT" >/dev/null 2>&1 \
  || { SKILLS_LINT_ROOT="$TMP/c11a" bash "$LINT"; fail "check 11 flagged names that are in the lists"; }
CASES=$((CASES + 1))

# 11b. A misspelled state in a skill -- the silent-new-tag defect.
_states_fixture "$TMP/c11b"
printf '\nTag the project `ready-for-agents`.\n' >> "$TMP/c11b/skills/demo/SKILL.md"
git -C "$TMP/c11b" add -A && git -C "$TMP/c11b" commit -qm c11b
_assert_load_bearing 11 "$TMP/c11b" "triage state not in the closed list"

# 11c. A name in both lists: a review verdict that would also be a tag write.
_states_fixture "$TMP/c11c"
printf '| `needs-info` | also a verdict |\n' >> "$TMP/c11c/skills/shared/project-well-formedness.md"
git -C "$TMP/c11c" add -A && git -C "$TMP/c11c" commit -qm c11c
_assert_load_bearing 11 "$TMP/c11c" "name in both the state list and the verdict table"

# 13. The work-item surface map (ADR-0021). The fixture's map is 2 types x 2
#     stages; Beta x Sweep is held only by #42, so it exercises the issue legs.
#     The issue legs ask `gh`; a stub first on PATH answers instead, with the
#     state and last-activity epoch that real `gh --jq` would print.
mkdir -p "$TMP/stub-bin"
cat > "$TMP/stub-bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$STUB_GH_ANSWER"
EOF
chmod +x "$TMP/stub-bin/gh"
NOW13=1792800000
DAY=86400
_lint_with_issues() {  # $1 = fixture, $2 = stub answer; extra env via caller
  PATH="$TMP/stub-bin:$PATH" STUB_GH_ANSWER="$2" SKILLS_LINT_CHECK_ISSUES=1 \
    SKILLS_LINT_NOW="$NOW13" SKILLS_LINT_ROOT="$1" bash "$LINT" >/dev/null 2>&1
}

# 13a. An empty cell -- the shape of the project-readiness gap.
_fixture "$TMP/c13a"
sedi 's/| #42 |/| |/' "$TMP/c13a/docs/surface-map.md"
git -C "$TMP/c13a" add -A && git -C "$TMP/c13a" commit -qm c13a
_assert_load_bearing 13 "$TMP/c13a" "empty surface-map cell"

# 13b. A command that does not exist, with no issue beside it. Adding an issue
#      turns it into a tracked plan, which is allowed offline.
_fixture "$TMP/c13b"
sedi 's/| \*\*Alpha\*\* | `demo-cmd` |/| **Alpha** | `ghost-cmd` |/' "$TMP/c13b/docs/surface-map.md"
git -C "$TMP/c13b" add -A && git -C "$TMP/c13b" commit -qm c13b
_assert_load_bearing 13 "$TMP/c13b" "unbuilt command with no tracking issue"
sedi 's/`ghost-cmd` |/`ghost-cmd` #999 |/' "$TMP/c13b/docs/surface-map.md"
SKILLS_LINT_ROOT="$TMP/c13b" bash "$LINT" >/dev/null 2>&1 \
  || { SKILLS_LINT_ROOT="$TMP/c13b" bash "$LINT"; fail "check 13: a planned command with a tracking issue was flagged offline"; }
CASES=$((CASES + 1))

# 13c. The review trigger: a stage in the glossary with no column in the map.
_fixture "$TMP/c13c"
sedi 's/^| \*\*Sweep\*\* | second stage |$/| **Sweep** | second stage |\n| **Archive** | third stage |/' "$TMP/c13c/CONCEPTS.md"
git -C "$TMP/c13c" add -A && git -C "$TMP/c13c" commit -qm c13c
_assert_load_bearing 13 "$TMP/c13c" "glossary stage with no map column"

# 13d. A type in the glossary with no row in the map.
_fixture "$TMP/c13d"
sedi 's/^| \*\*Beta\*\* | second type |$/| **Beta** | second type |\n| **Gamma** | third type |/' "$TMP/c13d/CONCEPTS.md"
git -C "$TMP/c13d" add -A && git -C "$TMP/c13d" commit -qm c13d
_assert_load_bearing 13 "$TMP/c13d" "glossary type with no map row"

# 13e. A map row the glossary does not name.
_fixture "$TMP/c13e"
printf '| **Gamma** | `demo-cmd` | `demo-cmd` | notes |\n' >> "$TMP/c13e/docs/surface-map.md"
git -C "$TMP/c13e" add -A && git -C "$TMP/c13e" commit -qm c13e
_assert_load_bearing 13 "$TMP/c13e" "map row not in the glossary"

# 13f. A map column that is neither a stage nor the Context column.
_fixture "$TMP/c13f"
sedi 's/| Sweep | Context |/| Sweep | Notes |/' "$TMP/c13f/docs/surface-map.md"
git -C "$TMP/c13f" add -A && git -C "$TMP/c13f" commit -qm c13f
_assert_load_bearing 13 "$TMP/c13f" "map column not in the glossary"

# 13g. A row too short to fill every stage column. Its missing cell is empty,
#      not unchecked.
_fixture "$TMP/c13g"
sedi 's/^| \*\*Beta\*\* | `demo-cmd` | #42 | notes |$/| **Beta** | `demo-cmd` |/' "$TMP/c13g/docs/surface-map.md"
git -C "$TMP/c13g" add -A && git -C "$TMP/c13g" commit -qm c13g
_assert_load_bearing 13 "$TMP/c13g" "short map row"

# 13h. No map at all. An absent map must not read as a clean one.
_fixture "$TMP/c13h"
git -C "$TMP/c13h" rm -q docs/surface-map.md && git -C "$TMP/c13h" commit -qm c13h
_assert_load_bearing 13 "$TMP/c13h" "surface map missing"

# 13i. An issue-only cell whose issue is CLOSED fails only with the issue gate
#      on; without it the lint stays offline and accepts the number.
_fixture "$TMP/c13i"
_lint_with_issues "$TMP/c13i" "CLOSED $NOW13" \
  && fail "check 13: an issue-only cell held by a CLOSED issue passed"
PATH="$TMP/stub-bin:$PATH" STUB_GH_ANSWER="CLOSED $NOW13" SKILLS_LINT_CHECK_ISSUES=1 SKILLS_LINT_SKIP=13 \
  SKILLS_LINT_NOW="$NOW13" SKILLS_LINT_ROOT="$TMP/c13i" bash "$LINT" >/dev/null 2>&1 \
  || fail "check 13 is not load-bearing for a closed issue"
PATH="$TMP/stub-bin:$PATH" STUB_GH_ANSWER="CLOSED $NOW13" \
  SKILLS_LINT_ROOT="$TMP/c13i" bash "$LINT" >/dev/null 2>&1 \
  || fail "check 13: the issue leg ran without SKILLS_LINT_CHECK_ISSUES"
CASES=$((CASES + 1))

# 13j. Staleness: an open issue idle 91 days fails; 89 days passes.
_lint_with_issues "$TMP/c13i" "OPEN $((NOW13 - 91 * DAY))" \
  && fail "check 13: an issue idle for 91 days still held its cell"
_lint_with_issues "$TMP/c13i" "OPEN $((NOW13 - 89 * DAY))" \
  || fail "check 13: an issue active 89 days ago was flagged as idle"
CASES=$((CASES + 1))

# 13k. The issue legs apply to issue-only cells. A built command beside a
#      closed issue still holds its cell.
_fixture "$TMP/c13k"
sedi 's/| #42 |/| `demo-cmd` #42 |/' "$TMP/c13k/docs/surface-map.md"
git -C "$TMP/c13k" add -A && git -C "$TMP/c13k" commit -qm c13k
_lint_with_issues "$TMP/c13k" "CLOSED $NOW13" \
  || fail "check 13: a cell with a built command was failed by the closed issue beside it"
CASES=$((CASES + 1))

# 13l. THE JULY REPLAY. The only proof that check 13 would have caught the gap
#      that A3 C4 answers. The facts are stated here, not read from git history:
#      on 2026-07-21 commands/ held these eleven files and no project-triage,
#      and nothing tracked a project-readiness command. The glossary is the
#      real one, so a renamed type or stage breaks this case loudly.
_july_fixture() {  # $1 = destination dir, $2 = map text
  mkdir -p "$1/commands" "$1/docs"
  for c in check-authority context capture-tension process-inbox supersession-sweep \
           tactical governance routines capture-project review-project stalled-project-sweep; do
    printf -- '---\ndescription: x\nargument-hint: [x]\n---\n' > "$1/commands/$c.md"
  done
  cp "$HERE/../CONCEPTS.md" "$1/CONCEPTS.md"
  printf '%s\n' "$2" > "$1/docs/surface-map.md"
  git -C "$1" init -q 2>/dev/null
  git -C "$1" config user.email t@t.t; git -C "$1" config user.name t
  git -C "$1" add -A && git -C "$1" commit -qm july
}
_findings13() {  # $1 = fixture, $2 = skip list; prints check 13's finding lines
  SKILLS_LINT_SKIP="$2" SKILLS_LINT_ROOT="$1" bash "$LINT" 2>/dev/null | grep '^\[13\]'
}
_july_fixture "$TMP/c13l" '| Work-item type | Create | Readiness | Quality or disposition | Hygiene sweep |
|---|---|---|---|---|
| **Tension** | `capture-tension` | | | `supersession-sweep` |
| **Project** | `capture-project` | | `review-project` | `stalled-project-sweep` |
| **Action** | | | | |
| **Checklist item or metric** | | | | |'
got="$(_findings13 "$TMP/c13l" "")"
grep -q 'Project × Readiness is empty' <<< "$got" \
  || { printf '%s\n' "$got"; fail "check 13: the July replay did not flag Project x Readiness"; }
[ -z "$(_findings13 "$TMP/c13l" 13)" ] || fail "check 13: findings remain with check 13 skipped"
CASES=$((CASES + 1))

# 13m. The same gap in isolation: today's map with only the July
#      Project x Readiness cell put back. It must be the one and only finding.
_july_fixture "$TMP/c13m" "$(sed 's/| `project-triage` |/| |/' "$HERE/../docs/surface-map.md")"
for c in tension-triage audit-portfolio; do printf -- '---\ndescription: x\nargument-hint: [x]\n---\n' > "$TMP/c13m/commands/$c.md"; done
git -C "$TMP/c13m" add -A && git -C "$TMP/c13m" commit -qm today
got="$(_findings13 "$TMP/c13m" "")"
if [ "$(printf '%s\n' "$got" | grep -c .)" != 1 ] || ! grep -q 'Project × Readiness is empty' <<< "$got"; then
  printf '%s\n' "$got"
  fail "check 13: the isolated July gap was not exactly one Project x Readiness finding"
fi
CASES=$((CASES + 1))

# 12. The real repository is clean. Fixtures prove the checks work; this proves
#    they are actually pointed at the plugin.
bash "$LINT" >/dev/null 2>&1 || { bash "$LINT"; fail "the live repository does not pass its own lint"; }
CASES=$((CASES + 1))

echo "skills-lint.test.sh: $CASES cases passed"
