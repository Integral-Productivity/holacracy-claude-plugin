# 11. Separate tension readiness from tension disposition

Date: 2026-08-04

## Status

Accepted

## Context

`/holacracy:process-inbox` shipped in v0.5 as the plugin's only surface for
working an existing tension backlog. Its own body carried the evidence that
something was wrong with it: a **"What this command does NOT do"** section
listing five prohibitions, four of which the command's users kept needing to
violate.

A live run on 2026-07-31 through 2026-08-01 worked the real backlog — 47
unprocessed tensions down to 21 — and violated four of the five, correctly each
time:

- **Filed successors.** `ten_343f2946` and `ten_564abcab` (both Nov 2024, on
  ◎Technology Architecture) had been structurally superseded by the later
  creation of ◎Information Security Officer. Archiving them alone would have
  dropped a live, material exposure, so successors were written on the correct
  role first, each citing the archived original.
- **Converted a tension to a project.** `ten_03c044b3` was a decision wholly
  inside a domain ◎Product Architecture already held. It needed no meeting at
  all. It had waited 21 months for one.
- **Converted tensions to actions**, nine of them.
- **Repaired the referenced artifact directly**, for three metric-source
  problems that were neither project nor action — the fix was an edit to the
  thing the tension complained about.

The first reading of that evidence ([#120](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/120)
item 3) was "widen the command's scope." That was the wrong conclusion drawn
from the right observation. The session did those things because the command had
**no processing sibling to hand off to**, and the workaround was about to get
encoded as the design.

The command's name promised more than it delivered, and the prohibitions were
the seam showing. Two different questions had been fused into one surface:

- *Is this tension well-formed, non-duplicate, and still real?* — a **readiness**
  question, answerable without deciding anything about the work.
- *What output does this tension become?* — a **disposition** question, which is
  where authority checks, well-formedness rubrics, and write confirmations belong.

Three further findings shaped the decision.

**The authority question is not a late check — it is the first one.** Across 35
processed tensions, the question *"does the authority that would resolve this
already exist?"* fired five times and **changed the disposition every time**:
◎Information Security Officer's existence superseding two 2024 tensions;
◎Product Architecture's Productboard domain; Circle Lead metric authority on
three tensions; ◎Platform Engineering's boundary-objects accountability;
◎Community Architect's gateway accountability. Roughly a third of the inbox was
work waiting on permission the role-filler already held. The shared reference
asked it last, as a fourth gate about *which role to attribute the write to* —
so the other three gates' work was spent on tensions that did not need a venue
at all.

**The API already enforces the architecture.** `glassfrog_create_proposal` has
signature `(tension_id required, changes optional)`. A governance proposal
cannot exist without a tension anchoring it. So a disposition router is not
merely *a* path into proposal-writing — it is the only technically valid one.
The constitutional logic (governance changes resolve tensions) and the API
contract agree.

**The plugin had already built this shape on the project side** across v0.7–v0.10
without naming it:

| | Tension | Project |
|---|---|---|
| Create | `capture-tension` ✅ | `capture-project` ✅ |
| Assess quality | `process-inbox` ⚠️ *(conflated)* | `review-project` ✅ |
| Hygiene sweep | `supersession-sweep` ✅ | `stalled-project-sweep` ✅ |
| Convert to output | **missing** | *n/a — projects don't convert* |

The project column separates "is this well-formed?" (`review-project`) from
"create one" (`capture-project`) cleanly. The tension column did not.

## Decision

**Tension readiness and tension disposition are separate concerns, handled by
separate commands, with a shared gate reference underneath.**

1. **Four stages, each answering one question.**

   ```
   /tension-triage       →  is this tension ready to be processed?
                            (the gates; archive / edit / defer)

   /process-tension      →  what output does a ready tension become?
                            (router only — dispatches, never implements)

   the write commands    →  produce that output, with its own
                            well-formedness rubric and confirm flow

   artifact-routing.md   →  where does the output land?
   ```

   This mirrors the Constitution rather than inventing a shape: in a tactical, an
   agenda item's output is next-action / project / information-shared. "Is this
   real and mine?" and "what does it become?" are different questions asked at
   different moments.

2. **`/holacracy:process-inbox` becomes `/holacracy:tension-triage`**, scoped to
   readiness only. The old name survives as a deprecated alias that dispatches to
   the new one — both are shipped on the `stable` branch the public marketplace
   tracks, so a hard rename would be a breaking change, and under
   `bump-minor-pre-major: false` that would take 0.x straight to 1.0.0. A version
   event of that size should be deliberate, not a side effect of a rename.

3. **`skills/shared/tension-triage.md` becomes
   `skills/shared/triage-gates.md`**, resolving the collision the command rename
   creates and describing the file more accurately. It is not a workflow; it is
   the constitutional gates a tension passes through.

4. **Authority becomes Gate 1**, generalised over both variants observed:
   *"Does the authority that would resolve this already exist — as a domain you
   hold, or as a role created since this was filed?"* The remaining gates
   renumber: role-vs-person → 2, venue → 3, supersession → 4, role-attribution
   → 5. Knowing you can simply *do* the thing short-circuits the venue question
   entirely.

5. **Write commands take a verb per authority class.** The verb varies because
   the authority *check* varies, and the command name should make the check
   legible before it runs:

   | Command | Authority drawn on |
   |---|---|
   | `/sense-tension` | Anyone filling the role |
   | `/commit-project`, `/commit-action` | The role's own accountabilities |
   | `/define-metric`, `/define-checklist-item` | Circle Lead of the circle containing the target role |
   | `/propose-*` | Governance process |
   | `/file-reference` | No authority claim; routes via `artifact-routing.md` |

   The gate is not "can this actor write?" but "does *this class of write* belong
   to this actor?" `/commit-action` needs no permission check — a role filler
   commits actions for their own role. `/define-metric` does.

6. **"File" is reserved for reference material** — the filing-cabinet sense —
   and the neutral verb in safeguard and mechanics prose is **"write"**.
   Holacracy's vocabulary for tensions is *sense / raise / bring / process*;
   "file a tension" is issue-tracker idiom that migrated in from adjacent
   tooling. Exactly one command in the family says "file," and it is the one
   dealing in reference material.

7. **`/process-tension` is the only path into `/propose-*`**, because the API
   makes it so. This is recorded as a decision, not merely a consequence, so
   that a future contributor does not add a standalone proposal command and
   discover at runtime that it has nothing to anchor to. See
   [ADR-0003](0003-glassfrog-tension-api-adoption.md) for the tension API
   adoption this rests on.

8. **The agenda-item command is deferred, not designed.** GlassFrog has no
   meeting-agenda API concept, and `meeting_type` is **rejected on write** —
   422 alone, with `status`, and with `body`; the identical call minus the field
   returns 200. It is settable in the GlassFrog UI only. The
   `[GOVERNANCE]` / `[TACTICAL]` body-prefix convention is therefore not a
   workaround for a stale constraint; it is the only mechanism the API offers.

## Consequences

**Easier**

- Each command can state honestly what it does, because it does one thing. The
  five-prohibition list disappears — not by widening the command, but by giving
  the prohibited work a home.
- The authority gate runs first, where it changes outcomes. A third of the
  observed inbox was authority parked as though it needed sanction; that class
  of debt is now surfaced before any venue routing happens.
- `processed` gets an honest rule. It becomes `/process-tension`'s to set,
  because that is the only command producing durable outputs: *`processed` is
  honest when a tension has produced a durable output — an action, a project, a
  governance proposal, or an executed change. It is not honest when the only
  thing that changed is the tension's status.*
- A user who types `define-metric` on a role they do not lead is told *why*
  before anything is written, and the command name already signalled that a
  Circle Lead check was coming.

**Harder**

- Five verbs instead of one. The cost is memorability. A uniform `capture-*`
  family was considered and rejected on the GTD frame — in Capture → Clarify →
  Organize, `/capture-project` is *Organize*, not Capture, so a uniform prefix
  mislabels four of six commands. A uniform `file-*` family was considered and
  withdrawn: the argument for it was that the plugin's own prose already says
  "filed" everywhere, which is evidence of a leak, not of fitness.
- Two commands where there was one means a handoff, and handoffs can drop
  things. `ten_61292811` is the cautionary case from the very session that
  identified this problem: marked `processed` on the strength of a cleanup
  action, while a second, genuinely governance question inside it survived only
  as a note on that action.
- The rename obligates a deprecation window. Alias stubs are cheap but not free,
  and they must eventually be removed in a major.
- Prose across 27 shipped files says "file" where it now means "write." The
  corpus also has ~170 legitimate filesystem uses of the word, so the sweep
  cannot be mechanical.

**Deferred**

- `/propose-*` ships able to create and circulate a draft proposal but **cannot
  express a policy change**: `changes` entries of type `CreatePolicy` require a
  numeric `domainDatabaseId` the v5 API never exposes (`get_domain` returns only
  `dom_` IDs). Stated in the command body rather than discovered at runtime.
- The agenda-item backend, per Decision 8. Unblocks when an agenda API lands,
  when `meeting_type` becomes writable, or when someone designs the
  note-maintenance convention an agenda-as-note would need.

## Related

- [ADR-0003](0003-glassfrog-tension-api-adoption.md) — tension API adoption; the
  `create_proposal` anchoring constraint. Its file paths and its deferred
  Option D name record the state at its decision time and are deliberately not
  retro-edited here.
- [ADR-0005](0005-holacracy-identity-glassfrog-as-first-connector-behind-a-seam.md)
  — the connector seam that keeps an agenda-as-calendar option outside scope.
- [ADR-0007](0007-route-artifacts-by-live-glassfrog-domains-not-a-hardcoded-table.md)
  and [ADR-0009](0009-artifact-routing-resolver-layered-domain-recognizer.md) —
  artifact routing. `/file-reference` will be the first caller of that resolver
  from the tension path.
- [#120](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/120)
  — the tracking epic, and the four comments in which this decision was reached
  and twice corrected.
