# 3. Generalize tension capture to cross-role, out-of-meeting use

Date: 2026-05-27

## Status

Accepted

## Context

Two recent commits on `main` set the stage for this decision:

- **v0.2.1** (`92f1477`, `feat: add /holacracy:tactical command + backlog-first capture`)
  established the durable role-backlog filing primitive via
  `glassfrog_create_tension(role_id, body)`, and encoded it in the
  Secretary skill's tactical-meeting capture flow. Motivated by a
  real incident on 2026-05-27 where six meeting-queued tensions were
  lost to a GlassFrog meeting timeout — the meeting-UI triage queue
  is ephemeral; the role backlog is durable.
- **v0.2.2** (`67f1c14`, `docs: bring glassfrog API constraints
  current with supported tension/project/action tools`) corrected
  `skills/holacratic-ai-governance/references/glassfrog-api-constraints.md`
  to reflect that tension filing, project creation, and action
  creation are now supported via MCP, narrowed the remaining hard
  boundary to meeting-association
  ([glassfrog-mcp-server#60](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/60)),
  and reframed the architectural rationale as "human-sensed, AI-mediated"
  to match the Secretary co-pilot behaviour.

The v0.2.1/v0.2.2 work answers the question *"how does the Secretary
co-pilot capture tensions during a tactical meeting?"*. It does not
answer:

- **What happens between meetings.** A role-filler senses a tension in
  the middle of code work, a calendar review, an email thread. The
  Secretary tactical flow is not the right surface — the user isn't
  in a tactical meeting.
- **What happens across roles.** A user fills multiple roles across
  multiple circles. The Secretary flow scopes to one Secretary role
  in one circle. A general-purpose capture surface should attribute to
  any role the actor fills.
- **What happens after a flood of in-flow capture.** When the proactive
  ambient sensing pattern surfaces three tensions in one conversation,
  some of them overlap. Without a deduplication primitive, the inbox
  grows faster than the user can triage it.

This ADR records the decision to fill those gaps in v0.3.0 with a
generalized capture flow, a cross-session supersession primitive, and
an ambient-detection pattern in the operating-frame skill.

## Decision

The plugin generalizes tension capture beyond the Secretary's
in-tactical-meeting flow with three artifacts and one design
contract.

### Artifacts

- **`agents/tension-capture.md`** — bundled subagent that resolves
  sensing role from the actor's full role roster (any role, any
  circle), applies the role-vs-person triage gate from
  `skills/shared/tension-triage.md` Step 1, drafts the body
  (topic-front-loaded since there is no `label` field), presents a
  single per-tension confirmation block, and on approval calls
  `glassfrog_create_tension(role_id, body)`. Captures the response ID
  into a session-tension cache for end-of-session supersession sweep.
- **`/holacracy:capture-tension`** — explicit slash command that
  dispatches the subagent. The cross-role, out-of-meeting companion
  to `/holacracy:tactical` (which is Secretary-scoped, in-meeting).
- **`/holacracy:process-inbox`** — review and triage existing
  unprocessed tensions on the actor's roles. Per-tension actions:
  archive false positives (`update_tension(status: "archived")`),
  mark processed catch-up (`update_tension(status: "processed")`,
  only for tensions actually worked in real meetings), edit body
  (`update_tension(body: ...)`), or defer.
- **`/holacracy:supersession-sweep`** — apply S.5.5.1d
  (the objection-independence test) across tensions in scope; offer
  to archive or merge subsumed ones. Default scope is `session`,
  which reads the session-tension cache.

### Design contract: the draft-and-confirm B-flow

Specified in `skills/shared/tension-capture-flow.md`. Three rules:

1. **Per-tension human confirmation, always.** No auto-file. Even when
   the user has just stated an unambiguous explicit tension, the
   subagent presents the per-tension confirmation block and waits
   for `y`/`e`/`n`. Option D (auto-file from explicit human statements)
   is deferred to v0.4 with its own ADR.
2. **Role-vs-person triage gate.** The subagent refuses to file
   person tensions and surfaces the IDR / direct-conversation route
   instead. Non-negotiable.
3. **AI-agent self-filing deferred.** When a scheduled routine fires
   as an AI-agent role-filler (per the actor model in
   `skills/shared/actor-and-role-resolution.md`), the agent could in
   principle file tensions on its own role. The constitutional
   question — does an AI-agent role-filler have analogous "lived
   experience" for filing? — is not resolved. v0.3 queues
   agent-detected tensions for human confirmation in the next
   interactive session. v0.4 will revisit with its own ADR.

The constitutional safeguard:

> Draft and confirm only. Do not call `glassfrog_create_tension`,
> `glassfrog_update_tension`, or `glassfrog_delete_tension` without
> explicit human confirmation. Do not process tensions on the
> human's behalf.

### Relationship to the v0.2.1 Secretary flow

The Secretary's in-tactical-meeting backlog-first capture
(`/holacracy:tactical` + `skills/holacracy-secretary/SKILL.md`
"Backlog-first tension capture") remains the canonical surface for
*in-meeting* tension capture. The v0.3 work adds a *parallel* surface
for everything else. Both call the same `glassfrog_create_tension`
primitive; they differ in conversational shape and consent contract.

- The Secretary flow takes consent from the live tactical-meeting
  context: a Circle Member names the tension out loud during triage,
  and the Secretary captures it. The consent is the social fact of
  the meeting.
- The cross-role flow takes consent from an explicit per-tension
  confirmation block. There is no meeting context to ground consent,
  so the contract surfaces it as an explicit user keystroke.

Both honour the same constitutional principle (humans author
tensions; AI captures on their behalf). The two surfaces are
appropriate to their contexts.

### What this ADR does NOT do

- **Option D (auto-file from explicit human tension statements).**
  Deferred to v0.4. Graduation conditions in
  [issue #14](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/14).
- **AI-agent self-filing during scheduled routines.** Deferred to
  v0.4. Constitutional question in
  [issue #15](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/15).
- **UserPromptSubmit hook for tension detection.** Considered and
  rejected for v0.3 because (a) hooks cannot call MCP and so cannot
  act on what they detect, and (b) skill-driven attention preserves
  the conversational quality of the offer. Filed for revisit in
  [issue #16](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/16).
- **Surface tension history in `/holacracy:context`.** Deferred to
  keep `/holacracy:context` cheap. Filed in
  [issue #17](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/17).

## Consequences

### Positive

- Capture is available everywhere a Holacratic tension might be
  sensed, not just in tactical meetings. Code work, calendar review,
  email triage — all gain the same draft-and-confirm surface.
- The supersession primitive (`/holacracy:supersession-sweep`)
  protects against inbox bloat that the ambient-detection pattern
  would otherwise cause.
- The two capture surfaces (Secretary in-meeting, cross-role
  out-of-meeting) compose cleanly. Both call the same API primitive;
  both honour the same constitutional principle through context-
  appropriate consent contracts.
- The doc surface stays honest. `glassfrog-api-constraints.md`
  is now the single source of truth on what the API supports, and
  the new work references it rather than restating what it claims.

### Negative / risks

- **Per-tension confirmation friction.** Users who file many tensions
  per session will feel the confirmation prompt. v0.3 ships strict
  (every file confirmed) and observes whether the friction is high
  enough to justify Option D. Issue #14 captures the graduation
  conditions.
- **Wrong-role attribution.** The subagent infers the sensing role
  from conversation context and the actor's role roster. Inference
  is sometimes wrong. The confirmation block surfaces the inferred
  role so the user can correct it.
- **Same-session list-back is unreliable.** This is a property of
  the underlying API, not the new surface. The session-tension cache
  pattern compensates: the subagent stores response IDs locally and
  `/holacracy:supersession-sweep`'s `session` scope reads from the
  cache rather than from `list_role_tensions`. This is documented
  in the constraints file and reiterated in the capture-flow spec.
- **Two capture surfaces.** New users may be unsure whether to run
  `/holacracy:tactical` or `/holacracy:capture-tension`. The
  README's command list disambiguates: tactical for in-meeting
  Secretary capture, capture-tension for everything else. If
  confusion becomes a real signal, we can collapse later — but
  collapsing is one ADR away and the two surfaces serve different
  needs today.

### Operational implications

- New artifacts shipped: `agents/tension-capture.md`,
  `commands/capture-tension.md`, `commands/process-inbox.md`,
  `commands/supersession-sweep.md`, `skills/shared/tension-triage.md`,
  `skills/shared/tension-capture-flow.md`.
- Modified artifacts:
  `skills/holacratic-ai-governance/SKILL.md` (Pattern 5 proactive
  detection, session-close supersession offer, tensions row in the
  MCP tools table), `skills/holacratic-ai-governance/references/engagement-patterns.md`
  (Pattern 3 extended with per-finding capture; full Pattern 5
  implementation guide added), `skills/holacracy-rep-link/references/tension-triage-guide.md`
  (cross-reference to the new shared triage), `.claude-plugin/plugin.json`
  (0.2.2 → 0.3.0), `README.md` (new commands documented,
  relationship to `/holacracy:tactical` made explicit).
- Four follow-up issues filed: #14 (Option D), #15 (AI-agent
  self-filing), #16 (UserPromptSubmit hook), #17 (tension history
  in `/holacracy:context`).

## Notes

The constitutional grounding for the supersession sweep is S.5.5.1d
(objection-independence test). The same logic that determines
whether an objection is genuinely separate from a proposer's
tension determines whether two tensions in an inbox are separate.
This is documented in `skills/shared/tension-triage.md` Step 3 and
referenced from `commands/supersession-sweep.md`.

The hook-cannot-call-MCP constraint — documented in
`hooks-handlers/session-start.sh` — is the reason the supersession
sweep is Claude-driven rather than fired automatically by a Stop
hook. A Stop hook could in principle read the local session-tension
cache and emit a hint, but it cannot itself archive or merge
tensions; the human-in-the-loop write must happen in the main
thread or a subagent. The implicit Claude-driven offer plus the
explicit slash command cover the use case without needing
additional hook machinery.

The `create_tension` signature is `(role_id, body)` only — `label`
and `meeting_type` are not part of the stable schema
([glassfrog-mcp-server#58](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/58)).
Suggested meeting venue is annotated for the user's mental routing
but not written to the API record. Users who want venue encoded in
the GlassFrog record can prepend `[GOVERNANCE]` or `[TACTICAL]`
to the body — body-level convention, not an API field.
