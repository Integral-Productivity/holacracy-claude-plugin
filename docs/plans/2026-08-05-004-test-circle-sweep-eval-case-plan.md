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

- **Objective:** Build the fixture and the two mechanical checks for a behavioural eval case that will prove `/holacracy:tension-triage` sweeps circle by circle and loses nothing. This round delivers them offline-verified; the case is graded, and its claim to prove anything is earned, only once [#172](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/172) lands and R11's measurement passes.
- **Product authority:** Kraig Parkinson (founder). Four design decisions settled by picker on 2026-08-05 (see Key Decisions).
- **Open blockers:** None. The sequencing is settled: the fixture and both check kinds are built now, and the case's entry into the graded suite waits on #172.

## Product Contract

### Summary

Add a fifth golden case for `/holacracy:tension-triage` asserting that a triage pass surfaces every unprocessed tension in a multi-level org. Two mechanical assertions carry it: one that every circle in the actor's scope was visited, one that every tension reached the run's own reported output. The fixture nests the shipped scenarios' circles into a single deeper organization so most bodies are already written.

### Problem Frame

`glassfrog_list_subrole_tensions` is documented recursive and returns direct children only, with `has_next_page: false` suppressing suspicion. Against the real org a single root call found 21 of 47 tensions — 55% missing, silently. `commands/tension-triage.md` Step 3 specifies the workaround: sweep every circle and union the results.

Nothing verifies that the workaround happens. `evals/stub/glassfrog_stub.py` already reproduces the non-recursive traversal on purpose, and `scripts/evals-harness.test.sh` § 4a asserts the stub does so. Both halves of the instrument exist; the case that would use them does not. That verification gap stays open in the nightly suite through this round — R12 holds the case out of grading — so nothing here should be cited as coverage until the follow-on completes.

The cost of the gap is asymmetric. A regression here does not surface as an error — it surfaces as a shorter, plausible-looking backlog. That is the same fail-silent shape [#122](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/122) documents, one level up.

### Key Decisions

- **Size the fixture for the smallest org that makes the loss stark, not for the real run's headcount.** (session-settled: user-directed — chosen over reproducing 47 tensions across 18 circles: hand-authoring every body is the only way the not-filler bar is met, and a fixture mirroring an 80-role org edges into structural resemblance the leak guard cannot see.) *Governs R1, R2, R5.*
- **Assert mechanism and outcome separately.** (session-settled: user-directed — chosen over either alone: a run can sweep every circle correctly and still drop tensions from its own summary, which is the more realistic regression.) *Governs R6, R7.*
- **Compose bodies from the shipped scenarios, then author the remainder.** (session-settled: user-directed — chosen over deliberately unremarkable bodies, one-per-disposition-class, and generated bulk: seven bodies already exist at the required standard.) *Governs R4, R15.*
- **Build the offline half now; hold the graded entry until #172.** (session-settled: user-directed — chosen over holding the issue entirely, shipping it all now, or fixing #172 first: the fixture and check kinds do not depend on triggering, while the case's score does.) The suite's measured stddev is 0.332 (`with_skill`) and 0.410 (`without_skill`), and [#208](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/208) traces it to inconsistent surface engagement rather than behaviour. A case whose central claim is that the surface engaged and swept cannot separate the two. *Governs R12.*
- **Discriminating-ness is measured before the case is trusted, never declared.** [#202](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/202) measured a sibling case at 5/5 in both configurations while four of its assertions declared `discriminating: true`. The harness enforces that the field is present, not that it is true. *Governs R10, R11.*

### Requirements

**Fixture**

- R1. The fixture is the smallest synthetic organization in which a single root-level `glassfrog_list_subrole_tensions` call reaches fewer than half the unprocessed tensions. Roughly 12-15 tensions across 5-6 circles is the expected size; the ratio is the requirement, the counts are the estimate.
- R2. At least one tension sits three levels below the root, so no single call can reach it regardless of which circle that call names.
- R3. Every circle in the fixture is reachable through the replay server's own read surface, and the actor fills at least one role in each. The replay server exposes no sub-role enumeration tool — a role carries a parent pointer and a has-subroles flag but no child list — and stub changes are out of scope, so downward discovery works only for a circle the actor fills, which the role-roster call returns, or one carrying a tension its parent's sub-role tension call surfaces. A fixture that assumes discovery the replay server cannot perform is unbuildable.
- R4. Tension bodies are hand-authored. Seven already exist across `evals/scenarios/authority-already-held.json`, `evals/scenarios/blended-tension.json` and `evals/scenarios/structural-supersession.json`, and are reused by copying them into the composed scenario, which records for each the source file and key it came from. Newly authored bodies record their own provenance the same way. No body is templated, generated, or padded to reach a count.
- R5. The role and circle structure does not mirror a real organization closely enough to read as a map of it, and the composed scenario's purpose field records that judgement — which structures were deliberately not mirrored, and why the chosen shape does not read as a map of them. `evals/README.md` names purposes, accountabilities and domains as the fields that "together read as a map of the organization's strategy"; `scripts/evals-harness.test.sh` § 2 matches known strings and cannot see structural resemblance, so a recorded judgement is the only thing a reviewer can check this against. `evals/scenarios/authority-already-held.json` already carries a binding authoring constraint in that field.

**Assertions**

- R6. A mechanical assertion establishes that every circle in the actor's scope was visited, read from the transcript's tool calls. A per-role `glassfrog_list_role_tensions` sweep satisfies it only when the transcript shows a circle-level call was attempted and failed: `commands/tension-triage.md` permits that fallback solely when the circle-level tool is unavailable, and the replay server advertises it in every run, so a per-role-only run has ignored Step 3 rather than fallen back.
- R7. A mechanical assertion establishes that every unprocessed tension in the actor's scope reached the run's own reported output. It reads only assistant-authored text and explicitly not the rendered tool-result blocks, which already contain every tension a full sweep returned.
- R8. The prompt requests the compact table `commands/tension-triage.md` Step 3 already recommends — tension id, role, circle, body excerpt, filed date. Without it, a correct run that summarises in prose fails R7, which is the false-failure trap this requirement exists to close.
- R9. Both R6 and R7 are evaluated in Python against the transcript and write log, not by the grader. Counting is the judged-assertion shape most prone to variance, and `evals/README.md` treats wide variance as a defect in the case.

**Trust in the result**

- R10. The case states its expected `without_skill` failure mode and the mechanism behind it — an unaided model accepts the root call's result because the response reports itself complete — so R11's measurement has a stated prediction to falsify rather than an unexamined assumption. Stating it also makes a cheap without-skill probe possible before the bodies are written.
- R11. Every assertion the case declares discriminating is demonstrated so by measurement — a with/without delta above zero across runs — before the case is treated as covering anything. Until that measurement exists, each assertion carries an explicit unmeasured marker citing this issue, so a later reader cannot mistake an unverified claim for a verified one. An assertion measurement falsifies is cut or reclassified with a stated reason for keeping it.
- R12. The case ships offline-verified first — authored, fixture generated, both check kinds mutation-tested — and lives at a path the graded workflow's case glob does not match, because that workflow runs every case file it finds and the runner offers no per-case exclude. Moving it into `evals/cases/tension-triage/evals.json` is itself the act that enters it into the nightly run, and happens only after #172 reports on triggering. Until then its worth is the hardening the two check kinds and their mutation cases give the runner, which holds regardless of any score. It enters the committed baseline in `evals/benchmark.json` only once its own pass-rate stddev is below 0.2; a flaky case in a baseline makes [#173](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/173)'s alarm fire on noise, and an alarm that fires on noise gets muted.

**Verification discipline**

- R13. Each new mechanical check kind carries a mutation case in `scripts/run-behavioural-eval.test.sh` asserting both that the check fails on a plan seeded with only that defect and that no other assertion catches it. This is the repo's standing contract, recorded in [ADR-0012](../adr/0012-test-the-skills-not-just-the-scaffolding.md).
- R14. Neither new check passes vacuously. A run that swept nothing must fail R6, and a run that reported nothing must fail R7 — the failure mode that made a dead executor and an unauthenticated session both score green during [#171](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/171).
- R15. `scripts/evals-harness.test.sh` asserts each copied body still matches its source verbatim. Composition is copying — the fixture generator takes one scenario and derives every id from its name — so without a check a correction lands in one copy and not the other, as one shipped scenario has already been corrected once.

### Key Flows

- F1. **Sweep and report.** **Trigger:** the eval prompt asks for a triage pass across the actor's roles. **Covers R6, R7, R8.** The run resolves the actor's roles, walks each circle in scope issuing one listing call per circle, unions the results, and reports them as the requested table. The mechanism check reads circle coverage from the tool calls; the outcome check reads tension coverage from the assistant's own reported text.

### Acceptance Examples

- AE1. **Covers R6, R7.** A run issues one sub-role tension call per circle in the actor's scope and reports every tension in its own output. Both assertions pass.
- AE2. **Covers R6, R7.** A run issues a single root-level call, reports the subset it returned, and stops. The mechanism assertion fails naming the unvisited circles; the outcome assertion fails naming the missing tensions. This is the regression the case exists to catch.
- AE3. **Covers R6.** A run sweeps per-role across every role without ever attempting a circle-level call. The mechanism assertion fails: the replay server advertises the circle-level tool, so the command's unavailability condition never held and the run ignored Step 3 rather than falling back.
- AE4. **Covers R7.** A run visits every circle but reports only the tensions it judged interesting. The mechanism assertion passes and the outcome assertion fails, because the outcome check reads the assistant's own text and not the tool results it received. This is the split the two-assertion decision exists to expose.
- AE5. **Covers R14.** A run that resolves the actor and then stops — one tool call, no listing call — fails both assertions rather than passing the negative one. A run with no tool calls at all is already an execution failure before any check runs.

### Scope Boundaries

- Reproducing the real run's 47 tensions across 18 circles.
- Extending the scenario schema so counts can be declared and bodies generated.
- Making the fixture a one-per-disposition-class corpus for future cases to draw on.
- The case's entry into the graded suite and the nightly workflow, until #172 reports. The fixture and both check kinds are in scope now; the score is not (R12).
- Repairing the triggering variance itself — that is #172, and this plan depends on it rather than absorbing it.
- Changing the replay server's traversal behaviour. Its non-recursive sub-role listing is the thing under test and is already asserted by `scripts/evals-harness.test.sh` § 4a. Adding a read log to it is a separate question (see Outstanding Questions).

### Dependencies / Assumptions

- **Depends on #172.** The suite's variance is traced to inconsistent surface engagement, not behaviour. This case cannot distinguish "the sweep regressed" from "the surface did not engage", because its assertion is that the sweep happened.
- **Depends on an upstream defect staying unfixed.** R6 asserts a per-circle traversal that exists only as a workaround for `glassfrog_list_subrole_tensions` not recursing — [glassfrog-mcp-server#122](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/122), in a repository Integral Productivity controls, whose own proposed fix is a docstring correction plus a recursive parameter. If that lands, `commands/tension-triage.md` collapses to a single recursive call and R6 starts failing correct runs. The traversal is a fixable choice, not a fixed constraint, and whoever plans this should weigh build-now against fix-upstream.
- **Assumes the suite-scoped eval directory keying introduced by [#201](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/201) holds.** The new case takes `eval_id: 3` in the tension-triage suite. Before that fix, two suites' eval 0 overwrote each other and a whole case vanished from a green benchmark.
- **Assumes the graded tier's timeout has headroom.** A fourth eval already pushed the run near 48 minutes against a 90-minute ceiling; a fifth adds to that. [#205](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/205) tracks tying the timeout and the runs range check together.

### Outstanding Questions

**Deferred to Planning**

- Q2. Whether R6 reads circle coverage from tool-call arguments alone or also requires the union to appear, given that a model may call for a circle and discard the result.
- Q3. Whether the two new check kinds are one parameterised kind or two, decided against what keeps the mutation cases in `scripts/run-behavioural-eval.test.sh` independent.
- Q4. Whether a bare-mode session emits a subagent's inner tool calls as top-level events. `commands/tension-triage.md` Step 3 recommends delegating the sweep to a subagent, so if those calls do not surface, R6 fails a run that followed the command's own advice.
- Q5. Where exactly the held case file lives between authoring and #172 reporting, and what moves it (R12 fixes the property; the path is a planning choice).
- Q6. Whether adding a read log to the replay server is a better source for R6 and R7 than reading the transcript. The write log deliberately excludes reads, so a read log would make both checks deterministic and render-independent. The scope exclusion covers traversal behaviour, not logging.
- Q7. Whether `scripts/evals-harness.test.sh` § 2 should gain entries for any real strings a newly authored body was modelled from — and whether adding a real string to a public test file is itself the exposure the list exists to prevent.
- Q8. Whether R5's judgement is a one-time authoring gate or re-made whenever the fixture is later edited.
- Q9. How R11's with/without delta is measured for a case R12 keeps out of the graded suite — whether that needs a run outside the nightly job, and who holds the key for it.
- Q10. If the upstream connector defect is fixed, whether this case is retired, rewritten against the new call shape, or kept as a guard for older servers.

### Sources / Research

- [#181](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/181) — the issue this plan scopes.
- [#120](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/120) — the 2026-08-01 backlog run. Records roughly fifteen tensions as truncated ids with one-line dispositions plus aggregate shape, not 47 bodies. The labelled ground truth is thinner than #181's framing implies, which is part of why the fixture is sized down.
- [#202](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/202) — a declared-discriminating case measured at 5/5 in both configurations. The source of R10 and R11.
- [#208](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/208) — the capture-tension case's constitutional floor held in 1 of 6 runs, and the variance is triggering. The source of R12 and of the sequencing decision.
- [glassfrog-mcp-server#122](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/122) — the upstream traversal defect this case's mechanism assertion depends on.
- `commands/tension-triage.md` — Step 3 specifies the circle-by-circle sweep and its recommended table, and conditions the per-role fallback on the circle-level tool being unavailable.
- `evals/README.md` — the flakiness rule, the leak rationale, and the triggering-versus-behavioural warning.
