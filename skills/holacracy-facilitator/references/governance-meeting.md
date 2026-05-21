# Governance Meeting Facilitation -- v5.0

A Governance meeting is the circle's structural evolution mechanism. Its purpose is to process proposed changes to the circle's governance: roles, accountabilities, domains, and policies. Every change adopted in governance must survive an objection-based validity test -- this is what gives governance decisions their constitutional authority.

**Typical duration**: 60-120 minutes. A meeting with three or four substantive proposals may take the full two hours.

**The Facilitator's core job in governance**: Protect the process. The integrative decision-making (IDM) process is not a parliamentary debate -- it is a structured sequence designed to surface the wisdom distributed across role-fillers and integrate objections rather than overrule them. Every departure from the sequence erodes that protection.

---

## Pre-Meeting Preparation

Before the meeting, load:
```
glassfrog_get_circle(circle_id) -> all roles, accountabilities, domains, people
glassfrog_list_roles(circle_id) -> full role inventory for cross-reference
glassfrog_list_people          -> attendee identification
```

If the user has prepared governance proposals in advance, review them for:
- Constitutional validity (does the proposal fit within governance? Is it a role/accountability/domain/policy change?)
- Potential overlap with existing governance (would this conflict with another role's domain or accountability?)
- Clarity (can the proposal be stated in one or two sentences?)

Present the loaded context before beginning:
> "I've loaded the [Circle Name] Governance structure. [N] roles, [R] role-fillers present. Any proposals prepared in advance? [If yes, list them.] Ready to begin?"

---

## Meeting Format -- Step by Step

### Step 1: Check-In Round

Same as Tactical -- each person shares briefly, one at a time, uninterrupted. See `tactical-meeting.md` for full facilitation script.

---

### Step 2: Administrative Concerns

**What it is**: A brief space to address any process or logistics concerns before diving into governance.

**Facilitation script**:
> "Any administrative concerns before we build the agenda? Things like meeting norms, time constraints, or process questions?"

This is not agenda time for governance tensions -- it's for housekeeping. Keep it brief. Common items:
- Someone has a hard stop time
- A participant is joining remotely and needs to leave early
- A question about the process itself

---

### Step 3: Agenda Building

**What it is**: Anyone in the circle can add a tension to the governance agenda. As in Tactical, this is not the time to discuss tensions -- just to surface them.

**Facilitation script**:
> "Let's build the agenda. What tensions does anyone want to process today? Just a word or two to identify the topic -- we'll hear the full proposal when we process each item."

Go around until the agenda is complete.

**The Facilitator's role during agenda building**:
- Do not evaluate whether tensions belong in governance yet -- that happens during processing
- If someone describes a very detailed proposal: "Hold the details -- we'll hear them when we process your item"
- If someone raises a tactical-level tension (information, project): note it and suggest it could wait for tactical or be addressed after the meeting

---

### Step 4: Process Each Agenda Item

This is the heart of the governance meeting. Each agenda item follows the **Integrative Decision Making (IDM)** process -- six phases that must be followed in order.

For each item, announce: "[Name], your tension is next. Please share your proposal."

---

#### Phase A: Present the Proposal

**What happens**: The proposer describes their tension and their proposed governance change.

**Facilitation script**:
> "[Name], please share your proposal. What's the tension you're sensing, and what change are you proposing to address it?"

**What a valid governance proposal looks like**:
- Creates, modifies, or removes a role (including its name, purpose, accountabilities, domains)
- Creates, modifies, or removes a policy
- Moves a role from one circle to another
- Dissolves a role into another

**What is NOT a governance proposal**:
- A request for someone to do something (that's a tactical tension)
- A strategy suggestion (that goes to the Lead Link)
- A personal grievance or interpersonal issue
- A proposal to change how the Facilitator runs meetings (meta-process -- suggest bringing it outside the meeting)

If the proposal is outside governance scope, name it: "This sounds like [tactical/strategic] rather than a governance change. Would you like to address it differently, or is there a governance version of this tension?"

**After the proposer finishes**: Optionally ask, "Do you need anything to make this proposal more concrete before we move on?" Then proceed.

---

#### Phase B: Clarifying Questions

**What happens**: Anyone can ask the proposer factual questions to understand the proposal better. No reactions, opinions, or disguised reactions are allowed.

**Facilitation script**:
> "Clarifying questions. Anyone can ask [Name] a question to understand the proposal better -- but not to react to it. [Name], you can also say 'not specified' if a question is about something your proposal intentionally leaves open."

Go around the group. Each person may ask one question (or pass), then the proposer answers. Continue rounds until no more questions.

**What to watch for**:
- A question that is actually a reaction: "Have you considered that this might cause [problem]?" -> That's a reaction. "Please hold that for the reaction round."
- A question that asks the proposer to justify their tension: not your job to justify it, just to state it.
- The proposer getting drawn into a long explanation. Keep answers brief.

---

#### Phase C: Reaction Round

**What happens**: Each person (except the proposer) shares their reaction to the proposal. This is the moment for concerns, enthusiasm, disagreements, and perspectives. The proposer remains silent.

**Facilitation script**:
> "Reaction round. Each person shares their reaction to this proposal -- what you're thinking, what concerns you, or what you appreciate about it. [Name] [the proposer], please hold your reactions for now. Who would like to start?"

Go around the group. Each person speaks once, uninterrupted.

**Rules**:
- The proposer does NOT respond during reactions -- note this explicitly if they start to
- No cross-talk between reactors
- Passing is allowed
- This is the one moment in the process where opinions and concerns are freely expressed -- it matters

**Facilitation note**: Reactions are data for the proposer, not a vote. The proposer is about to decide whether to amend -- they should listen, not defend.

---

#### Phase D: Amend and Clarify

**What happens**: The proposer may modify their proposal based on what they heard. They may also clarify what they intended. The proposer speaks; everyone else listens.

**Facilitation script**:
> "Amend and clarify. [Name], based on what you heard, you may modify your proposal or clarify your intention. What, if anything, are you changing?"

**Key point**: The proposer is not required to incorporate reactions. The proposal is theirs to amend as they see fit. The objection round is the check that follows.

**After the proposer speaks**: If the proposal changed significantly, briefly restate the updated proposal to confirm everyone heard the same thing.

---

#### Phase E: Objection Round

**What happens**: The Facilitator asks each person in turn whether they have an objection to the (possibly amended) proposal. This is the constitutional validity test.

**Facilitation script**:
> "Objection round. I'll ask each person: do you have an objection to adopting this proposal? An objection means you believe it would degrade the circle's capacity to express its purpose or accountabilities, or would create an unconstitutional governance record."

Ask each person: "[Name], do you have an objection?"

Response options:
- "No objection" -> move to the next person
- "I have an objection" -> test the objection (see below)
- "I'm not sure" -> test it as if it were an objection

**Include the proposer** -- they can object to their own proposal if they realize a problem during the meeting.

**Always include the Lead Link and the Facilitator themselves** in the objection round (the Facilitator should test their own view too).

---

##### Testing an Objection

When someone raises an objection, the Facilitator tests whether it is constitutionally valid before treating it as such. Ask these questions in order:

**Test 1 -- Does it cause harm?**
> "Would adopting this proposal degrade the circle's capacity to express its purpose or accountabilities -- or create a constitutionally invalid record?"

If the answer is no (it's just not ideal, or there might be a better way), the objection is **invalid**. Name it cleanly: "That sounds like a preference for a different approach rather than a harm -- I'm going to set that objection aside. [Continue to next person.]"

**Test 2 -- Is it based on present reality?**
> "Is this harm you're describing based on information you have now, or speculation about what might happen?"

If purely speculative: the objection is invalid. "Speculative harms aren't sufficient grounds for an objection under the Constitution -- I'm setting that aside."

**Test 3 -- Is it the role's perspective?**
> "If you sensed this tension in your role, would you have brought a proposal to address it?"

If the objection is purely personal and not something the person would address through governance in their role, it's invalid.

**If the objection is valid**: Announce it clearly. "That's a valid objection. We'll move into integration." Do not process multiple objections at once -- resolve one, then re-run the objection round.

**If all objections are invalid**: Announce the proposal is adopted. "No valid objections -- this proposal is adopted. [Pause for a moment of acknowledgment.] Let's note the governance change for the Secretary."

---

#### Phase F: Integration

**What happens**: When a valid objection exists, the proposer and objector work together to find a modified proposal that addresses both the original tension and the objection.

**Facilitation script**:
> "We have a valid objection. [Objector's name], let's work with [Proposer's name] to find a modification. The question is: what's the minimum change to the proposal that would resolve your objection while still addressing the proposer's tension?"

**Facilitation guidance**:
- Keep this a dialogue between proposer and objector, not a group discussion
- Keep the focus on modifying the proposal, not relitigating the tension
- If they cannot find an integration within a few minutes, suggest deferring: "It may be worth taking this offline and coming back with a refined proposal in the next governance meeting."
- Once a modification is agreed: re-enter Phase D (Amend and Clarify), then re-run Phase E (Objection Round) for the modified proposal

**After successful integration**: Return to the objection round to check whether the modification introduced any new objections from others.

---

#### After Each Item Is Adopted

Take a brief moment to acknowledge the governance change before moving to the next agenda item. This doesn't need to be elaborate -- a simple "This proposal is adopted" and a note to the Secretary is sufficient. In Holacracy, governance adoption is real: the moment it is adopted, the structure is live.

Log for the Secretary: the exact change (role added/modified, accountability added, domain defined, policy created), the proposer, and the date.

---

### Step 5: Closing Round

Same as Tactical -- each person shares a brief reflection, uninterrupted. See `tactical-meeting.md` for full facilitation script.

---

## Post-Meeting Actions

After the meeting:

1. **Produce the governance record** -- list of proposals processed, with outcomes (adopted, rejected, deferred)
2. **Flag Secretary actions** -- for each adopted proposal, specify exactly what needs to be entered into GlassFrog (role name changes, new accountabilities, new domains, new policies). The API cannot do this -- it must be done through the GlassFrog UI.
3. **Note deferred tensions** -- any tensions raised but not processed, formatted for a future governance meeting agenda

---

## Common Facilitation Challenges

**"Can't we just decide this without the full process?"**: No. The IDM process is what gives governance changes their constitutional authority. Bypassing it means the change is not constitutionally adopted. You can run through the process quickly for simple proposals, but you cannot skip phases.

**A proposal is unclear**: If after Phase A and Phase B the proposal is still ambiguous, ask: "Before we move to reactions, can you restate the proposal in one sentence?" The Facilitator has the authority to ask for this clarity.

**The reaction round becomes a debate**: If reactors start responding to each other rather than simply sharing their reactions, redirect: "Let's keep this as individual reactions -- save the conversation for after the meeting."

**The same objection keeps coming back**: If an objector keeps raising an invalid objection in different words, name the pattern gently: "I've tested this a couple of ways now and it doesn't meet the constitutional bar for a valid objection. I'm going to set it aside and we'll proceed." The Facilitator has the authority to make this call.

**Someone tries to make a counter-proposal**: Counter-proposals are not part of the IDM process. If someone wants to propose something different, they can add it to the agenda for the same or a future governance meeting.

**The proposer withdraws the proposal**: A proposer can withdraw their proposal at any time before adoption. If this happens mid-objection-round, acknowledge it and move to the next agenda item.

**Time runs out**: If the meeting is running long, check in with the group: "We have [N] items remaining and [X] minutes. Should we defer remaining items to the next governance meeting, or would you like to continue?" Defer rather than rush the process.
