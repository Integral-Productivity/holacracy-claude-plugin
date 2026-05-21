# Tactical Meeting Facilitation -- v5.0

A Tactical meeting is the circle's regular operational heartbeat. Its purpose is to synchronize work, clear blockers, and triage tensions that can be resolved with information or commitments -- not structural changes. Nothing in a Tactical meeting changes governance.

**Typical duration**: 45-90 minutes depending on circle size and project volume.

---

## Pre-Meeting Preparation

Load the following before the meeting starts:

```
glassfrog_list_checklist_items(circle_id)  -> organized by role
glassfrog_list_metrics(circle_id)          -> organized by role
glassfrog_list_projects(circle_id)         -> organized by role and status
glassfrog_get_circle(circle_id)            -> confirm role/people assignments
```

Prepare the meeting agenda by organizing these into sections:

**Checklist section**: Group items by role. Note any items with null or missing frequency -- flag these as potential tensions.

**Metrics section**: Group by role. Note any metrics that have no description or whose descriptions seem outdated.

**Projects section**: Group by role. Sort by: (1) projects with stale status (no update in a long time), (2) in-progress projects, (3) projects flagged with non-trivial status.

Present this pre-loaded agenda to the user before beginning. Example:
> "I've loaded the [Circle Name] Tactical agenda. We have [N] checklist items across [R] roles, [M] metrics, and [P] projects. Ready to begin?"

---

## Meeting Format -- Step by Step

### Step 1: Check-In Round

**What it is**: Each person in the meeting speaks briefly about their current state. One at a time, uninterrupted. No cross-talk.

**Facilitation script**:
> "Let's open the meeting. We'll do a check-in round -- each person shares a word or sentence about their current state. No need to respond to anyone else. [Name], would you like to start?"

**Rules**:
- No responses, reactions, or follow-up questions during check-in
- Passing is allowed
- Keep it brief -- this is not a status update, just a human moment

**What to watch for**: Someone using check-in as agenda time ("I'm stressed because the project is late..."). Gently redirect: "Let's capture that as an agenda item and come back to it."

---

### Step 2: Checklist Review

**What it is**: Each checklist item is called out, and the role-filler reports whether they completed it since the last meeting. This is not a discussion -- it is a binary report.

**Facilitation script**:
> "Checklist review. I'll read each item and the role-filler responds yes or no -- no discussion needed. If someone has a concern, add it to the agenda."

For each item: "[Item description] -- [Role name]?"

Role-filler responds: "Yes" / "No" / "Not applicable this period"

**Rules**:
- No explanations required (though brief context is fine)
- If someone starts explaining, acknowledge and redirect: "Got it -- do you want to add a tension to the agenda about that?"
- Not every item needs the person present -- if the role-filler isn't in the meeting, note it

**What to watch for**:
- Items consistently reporting "no" -- potential tension to raise
- Items with no assigned role (orphaned) -- flag for governance
- Items with null frequency -- note for potential definition update

---

### Step 3: Metrics Review

**What it is**: Each role-filler with metrics to report shares the current value or status. This is a report, not a discussion.

**Facilitation script**:
> "Metrics review. Each person with a metric shares their current update. If someone sees a tension, add it to the agenda."

For each metric: "[Metric description] -- [Role name]?"

Role-filler shares the value, trend, or relevant note.

**Rules**:
- No deep discussion -- surface the number or status and move on
- Questions are fine ("What does that number represent?") but answers should be brief
- Flag metrics with no clear value to report as potential tension items

**Note**: The AI cannot record metric values in GlassFrog -- the role-filler must enter their actual values in the GlassFrog UI during or after the meeting.

---

### Step 4: Project Updates

**What it is**: Each role-filler with active projects shares a brief update. The purpose is to surface blockers and give the circle visibility into project progress.

**Facilitation script**:
> "Project updates. For each project, a brief status -- what's the current state, and is there anything blocking progress? If you need something from this group, add it to the agenda."

For each project: "[Project description] -- [Role name or person]?"

Role-filler shares: current status, any blockers, next action.

**Facilitation guidance**:
- Keep this section moving. "Brief" means one to three sentences per project.
- If someone starts a long explanation, invite them to add it as an agenda item: "Let's put that on the agenda so we can give it proper time."
- If a project has had no update for a long time, name it: "This one looks stale -- worth a quick status?"

**Post-meeting**: Offer to update project statuses in GlassFrog using `glassfrog_update_project` for projects where status or description changed during the meeting.

---

### Step 5: Agenda Building

**What it is**: Anyone in the meeting can add a tension to the agenda. This is not the time to process tensions -- just to surface them.

**Facilitation script**:
> "Agenda building. What tensions do you want to process today? One or two words per item is enough -- we don't need to know the whole story yet. Who has something?"

Go around the circle (or open the floor) until no one has additional items. Build a visible list.

**Rules**:
- No discussion of agenda items during building -- just the topic keywords
- Items can come from the check-in, checklist, metrics, or projects sections, or arise fresh
- The AI can suggest agenda items based on tensions it detected during data loading, but only if they seem worth raising: "I noticed [Project X] hasn't had a status update -- worth adding?"

**Ordering**: The Facilitator processes items in the order they were raised, unless the tension-holder requests otherwise.

---

### Step 6: Triage Agenda Items

**What it is**: Each agenda item is processed one at a time. The Facilitator helps the tension-holder get what they need.

**For each item**, follow this sequence:

**1. Invite the tension**:
> "[Name], what's your tension?"

Let the person describe it briefly. The Facilitator listens -- not to understand the full context, but to understand what they need.

**2. Ask the key question**:
> "What do you need?"

This is the Facilitator's most important tactical move. It focuses the meeting on outputs, not discussion. Valid answers:

| What they need | Facilitator response |
|---|---|
| Information from someone | "Can [Name] address that directly?" |
| Someone to take on a project | "Is there someone here willing to take that on?" |
| A next action from someone | "Would you be willing to commit to [action] by [when]?" |
| A governance change | "This sounds like it needs a governance meeting -- shall I note it as a proposal for next governance?" |
| Just to be heard | "Does anyone have a quick reaction?" (optional, brief) |

**3. Check if the tension is resolved**:
> "Does that work for you?"

If yes, move to the next item. If no: "What else do you need?"

**Key rules**:
- The Facilitator does not solve the tension -- the tension-holder does, with the circle's help
- If the tension can be addressed with information or a commitment, resolve it now
- If the tension requires a governance change (a new role, accountability, domain, or policy), note it and defer to a governance meeting: "That's a governance matter -- let's add it to the governance meeting agenda."
- If two people start debating a topic: "This sounds like it needs more air than tactical allows -- can you two take this offline, or should we flag it for governance?"
- Keep each agenda item crisp. Most tensions resolve in two to five minutes.

---

### Step 7: Closing Round

**What it is**: Each person shares a brief reflection on the meeting. This is a moment of closure, not a retrospective.

**Facilitation script**:
> "Let's close the meeting. Each person shares a word or sentence -- a reflection on the meeting, or just how you're landing. [Name], would you like to start?"

**Rules**:
- No responses or reactions
- Passing is allowed
- Brief -- one sentence is plenty

After the closing round:
> "The meeting is closed. Thanks everyone."

---

## Post-Meeting Actions

After the meeting, offer to:

1. **Produce the meeting record** -- list of tensions processed, projects/next actions captured, and any items deferred to governance
2. **Update project statuses in GlassFrog** -- use `glassfrog_update_project` for any projects whose status or description changed
3. **Flag governance items** -- summarize any tensions identified as governance-level, formatted as potential proposals

---

## Common Facilitation Challenges

**The meeting runs long**: If the agenda is not being cleared in time, name it: "We have [N] items left and [X] minutes. We can either go faster, or carry remaining items to the next tactical. Which do you prefer?"

**Someone dominates the triage**: Each agenda item belongs to its tension-holder. If someone other than the tension-holder is driving, redirect: "[Tension-holder's name], does that address what you need?"

**A tension is actually a governance issue**: Some practitioners try to resolve governance matters in tactical because governance meetings feel heavy. Name the difference clearly: "What you're describing is a structural change -- adding an accountability, defining a domain, or creating a policy. We can't do that in tactical. The good news is governance proposals don't have to be fully formed -- we just need a tension and a proposal. Want me to help you draft one?"

**No-shows**: If a Core Role (especially Lead Link) is absent, note it in the record. A governance meeting without the Lead Link can still proceed, but governance changes adopted without notice to missing members should be flagged.

**The checklist is too long**: If checking every item is taking more than 10 minutes, it's a signal the circle's checklist needs pruning. Note it as a tension for governance: "Our checklist is taking [X] minutes. That may be a signal some items have outlived their usefulness -- worth a governance look."
