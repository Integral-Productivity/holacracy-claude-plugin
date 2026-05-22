# Holacracy Actor and Role Resolution -- Shared Reference

This document is shared across all holacracy skills. It defines how a skill resolves *who* is operating (the **actor**) and *which* role + circle they are operating from (the **role context**) before performing any work.

Holacracy depends on the role/soul distinction: a person *energizes* a role but is not identical to it. The same person can fill many roles across many circles. An AI agent can also be a role-filler in its own right. A skill that doesn't know which role context it's operating in will produce ungrounded, generic work. This document is the procedure that prevents that.

Load this when a role skill begins a session, when a scheduled routine fires and needs to assert its acting role, when a slash command starts that depends on actor identity, or when ambiguity arises mid-conversation about which role's authority is in play.

---

## The Actor Model

A skill always operates on behalf of exactly **one actor per session**. The actor is either:

- **A person.** A human Partner of the Holacracy-governed organization. Most interactive sessions have a human actor.
- **An AI agent.** A first-class actor type in GlassFrog (queryable via `glassfrog_list_agents`, `glassfrog_get_agent`). AI agents can be assigned to roles via `glassfrog_assign_actor_to_role`, exactly like people. Most scheduled routines have an agent actor.

This is not just terminology -- GlassFrog's data model treats people and agents as distinct entities. Routines that fire under an AI agent identity produce work attributed to that agent in audit trails, separately from any human's work.

### Where the actor identity comes from

| Invocation context | How the actor is resolved |
|---|---|
| Interactive session, user is logged into Claude with their GlassFrog credentials | `glassfrog_get_me` returns the human actor. This is the default. |
| Interactive session, user is helping a different person | User states the actor explicitly: "I'm helping Alex prep for tactical." The skill operates as if the actor is Alex (Observer/Advisor mode -- see below). |
| Scheduled routine fires | The routine's prompt declares the acting AI agent at creation time. The skill trusts that declaration and operates as that agent. |
| Slash command invoked | Same resolution as the underlying session context. `/holacracy:context` is the explicit override. |

### What the plugin does NOT do

- The plugin does **not auto-create** AI agents in GlassFrog. AI agents must already exist (registered in the GlassFrog UI) and be assigned to the relevant role before any routine references them.
- The plugin does **not persist** resolved actor identity across sessions. Each interactive session resolves fresh via `glassfrog_get_me`; each scheduled routine carries its identity in its own prompt.
- The plugin does **not** assume the human is the actor when GlassFrog is unavailable. It names the limitation: "I don't have live actor data -- who should I treat as the actor for this session?"

---

## The Role-Context Resolution Procedure

When a role skill is invoked, run this procedure **before** producing any role-specific output. It costs at most two tool calls and dramatically improves the grounded quality of every subsequent response.

### Step 1 -- Confirm actor identity

If actor identity has not yet been resolved this session:

1. Call `glassfrog_get_me`. If it returns a person/agent, that is the actor. Note the actor name and id.
2. If `glassfrog_get_me` fails or returns nothing, ask the user: "Which actor should I treat as the basis for this session? (your own GlassFrog identity, or someone you're supporting?)"

If GlassFrog is not connected at all, name the constraint: "I don't have live GlassFrog data, so I'm working from what you tell me. Whose role-context should I treat as primary?"

### Step 2 -- Load the actor's role roster

Call `glassfrog_list_my_roles` (or, if operating on behalf of someone else, the appropriate filtered `list_roles` query for that person). This returns every role the actor currently fills, each scoped to a circle.

### Step 3 -- Resolve to a single role + circle

The skill's purpose narrows the resolution. For example, `holacracy-secretary` cares only about roles named "Secretary" (or sub-circle Secretary equivalents). For each role skill, there is a target role name.

Apply the **silent-when-obvious + ascertain-vs-ask + announce-the-result** policy:

| Situation | Action |
|---|---|
| Actor fills the target role in exactly one circle | Proceed silently with that circle. Announce the resolved context in the first response: "Operating as **Secretary of [Circle Name]**." |
| Actor fills the target role in multiple circles | Ask: "You hold [Role] in [Circle A], [Circle B], and [Circle C]. Which one is this about?" Then proceed. |
| Actor does not fill the target role anywhere | Name it clearly. Offer Advisor or Observer mode: "You don't currently fill the [Role] role in any circle. Do you want to (a) explore how the role works, (b) prepare for taking on the role, or (c) advise someone else who fills it?" |
| The user named the circle in their prompt | Use it as the resolution signal. Validate against the actor's role roster: if it's a circle the actor fills the role in, use it silently; if not, name the mismatch. |
| User explicitly overrides via `/holacracy:context` | Use the override. Announce the override is active. |

### Step 4 -- Announce the resolved context (always)

Every response that uses the resolved context names it in the opening lines. Examples:

- "Operating as **Secretary of Operations Circle**. Pulling the checklist and metrics now..."
- "I'm treating this as **Lead Link of the Product Circle** work. Strategy on file says..."
- "**Observer mode** -- you don't currently fill Rep Link anywhere, so I'll explain how this role normally operates..."

This is non-negotiable. Without the announcement, the user has no way to catch a wrong resolution before the skill's output is built on it.

### Step 5 -- Validate context didn't go stale

If the same session continues past a major turn (e.g., the user pivots to a different topic), re-validate before continuing: a quick `glassfrog_list_my_roles` confirms the actor still fills the role. Governance can change between turns. If the actor no longer fills the role, name it and re-resolve.

---

## Three Engagement Modes (Where Resolved Context Lands)

Once the actor and role are resolved, the skill operates in one of three modes from `holacratic-ai-governance` SKILL.md. The mode determines what the skill *does* with the resolved context.

| Mode | Actor relationship | Example |
|---|---|---|
| **Observer** | Actor does NOT fill the target role. Skill explains/analyzes from outside. | User exploring what Rep Link does before standing for election. |
| **Advisor** | Actor fills the role and is making a decision themselves. Skill augments. | Lead Link asking "should I assign Robin to this role?" |
| **Actor** | The actor IS the role and Claude is producing work that fulfills its accountabilities. Human reviews and acts. | Secretary asking the skill to draft tactical meeting capture. Scheduled routines almost always operate in this mode. |

Resolution does not pick the mode -- the user's intent does. But the announcement should make the mode visible: "Operating as **Lead Link of Product Circle (Advisor)** -- I'll surface considerations rather than make a recommendation."

---

## Scheduled Routines: Context Encoding at Creation Time

When the agentic capability (v0.3+) creates a scheduled routine via `mcp__scheduled-tasks__create_scheduled_task`, the routine's prompt **must encode** the resolved context. There is no shared memory the routine can read at fire time -- the prompt is the only carrier of identity.

The required preamble for every routine prompt:

```
You are firing as a scheduled Holacracy routine.

Acting actor: [Agent name] (GlassFrog agent id: [id])
Acting role: [Role name]
Acting circle: [Circle name] (GlassFrog circle id: [id])
Accountability being energised: [accountability text from governance]
Output channel: [Slack channel / file path / notification]

Constitutional safeguard: Draft only. Do not file proposals, assign people, issue
constitutional rulings, or modify governance. Produce output for human review.

[Then the routine-specific task...]
```

The plugin prefix `holacracy/` (or `holacracy:`) appears in the routine's task title so the SessionStart hook can filter to its own routines without scanning every scheduled task on the system. Example title: `holacracy/secretary/pre-tactical-prep/operations-circle`.

---

## When GlassFrog Data Is Unavailable

A skill can still operate without GlassFrog, but it must:

1. **Name the limitation in the announcement**: "GlassFrog isn't connected, so I don't have live role data. I'll work from what you've told me."
2. **Ask the user to declare the context**: "Whose role should I treat as primary? In which circle?"
3. **Not silently assume** the human is the actor or that the canonical role definition matches their current accountabilities.

This is the same pattern as the existing `holacratic-ai-governance` SKILL.md "Required: GlassFrog MCP Tools" section -- it doesn't refuse to operate, it names the constraint.

---

## Cross-Skill Load Guide

This document is referenced from multiple holacracy skills. The relevant sections depend on the skill context:

| If you're working in... | Most relevant sections |
|---|---|
| `holacracy-facilitator` | Steps 1-4 (resolution); Engagement Modes (Facilitator is Actor in meetings, Advisor outside) |
| `holacracy-secretary` | Steps 1-5 (especially Step 5 re: meeting-day staleness); Scheduled Routines preamble |
| `holacracy-lead-link` | Steps 1-4; Engagement Modes (most Lead Link work is Actor or Advisor) |
| `holacracy-rep-link` | Steps 1-4; Engagement Modes (Rep Link mostly Advisor when carrying tensions) |
| `holacratic-ai-governance` | All sections -- this skill is the operating frame; resolution is foundational |
| `holacracy-policy-steward` (v0.4) | Steps 1-4; resolution may target a circle scope rather than a single role |
| `holacracy-circle-member` (v0.4) | Steps 1-3 (often the actor fills many roles in the circle; resolve circle scope, then list all roles the actor fills there) |
| Scheduled routines (v0.3+) | Scheduled Routines section is the canonical prompt-preamble spec |
| `/holacracy:context` slash command | Whole document -- this command is the user's surface for the resolution machinery |
