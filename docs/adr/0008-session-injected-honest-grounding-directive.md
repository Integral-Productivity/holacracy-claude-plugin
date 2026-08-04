# 8. Make role-grounding a system behavior via a session-injected, honest-by-construction directive

Date: 2026-07-20

## Status

Accepted (experimental — the first PDCA experiment of the Continuous Organizational-Context Grounding effort; superseding/escalation is decided at that experiment's Act step)

> **Amended 2026-08-04** — see [Amendments](#amendments). The Decision and Consequences below are the record as accepted on 2026-07-20; three of their claims no longer describe the shipped system. Read the amendments before relying on this ADR.

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

## Amendments

### A1 — 2026-08-04: "fail-silent" never meant "write nothing" (issue [#122](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/122))

Invariant 2 above conflated two things, and the shipped hook took the wrong one. A hook that writes nothing to stdout leaves **no record in the transcript at all**, so "ran and had nothing to surface" is indistinguishable from "never ran."

That is not hypothetical. From 2026-07-20 the Claude desktop app loaded a **v0.6.0** copy of the plugin — predating the directive — whose handler emitted nothing. It ran every session and left no trace. The directive reached **1 of 301** sessions for two weeks and nothing surfaced it.

Invariant 2 is restated:

> **Fail-silent on *error*, never silent in *output*.** A broken or gated-off directive must never block a session. But when there is nothing to surface, the hook emits a one-line quiet marker naming the plugin version, so a transcript can always distinguish "ran with nothing to say" from "never ran."

Every payload — directive or quiet marker — now carries the running version, read from `version.txt` at fire time (`unknown` if unreadable, never blank). Diagnosing the outage required archaeology across three install channels precisely because nothing the hook emitted said which version produced it.

The version string is appended **after** the `DIRECTIVE` heredoc, never inside it: `scripts/grounding-readout.sh` derives its detection marker from the heredoc's first non-empty line at run time, and a per-release string in that block would silently break cross-window comparison.

### A2 — 2026-08-04: scoping is an opt-out, and the GlassFrog gate was dead (issue [#122](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/122))

Invariant 3's list of gates is amended by adding `HOLACRACY_GROUNDING_EXCLUDE` (`<regex>`; do **not** inject when `$PWD` matches). It is evaluated last and wins over every positive gate.

**Always-on remains the default**, and scoping is expressed as exclusion rather than as a positive gate that must be satisfied. Every opt-in form shares one property: a misconfiguration makes the directive *silently absent* — byte-for-byte the failure above, invisible for two weeks. An opt-out inverts the failure mode into something visible and one edit from fixed. Given that this whole effort exists because a silent zero went undetected, the default belongs to the option whose failure announces itself.

Measurement drove this rather than preference. A connector-declaration gate was the intuitive scoping choice and turned out close to inverted: of 139 repos under `~/GitHub`, **4** declare a GlassFrog connector, accounting for ~7% of sessions — and they are where the GlassFrog *tooling* is built, not where governed work happens. Session volume concentrates in repos that declare nothing.

Separately, the third Consequence above — that the gate's proxy "can drift from 'the connector is actually connected'" — understated the defect. `_glassfrog_declared()` probed `$CLAUDE_PLUGIN_ROOT/.mcp.json` **first**, and the plugin ships its own `.mcp.json` naming glassfrog, so the gate returned true in every directory on the machine. It was not a drifting proxy; it was dead configuration that read as a working check. It now consults only the working tree — `$PWD`, `$PWD/.claude`, and up to the enclosing git root, which also fixes its failure to match from a subdirectory.

### A3 — 2026-08-04: the readout description is pre-#123 (issue [#127](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/127))

The Decision's closing paragraph describes `scripts/grounding-readout.sh` as it was before #123/#124. It no longer greps whole transcripts. It parses JSONL and counts announcements only from **assistant-emitted** text in the anchored form `Operating as **<role> of <circle>**`, excluding template placeholders and directive echoes; it excludes subagent transcripts, sidechain records, and this repo's own sessions (`--include-self` opts back in); and it reports delivery alongside behavior (`announced / directive-fired` as well as `announced / all-sessions`), deriving the directive marker from the hook at run time and exiting 2 if it cannot find one.

The fifth Consequence — "a transcript merely quoting 'operating as' counts" — is therefore no longer true as written. A weaker version survives: an assistant verbatim-quoting a documentation example still scores.

A caveat the original Decision did not record, and which now constrains how this experiment may be read: **the readout derives its directive marker from the *current* hook source at run time.** That is deliberate — a hard-coded copy would report a confident zero after any reword, the same fail-silent shape the instrument exists to detect (the [ADR-0007](0007-route-artifacts-by-live-glassfrog-domains-not-a-hardcoded-table.md) principle: derive from live source, never a static table). The consequence is that re-running the readout over a window recorded *before* a reword under-counts `directive-fired`. **Windows are comparable only within one directive revision.** Any future change to the directive's leading line closes the current measurement window and opens a new one; treat cross-revision comparisons as invalid rather than as a change in behavior.

Folded into this amendment rather than raised as a competing edit, per #127's own sequencing note.
