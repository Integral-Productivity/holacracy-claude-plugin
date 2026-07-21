---
description: Prime Facilitator AND Secretary scope for a Governance Meeting. Resolves the actor's standing in the target circle, optionally surfaces a pre-governance-prep packet, and hands off to the skills for IDM facilitation and governance capture. Primes and waits -- does not auto-advance.
argument-hint: [circle name to focus on, optional]
---

# /holacracy:governance

Open this session in **Governance Meeting** mode for a specific circle. A Governance Meeting structurally needs both functions present -- the Facilitator protecting the Integrative Decision-Making (IDM) process and the Secretary capturing the governance output -- so this command primes **both** the `holacracy-facilitator` and `holacracy-secretary` skills together. The command primes context; the underlying skills carry the meeting flow.

## What this command does

1. **Resolve the actor's standing in the target circle** via the procedure in `skills/shared/actor-and-role-resolution.md`. Concretely: call `glassfrog_get_me` and `glassfrog_list_my_roles`, then resolve which circle this session covers.
   - If `$ARGUMENTS` was provided, treat it as a circle-name hint. Validate it against the actor's role roster; if exactly one circle matches, proceed silently with that one.
   - If the actor's roster spans multiple circles and no hint was given (or the hint is ambiguous), ask which circle. **Only the circle is ever disambiguated -- never the role.**
   - Then classify the actor into one of three cases for that circle:
     - **(a) Holds Facilitator and/or Secretary.** Prime **both** skills regardless of which Core Role they hold -- a Governance Meeting needs both functions present, and priming both is cheap and non-committal. Announce the actor's real hat(s): `Operating as **Facilitator AND Secretary of [Circle]**`, or `Operating as **Facilitator of [Circle]** -- Secretary is held by another` (and the converse).
     - **(b) Holds other role(s) in the circle but neither Core Role -- a Circle Member.** A Circle Member is a real IDM *participant*, not a bystander. Prime both skills for read-along, and orient the actor to their participant touchpoints in the governance process: presenting a tension to be processed (or noted for the agenda), answering clarifying questions, giving reactions in the reaction round, raising an objection **from their role's perspective** during the objection round, responding to the Facilitator's "what do you need to resolve your tension?", and giving feedback on proposals. The Facilitator skill's `references/governance-meeting.md` carries the IDM flow -- reference it, don't restate it here.
     - **(c) Holds no role in the circle at all.** Offer **Observer mode** (prime both skills read-along so the session can follow IDM and capture, with no recording authority) or **Advisor mode** (support whoever holds the Core Roles in that circle). Mirror `tactical.md`'s zero-role handling.
2. **Announce the resolved context** before doing anything else: which circle, and which case / hat(s) apply. This is non-negotiable -- an operator working across several circles needs to see which one's governance record this meeting lands in.
3. **Check for a pre-governance-prep routine.** Call `mcp__scheduled-tasks__list_scheduled_tasks` and filter to titles matching `holacracy/secretary/pre-governance-prep/<resolved-circle>`. If a matching routine exists and has produced recent output, surface a one-paragraph summary of that output -- this *is* the "prep packet"; there is no separate file format. If no matching routine exists, say so once -- "No pre-governance-prep routine on file for this circle (v0.3 feature)" -- and continue.
4. **Hand off to the skills for the meeting itself.** `holacracy-facilitator` carries the IDM process -- agenda building, the six IDM phases, objection testing, and integration (`references/governance-meeting.md`). `holacracy-secretary` carries governance capture -- the "Governance Meetings" capture process and the Governance Meeting output template (`references/meeting-templates.md`). Do not duplicate that content here -- hand off, as `tactical.md` does.

## Transcript at invocation (dispatch to the holacracy-coach subagent)

If the user supplies a meeting transcript when invoking the command, delegate processing to the `holacracy-coach` subagent (`subagent_type: holacracy-coach`) so the capture runs in an isolated context instead of consuming the main session's context window:

- Dispatch the coach with: task type `governance-transcript`, the transcript text, the resolved circle + actor context from the resolution step above, and a draft destination — a temporary/scratch path outside the repo working tree (governance content can contain personnel data). If you don't specify one, the coach writes to a system-temp default and reports the path back. Instruct it to run the Secretary governance-capture function and draft the Governance Meeting output (per `holacracy-secretary`'s `references/meeting-templates.md`) to that file.
- The coach is **read-only on GlassFrog**: it returns a structured summary plus the draft file path, and never files anything. Present the draft to the user for review. Anything it flags under "Needs a write" — filing adopted proposals or tensions — happens back here in the main session under explicit human confirmation. This preserves the two-stage review pattern.
- Do not build runtime "is the coach available?" detection — it is a bundled plugin subagent; dispatch directly. If GlassFrog isn't connected, the coach reports that itself and works from the supplied transcript.

This is the single localized hand-off point for transcript processing.

## Behaviour

- If GlassFrog is not connected, the Secretary skill's existing "I don't have live governance data, so I'm working from what you've shared" path handles it. This command does not re-handle disconnect.
- If the user starts narrating a governance meeting before the resolution has been announced, complete the announcement first, then resume.
- This command primes context. It does not advance into facilitating IDM or capturing governance changes on its own -- the skills own those processes. It waits for the user's first input (an agenda item, a tension to process, a transcript) before producing meeting output.
