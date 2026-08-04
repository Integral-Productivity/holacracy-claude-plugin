# Triage Gates -- Shared Reference

This is the canonical set of gates any Holacratic tension passes through before the plugin captures, routes, or processes it. It is not a workflow -- it is the constitutional checks, in the order that makes each one worth asking. Loaded by:

- The `tension-capture` subagent (every capture flow runs Gates 1--2 before drafting).
- The `/holacracy:capture-tension` slash command.
- The `/holacracy:tension-triage` slash command (readiness assessment over an existing backlog).
- The `/holacracy:supersession-sweep` slash command (Step 4 is the supersession check).
- The `holacratic-ai-governance` skill (proactive tension sensing during conversation).
- The `holacracy-rep-link` skill, whose `references/tension-triage-guide.md` extends this with Rep-Link-specific escalation logic.

Triage runs in sequence. **Stop at the first step that resolves the tension.**

> **Why authority is first.** Across 35 tensions processed in the 2026-08-01 backlog run, Step 1 fired five times and **changed the disposition every time**. Roughly a third of the inbox was work waiting on permission the role-filler already held. Knowing you can simply *do* the thing short-circuits the venue question entirely, so asking it last wastes the other gates' work. See [ADR-0011](../../docs/adr/0011-separate-tension-readiness-from-tension-disposition.md).

---

## Step 1 -- Does the authority that would resolve this already exist?

The generalised form covers both variants seen in practice:

> **As a domain you already hold, or as a role created since this tension was filed?**

Article 4 gives a role-filler unilateral authority to act within their role's domains. A tension whose resolution sits entirely inside a domain the sensing role holds needs no meeting, no proposal, and no venue -- it needs someone to do the work. And roles created *after* a tension was filed can structurally supersede it, leaving only operational work behind.

This is a distinct class of inbox debt: **authority parked as though it needed sanction.**

**Evidence.** Every one of these changed what happened to the tension:

| Tension(s) | What the check found |
|---|---|
| `ten_343f2946`, `ten_564abcab` | ◎Information Security Officer was created *after* they were filed -- structurally superseded; only operational work remained |
| `ten_03c044b3` | ◎Product Architecture held the Productboard domain outright; 21 months waiting for a meeting that was never required |
| `ten_02b1a22a`, `ten_a86c6fd8`, `ten_2a981db9` | Circle Lead defines metrics for roles in the circle -- all three resolvable without governance |
| `ten_580f803a` | ◎Platform Engineering's "boundary objects" accountability already covers the Custom Skills Platform -- the tension is energization, not structure |
| `ten_4e489b1a` | ◎Community Architect already holds both the gateway accountability and the taxonomy domain -- narrowed the governance question substantially |

**Procedure:**

1. Read the sensing role's domains and accountabilities (`glassfrog_get_role_context`, or `glassfrog_list_role_domains` for the domain list alone).
2. Ask whether resolving this tension would require acting *outside* them. If it would not, the tension is energization, not structure.
3. For older tensions, check whether a role has since been created that now covers the gap. `glassfrog_search` on the tension's subject matter surfaces this faster than reading the tree.

**Decision:**

- **Authority already exists, wholly** -> name it plainly: *"◎[Role] already holds [domain / accountability]. This doesn't need a meeting -- it needs the work done."* Offer to convert to a project or action, or to make the change directly if it is an artifact repair. Then archive the tension. **Do not route it to a venue.**
- **Authority exists but only narrows the question** -> say what it covers, restate the residual gap as the real tension, and continue to Step 2 with the narrowed framing.
- **Authority does not exist** -> continue to Step 2. This is the genuinely governable case.

**Confirmation, not automation.** Recognising that authority exists is a reading; acting on it is a write. Surface the reading, let the user decide, and never convert or archive without an explicit per-item keystroke.

> **Note on dispatch.** The disposition this gate produces -- "convert to project," "convert to action," "repair the artifact directly" -- is the province of `/holacracy:process-tension`, which does not exist yet ([#160](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/160)). Until it ships, hand the project case to `/holacracy:capture-project` and name the rest honestly for the user to act on.

---

## Step 2 -- Is this a role tension, a person tension, or both?

This is the constitutional gate. The Constitution distinguishes structural matters (governable) from interpersonal matters (the Integrative Decision Record process). Writing a person tension to the GlassFrog tension inbox pollutes the inbox and routes the issue to the wrong process.

**Role tension.** A gap between what a role is currently able to do and what it could do. Structural or operational. Governance or coordination can address it. *Example: "The Engineering Lead role has no clear accountability for approving vendor integrations, so when other roles ask for approval, there's no one to ask."*

**Person tension.** About how a specific individual is showing up in their role -- behavior, reliability, communication, follow-through. *Example: "The person filling the Lead Link role isn't following through on commitments they make in tactical meetings."*

**Decision:**

- **Role tension** -> continue to Step 3.
- **Person tension** -> **Refuse to draft `create_tension`.** Surface the IDR / direct-conversation route instead. *"That reads like a tension about how someone is showing up in their role, not about the role itself. The Integrative Decision Record process is the right path for that -- I can help you frame the conversation, but I won't write this to the GlassFrog tension inbox."*
- **Genuinely both** -> partition it. See below.

### Disguised role tensions

Sometimes what presents as a person tension is structural in disguise. Apply the substitution test:

> "If a different person energized this role tomorrow, would the same problem exist?"

If yes -- the problem is structural; reframe as a role tension and continue. If the issue is that *no governance holds the person accountable* for the missing behavior, the structural framing is: "the role's accountabilities don't require X" -- that is a governable tension. The person's behavior is downstream of the missing accountability.

### Blended tensions -- partition the body, don't fuse or refuse

Some tensions are genuinely both, and the substitution test splits them cleanly rather than resolving them either way. Refusing loses the structural half; keeping them fused makes the tension unresolvable, because no proposal can address the behavioural part.

**Worked example -- `ten_00fc5815`:**

> *"I'm unclear on my priority work... I haven't been finishing things as planned and have left some work incomplete while moving on to fresh/new/novel work."*

Applying the substitution test to each half:

| Half | Survives a change of role-filler? | Therefore |
|---|---|---|
| No mechanism makes priority visible | **Yes** -- the absence is structural | Governable |
| Novelty-seeking over completion | **No** -- it travels with the person | Not governable |

The useful move is to **keep the tension and partition the body**, marking the behavioural half explicitly out of scope for proposals:

```
[STRUCTURAL] No mechanism in this circle makes priority order visible across
roles, so competing commitments are resolved ad hoc.

[PERSONAL -- not a proposal target] I move to novel work before finishing
committed work. Noted here for my own tracking; this is self-management, not
governance.
```

`ten_00fc5815` sat unresolvable for 15 months because both halves were fused. Partitioning is what made the structural half actionable.

**Decision:** partition, then continue to Step 3 carrying **only the structural half** into venue routing.

### Carrying tensions on behalf of others

A circle member can sense a tension that belongs to another role-filler's work but cannot bring it directly. Two common cases:

- A Rep Link carries a tension from a sub-circle member who can't bring it to the enclosing circle directly.
- An Advisor-mode user surfaces a tension on behalf of someone they're helping.

When this applies, the body of the tension should explicitly preserve the chain of custody. Prepend the body with:

> `Sensed by [name], carried as [role]:`

This keeps attribution honest when the tension is later processed.

---

## Step 3 -- Which meeting venue should the user bring this to?

**Important:** This is a *suggestion for the user's mental routing*, not a field written to GlassFrog.

**Governance venue.** Needs a structural change: new role, modified accountability, new policy, domain clarification, role placement change, or removal of a constraint that governance imposes.

*Indicators:* "We don't have a role for...", "the accountability doesn't cover...", "the policy prevents...", "no one owns...", recurring ambiguity about authority.

**Tactical venue.** Needs operational coordination, a resource, a project assignment, or unblocking. The structure is fine; the work just needs to flow.

*Indicators:* "I need X to happen", "we're waiting on...", "this project is stuck because...", "can someone update...", a one-off request rather than a recurring pattern.

### Edge case: the recurring tactical pattern

A tactical tension that recurs across multiple meetings often signals a missing governance element. The strongest real instance in this org is a single structural absence -- no practice around commitment and completion -- sensed independently **four times across three roles and three years**:

| Tension | Filed | Role | Sensing |
|---|---|---|---|
| `ten_e1df0c3b` | 2024-10 | ◎Product Architecture | a delivery date with no commitment practice behind it |
| `ten_00fc5815` | 2025-04 | ◎Circle Lead | no mechanism makes priority visible; work left incomplete |
| `ten_2e600a8a` | 2026-05 | ◎Circle Lead | five projects, 11+ months without updates |
| `ten_1fc3b778` | 2026-05 | ◎Resilience Management | work miscast as a project, no update in a year |

Four sensings of one absence, surfacing wherever work is committed to. Any one of them reads tactical. Together they are unmistakably governance.

**The lesson for triage:** when a tension feels familiar, check whether it has been sensed before on *other* roles. Repetition across roles is the signal; repetition on one role is just a backlog. When in doubt, surface both framings and let the user choose.

### Encoding the venue in the record

`meeting_type` **cannot be written through the API.** The field is exposed in the `update_tension` schema and returned in every response, but the write is rejected:

| Call | Result |
|---|---|
| `update_tension({tension_id, meeting_type})` | 422 |
| `update_tension({tension_id, meeting_type, status})` | 422 |
| `update_tension({tension_id, meeting_type, body})` | 422 |
| `update_tension({tension_id, body})`, identical body | 200 OK |

Isolated systematically 2026-08-04; see [glassfrog-mcp-server#123 (comment)](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/123#issuecomment-5149496749), which **corrects the central claim in that issue's body**. It is settable in the GlassFrog UI, not through the MCP.

So if the user wants the venue encoded *in the record itself*, the mechanism is a **body prefix** -- start the body with `[GOVERNANCE]` or `[TACTICAL]` -- which keeps the backlog scannable. This is not a workaround for a stale constraint. **It is the only mechanism the API offers. Do not "fix" it to use the field.**

**Decision:**

- **Governance** -> annotate as "Suggested venue: governance" in the per-tension confirmation.
- **Tactical** -> annotate as "Suggested venue: tactical".
- **Genuinely ambiguous** -> annotate as "Suggested venue: either / unclear" and surface the ambiguity to the user.

---

## Step 4 -- Is this superseded by an existing tension?

Constitutional grounding: S.5.5.1d -- the test for whether a proposed objection is actually independent of an existing tension is "the tension would exist even if the Proposer's tension were already resolved." The same logic applies *between* tensions in the inbox: if Tension A would be fully addressed by resolving Tension B, then A is not a separate tension worth keeping.

**Procedure** (especially for `/holacracy:supersession-sweep` and during `/holacracy:tension-triage`):

1. List existing unprocessed tensions on the same role (or, for broad sweeps, on related roles in the same circle).
2. For each candidate pair, ask: "Would Tension A still exist as a felt gap if Tension B were resolved?"
3. If no -- A is superseded by B. Offer to archive A via `update_tension(status: "archived")`, or merge A's specifics into B's body.
4. If yes -- both stand.

**Important caveat.** Supersession is not the same as similarity. Two tensions can describe the same circle's structural debt from different angles, and both may be worth keeping for the role-filler's own clarity. Only collapse when the resolution of one *truly* eliminates the other.

**Successor before archive.** When a tension is superseded *structurally* -- by a role that now exists, per Step 1 -- archiving it alone can drop a live exposure that no other record carries. Write the successor on the correct role first, citing the archived original, *then* archive. This is what `ten_343f2946` and `ten_564abcab` required.

---

## Step 5 -- Is this within the actor's role authority to write?

Distinct from Step 1. Step 1 asks whether the authority to *resolve* the tension already exists. This step asks which role the tension should be *attributed to* -- it shapes the write, it does not decide the disposition.

Tensions are written *on a role*. The API requires `role_id`. The role must be one the actor fills, with one exception (see "Cross-link carrying" below).

**Procedure:**

1. Confirm the actor's role roster via `glassfrog_list_my_roles` (or the resolution procedure in `./actor-and-role-resolution.md`).
2. If the actor fills exactly one plausible sensing role for this tension's content, use it silently.
3. If multiple plausible roles, ask. Do not guess.
4. If the actor fills no role in the relevant circle, name the constraint honestly: *"You don't currently fill a role in [Circle X]. To write this to GlassFrog the tension must be attributed to a role you do fill, or escalated via someone who does (e.g., the Rep Link, or a circle member who fills the relevant role)."*

**Cross-link carrying.** When a Rep Link is carrying a sub-circle member's tension upward, the sensing role is the **Rep Link role**, not the sub-circle role. The body should use the Step 2 attribution preamble ("Sensed by [name], carried as Rep Link"). This is constitutionally correct: the Rep Link is the role through which the tension enters the enclosing circle's governance.

---

## Outputs of the gates

A tension that passes all five gates is ready to write:

- `role_id`: the sensing role resolved in Step 5
- `body`: the tension text, with topic front-loaded in the first sentence, the Step 2 attribution preamble if applicable, and the Step 2 partition markers if the tension was blended
- Suggested venue (from Step 3): annotation surfaced in the user-facing confirmation block -- *not* written to the API record

The actual call is `glassfrog_create_tension(role_id, body)`. Status defaults to `unprocessed` on the API side and is not parameterized at write time. See `./tension-capture-flow.md` for the full flow.

A tension that resolves at Step 1 is not written -- the work is done instead, and the reading is surfaced for confirmation first.

A tension that fails Step 2 is not written. A tension that fails Step 5 (no role to attribute to) is not written; the constraint is named to the user.

A tension flagged in Step 4 is kept only if the user confirms it's genuinely independent of the superseding candidate.

---

## When the gates feel heavy

If the user is mid-conversation and just wants to capture a quick tension, do not run the gates as a five-question interrogation. Run them *internally* and only surface the steps that produce a decision the user needs to make:

- **Step 1** surfaces only when the answer is yes -- when the user can already act. That is worth interrupting for; it is the difference between doing the work and queueing it. Otherwise silent.
- **Step 2** surfaces only when the tension reads like a person tension or a blended one -- otherwise silent.
- **Step 3** surfaces as the suggested meeting venue annotation in the per-tension confirmation -- the user can override; not stored on the API record.
- **Step 4** surfaces only during explicit sweep or backlog triage, not during initial capture.
- **Step 5** surfaces only when role attribution is ambiguous.

The goal is to make capturing tensions cheap and accurate, not to gate every capture behind a constitutional quiz.
