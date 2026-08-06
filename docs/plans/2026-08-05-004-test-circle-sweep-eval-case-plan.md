---
title: Circle-Sweep Completeness Eval Case - Plan
type: test
date: 2026-08-05
topic: circle-sweep-eval-case
artifact_contract: ce-unified-plan/v1
artifact_readiness: requirements-only
product_contract_source: ce-brainstorm
execution: code
issue: 181
---

# Circle-Sweep Completeness Eval Case - Plan

## Goal Capsule

- **Objective:** A behavioural eval case proving `/holacracy:tension-triage` sweeps circle by circle and loses nothing, against a fixture sized so a root-only sweep provably misses more than half the backlog.
- **Product authority:** Kraig Parkinson (founder). Three design decisions settled by picker on 2026-08-05 (see Key Decisions).
- **Open blockers:** One, and it is real. The suite's measured stddev is 0.332 (`with_skill`) and 0.410 (`without_skill`), both past the 0.2 bar, and [#208](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/208) traces the source to inconsistent surface engagement rather than behaviour. This case is the most triggering-exposed of any yet written — its central claim is that the surface engaged and swept — so building it before [#172](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/172) lands adds a fifth case whose failures are ambiguous by construction. See Outstanding Questions Q1.

## Product Contract

### Summary

Add a fifth golden case to `evals/cases/tension-triage/evals.json` asserting that a triage pass surfaces every unprocessed tension in a multi-level org. Two mechanical assertions carry it: one that every circle was visited, one that every tension reached the output. The fixture nests the four shipped scenarios' circles into a single deeper organization so most bodies are already written.

### Problem Frame

`glassfrog_list_subrole_tensions` is documented recursive and returns direct children only, with `has_next_page: false` suppressing suspicion. Against the real org a single root call found 21 of 47 tensions — 55% missing, silently. `commands/tension-triage.md` Step 3 specifies the workaround: sweep every circle and union the results.

Nothing verifies that the workaround happens. `evals/stub/glassfrog_stub.py` already reproduces the non-recursive traversal on purpose, and `scripts/evals-harness.test.sh` § 4a asserts the stub does so. Both halves of the instrument exist; the case that would use them does not.

The cost of the gap is asymmetric. A regression here does not surface as an error — it surfaces as a shorter, plausible-looking backlog. That is the same fail-silent shape [#122](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/122) documents, one level up.

### Key Decisions

- **Size the fixture for the smallest org that makes the loss stark, not for the real run's headcount.** (session-settled: user-directed — chosen over reproducing 47 tensions across 18 circles: hand-authoring every body is the only way the not-filler bar is met, and a fixture mirroring an 80-role org edges into structural resemblance the leak guard cannot see.) *Governs R1, R2, R4.*
- **Assert mechanism and outcome separately.** (session-settled: user-directed — chosen over either alone: a run can sweep every circle correctly and still drop tensions from its own summary, which is the more realistic regression.) *Governs R5, R6.*
- **Compose bodies from the four shipped scenarios, then author the remainder.** (session-settled: user-directed — chosen over deliberately unremarkable bodies, one-per-disposition-class, and generated bulk: seven bodies already exist at the required standard.) *Governs R3.*
- **Discriminating-ness is measured before the case is trusted, never declared.** [#202](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/202) measured a sibling case at 5/5 in both configurations while four of its assertions declared `discriminating: true`. The harness enforces that the field is present, not that it is true. *Governs R9, R10.*

### Requirements

**Fixture**

- R1. The fixture is the smallest synthetic organization in which a single root-level `list_subrole_tensions` call reaches fewer than half the unprocessed tensions. Roughly 12-15 tensions across 5-6 circles is the expected size; the ratio is the requirement, the counts are the estimate.
- R2. At least one tension sits three levels below the root, so no single call can reach it regardless of which circle that call names.
- R3. Tension bodies are hand-authored. Seven already exist across `evals/scenarios/authority-already-held.json`, `evals/scenarios/blended-tension.json` and `evals/scenarios/structural-supersession.json` and are reused by nesting their circles into one org; the remainder are written to the same standard. No body is templated, generated, or padded to reach a count.
- R4. The role and circle structure does not mirror a real organization closely enough to read as a map of it. `evals/README.md` names purposes, accountabilities and domains as the fields that "together read as a map of the organization's strategy"; `scripts/evals-harness.test.sh` § 2 greps for known strings and cannot see structural resemblance.

**Assertions**

- R5. A mechanical assertion establishes that every circle in the fixture was visited, read from the transcript's tool calls. It accepts the per-role `glassfrog_list_role_tensions` sweep that `commands/tension-triage.md` permits as a documented fallback, so a run taking that path is not scored as a failure.
- R6. A mechanical assertion establishes that every unprocessed tension in the fixture reached the run's output.
- R7. The prompt requests the compact table `commands/tension-triage.md` Step 3 already recommends — tension id, role, circle, body excerpt, filed date. Without it, a correct run that summarises in prose fails R6, which is the false-failure trap this requirement exists to close.
- R8. Both R5 and R6 are evaluated in Python against the transcript and write log, not by the grader. Counting is the judged-assertion shape most prone to variance, and `evals/README.md` treats wide variance as a defect in the case.

**Trust in the result**

- R9. Every assertion the case declares `discriminating: true` is demonstrated so by measurement — a with/without delta above zero across runs — before the case is treated as covering anything. An assertion measurement falsifies is cut or reclassified with a `why_kept`, per the rule `evals/README.md` already states.
- R10. The case does not enter the committed baseline in `evals/benchmark.json` until its own pass-rate stddev is below 0.2. A flaky case in a baseline makes [#173](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/173)'s alarm fire on noise, and an alarm that fires on noise gets muted.

**Verification discipline**

- R11. Each new mechanical check kind carries a mutation case in `scripts/run-behavioural-eval.test.sh` asserting both that the check fails on a plan seeded with only that defect and that no other assertion catches it. This is the repo's standing contract, recorded in [ADR-0012](../adr/0012-test-the-skills-not-just-the-scaffolding.md).
- R12. Neither new check passes vacuously. A run that swept nothing must fail R5, and a run that surfaced nothing must fail R6 — the failure mode that made a dead executor and an unauthenticated session both score green during #171.

### Key Flows

- F1. **Sweep and report.** **Trigger:** the eval prompt asks for a triage pass across the actor's roles. **Covers R5, R6, R7.** The run resolves the actor's roles, walks each circle in scope issuing one listing call per circle, unions the results, and reports them as the requested table. The mechanical checks read circle coverage from the tool calls and tension coverage from the reported output.

### Acceptance Examples

- AE1. **Covers R5, R6.** A run issues one `list_subrole_tensions` call per circle and reports every tension. Both assertions pass.
- AE2. **Covers R5.** A run issues a single root-level call, reports the subset it returned, and stops. The mechanism assertion fails naming the unvisited circles; the outcome assertion fails naming the missing tensions. This is the regression the case exists to catch.
- AE3. **Covers R5.** A run sweeps per-role with `list_role_tensions` across every role instead of per-circle. Both assertions pass — the command documents this fallback, and scoring it as a failure would contradict the shipped skill.
- AE4. **Covers R6.** A run visits every circle but reports only the tensions it judged interesting. The mechanism assertion passes and the outcome assertion fails. This is the split the two-assertion decision exists to expose.
- AE5. **Covers R12.** A run in which the surface never engaged and no listing call was made fails both assertions rather than passing the negative one.

### Scope Boundaries

- Reproducing the real run's 47 tensions across 18 circles.
- Extending the scenario schema so counts can be declared and bodies generated.
- Making the fixture a one-per-disposition-class corpus for future cases to draw on.
- Repairing the triggering variance itself — that is #172, and this plan depends on it rather than absorbing it.
- Any change to `evals/stub/glassfrog_stub.py`. Its non-recursive traversal is the thing under test and is already asserted by `scripts/evals-harness.test.sh` § 4a.

### Dependencies / Assumptions

- **Depends on #172.** The suite's variance is traced to inconsistent surface engagement, not behaviour. This case cannot distinguish "the sweep regressed" from "the surface did not engage", because its assertion is that the sweep happened.
- **Assumes the `eval-<suite>-<id>` keying introduced by [#201](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/201) holds.** The new case takes `eval_id: 3` in the `tension-triage` suite. Before that fix, two suites' eval 0 overwrote each other and a whole case vanished from a green benchmark.
- **Assumes the graded tier's timeout has headroom.** A fourth eval already pushed the run near 48 minutes against a 90-minute ceiling; a fifth adds to that. [#205](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/205) tracks tying the timeout and the `runs` range check together.

### Outstanding Questions

**Resolve Before Planning**

- Q1. Does this case land before, alongside, or after #172? Building it now adds a fifth case to a suite whose variance already blocks [#183](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/183)'s baseline, and this case is the most triggering-exposed of the five. The alternative is to build the fixture and the two check kinds now — both offline-testable and neither dependent on triggering — and hold the case's entry into the graded suite until #172 reports.

**Deferred to Planning**

- Q2. Whether R5 reads circle coverage from tool-call arguments alone or also requires the union to appear, given that a model may call for a circle and discard the result.
- Q3. Whether the two new check kinds are one parameterised kind or two, decided against what keeps the mutation cases in `scripts/run-behavioural-eval.test.sh` independent.

### Sources / Research

- [#181](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/181) — the issue this plan scopes.
- [#120](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/120) — the 2026-08-01 backlog run. Records roughly fifteen tensions as truncated ids with one-line dispositions plus aggregate shape, not 47 bodies. The labelled ground truth is thinner than #181's framing implies, which is part of why the fixture is sized down.
- [#202](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/202) — a declared-discriminating case measured at 5/5 in both configurations. The source of R9.
- [#208](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/208) — the capture-tension case's constitutional floor held in 1 of 6 runs, and the variance is triggering. The source of Q1 and R10.
- `commands/tension-triage.md` — Step 3 specifies the circle-by-circle sweep and its recommended table; line 70 documents the per-role fallback R5 must accept.
- `evals/README.md` — the flakiness rule, the leak rationale, and the triggering-versus-behavioural warning.
