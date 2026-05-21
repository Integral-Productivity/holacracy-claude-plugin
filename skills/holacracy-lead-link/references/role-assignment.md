# Role Assignment -- Lead Link Reference

This reference provides complete guidance for the Lead Link's role assignment work: assessing fit, making assignments, running fit conversations, handling re-assignment, and managing vacancies. Load it for substantive assignment work or when the user is navigating a difficult assignment situation.

---

## The Assignment Domain

Role assignment is the Lead Link's Domain -- only the Lead Link may assign Partners to Roles within the circle, absent a governance policy that grants others this authority. This is one of the Lead Link's most direct organizational authorities.

**What the assignment domain covers**:
- Who fills a role
- When a role is un-filled (vacancy)
- When a role-filler is replaced
- When one person fills multiple roles

**What the assignment domain does not cover**:
- How the role-filler does their work (that is within the role-filler's authority)
- What the role's accountabilities are (that is governance)
- Whether the role should exist (that is governance)

---

## Fit: The Organizing Concept

The Lead Link does not "manage" role-fillers in the traditional sense -- they manage *fit*. Fit is the match between a person's capacity and the role's demands.

**Four dimensions of fit**:

| Dimension | Question |
|-----------|----------|
| **Capability** | Does the person have the skills and knowledge the role requires? |
| **Capacity** | Does the person have the time and bandwidth to fulfill the role's accountabilities? |
| **Interest** | Is the person energized by this work, or is it a burden? |
| **Availability** | Is the person actually accessible for this role's obligations? |

A person can have high capability but low capacity (overscheduled). They can have high interest but low capability (new to the domain). They can have high capacity but low availability (time zones, other commitments). Fit conversations need to be specific about which dimension is in play.

**Important distinction**: A fit problem is not the same as a performance problem. Fit is about the match between person and role. Performance judgment implies the person is failing a standard they should be meeting. In Holacracy, the Lead Link's frame is: "Does this role-person match serve the circle? If not, let's find a better match -- not evaluate whether this person is good enough."

---

## Making a New Assignment

### Pre-Assignment Checklist

Before assigning someone to a role:

- [ ] Load the role definition: `glassfrog_get_role(role_id)` -- confirm purpose, accountabilities, domains
- [ ] Understand the role's current state: Is it vacant? Is someone being replaced?
- [ ] Assess the proposed person's current portfolio: `glassfrog_list_roles` filtered for their person ID or scanned across all circles
- [ ] Check capacity: Are they already carrying high accountability weight elsewhere?
- [ ] Confirm the person is willing to take on the role (constitutionally not required, but practically essential)
- [ ] Identify any onboarding needed: Is there context the new role-filler needs to get up to speed?

### Assignment GlassFrog Mechanics

```
glassfrog_assign_person_to_role(person_id, role_id)
```

`person_id` is obtained from `glassfrog_list_people`. Note: in some GlassFrog API configurations, this field may need to be sourced from `glassfrog_list_projects` or role-specific queries if `list_people` returns limited data.

After assignment, verify: `glassfrog_get_role(role_id)` should show the new assignment.

### Assignment Communication

After making an assignment, produce a brief orientation memo for the new role-filler:

```
Role Assignment -- [Role Name] in [Circle Name]

Assigned to: [Name]
Effective: [date]

Role Purpose: [purpose statement from GlassFrog]

Key Accountabilities:
- [accountability 1]
- [accountability 2]
- [accountability 3]

Domains (exclusive authority): [list, if any]

Current active projects in this role: [from glassfrog_list_projects]
Checklist items owned by this role: [from glassfrog_list_checklist_items]
Metrics owned by this role: [from glassfrog_list_metrics]

Lead Link context: [brief note on current circle strategy and what this role contributes to it]

Questions? [how to reach the Lead Link]
```

---

## Monitoring Fit

Fit is not static -- it can improve or deteriorate over time as the person grows, the role's demands change, or organizational context shifts. The Lead Link monitors fit continuously.

**Signals of deteriorating fit**:

| Signal | Possible interpretation |
|--------|------------------------|
| Accountabilities consistently not fulfilled | Capability, capacity, or interest issue |
| Projects stalling or not being updated | Capacity or attention issue |
| Recurring tensions at tactical meetings about this role | Fit or role definition issue |
| Role-filler explicitly stating difficulty or disengagement | Interest or capacity issue |
| Long-term vacancy in key accountabilities | The role definition may need governance update |

**GlassFrog-based fit monitoring**:
```
glassfrog_list_projects(circle_id) -> filter by role; look for stale status, no recent updates
glassfrog_list_checklist_items(circle_id) -> look for recurring non-completion patterns
glassfrog_list_metrics(circle_id) -> look for metrics with no updates or concerning trends
```

**Caution**: Stale GlassFrog data may reflect administrative neglect (not updating the system) rather than actual work neglect. Always confirm interpretation with the role-filler before drawing fit conclusions from data alone.

---

## The Fit Conversation

When fit signals suggest a problem, the Lead Link initiates a fit conversation. This is a constitutional practice, not a performance review.

### Fit Conversation Structure

**1. Open with the purpose**
> "I want to check in about your fit with [Role]. The Lead Link's job is to make sure roles are well-matched to the people filling them -- this isn't a performance conversation, it's a fit conversation."

**2. Name what you're observing**
> "What I've been noticing is [specific, observable pattern -- e.g., 'several of the role's projects haven't had status updates in the last two tacticals' or 'the checklist item for X has been getting No completions']."

**3. Invite their perspective**
> "Before drawing any conclusions, I want to understand what's happening from your end. What's going on with this role for you right now?"

**4. Diagnose the dimension**

Listen for which fit dimension is the actual problem:
- "I don't have time" -> capacity issue
- "I'm not sure what I'm supposed to do" -> capability or unclear role definition
- "This work doesn't energize me anymore" -> interest issue
- "I keep running into obstacles I can't resolve" -> accountability structure or authority issue

**5. Name the options**

The fit conversation ends with one of three outcomes:
- **Continue with support**: A specific change that would help the role-filler succeed (clearer definition, resource help, coaching)
- **Re-assignment**: The match isn't serving the circle; find a better-fit person for this role
- **Governance**: The problem isn't the person, it's the role definition itself -- bring a proposal

**6. Agree on a path**

State the outcome clearly. If continuing with support, name a specific check-in point: "Let's revisit in [timeframe] and see if this is working."

### Solo-Operator Fit Conversations

In solo-operator contexts, fit conversations are internal. The Lead Link hat asks: "Is this role definition a good fit for the work I'm actually doing and the energy I have for it?"

Prompt structure for internal fit reflection:
> "What accountabilities in [Role] do I consistently fulfill? Which ones do I consistently avoid or defer? What's making the difference? Is that a signal I should change how I'm approaching the role, change the role definition through governance, or accept the current state as a choice?"

---

## Re-Assignment

When fit has deteriorated and support has not resolved it, re-assignment is the appropriate Lead Link action.

### Re-Assignment Principles

**Act decisively but humanely.** Delaying re-assignment when fit has clearly broken down does not serve the role-filler, the circle, or the work. It signals that the organization tolerates misalignment, which undermines the integrity of the role structure.

**Separate the decision from the conversation.** Make the decision to re-assign before having the conversation -- arrive at the conversation with clarity, not uncertainty. Arriving uncertain creates false hope and makes the conversation harder.

**Be honest about the reason.** Role-fillers deserve to know whether the re-assignment is about their fit to this particular role, organizational changes to the role's demands, or a different need in the circle. Vague reassurances ("this is just an organizational adjustment") erode trust.

### Re-Assignment Conversation Structure

**1. Name the decision clearly**
> "I've decided to re-assign you from [Role]. I want to tell you directly and explain my reasoning."

**2. Name the specific fit dimension**
> "The specific issue is [capacity / capability / interest / availability]. What I've observed is [concrete pattern]. I've concluded that a different assignment would better serve both you and the circle."

**3. Acknowledge what the person has contributed**
> "Before we talk logistics, I want to name what you've brought to this role: [specific contribution]."

**4. Address next steps**
> "Here's what happens next: [timeline for transition, who will fill the role, what the person might take on instead if applicable]."

**5. Execute in GlassFrog**
```
glassfrog_unassign_person_from_role(person_id, role_id)
```
Do this after the conversation, not before -- the person should hear it from you first.

---

## Managing Vacancies

A vacant role is a governance signal: the circle's structure says this work matters, but no one is energizing it. Vacancies need active management.

**Types of vacancies**:
- **Planned vacancy**: Role is being transitioned; a new assignment is in process
- **Unintended vacancy**: Role-filler left unexpectedly; immediate attention required
- **Chronic vacancy**: No one has filled this role for a long time; possibly a structural problem

**Lead Link options for vacancies**:

| Situation | Response |
|-----------|----------|
| Temporary gap, new assignment in process | Fill the role temporarily yourself (Lead Link can energize any role in the circle) and flag the timeline |
| Role is critical and no suitable person exists | Surface to Super-Circle as a resource constraint (accountability: removing constraints) |
| Role hasn't been filled in months | Consider whether the role still needs to exist; bring a governance proposal to remove if not |
| Role's accountabilities are being absorbed informally | Name this as a tension; either assign formally or bring governance to clarify |

**Filling roles temporarily**: The Lead Link can energize any role in the circle as Lead Link. This is not an assignment -- it is the Lead Link temporarily taking on the work to prevent an organizational gap. Use it sparingly and with a clear timeline for the actual assignment.

---

## Role Assignment in Solo-Operator Contexts

In a solo-operator context, formal role assignment still matters -- it is the mechanism by which the organization's governance record reflects who is responsible for what.

**Why it matters even when you're the only person**:
- It forces clarity about which accountabilities you're committed to energizing vs. which are currently unattended
- It makes the organizational structure legible when other people become involved (contractors, future hires, collaborators)
- It creates a disciplined practice of reviewing fit as your focus and capacity change over time

**Practical discipline**:
- At least annually, review all role assignments: are you genuinely energizing all the roles you're formally assigned to?
- Roles you are not energizing represent either vacancies to acknowledge or governance opportunities to remove accountabilities that no longer belong in the structure
- In GlassFrog, every role should be assigned to someone -- "nobody" assigned to a role signals governance neglect

---

## Assignment Patterns to Avoid

| Pattern | Problem |
|---------|---------|
| Assigning someone to a role without talking to them | Constitutionally valid but practically corrosive -- role-filler will resent it |
| Leaving roles vacant indefinitely | Signals the role definition doesn't match organizational reality; brings a governance tension |
| Assigning one person to so many roles they cannot fulfill any | Creates systemic under-fulfillment; better to have fewer, better-staffed roles |
| Re-assigning as a punitive act | Undermines the organizational integrity of the assignment domain; if it's punitive, it should be handled differently |
| Assigning to avoid a governance proposal | Using assignment to work around a structural problem rather than fixing the structure |
