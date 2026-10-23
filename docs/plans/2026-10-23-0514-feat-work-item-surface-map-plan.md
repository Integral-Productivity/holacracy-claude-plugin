---
title: Work-Item Surface Map - Plan
type: feat
date: 2026-10-23
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Work-Item Surface Map - Plan

---

## Goal Capsule

- **Objective:** A maintainer, or a reviewer of any PR, can see in one lookup which plugin command serves each lifecycle stage of each work-item type, and no stage can be missing without a named, live tracking issue: the PR that would leave a stage empty fails CI.
- **Means:** a surface map in `docs/surface-map.md`, a lifecycle glossary section in `CONCEPTS.md`, and a new `skills-lint.sh` check that holds the map, the glossary, the commands, and the tracking issues in step (KTD1 to KTD6).
- **Authority:** the A3 countermeasures C4 and C5 and the three C4 hardenings (Kraig, Rev E decision P4). ADR-0018 and ADR-0011 are the readiness/quality splits the map makes visible. A new ADR-0021 records the convention.
- **Execution profile:** shell (bash, portable to BSD), markdown, and a mutation-checked test suite. Test it like code (CLAUDE.md § Testing the skills).
- **Stop conditions:** stop and report if the check cannot be made load-bearing (a mutation case still fails with the check skipped), or if the July replay passes.
- **Finish and ship:** `lfg` opens the PR; Kraig merges.

---

## Product Contract

### Summary

Add a 4 × 4 surface map (work-item type × lifecycle stage), a glossary of those types and stages, and lint check 13, which fails when a cell is empty, names a command that does not exist, or rests on a closed or idle issue, or when the glossary and the map disagree. A replay of the map as it stood on 2026-07-21 proves the check would have caught the missing project-readiness surface.

### Problem Frame

From July to October 2026 the plugin had no project-readiness command, and nobody could see it. The project-triage ideation of 2026-07-20 proposed it, nothing tracked it, and the gap surfaced only when a person counted idle projects by hand. The root cause (A3, whys 4 and 5) is that the plugin has no shared model of work-item lifecycle stages, so a missing stage looks the same as a stage nobody needs. Actions and checklist items have the same empty slots today.

### Requirements

- **R1.** `docs/surface-map.md` holds one table: a row per work-item type, a column per lifecycle stage, 16 cells.
- **R2.** Every cell names a built command by its bare file name in backticks (`project-triage`), or an open tracking issue (`#409`), or both (a planned command and its issue).
- **R3.** The lint fails on an empty cell, on a cell with neither a command nor an issue, and on a backticked command with no `commands/<name>.md` and no issue in the same cell.
- **R4.** When `gh` is present and `SKILLS_LINT_CHECK_ISSUES` is set, the lint fails on a cell held only by an issue that is closed, or whose last activity is more than 90 days old. Otherwise the issue legs are skipped and the lint stays offline.
- **R5.** `CONCEPTS.md` gains a "Work-item lifecycle" section that names each work-item type and each lifecycle stage. The lint fails when a type or stage named there has no row or column in the map, or the map has a row or column the glossary does not name.
- **R6.** A test replays the map as it stood on 2026-07-21 and asserts the lint fails on the Project × Readiness cell.
- **R7.** The map links, per row, the ideation documents and ADRs that motivated it (C5).
- **R8.** Commands are named without a plugin prefix, so the map survives the `self-org` rename in PR #408.
- **R9.** Every rule of the new check has a mutation case: the seeded defect fails the lint, and the lint passes with the check skipped.
- **R10.** CLAUDE.md's list of what `skills-lint.sh` checks names the new check, and ADR-0021 records the convention.

### Key Decisions

- **Every lifecycle cell is filled or tracked.** (session-settled: user-approved — chosen over a prose list of commands with no lint: an unchecked map is how the project-readiness gap stayed hidden from July to October.) Governs R1, R2, R3.
- **Three hardenings.** (session-settled: user-approved — chosen over relying on reviewers to remember: the glossary trigger, the 90-day staleness rule, and the July replay are what let C4 fail.) Governs R4, R5, R6.
- **Ideation is linked from the map.** (session-settled: user-approved — chosen over leaving ideation unlinked: ideation decisions were not findable.) Governs R7.

### Scope Boundaries

- Building any command for an empty cell. The cells are held by #160, #161, #409 and #410.
- Rows for other work-item types (goals, targets, policies). A new row arrives with a glossary entry and an ADR or PR that names it (R5).
- Live-org data of any kind. The map names commands and public issues only (ADR-0017).

**Considered and not built:**

- A machine-readable sidecar (YAML or TSV) for the map. One markdown table read by a small parser is enough; two sources of truth would need their own sync check. Revisit if a second consumer needs the map.
- Checking the ideation links beyond what check 1 already does for markdown links. A broken link already fails check 1.

### Deferred to Follow-Up Work

- Update the A3 (step 9 row, C4, C5, goal (b)) after merge. The A3 lives outside this public repo.

### Sources

- A3 "GlassFrog project readiness" (private), sections 06 C4/C5 and 09 (first sketch of the map).
- `docs/ideation/2026-07-20-glassfrog-project-triage-ideation.html`.
- ADR-0011, ADR-0018, ADR-0019.
- `scripts/skills-lint.sh` check 5 (forward references with an issue), check 11 (table-driven closed list).
- PR #408 (rename to `self-org`): claims lint check 12 and ADR-0020.

---

## Planning Contract

### Key Technical Decisions

- **KTD1. The map lives at `docs/surface-map.md`.** It is documentation for maintainers, not a file a skill loads, so `skills/shared/` would trip check 6 (no caller). `docs/` keeps it in `_shipped_md`, so check 1 still resolves its markdown links.
- **KTD2. The check is number 13, not 12.** PR #408 adds check 12 (legacy names). Taking 13 avoids a renumber whichever PR merges first; a gap in check IDs is harmless, because `SKILLS_LINT_SKIP` takes IDs, not positions.
- **KTD3. The table is the source; the parser reads its header.** The header's first cell is the type column; each later header cell that the glossary names as a stage is a stage column; other columns (the C5 "Context" column) are ignored. A row whose first cell the glossary names as a type is checked. This mirrors check 11, which reads names from backticked table cells.
- **KTD4. The glossary uses two small tables** under `## Work-item lifecycle` in `CONCEPTS.md`: `| Work-item type | Meaning |` and `| Lifecycle stage | Meaning |`, with the name in bold in the first cell. Tables parse reliably in bash; prose entries would not.
- **KTD5. Issue legs reuse check 5's gate and ask `gh` once per issue.** One call returns state and last-activity time as epoch seconds (`gh issue view N --json state,updatedAt --jq '.state + " " + (.updatedAt | fromdateiso8601 | tostring)'`), so no `date -d` (GNU-only) is needed. The clock is `SKILLS_LINT_NOW` (epoch seconds), default `date +%s`. Tests put a stub `gh` first on `PATH`. Issue legs are evaluated for issue-only cells only (R4): a cell with a built command is not failed by an old issue next to it.
- **KTD6. Commands are bare names, resolved from `commands/*.md`.** (session-settled: user-directed — chosen over `/holacracy:` prefixed names: keeps the change prefix-free so it rebases cleanly over PR #408.) A bare backticked name also keeps the map out of check 5's `/holacracy:` scan and out of PR #408's legacy-name check.
- **KTD7. The pristine test fixture gains a minimal map and glossary,** so the check runs in every case and deleting the map is itself a mutation case. A missing map is a finding, not a skip: an absent map must not read as a clean one.

### High-Level Technical Design

Directional sketch of check 13's rules (not implementation):

```text
types  <- bold first cells of the "Work-item type" table in CONCEPTS.md
stages <- bold first cells of the "Lifecycle stage" table in CONCEPTS.md
map    <- the table in docs/surface-map.md (missing file -> finding)

for each stage not in map header            -> finding "stage has no column"
for each map stage column not in stages     -> finding "column not in glossary"
for each type with no map row               -> finding "type has no row"
for each map row type not in types          -> finding "row not in glossary"
for each (row, stage column) cell:
    cmds   <- backticked names;  issues <- #NNN
    built  <- cmds with commands/<name>.md
    if built non-empty                        -> ok
    elif issues empty and cmds empty          -> finding "empty cell"
    elif issues empty                         -> finding "names <cmd>, which does not exist, and no issue"
    elif ISSUE CHECKS ON:
        for each issue: state, updated <- gh (cached)
            CLOSED                            -> finding "held by closed issue"
            now - updated > 90 days           -> finding "held by idle issue"
```

### Assumptions

- `gh issue view` works in CI with the workflow token, as check 5 already relies on (`scripts-test.yml` sets `SKILLS_LINT_CHECK_ISSUES: "1"`).
- The Action row's create cell names `commit-action` with #161: the command is planned and tracked.

---

## Implementation Units

### U1. Glossary and map

**Goal:** Add the lifecycle glossary and the filled map.

**Requirements:** R1, R2, R5, R7, R8.

**Dependencies:** none.

**Files:** `CONCEPTS.md`, `docs/surface-map.md` (new).

**Approach:**
1. In `CONCEPTS.md`, add `## Work-item lifecycle` with a short definition of a work item and of a lifecycle stage, then the two tables (KTD4). Types: Tension, Project, Action, Checklist item or metric. Stages: Create, Readiness, Quality or disposition, Hygiene sweep. Each meaning is one sentence; say that a new type or stage needs a map row or column in the same PR.
2. In `docs/surface-map.md`, explain the cell grammar in three lines, then the table with the 16 facts from the brief, and a Context column (C5) linking `docs/ideation/2026-07-20-glassfrog-project-triage-ideation.html`, ADR-0011 and ADR-0018 where they apply, and the tracking issues. Link ADRs by a path that does not contain a `holacracy-` identifier (PR #408's check).
3. Note at the top that `scripts/skills-lint.sh` check 13 enforces the file.

**Patterns to follow:** existing `CONCEPTS.md` entry tone; ADR-0019's table style.

**Test scenarios:** covered by U2's live-repo case (the real map must pass the real lint).

**Verification:** 16 cells filled; every link resolves under check 1.

### U2. Lint check 13

**Goal:** Enforce R2 to R5 in `scripts/skills-lint.sh`.

**Requirements:** R2, R3, R4, R5, R8.

**Dependencies:** U1.

**Files:** `scripts/skills-lint.sh`, `scripts/skills-lint.test.sh`.

**Approach:**
1. Add `check_surface_map` after check 11 with a header comment in the file's style: why (the July-to-October gap), what it reads, the two rules families, the gate (KTD5).
2. Parse per KTD3 and KTD4. Cache `gh` answers per issue number.
3. Wire it into the check list at the bottom.

**Execution note:** write each mutation case first and watch it fail against the unchanged lint.

**Patterns to follow:** check 5 (issue gate), check 11 (table parsing, `_live_md`), `lib/check-common.sh` `finding`/`skipped`.

**Test scenarios:**
- The pristine fixture (now with a minimal 2 × 2 map and glossary) is clean.
- An empty cell fails; passes with 13 skipped.
- A cell naming `` `ghost-cmd` `` with no issue fails; adding `#999` to the cell clears it (offline).
- A glossary stage with no map column fails; passes with 13 skipped.
- A map row whose type is not in the glossary fails.
- A missing `docs/surface-map.md` fails.
- With a stub `gh` reporting `CLOSED`, an issue-only cell fails when `SKILLS_LINT_CHECK_ISSUES=1`, and passes when it is unset.
- With a stub `gh` reporting OPEN and an `updatedAt` 91 days before `SKILLS_LINT_NOW`, an issue-only cell fails; at 89 days it passes.
- A cell with a built command and a closed issue passes (issue legs apply to issue-only cells).

**Verification:** every case asserts both directions where it is a mutation case; the suite count rises accordingly.

### U3. July replay

**Goal:** Prove C4 would have caught the gap (R6).

**Requirements:** R6, R9.

**Dependencies:** U2.

**Files:** `scripts/skills-lint.test.sh`.

**Approach:** build a fixture whose `commands/` holds the commands that existed on 2026-07-21 (no `project-triage`) and whose map is the real map with the Project × Readiness cell blank and no issue. Assert the lint fails, that the output names that cell, and that it passes with 13 skipped. Do not read git history at test time; the fixture states the July facts.

**Test scenarios:**
- July map: lint fails and the finding names Project and Readiness.
- Same fixture with check 13 skipped: lint passes.

**Verification:** the replay case is in the suite and green.

### U4. Docs and ADR

**Goal:** Record the convention (R10).

**Requirements:** R10.

**Dependencies:** U2.

**Files:** `CLAUDE.md`, `docs/adr/0021-every-work-item-lifecycle-stage-has-a-command-or-a-tracked-gap.md` (new).

**Approach:**
1. CLAUDE.md § Testing the skills: add "every work-item lifecycle cell names a command or a live tracking issue" to the list of checks; one line pointing at `docs/surface-map.md` and the glossary rule.
2. ADR-0021 (status Accepted, date 2026-10-23): context (the gap, A3 C4), decision (map + glossary + check 13 with the three hardenings), consequences (a new type or stage needs a row or column; an idle issue fails after 90 days; number 0020 is taken by PR #408).

**Test scenarios:** Test expectation: none -- documentation; check 1 and the live-repo case cover its links.

**Verification:** the lint is clean on the live repo.

---

## Verification Contract

| Command | Proves |
|---|---|
| `bash scripts/skills-lint.sh` | the live map, glossary, and every other check |
| `bash scripts/skills-lint.test.sh` | check 13's mutation cases, the July replay, and the live-repo case |
| `bash scripts/evals-harness.test.sh` | leak scan over the new files; nothing else changes |
| `bash scripts/run-behavioural-eval.test.sh` | unchanged runner still passes |
| `shellcheck --severity=style -x -P scripts scripts/*.sh scripts/lib/*.sh` (pinned version in `scripts-test.yml`) | shell edits |

---

## Definition of Done

- The map has 16 filled cells and passes the live lint.
- Check 13 has a mutation case for each rule in U2, plus the July replay, all green.
- `CONCEPTS.md`, `CLAUDE.md`, and ADR-0021 are updated.
- No skill content changed, so no skill version bump; the plugin version is untouched.
- No experimental or abandoned code is left in the diff.
