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

### A4 — 2026-08-04: the alarms that read the fail-loud data, and the window this experiment restarts from (issues [#122](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/122), [#150](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/150))

A1 made the failure *observable*: every payload now carries the running version, and a quiet session emits a marker instead of nothing. Observable is not the same as observed. For a day the data sat in every transcript with no consumer — which is the same position the outage occupied for two weeks, one step earlier in the chain. Two operator-local alarms close it:

- **`scripts/grounding-fire-rate-check.sh`** — counts hook-output records over a rolling window and fails when the directive's fire rate falls below a floor (default 0.9, n ≥ 10). It shells `grounding-readout.sh` rather than scanning transcripts itself, because whole-file grep cannot distinguish *the hook injected this* from *the session read it* — the error that produced the false 2.2% in #122 and the 23 false positives in #123.
- **`scripts/plugin-version-skew-check.sh`** — compares the version actually **loaded** (from the transcript stamp) against the desktop-app copy, the plugin cache, the recorded install, and `stable`. This is the check that would have caught #122 on day one.

Three properties are load-bearing, and each is the inverse of something that went wrong:

1. **`stable` is the authority, not `main` and not the newest tag.** The marketplace installs from `stable`, and a tag can exist while promotion has failed (#108).
2. **An undeterminable answer is an alarm, never a pass.** A copy predating the version stamp emits no stamp at all — exactly how v0.6.0 presented — so "cannot determine the loaded version", "zero sessions in the window", and "no channels found" all fail loudly rather than reporting clear. Reporting health from absent evidence is the failure this ADR keeps rediscovering.

   Refined on 2026-08-04 by the skew alarm's first live run, which reported four false BEHINDs and said nothing at all about the two channels #122 lived in. Two rules came out of it, and they pull in opposite directions:

   - **Silence is never acceptable.** A channel with nothing to report still emits a row. `channels_found` was 6 on that run, so even the "nothing compared" guard stayed quiet while the important probes returned empty. The guard now counts channels whose version could actually be *compared*, not rows.
   - **But not every absence is a fault.** The test is whether absence *proves* the channel is unused or only means we could not read it. Where the plugin's name is in the path (the cache) or in a key (the install record), absence is proof — report `n/a` and do not alarm. Where identity is opaque (`rpm/plugin_<ID>/`), absence among copies that do exist means we cannot tell what is running — that is the #122 condition, and it alarms.

   The second rule is not a softening of the first. An alarm that fires on every legitimate absence gets ignored, and an ignored alarm is indistinguishable from no alarm — which is what invariant 2 exists to prevent.

3. **Both alarms are demonstrated firing, not merely asserted.** Their suites reproduce the #122 condition (v0.6.0 loaded, 0.10.2 recorded, `stable` ahead of both) and drive the alarm path on every PR through fixture affordances. An alarm nobody has ever seen fire is the same fail-silent shape as no alarm.

They run **operator-local**, on the schedule that runs the weekly readout; CI runs their test suites. Transcripts and install channels live on the operator's machine, and no runner can see them.

**The standing lesson, stated because it caused layer 1 of the outage and then recurred while this amendment was being written:** *shipped* means **released, promoted to `stable`, and loaded** — not merged. PR #70 merged the directive on 2026-07-20; the next release was 2026-07-27; no session could have received it in between no matter what the handler said. `scripts/release-pr-age-check.sh` alarms on the gap.

#### The measurement window this reopens

Two start dates, because they answer different questions and only one of them survives a reword of the directive (see A3):

| window | starts | why |
| --- | --- | --- |
| **delivery** (`directive-fired`) | 2026-08-03 19:52 PDT | the verified re-install. The directive's leading line — the marker the readout derives — is unchanged across v0.10.3 → v0.12.0, so firings remain comparable across that boundary. |
| **behavior** (`resolve+announce`) | the date **v0.12.0 is verifiably loaded** | v0.12.0 changed the directive's *body*: the call it previously prescribed returned ~124k characters and was rejected for exceeding the tool-result limit, which is the most plausible explanation for the one post-fix session that did not announce. Announce rates either side of that change measure two different treatments. |

The minimum n is stated **before** the result, not after: **≥ 30 directive-fired sessions cross-repo and ≥ 7 elapsed days**, whichever is later. The prior window supported no conclusion, and choosing a threshold after seeing the number is how a null result becomes an argument.

*Corrected 2026-08-05:* that prior window was recorded as **n = 3**, and the 3 was itself an artifact. `grounding-readout.sh` dated a session by its *first* record and dropped it when that record carried no `timestamp` — which Claude Code's opening summary record routinely does not. Re-run after the repair (#175), the same shape of window reported **8 sessions where it had reported 1**, six of them carrying the v0.12.0 stamp that showed delivery working. So the true prior n is unknown and larger than 3, and every `--since-start` figure taken before #175 under-counted its denominator silently.

This does not weaken the rule above; it is the sharpest argument for it. A threshold chosen after the fact would have been chosen against a number the instrument had quietly truncated. The window opens on the post-#175 instrument, and figures from before it are not comparable to what follows.

The denominator stays "all sessions" — A2 kept always-on — so the reopened window remains comparable to the 0-of-40 pre-experiment baseline. No redefinition needed.
