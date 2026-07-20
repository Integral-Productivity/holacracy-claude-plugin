# 8. Make role-grounding a system behavior via a session-injected, honest-by-construction directive

Date: 2026-07-20

## Status

Accepted (experimental — the first PDCA experiment of the Continuous Organizational-Context Grounding effort; superseding/escalation is decided at that experiment's Act step)

## Context

The plugin *documents* a grounding standard — before doing role-specific work, resolve the active actor and role/circle and **announce** it ("Operating as **Role of Circle**"), re-validating on pivot (`skills/shared/actor-and-role-resolution.md`). But nothing *made it hold*. The one event-driven hook (`hooks-handlers/session-start.sh`) only surfaced scheduled-routine briefings; in ordinary sessions the grounding machinery never engaged. A baseline sample found the announcement string "Operating as …" in **0 of 40** recent sessions. Grounding depended entirely on operator vigilance, and got none.

This is the Do phase of Track A / PDCA-1 (issue [#62](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/62), under parent [#60](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/60)). The riskiest assumption under test: **does a system-injected grounding directive at session start actually change model behavior?** If even a start-of-session nudge doesn't move the rate off zero, a heavier continuous per-turn detector (Track B, #61) won't either, and the effort should pivot to role-initiated work entry instead. That makes a cheap, reversible experiment the correct instrument — not a durable architectural commitment.

A hard constraint shapes the design: **a SessionStart hook is plain shell with no MCP access at fire time.** It cannot call `glassfrog_get_me`, cannot know which role is active, and therefore cannot verify that grounding occurred. This is the same limitation the routine half already documents, and it is the direct descendant of the [ADR-0004](0004-opt-in-inherited-context-in-context-command.md) scar, where a shared reference narrated "Strategy on file says…" as if inherited context were loaded when it was not. Any mechanism that *claimed* grounding from a position that cannot observe it would repeat that dishonesty.

## Decision

Inject a **role-grounding directive** at session start through the SessionStart hook's existing `hookSpecificOutput.additionalContext` envelope, governed by three invariants:

1. **Honest by construction.** The directive *demands* the load and explicitly **never claims** it happened. Its wording says so outright ("This grounding has NOT yet been performed — this directive only requests it and does not assert it happened"). The only honest evidence that grounding occurred is what the model subsequently emits into the transcript — never the hook's own text.
2. **Fail-silent / non-blocking.** A broken, empty, or gated-off directive never blocks a session. The routine-briefing path — which previously `exit 0`'d the whole hook on a missing ledger — now *falls through* so the directive can still emit, and the routine-briefing behavior is preserved byte-for-byte (its regression tests run with the directive disabled).
3. **System-fired, on by default.** No operator vigilance. Always-on maximizes signal for the experiment. Optional environment gates AND together for scoping without code changes: `HOLACRACY_GROUNDING_DIRECTIVE` (master off), `HOLACRACY_GROUNDING_REQUIRE_GLASSFROG` (inject only when a `.mcp.json` declares a glassfrog connector — a shell-detectable *proxy* for "wired", not a live-connection claim), and `HOLACRACY_GROUNDING_REQUIRE_PATH` (inject only when `$PWD` matches a regex).

Measurement is a separate, equally honest artifact: `scripts/grounding-readout.sh` greps session transcripts for the three experiment signals — resolve+announce, remit-crossing flag, chapter-mark — and prints counts and rates against the 0-baseline. It counts only literal transcript text; it is a deliberately coarse proxy, adequate for a decisive move-off-zero read, not a precise instrument.

## Consequences

- Grounding becomes a system behavior rather than a documented aspiration, with the honesty seam enforced structurally: a component that cannot observe grounding is wired so it can only ever request it.
- The experiment is cheap and reversible: one env var disables the directive; the readout gives an objective Act-step signal.
- The routine-briefing refactor (fall-through instead of early exit) is a small, tested behavioral-preservation change that future additions to the hook must respect — any new early `exit` in the briefing path would re-introduce the short-circuit bug this ADR fixed.
- The GlassFrog gate's proxy (presence of a `.mcp.json` naming glassfrog) can drift from "the connector is actually connected." That is accepted: the gate is an opt-in scoping convenience, and mislabeling it as a live-connection check would itself violate invariant 1.
- The transcript-grep readout is coarse (a transcript merely quoting "operating as" counts). A higher-fidelity structured session log is deferred to a post-MVP follow-up.

## What this ADR does NOT do

- It does **not** commit to the continuous per-turn detector (Track B, #61). Escalation there is contingent on this experiment moving the rate off zero, decided at the Act step and recorded on #60.
- It does **not** change any skill's resolution procedure — `skills/shared/actor-and-role-resolution.md` is unchanged; the directive points the session at it.
- It does **not** make the hook call GlassFrog or assert live connection state — by constitution of the honesty invariant, it cannot.
- It does **not** replace the coarse readout with structured logging; that is a separate, deferred follow-up.
