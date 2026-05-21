# Facilitator Constitutional Duties -- v5.0 Reference

This document inventories every constitutional duty of the Facilitator role and provides guidance for fulfilling each one. Use it for audit support, onboarding new Facilitators, or constitutional compliance questions.

---

## Full Duty Inventory

### 1. Facilitate Required Meetings

**Constitutional basis**: The Facilitator is accountable for facilitating the circle's constitutionally-required meetings.

**Required meetings**:
- **Tactical meetings**: Required by the Constitution as the circle's primary operational synchronization mechanism. Frequency is not specified constitutionally; the circle sets its own cadence.
- **Governance meetings**: Required to process governance proposals. Must be available when any circle member wants to process a governance tension.

**What "facilitate" means constitutionally**: Conduct the meeting using the constitutionally-defined format. The Facilitator has authority to rule on process questions and override departures from the format.

**What the Facilitator does NOT control**:
- Who attends (open to all circle members by default)
- What proposals are brought (any member can propose governance changes)
- The outcomes of governance (determined by the IDM process)
- Tactical decisions or project assignments (determined by role-fillers)

**AI facilitation support**: Load the appropriate reference file before any meeting:
- `references/tactical-meeting.md` for Tactical
- `references/governance-meeting.md` for Governance

---

### 2. Audit Sub-Circle Meetings and Records

**Constitutional basis**: The Facilitator may audit meetings and records of any sub-circles as needed.

**What this means**: The Facilitator can review whether sub-circles are:
- Holding their required meetings (Tactical and Governance)
- Maintaining governance records (kept by sub-circle Secretaries)
- Operating within constitutional process

**This is an "as needed" duty** -- not a mandatory regular activity -- but it becomes important when:
- A sub-circle appears to have lapsed in its meeting cadence
- Governance decisions from a sub-circle seem constitutionally questionable
- The parent circle has concerns about a sub-circle's operational health

**AI support for auditing**:
```
glassfrog_list_circles -> identify all sub-circles of the current circle
glassfrog_get_circle(sub_circle_id) -> check for Facilitator and Secretary assignments
glassfrog_list_roles(sub_circle_id) -> verify core roles are filled
```

**Signals that warrant an audit**:
- A sub-circle has no one assigned to Facilitator or Secretary
- A sub-circle's governance records (per the Secretary) have not been updated recently
- Tensions from the sub-circle are surfacing in the parent circle's tactical meetings, suggesting the sub-circle's own meetings are not addressing them

**Audit output format**:
> "Sub-circle audit -- [Circle Name]: [Core roles filled/unfilled] | [Meeting cadence status: active/lapsed/unknown] | [Governance record status: current/stale/unavailable] | [Recommended action if any]"

---

### 3. Assist with Meeting Scheduling

**Constitutional basis**: The Facilitator assists the Secretary with scheduling the circle's required meetings.

**In practice**: The Secretary is constitutionally responsible for scheduling meetings. The Facilitator assists -- which in practice often means the Facilitator takes the initiative when the Secretary doesn't.

**AI support for scheduling**:
- Review the user's calendar context (if available via calendar MCP tools)
- Propose meeting slots that fit the circle's operational rhythm
- Suggest default cadences for circles that haven't established one

**Baseline cadences to suggest**:

| Meeting | Recommended | Minimum |
|---|---|---|
| Tactical | Weekly | Biweekly |
| Governance | Monthly | As tensions warrant |
| Elections | Per term end or vacancy | N/A |
| Strategy | Quarterly | Annually |

**Scheduling considerations**:
- Tactical meetings work best on consistent days and times (creates habit and predictability)
- Governance meetings should be calendared in advance, not just called reactively -- reactive governance tends to be rushed and lower quality
- If the circle is a solo-operator context, scheduling still matters: calendar entries create accountability

---

### 4. Rule on Process Questions

**Constitutional basis**: The Facilitator has authority to rule on process questions during meetings.

**What this means**: When a dispute arises about whether the meeting is following the correct constitutional process, the Facilitator's ruling is final (within the meeting). Examples:
- "Is this a valid objection?" -> Facilitator decides
- "Can this tension be processed in tactical, or does it need governance?" -> Facilitator decides
- "Is this question a clarifying question or a disguised reaction?" -> Facilitator decides

**Important limit**: The Facilitator's process authority applies *during meetings*. Outside of meetings, the Secretary is the constitutional interpreter.

**When uncertain**: The Facilitator can pause and reason through the process question explicitly. It is better to take a moment to think than to make a fast incorrect ruling.

---

### 5. Protect the Process Over Outcomes

**Constitutional basis**: Implicit throughout the Constitution -- the Facilitator's role is defined entirely in terms of process, not outcomes.

**What this means in practice**: The Facilitator must be willing to rule in ways that protect constitutional process even when it's uncomfortable:
- Declaring an objection invalid even when the objector is visibly upset
- Keeping the reaction round one-directional even when the proposer wants to defend their proposal
- Deferring a governance proposal that hasn't been properly formulated, even when the proposer is impatient
- Ending a governance meeting rather than rushing a proposal through

**The Facilitator's authority is procedural, not substantive**: The Facilitator cannot decide what good governance looks like. They can only ensure the process runs correctly so that the circle can decide.

---

## Constitutional Validity Quick Reference

### What belongs in Governance (not Tactical)
- Creating, modifying, or removing roles
- Adding, changing, or removing accountabilities
- Defining or removing domains
- Creating or removing policies
- Changing circle strategy (Lead Link's call, but via governance if proposed)
- Converting a role into a sub-circle or vice versa

### What belongs in Tactical (not Governance)
- Sharing information
- Making a commitment or capturing a project
- Requesting a next action from someone
- Flagging a tension (that might be processed in governance later)
- Coordinating between roles on current work

### What belongs outside of meetings entirely
- Interpersonal issues (address via direct conversation or coaching)
- Personal performance concerns (Lead Link's domain)
- Meta-process complaints about Holacracy itself (bring as a governance proposal or outside conversation)

---

## Facilitator Ethics and Stance

These are not constitutional rules, but operating principles that make for an effective Facilitator:

**Neutrality on substance**: The Facilitator must protect the process even for proposals they personally disagree with. If you are both Facilitating and a circle member with strong opinions, name the tension: "I want to flag that I have a personal view here. As Facilitator, I'm going to hold the process -- if I need to respond as a circle member, I'll name that explicitly."

**Clarity over comfort**: A good Facilitator names what's happening, even when it's awkward. "That objection isn't constitutionally valid." "We've been debating for 10 minutes and I don't see integration happening." "This tension belongs in governance, not tactical." These moments are uncomfortable but necessary.

**Consistency**: Apply the same rigor to every proposal and every objector, regardless of seniority, relationship to the Lead Link, or popularity of the proposal.

**Humility about process knowledge**: The Holacracy Constitution is detailed. When genuinely uncertain about process, say so and consult the Constitution rather than improvise. "I want to check the constitutional language on this before ruling."

---

## When Things Go Wrong

### Someone refuses to accept a process ruling
The Facilitator's rulings are final within the meeting. If someone repeatedly challenges the process: "I understand you disagree with my ruling. In Holacracy, the Facilitator's process calls are final in the meeting. You can bring a governance proposal to modify this circle's interpretation of process, or raise it with the Secretary outside the meeting."

### The Facilitator makes a mistake
It happens. If you realize mid-meeting that you made a wrong ruling: "I made an error earlier -- [describe it]. Let's correct that now and continue." The ability to self-correct builds trust in the process.

### Someone is consistently problematic in meetings
The Facilitator manages process, not people. If someone is repeatedly disruptive, the appropriate response is a Lead Link conversation, not a facilitation intervention. The Facilitator can name the pattern: "I've been redirecting [Name] several times on this. I want to flag that for the Lead Link outside of this meeting."

### No one shows up
A governance or tactical meeting with no quorum still has meaning: note it, and consider whether the circle's meeting cadence needs revisiting. A persistent pattern of low attendance is a tension worth surfacing to the Lead Link.
