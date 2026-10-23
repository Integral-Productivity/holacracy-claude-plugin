# Integrative Election Process -- v5.0

The Integrative Election (IE) process is used to fill the three elected Core Roles in a circle: **Facilitator**, **Secretary**, and **Rep Link**. It can be run as a standalone session or embedded within a governance meeting.

**When to run an election**:
- A Core Role is vacant (no one is assigned)
- An elected role-filler steps down or is removed
- The term for an elected role has expired (if the circle has set terms)
- The circle has never formally elected someone to the role

**Who can be elected**: Any member of the circle can be elected to any of the three Core Roles. There are no constitutional prerequisites beyond circle membership, though the Lead Link may have excluded specific individuals from specific roles via their authority.

**Duration**: 15-30 minutes per role.

---

## When Elections Happen in Governance

If running an election during a governance meeting, it is processed as a governance agenda item -- it follows its own distinct process (below), not the standard IDM process. The Facilitator should announce: "The next agenda item is an election for [Role]. We'll use the Integrative Election process for this."

---

## The Process -- Step by Step

### Step 1: Describe the Role

Before nominations, ensure everyone understands what the role does.

**Facilitation script**:
> "Let's run an election for [Role Name]. Before we nominate, let me read the role's purpose and accountabilities so everyone has the same picture."

Read the role's purpose and key accountabilities from GlassFrog:
```
glassfrog_get_role(role_id) -> purpose, accountabilities
```

For reference, the three elected roles:

**Facilitator**
- Purpose: Governance and operational practices aligned with the Constitution
- Accountabilities: Facilitating governance and tactical meetings; auditing sub-circle meetings and records; assisting with meeting scheduling

**Secretary**
- Purpose: Stabilize the circle's governance and operational records
- Accountabilities: Scheduling meetings; maintaining and communicating governance records; interpreting governance and the Constitution on request; serving as the circle's records custodian

**Rep Link**
- Purpose: The circle's tensions that are relevant for the broader organization to process are carried to the super-circle
- Accountabilities: Removing constraints that limit the circle's capacity; bringing tensions felt in the circle into the super-circle's governance process; representing the circle's perspective in the super-circle

**After reading the role**:
> "Any clarifying questions about what this role does before we nominate?"

Answer questions briefly. Do not begin discussing candidates yet.

---

### Step 2: Nomination Round (Written)

**What happens**: Each person nominates someone for the role -- including themselves -- and writes it down privately before anyone speaks.

**Facilitation script**:
> "Nomination round. Everyone please write down who you nominate for [Role Name] -- you can nominate yourself. Write just the name, not your reasoning. Don't share your nomination yet."

Give 30 seconds to a minute for everyone to write.

**Key rule**: Nominations are written first, before anyone speaks. This prevents anchoring bias -- people should form their own view before hearing what others think.

---

### Step 3: Share Nominations

**What happens**: Each person shares who they nominated and their brief reasoning.

**Facilitation script**:
> "Please share your nomination and a brief reason why. [Name], let's start with you."

Go around once. Each person states: "I nominate [Name] because [brief reason]."

**Rules**:
- No responses, reactions, or counter-nominations during this round
- Reasons should be brief -- one or two sentences
- People can nominate anyone in the circle, including the current role-filler

**Track the nominations**: Note who was nominated and how many nominations they received.

---

### Step 4: Opportunity to Change Nominations

**What happens**: After hearing all nominations and reasons, each person has the opportunity to change their nomination if they choose.

**Facilitation script**:
> "Now that you've heard everyone's nominations, does anyone want to change their nomination? [Go around.] You don't have to explain why."

This is a brief round. Most people will not change. Accept changes without comment.

---

### Step 5: Facilitator Makes a Nomination

**What happens**: The Facilitator (that's the AI in this context, or the human Facilitator) makes a nomination based on what was heard in the process -- not necessarily the person with the most nominations, but the one most likely to succeed without objection.

**Facilitation script**:
> "Based on what I've heard, I'd like to nominate [Name] for [Role Name]."

**How to choose**: Consider:
- Who received the most nominations?
- Did anyone receive particularly strong reasoning?
- Is there a candidate who seems well-suited and unlikely to generate objections?
- Is the current role-filler being re-nominated? (Default to continuity unless there's a clear signal otherwise)

The Facilitator does not need to choose the plurality nominee -- they are making a judgment call informed by the full process. State the nominee with a brief framing: "I'm nominating [Name] because [one sentence]."

---

### Step 6: Objection Round

**What happens**: The Facilitator asks each person whether they have an objection to the proposed nominee. This follows the same constitutional validity test as governance objections, but applied to a person filling a role rather than a governance proposal.

**Facilitation script**:
> "Objection round. I'll ask each person: do you have an objection to [Name] filling the [Role Name] role? An objection means you believe this would harm the circle's ability to express its purpose or accountabilities."

Ask each person: "[Name], any objection?"

**Valid objection criteria** in elections:
- The nominee would actively harm the circle's capacity to perform the role (not just "I think someone else would be better")
- A constitutional constraint exists (the nominee was explicitly excluded from this role by the Lead Link)
- The nominee has a direct conflict of interest that would undermine the role's purpose

**Invalid objection**: "I think [other person] would be better" -- preference for a different candidate is not a valid objection. Name it: "That's a preference, not a harm. Let's continue."

If valid objections arise, ask the objector: "What modification would address your concern?" -- in elections, this often means asking whether the objector would support a different candidate, or whether the nominee would be willing to accept conditions. The Facilitator may then nominate someone else and re-run the objection round.

---

### Step 7: Announce the Elected Person

When the objection round completes without valid objections:

**Facilitation script**:
> "[Name] is elected as [Role Name] for [this circle]. Congratulations."

Log this for the Secretary:
- Role: [Role Name]
- Elected: [Name]
- Date: [Date]
- Circle: [Circle Name]

The Secretary must update GlassFrog to reflect the new role assignment, since the API does not support role assignment changes.

---

## Running Multiple Elections in One Session

If electing more than one Core Role in a single session, run each election fully before moving to the next. The order matters in one specific case: if you are electing a new Facilitator, run that election first -- you may need a neutral party to facilitate the remaining elections, and whoever is elected Facilitator can take over from there.

---

## Common Challenges

**No one wants to nominate themselves**: This is common, especially for Facilitator and Secretary. Remind the group that nominations are offers, not demands, and that the nominee can decline. "You can nominate yourself provisionally -- if you're elected and it doesn't feel right, we can address that in governance."

**The current role-filler is clearly not working but no one will object**: If everyone is nominatively "fine" with the current person but operational reality suggests otherwise, the Facilitator can name the pattern: "I'm hearing no formal objections, but I want to make sure we're naming the situation honestly. Does anyone have a valid objection, or are we ready to proceed with this election?" This gives people one more moment without forcing the issue.

**Someone declines after being nominated**: Accept this gracefully and return to the nomination pool. If no other candidate is clearly indicated, run a second brief nomination round.

**The Facilitator is being elected**: When the role being elected is the current Facilitator, the current Facilitator should not facilitate their own election. Ask the Lead Link (or another willing circle member) to facilitate the Facilitator election, then return to the elected Facilitator for remaining business.
