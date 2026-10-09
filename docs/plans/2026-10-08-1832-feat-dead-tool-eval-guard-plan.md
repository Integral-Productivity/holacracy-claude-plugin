---
title: Fail Graded Evals on Tools Missing from the Session - Plan
type: feat
date: 2026-10-08
topic: dead-tool-eval-guard
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-brainstorm
execution: code
---

# Fail Graded Evals on Tools Missing from the Session - Plan

## Goal Capsule

- **Objective:** A green graded eval run means two things: every GlassFrog capability the skill under test cites had a tool in that session, and every tool call the model made named a tool that existed.
- **Means:** a zero-cost capability check before any model turn, a sixth execution-failure condition for calls to absent tools, a stub that presents the real tool surface, and a per-PR drill that proves both checks fire.
- **Product authority:** [#345](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/345), under the drift umbrella [#341](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/341). Idea 2 of `docs/ideation/2026-10-08-mcp-tool-name-drift-guards-ideation.html`.
- **Open blockers:** implementation waits for U5 of `docs/plans/2026-10-08-1200-feat-official-glassfrog-mcp-default-plan.md` (#340) to merge, because both change `scripts/run-behavioural-eval.py` and its suite (one owner per shared file). This work also consumes that plan's U1 tool inventories and U2 capability map.

---

## Product Contract

### Summary

The eval runner refuses to score a run whose session could not have done what the skill asks. Before any model turn, each plugin-loading leg checks that every capability the case's skill cites has a tool in that leg's session. During the run, a call naming a tool the session does not have fails the run under its own named cause. The stub presents the full production tool surface so neither check fires on a stub gap, and a per-PR drill renames a stub tool to prove both checks fire.

### Problem Frame

The graded tier exists to catch a skill that does the wrong thing. It currently cannot catch a skill that cites a tool the session does not have, and the paths around that gap all read as green.

- A call to a dead or renamed tool counts as "made a call" (`scripts/run-behavioural-eval.py:927-935`), so the run clears the no-tool-calls execution-failure condition and is scored.
- The stub preflight fails only when the stub advertises no tools at all (`:645`). It never checks that the tools a skill cites are present.
- `--validate-only` starts its probe session with an empty `mcpServers` config (`:750`), so the zero-cost tier sees no GlassFrog tools at all.
- `events.jsonl` keeps only `system`, `assistant` and `result` events (`:1079`), so an errored tool result survives only in `transcript.md`, which no check reads.
- The `no_writes` floor in `evals/cases/tension-triage/evals.json` passes when a write could not be built because its tool was missing, exactly as it passes a correct refusal.

This is the #226 shape again: a healthy transcript that measured nothing. It is also the one verified place where this repo's own instrument reports green while a cited tool does not exist. #337 found eight dead tool names in shipped skills by a one-off grep, and nothing in the eval tier would have caught them.

<!-- ce-section: work-relationships -->
### How This Work Fits Together

This plan covers the eval runner's detection of absent tools. The relationships below reflect current understanding, not a committed roadmap.

- #340's plan, U5 (two-server eval legs): Depends on. U5 gives `--validate-only` real stub servers per leg and introduces the `loads_plugin` leg predicate; R2, R4 and R9 build on both rather than adding a second preflight.
- #340's plan, U1 (per-server tool inventories and lint check 8): Depends on. R1 reads the committed inventories. R2's citation scan is the same scan check 8 performs.
- #340's plan, U2 (capability map): Depends on. R2 resolves citations to tools through it.
- [#350](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/350) (re-seed `evals/benchmark.json` after U5): Shares. One re-seed after both this work and U5 land covers both changes to what a green run means.
- Other #341 ideas (lockfile-generated consumers, a scheduled drift alarm, a consumer contract on the Extended server): Can proceed independently of. They detect drift upstream; this plan detects it in the eval tier.

### Key Decisions

- **The preflight checks what the skill under test cites, not a hand-kept list.** Expected tools come from the case's skill and command citations, so the check fails exactly when this case would hit a dead name and adds no list to maintain. (session-settled: user-directed — chosen over a per-case `expected_tools` list, the whole server inventory, and the stub's own tool list: the first drifts like the stub's dicts already have, the second says nothing about this skill, the third is circular.) Governs R2.
- **Presence is judged per capability, per leg.** A leg passes when each cited capability has at least one tool its server set binds it to, which lets the official-only leg run without Extended names. (session-settled: user-directed — chosen over requiring every cited name per leg, and over checking the both-servers leg only: the first duplicates the capability map, the second leaves the official-only leg unguarded.) Governs R2, R3.
- **A call to an absent tool is an execution failure with its own named cause.** The run stays unscoreable like the other five conditions, but its error says which tool and which skill, so a nightly reader can tell a skill defect from broken harness plumbing. (session-settled: user-directed — chosen over a plain execution failure, which hides the cause, and over a scored mechanical assertion, which a 0.9 pass rate can hide.) Governs R5.
- **The stub presents the production tool surface.** It advertises every inventoried tool and keeps answering the ones it does not fake with its existing not-implemented error. The eval session then matches production, and the checks fire only on names that do not exist. (session-settled: user-directed — chosen over checking citations against the inventory only, which leaves the eval session quieter than production, and over failing on every stub gap, which goes red on day one.) Governs R1.
- **The `no_writes` floor stays as it is.** With R5 in place, a write whose tool is absent fails the run before any assertion is scored, which closes the gap without making a constitutional floor case-specific. (session-settled: user-approved — proposed with the tradeoff shown in the scoping synthesis; the user confirmed.)

### Requirements

**Session surface**

- R1. The eval stub advertises every tool name in the committed per-server inventory and answers any it does not fake with its existing not-implemented error. Its deliberate reproductions of live defects are unchanged.
- R2. Before any model turn, each plugin-loading leg verifies that every GlassFrog capability cited by the case's skill or command resolves to at least one tool present in that leg's session. A failure stops the leg, and the error names the capability, the citing file and the leg.
- R3. The R2 check also runs against the graded session's own init event, so a run whose tool surface differs from the preflight's cannot score.
- R4. Control legs, which do not load the plugin, are exempt from R2 and R3 and keep their existing shape checks.

**During the run**

- R5. On every leg, a tool call naming a tool absent from the session's init tool list is a sixth execution-failure condition. Its error names the tool and the leg and labels the cause as a citation defect, distinct from the harness failures.
- R6. Tool results marked as errors are kept in `events.jsonl`. Successful tool results stay excluded, for the size reason recorded with #221.

**Proof**

- R7. A per-PR drill in `scripts/run-behavioural-eval.test.sh` renames one stub tool that a case's skill cites. It asserts that the preflight fails naming that tool, and that a fake-executor replay calling the old name fails with R5's cause.
- R8. The drill follows the repo's mutation convention: each check it exercises is shown to fail the drill when disabled, so neither check passes only because the other one covers it.
- R9. `--validate-only` reports the R2 result for each leg, at no API cost.

### Acceptance Examples

- AE1. **Covers R2, R7.**
  - **Given:** a case whose skill cites a capability bound only to a tool the stub no longer advertises under that name.
  - **When:** the leg's preflight runs.
  - **Then:** the leg stops before any model turn, naming the capability, the citing file and the leg.
- AE2. **Covers R2, R4.**
  - **Given:** the official-only leg, and a skill citing a capability that both servers bind.
  - **When:** the session has the official tool but no Extended tool.
  - **Then:** the preflight passes.
- AE3. **Covers R5.**
  - **Given:** a run of any leg.
  - **When:** the model calls a tool that is not in the session's init tool list.
  - **Then:** the run is an execution failure whose error names that tool and labels the cause as a citation defect, and every assertion for the run fails.
- AE4. **Covers R1, R5, R6.**
  - **Given:** a tool present in the inventory that the stub does not fake.
  - **When:** the model calls it.
  - **Then:** R5 does not fire because the tool exists, the run continues, and the stub's not-implemented error is kept in `events.jsonl`.
- AE5. **Covers R3.**
  - **Given:** a preflight that passed.
  - **When:** the graded session's own init event lacks a tool a cited capability needs.
  - **Then:** the run is an execution failure and is not scored.

### Success Criteria

- The drill lands in the same change as the checks. Without the checks the drill fails; with them it passes.
- The first graded run after this lands either passes, or fails with R2's or R5's named cause. It never fails with an unnamed cause traceable to a missing tool.

### Scope Boundaries

- No change to the `no_writes` floor or any other assertion's text (see Key Decisions).
- No separate baseline re-seed. #350 covers one re-seed after both this work and #340's U5 land.
- No upstream drift detection. Scheduled drift alarms, lockfile-generated consumers and server-side contracts are other #341 ideas.
- No change to which leg configurations exist. Legs are #340's U5.
- No change to the lint's citation scan beyond reusing it. That scan is #340's U1, check 8.

### Dependencies / Assumptions

- Verified 2026-10-08: a session started with the stub's MCP config and no API key emits an init event listing the stub's `mcp__glassfrog-extended__*` tools, with the server `connected`, before it checks credentials. The zero-cost preflight can therefore see the GlassFrog tool surface once U5 hands it a real config.
- Verified 2026-10-08: `EVAL_TOOLS` is `Skill,Task,Read`, so graded sessions are not offered ToolSearch and MCP tools appear directly in the init tool list.
- Verified 2026-10-08: an execution error fails every mechanical assertion and leaves judged assertions ungraded (`scripts/run-behavioural-eval.py:1406-1440`). R5 inherits this rule.
- Verified 2026-10-08: `evals/benchmark.json` is measured (seeded 2026-08-17), so runs after this change may compare worse against it until #350 re-seeds.
- Assumption: Claude Code returns an error tool result, rather than refusing the turn, when a model calls a tool it does not have. R5 reads tool names from the assistant's calls, so it holds either way. The assumption only affects what R6 records.

### Outstanding Questions

**Deferred to Planning**

- How the citation scan is shared between lint check 8 and R2: one module both import, or the lint emits an index the runner reads.
- Where the stub's advertised list comes from at runtime: read from the inventory files, or generated into the stub. Either must keep the defect overlay hand-written.
- Whether the R5 error lists every absent tool called in the run or only the first.

### Sources

- `scripts/run-behavioural-eval.py`: preflight `:609-646`, probe config `:750`, execution-failure conditions `:887-940`, events filter `:1079-1095`, grading on error `:1406-1440`.
- `evals/stub/glassfrog_stub.py:238` (not-implemented error) and `:290` (`isError` on the MCP result).
- `docs/plans/2026-10-08-1200-feat-official-glassfrog-mcp-default-plan.md`: KTD9, KTD10, U1, U2, U5.
- `docs/ideation/2026-10-08-mcp-tool-name-drift-guards-ideation.html`, idea 2.
- `docs/adr/0012-test-the-skills-not-just-the-scaffolding.md` and `docs/adr/0014-eval-hermeticity-by-config-dir-isolation-not-bare.md`.
