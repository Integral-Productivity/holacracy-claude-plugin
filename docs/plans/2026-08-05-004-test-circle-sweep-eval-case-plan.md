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

- **Objective:** Build the fixture and the two mechanical checks for a behavioural eval case that will prove `/holacracy:tension-triage` sweeps circle by circle and loses nothing. This round delivers them offline-verified. The case enters the graded suite, and earns its claim to prove anything, only after [#172](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/172) lands and R11's measurement passes.
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

- **Size the fixture for the smallest org that makes the loss stark, not for the real run's headcount.** (session-settled: user-directed — chosen over reproducing 47 tensions across 18 circles: hand-authoring every body is the only way the not-filler bar is met, and a fixture mirroring an 80-role org edges into structural resemblance the leak guard cannot see.) *Governs R1, R2, R4, R5.*
- **Assert mechanism and outcome separately.** (session-settled: user-directed — chosen over either alone: a run can sweep every circle correctly and still drop tensions from its own summary, which is the more realistic regression.) *Governs R6, R7.*
- **Compose bodies from the shipped scenarios, then author the remainder.** (session-settled: user-directed — chosen over deliberately unremarkable bodies, one-per-disposition-class, and generated bulk: seven bodies already exist at the required standard.) *Governs R4, R15.*
- **Build the offline half now; hold the graded entry until #172.** (session-settled: user-directed — chosen over holding the issue entirely, shipping it all now, or fixing #172 first: the fixture and check kinds do not depend on triggering, while the case's score does.) The suite's measured stddev is 0.332 (`with_skill`) and 0.410 (`without_skill`), and [#208](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/208) traces it to inconsistent surface engagement rather than behaviour. A case whose central claim is that the surface engaged and swept cannot separate the two. *Governs R12.*
- **The mechanism check reads a replay-server read log, not the transcript.** (session-settled: user-directed — chosen over keeping both checks on the transcript, splitting the sources, or deferring to planning: a log records each call's tool and arguments independent of how the transcript renders and of whether the call came from a subagent.) It also retires the question of whether a bare-mode session surfaces a subagent's inner tool calls, which `commands/tension-triage.md` Step 3 makes load-bearing by recommending delegation. *Governs R6, R9.*
- **The leak record describes the synthetic shape and names nothing real.** (session-settled: user-directed — chosen over dropping the record for a structural check, or constraining content without asserting presence: naming which real structures were avoided means naming real structures, in a field the generator copies into a second committed file.) *Governs R4, R5, R15.*
- **Discriminating-ness is measured before the case is trusted, never declared.** [#202](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/202) measured a sibling case at 5/5 in both configurations while four of its assertions declared `discriminating: true`. The harness enforces that the field is present, not that it is true. *Governs R10, R11.*

### Requirements

**Fixture**

- R1. The fixture is the smallest synthetic organization in which a single root-level `glassfrog_list_subrole_tensions` call reaches fewer than half the unprocessed tensions. Roughly 12-15 tensions across 5-6 circles is the expected size; the ratio is the requirement, the counts are the estimate.
- R2. At least one tension sits three levels below the root, so no single root-level call reaches it. A call naming the intermediate circle does reach it — the replay server returns the direct children of whatever role a call names — so it is R1's ratio, not depth alone, that forces a sweep.
- R3. Every circle in the fixture is reachable through the replay server's own read surface, and the actor fills at least one role in each. The replay server exposes no sub-role enumeration tool — a role carries a parent pointer and a has-subroles flag but no child list — and stub changes are out of scope, so downward discovery works only for a circle the actor fills, which the role-roster call returns, or one carrying a tension its parent's sub-role tension call surfaces. A fixture that assumes discovery the replay server cannot perform is unbuildable.
- R4. Tension bodies are hand-authored. Seven already exist across `evals/scenarios/authority-already-held.json`, `evals/scenarios/blended-tension.json` and `evals/scenarios/structural-supersession.json`, and are reused by copying them into the composed scenario, which records for each the source file and key it came from. Recorded provenance is limited to in-repo identifiers — a scenario file and a key — and never references a real tension, role, circle, domain, or organization record; a newly authored body records the scenario and key it is authored at. Recording it at all requires adding a spec-only `source` key to `TENSION_SPEC_KEYS` in `scripts/glassfrog-fixture-gen.py`, and that generator change is in scope: the generator treats an unrecognized spec key as an error and writes no fixture, while the key must stay spec-only because generated tension objects are validated against the captured live schema, which has no such field. No body is templated, generated, or padded to reach a count.
- R5. The role and circle structure does not mirror a real organization closely enough to read as a map of it, and the composed scenario's purpose field records that judgement by describing the synthetic org's own shape and the general categories of resemblance avoided — depth, fan-out, naming style, domain-to-tension adjacency. It names no real circle, role, domain, accountability, or purpose. That constraint is the requirement, not a stylistic preference: `scripts/glassfrog-fixture-gen.py` copies the purpose field verbatim into the generated fixture, so anything written there lands in two committed files in a public repository, one of which states it contains no data from any real organization. No entry is added to `scripts/evals-harness.test.sh` § 2's match list for a string a body was modelled from — a body that would need one is re-authored until it does not, because a growing needle list is the redaction-shaped control `evals/README.md` rejected in favour of the structural property.

**Assertions**

- R6. A mechanical assertion establishes that every circle in the actor's scope was visited, read from a read log the replay server writes — the same mechanism as its existing write log, recording each call's tool name and arguments. The log is independent of transcript rendering and of whether a call originated inside a subagent, which is what makes the assertion deterministic. No per-role-only run satisfies it: `commands/tension-triage.md` conditions the `glassfrog_list_role_tensions` fallback on the circle-level tool being absent from the session, the replay server advertises it in every run, and the server has no error path for it — so R6 specifies no acceptance branch for a run that never attempts a circle-level call.
- R7. A mechanical assertion establishes that every unprocessed tension in the actor's scope reached the run's own reported output. It reads an assistant-text projection built from the event stream, not the rendered transcript — that string interleaves tool-result blocks which already contain every tension a full sweep returned, so a check reading it would pass on the run AE4 exists to fail.
- R8. The prompt requests the compact table `commands/tension-triage.md` Step 3 already recommends — tension id, role, circle, body excerpt, filed date. Without it, a correct run that summarises in prose fails R7, which is the false-failure trap this requirement exists to close.
- R9. Both R6 and R7 are evaluated in Python, not by the grader, against three named inputs: the replay server's read log for R6, an assistant-text projection built from the event stream for R7, and the existing write log. `run_check` in `scripts/run-behavioural-eval.py` today receives only the write log and one flattened transcript string, so widening its inputs and building the projection are part of this work rather than assumed. Counting is the judged-assertion shape most prone to variance, and `evals/README.md` treats wide variance as a defect in the case.

**Trust in the result**

- R10. The case states its expected `without_skill` failure mode and the mechanism behind it — an unaided model accepts the root call's result because the response reports itself complete — so R11's measurement has a stated prediction to falsify rather than an unexamined assumption. Stating it also makes a cheap without-skill probe possible before the bodies are written.
- R11. Every assertion the case declares discriminating is demonstrated so by measurement — a with/without delta above zero across runs — before the case is treated as covering anything. Until that measurement exists, each assertion carries an explicit unmeasured marker citing this issue, and `load_case_file` in `scripts/run-behavioural-eval.py` rejects any assertion declaring itself discriminating that carries neither the marker nor a recorded measurement — the same enforcement it already applies to a non-discriminating assertion's stated reason. A marker nothing checks is a comment, which reproduces the defect [#202](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/202) names. An assertion measurement falsifies is cut or reclassified with a stated reason for keeping it.
- R12. The case ships offline-verified first — authored, fixture generated, both check kinds mutation-tested — and lives at a path the graded workflow's case glob does not match, because that workflow runs every case file it finds and the runner offers no per-case exclude. **The held case stays under every offline guard by explicit path.** That glob is not the graded job's alone: `.github/workflows/skills-eval.yml` uses it for the credential-free validate-and-probe step and for deriving the runs ceiling, and § 6 of `scripts/run-behavioural-eval.test.sh` uses it on every PR for the stale-id guard and the fixture probe. Held behind the glob alone, the case would get no CI coverage at all and the first run to check it would be the paid one it was held back from — so the held path is passed explicitly to those offline guards, and only the graded job's list omits it. Moving it into `evals/cases/tension-triage/evals.json` is itself the act that enters it into the nightly run, and happens only after #172 reports on triggering. Until then its worth is the hardening the two check kinds and their mutation cases give the runner, which holds regardless of any score. It enters the committed baseline in `evals/benchmark.json` only once its own pass-rate stddev is below 0.2; a flaky case in a baseline makes [#173](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/173)'s alarm fire on noise, and an alarm that fires on noise gets muted.

**Verification discipline**

- R13. Each new mechanical check kind carries a mutation case in `scripts/run-behavioural-eval.test.sh` asserting both that the check fails on a plan seeded with only that defect and that no other assertion catches it. This is the repo's standing contract, recorded in [ADR-0012](../adr/0012-test-the-skills-not-just-the-scaffolding.md).
- R14. Neither new check passes vacuously. A run that swept nothing must fail R6, and a run that reported nothing must fail R7 — the failure mode that made a dead executor and an unauthenticated session both score green during [#171](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/171).
- R15. `scripts/evals-harness.test.sh` asserts each copied body still matches its source verbatim, and that the composed scenario's purpose field is present and non-empty. Composition is copying — the fixture generator takes one scenario and derives every id from its name — so without a check a correction lands in one copy and not the other, as one shipped scenario has already been corrected once. The purpose assertion is what stops R5's judgement from being satisfied by a placeholder: § 2 matches known strings and would see nothing wrong with an empty field, returning the leak property to the unverified state this plan started from.

### Key Flows

- F1. **Sweep and report.** **Trigger:** the eval prompt asks for a triage pass across the actor's roles. **Covers R6, R7, R8.** The run resolves the actor's roles, walks each circle in scope issuing one listing call per circle, unions the results, and reports them as the requested table. The mechanism check reads circle coverage from the tool calls; the outcome check reads tension coverage from the assistant's own reported text.

### Acceptance Examples

- AE1. **Covers R6, R7.** A run issues one sub-role tension call per circle in the actor's scope and reports every tension in its own output. Both assertions pass.
- AE2. **Covers R6, R7.** A run issues a single root-level call, reports the subset it returned, and stops. The mechanism assertion fails naming the unvisited circles; the outcome assertion fails naming the missing tensions. This is the regression the case exists to catch.
- AE3. **Covers R6.** A run sweeps per-role across every role without ever attempting a circle-level call. The mechanism assertion fails: the read log shows no circle-level call, and the replay server advertised that tool throughout, so the command's absence condition never held and the run ignored Step 3 rather than falling back.
- AE4. **Covers R7.** A run visits every circle but reports only the tensions it judged interesting. The mechanism assertion passes and the outcome assertion fails, because the outcome check reads the assistant's own text and not the tool results it received. This is the split the two-assertion decision exists to expose.
- AE5. **Covers R14.** A run that resolves the actor and then stops — one tool call, no listing call — fails both assertions rather than passing the negative one. A run with no tool calls at all is already an execution failure before any check runs.

### Scope Boundaries

- Reproducing the real run's 47 tensions across 18 circles.
- Extending the scenario schema so counts can be declared and bodies generated. The spec-only provenance key R4 requires is a different change and is in scope.
- Scope selection. R3 puts the actor in every circle, so no out-of-scope circle or tension exists in the fixture and a run that ignored scope entirely would pass R6 and R7 identically to a correctly-scoped one. The case covers enumeration, not the judgement about which circles are in scope.
- Making the fixture a one-per-disposition-class corpus for future cases to draw on.
- The case's entry into the graded suite and the nightly workflow, until #172 reports. The fixture and both check kinds are in scope now; the score is not (R12).
- Repairing the triggering variance itself — that is #172, and this plan depends on it rather than absorbing it.
- Changing the replay server's **traversal** behaviour. Its non-recursive sub-role listing is the thing under test and is already asserted by `scripts/evals-harness.test.sh` § 4a. Adding the read log R6 reads is a different change and is in scope: it records calls without altering what any call returns.

### Dependencies / Assumptions

- **Depends on #172.** The suite's variance is traced to inconsistent surface engagement, not behaviour. This case cannot distinguish "the sweep regressed" from "the surface did not engage", because its assertion is that the sweep happened.
- **Depends on an upstream defect staying unfixed.** R6 asserts a per-circle traversal that exists only as a workaround for `glassfrog_list_subrole_tensions` not recursing — [glassfrog-mcp-server#122](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/122), in a repository Integral Productivity controls, whose own proposed fix is a docstring correction plus a recursive parameter. If that lands, `commands/tension-triage.md` collapses to a single recursive call and R6 starts failing correct runs. The traversal is a fixable choice, not a fixed constraint, and whoever plans this should weigh build-now against fix-upstream.
- **Assumes the suite-scoped eval directory keying introduced by [#201](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/201) holds.** The new case takes `eval_id: 3` in the tension-triage suite. Before that fix, two suites' eval 0 overwrote each other and a whole case vanished from a green benchmark.
- **The measurement in R11 runs by `workflow_dispatch`, not by the nightly job.** R11 requires a with/without delta while R12 holds the case out of the graded suite, so the route is named rather than left circular: a dispatch run of `.github/workflows/skills-eval.yml` with the held case path added to the graded job's case list. `ANTHROPIC_API_KEY` exists as a repository secret, so the precondition is met; whoever runs it is the operator who holds repository access.
- **Assumes the graded tier's timeout has headroom.** A fourth eval already pushed the run near 48 minutes against a 90-minute ceiling; a fifth adds to that. [#205](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/205) tracks tying the timeout and the runs range check together.

### Outstanding Questions

**Deferred to Planning**

- Q2. Whether R6 treats a circle as visited on the call alone, or requires the returned tensions to reach the union, given that a model may call for a circle and discard the result. The read log records the call either way.
- Q3. Whether the two new check kinds are one parameterised kind or two, decided against what keeps the mutation cases in `scripts/run-behavioural-eval.test.sh` independent.
- Q5. Which exact path the held case file occupies between authoring and #172 reporting. R12 fixes the properties it must satisfy — outside the graded glob, inside the offline guards — and the path itself is a planning choice.
- Q8. Whether R5's judgement is a one-time authoring gate or re-made whenever the fixture is later edited.
- Q10. If the upstream connector defect is fixed, whether this case is retired, rewritten against the new call shape, or kept as a guard for older servers.

### Sources / Research

- [#181](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/181) — the issue this plan scopes.
- [#120](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/120) — the 2026-08-01 backlog run. Records roughly fifteen tensions as truncated ids with one-line dispositions plus aggregate shape, not 47 bodies. The labelled ground truth is thinner than #181's framing implies, which is part of why the fixture is sized down.
- [#202](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/202) — a declared-discriminating case measured at 5/5 in both configurations. The source of R10 and R11.
- [#208](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/208) — the capture-tension case's constitutional floor held in 1 of 6 runs, and the variance is triggering. The source of R12 and of the sequencing decision.
- [glassfrog-mcp-server#122](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/122) — the upstream traversal defect this case's mechanism assertion depends on.
- `commands/tension-triage.md` — Step 3 specifies the circle-by-circle sweep and its recommended table, and conditions the per-role fallback on the circle-level tool being unavailable.
- `evals/README.md` — the flakiness rule, the leak rationale, and the triggering-versus-behavioural warning.
