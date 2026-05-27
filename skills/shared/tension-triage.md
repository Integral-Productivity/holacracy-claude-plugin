# Tension Triage -- Shared Reference

This is the canonical triage procedure for any Holacratic tension that the plugin is about to capture, file, route, or process. Loaded by:

- The `tension-capture` subagent (every capture flow runs Step 1 before drafting).
- The `/holacracy:capture-tension` slash command.
- The `/holacracy:process-inbox` slash command (for routing existing tensions to tactical vs. governance).
- The `/holacracy:supersession-sweep` slash command (Step 3 is the supersession check).
- The `holacratic-ai-governance` skill (proactive tension sensing during conversation).
- The `holacracy-rep-link` skill, whose `references/tension-triage-guide.md` extends this with Rep-Link-specific escalation logic.

Triage runs in sequence. **Stop at the first step that resolves the tension.**

---

## Step 1 -- Is this a role tension or a person tension?

This is the constitutional gate. The Constitution distinguishes structural matters (governable) from interpersonal matters (the Integrative Decision Record process). Filing a person tension into the GlassFrog tension inbox pollutes the inbox and routes the issue to the wrong process.

**Role tension.** A gap between what a role is currently able to do and what it could do. Structural or operational. Governance or coordination can address it. *Example: "The Engineering Lead role has no clear accountability for approving vendor integrations, so when other roles ask for approval, there's no one to ask."*

**Person tension.** About how a specific individual is showing up in their role -- behavior, reliability, communication, follow-through. *Example: "The person filling the Lead Link role isn't following through on commitments they make in tactical meetings."*

**Decision:**

- **Role tension** -> Continue to Step 2.
- **Person tension** -> **Refuse to draft `create_tension`.** Surface the IDR / direct-conversation route instead. *"That reads like a tension about how someone is showing up in their role, not about the role itself. The Integrative Decision Record process is the right path for that -- I can help you frame the conversation, but I won't file this to the GlassFrog tension inbox."*

### Disguised role tensions

Sometimes what presents as a person tension is structural in disguise. Apply the substitution test:

> "If a different person energized this role tomorrow, would the same problem exist?"

If yes -- the problem is structural; reframe as a role tension and continue. If the issue is that *no governance holds the person accountable* for the missing behavior, the structural framing is: "the role's accountabilities don't require X" -- that is a governable tension. The person's behavior is downstream of the missing accountability.

### Carrying tensions on behalf of others

A circle member can sense a tension that belongs to another role-filler's work but cannot bring it directly. Two common cases:

- A Rep Link carries a tension from a sub-circle member who can't bring it to the enclosing circle directly.
- An Advisor-mode user surfaces a tension on behalf of someone they're helping.

When this applies, the body of the tension should explicitly preserve the chain of custody. Prepend the body with:

> `Sensed by [name], carried as [role]:`

This keeps attribution honest when the tension is later processed.

---

## Step 2 -- Which meeting venue should the user bring this to?

**Important:** This is a *suggestion for the user's mental routing*, not a field written to GlassFrog. The GlassFrog tension API does not have a `meeting_type` field ([glassfrog-mcp-server#58](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/58)); all tensions filed via `glassfrog_create_tension` land on a role's durable backlog regardless of venue. The user still benefits from a venue annotation in the capture confirmation, because they will bring the tension to one specific meeting agenda — but Claude is annotating their thinking, not the API record.

**Governance venue.** Needs a structural change: new role, modified accountability, new policy, domain clarification, role placement change, or removal of a constraint that governance imposes.

*Indicators:* "We don't have a role for...", "the accountability doesn't cover...", "the policy prevents...", "no one owns...", recurring ambiguity about authority.

**Tactical venue.** Needs operational coordination, a resource, a project assignment, or unblocking. The structure is fine; the work just needs to flow.

*Indicators:* "I need X to happen", "we're waiting on...", "this project is stuck because...", "can someone update...", a one-off request rather than a recurring pattern.

**Edge case: recurring tactical pattern.** A tactical tension that recurs across multiple meetings often signals a missing governance element. *"We keep asking for IT approval and waiting weeks"* might be a tactical tension once or twice, but the third time it becomes a governance tension about whether the IT Governance role's accountability needs to require response timelines or whether a new policy is needed. When in doubt, surface both framings to the user and let them choose.

**Decision:**

- **Governance** -> annotate as "Suggested venue: governance" in the per-tension confirmation.
- **Tactical** -> annotate as "Suggested venue: tactical".
- **Genuinely ambiguous** -> annotate as "Suggested venue: either / unclear" and surface the ambiguity to the user.

If the user wants the venue encoded *in the GlassFrog record itself*, they can include a body prefix (e.g., start the body with `[GOVERNANCE]` or `[TACTICAL]`) so the backlog stays scannable. That is body-level convention, not an API field.

---

## Step 3 -- Is this superseded by an existing tension?

Constitutional grounding: S.5.5.1d -- the test for whether a proposed objection is actually independent of an existing tension is "the tension would exist even if the Proposer's tension were already resolved." The same logic applies *between* tensions in the inbox: if Tension A would be fully addressed by resolving Tension B, then A is not a separate tension worth filing.

**Procedure** (especially for `/holacracy:supersession-sweep` and during `/holacracy:process-inbox`):

1. List existing unprocessed tensions on the same role (or, for broad sweeps, on related roles in the same circle).
2. For each candidate pair, ask: "Would Tension A still exist as a felt gap if Tension B were resolved?"
3. If no -- A is superseded by B. Offer to archive A via `update_tension(status: "archived")`, or merge A's specifics into B's body.
4. If yes -- both stand.

**Important caveat.** Supersession is not the same as similarity. Two tensions can describe the same circle's structural debt from different angles, and both may be worth filing for the role-filler's own clarity. Only collapse when the resolution of one *truly* eliminates the other.

---

## Step 4 -- Is this within the actor's role authority to file?

Tensions are filed *on a role*. The API requires `role_id`. The role must be one the actor fills, with one exception (see "Cross-link carrying" below).

**Procedure:**

1. Confirm the actor's role roster via `glassfrog_list_my_roles` (or the resolution procedure in `../shared/actor-and-role-resolution.md`).
2. If the actor fills exactly one plausible sensing role for this tension's content, use it silently.
3. If multiple plausible roles, ask. Do not guess.
4. If the actor fills no role in the relevant circle, name the constraint honestly: *"You don't currently fill a role in [Circle X]. To file in GlassFrog the tension must be attributed to a role you do fill, or escalated via someone who does (e.g., the Rep Link, or a circle member who fills the relevant role)."*

**Cross-link carrying.** When a Rep Link is carrying a sub-circle member's tension upward, the sensing role is the **Rep Link role**, not the sub-circle role. The body should use the Step 1 attribution preamble ("Sensed by [name], carried as Rep Link"). This is constitutionally correct: the Rep Link is the role through which the tension enters the enclosing circle's governance.

---

## Outputs of triage

A tension that passes all four steps is ready to file:

- `role_id`: the sensing role resolved in Step 4
- `body`: the tension text, with topic front-loaded in the first sentence and the Step 1 attribution preamble if applicable
- Suggested venue (from Step 2): annotation surfaced in the user-facing confirmation block — *not* written to the API record

The actual call is `glassfrog_create_tension(role_id, body)`. Status defaults to `unprocessed` on the API side and is not parameterized at file time. See `skills/shared/tension-capture-flow.md` for the full flow.

A tension that fails Step 1 is not filed. A tension that fails Step 4 (no role to file on) is not filed; the constraint is named to the user.

A tension flagged in Step 3 is filed only if the user confirms it's genuinely independent of the superseding candidate.

---

## When triage feels heavy

If the user is mid-conversation and just wants to capture a quick tension, do not run the triage as a four-question interrogation. Run it *internally* and only surface the steps that produce a decision the user needs to make:

- Step 1 surfaces only when the tension reads like a person tension -- otherwise silent.
- Step 2 surfaces as the suggested meeting venue annotation in the per-tension confirmation -- the user can override; not stored on the API record.
- Step 3 surfaces only during explicit sweep or inbox processing, not during initial capture.
- Step 4 surfaces only when role attribution is ambiguous.

The goal is to make filing tensions cheap and accurate, not to gate every capture behind a constitutional quiz.
