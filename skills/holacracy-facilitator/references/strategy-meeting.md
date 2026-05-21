# Strategy Meeting Facilitation -- v5.0

A Strategy meeting is a Lead Link-initiated session for setting or revisiting the circle's strategy. Unlike Tactical and Governance meetings, Strategy meetings have no constitutionally mandated format -- the Facilitator's job is to run a productive diverge-converge process that helps the Lead Link articulate clear strategy statements.

**Purpose**: Help the Lead Link develop strategy statements that guide how circle members should prioritize and make decisions in the absence of direct instruction.

**Who owns strategy**: The Lead Link. This is not a consensus decision -- it is an informed decision by the Lead Link, informed by perspectives from circle members. The process draws on the circle's collective intelligence, but the Lead Link decides.

**Output**: One or more strategy statements that are:
- Directional ("prioritize X over Y in similar situations")
- Durable (they apply across many decisions, not just one)
- Distinguishable (they help differentiate between choices that would otherwise look equivalent)

**Typical duration**: 90-180 minutes depending on circle complexity.

---

## Pre-Meeting Preparation

Load the current circle context before beginning:
```
glassfrog_get_circle(circle_id) -> current strategy, all roles, people
glassfrog_list_projects(circle_id) -> current project landscape
glassfrog_list_roles(circle_id) -> role purposes and accountabilities
```

Review the current strategy statement(s) if any exist. They will be either affirmed, refined, or replaced by the end of this session.

Present a brief context summary to the Lead Link before beginning:
> "I've loaded [Circle Name]'s current strategy: '[Current strategy statement(s)].' I've also reviewed the current roles and projects. Here's what I'm noticing about the current state of the circle before we begin... [brief synthesis]. Ready to start the strategy session?"

---

## Meeting Format -- Recommended Structure

This is a facilitation guide, not a mandatory script. Adapt the sections based on available time, the Lead Link's needs, and what the circle actually requires.

---

### Section 1: Ground in Current Reality (20-30 min)

Before generating strategy, the circle needs a shared picture of where it currently stands.

**Facilitation script**:
> "Before we explore where we want to go, let's ground in where we actually are. I'll ask a few questions to surface the current reality. Answer from your role's perspective -- what you observe, not what you think should be true."

**Questions to ask (select or adapt)**:
- "What is the circle doing really well right now?"
- "Where are we falling short of our purpose?"
- "What tensions keep coming up that we haven't fully resolved?"
- "What's changed in our context -- internally or externally -- since we last set strategy?"
- "What are we saying no to that we wish we could say yes to?"
- "What's our biggest constraint right now?"

**Facilitation guidance**:
- This section is about sensing, not solving. Keep it descriptive.
- If discussion starts to drift into solutions, redirect: "Let's hold that idea -- I want to make sure we fully map the terrain first."
- The AI can surface patterns from the GlassFrog data loaded during prep: "Based on the project list, I notice [X]. Does that match what you're experiencing?"

After this section, briefly synthesize: "Here's the picture I'm hearing of current reality: [synthesis]. Does that feel accurate?"

---

### Section 2: Diverge -- Explore Strategic Options (30-45 min)

With reality grounded, explore the strategic landscape without converging prematurely.

**Facilitation script**:
> "Now let's explore the possibilities. We're not deciding yet -- we're opening up the space. I'll offer some strategic questions. Don't filter your answers for feasibility; just say what's true from your perspective."

**Questions to ask (select or adapt)**:
- "If you could only focus on one thing this circle does for the next year, what would it be?"
- "What opportunity are we most at risk of missing?"
- "If you were advising a peer circle, what would you tell them to prioritize in our position?"
- "What does success look like for this circle in 12 months? 3 years?"
- "What trade-off feels most urgent to name -- what should we explicitly prioritize over what?"

**Strategic trade-off framing**: Strategy is often most useful when stated as a deliberate trade-off. Help the group articulate: "In a situation where we could do X or Y, we should generally do X." Examples:
- "Prioritize depth of client relationship over breadth of client portfolio"
- "Invest in platform stability over new feature development when resources are constrained"
- "Say yes to strategic partnerships before saying yes to revenue opportunities that don't build the platform"

Capture emerging themes and trade-off frames as they surface. Present them back to the group periodically: "I'm hearing a theme around [X]. Is that resonating?"

---

### Section 3: Converge -- Draft Strategy Statements (30-45 min)

Now the Lead Link moves from exploring to deciding. Other circle members can still offer input, but the Lead Link is making the call.

**Facilitation script**:
> "[Lead Link's name], based on what you've heard in this session, what directional choices feel most important to name? I'll help shape them into strategy statements."

Work with the Lead Link to draft strategy statements that are:
- **Directional**: They indicate a direction to move in, not just a goal
- **Trade-off bearing**: They imply what is less important, not just what matters
- **Broadly applicable**: They apply across many future decisions, not just the current situation

**Statement formats that work**:
- "Prioritize [X] over [Y]"
- "When [situation], default to [direction]"
- "Invest in [capability] before [other option]"

**Statement formats that don't work well**:
- "Be excellent at everything" (not directional)
- "Do X" (not a trade-off framing, just a goal)
- "Consider [X] when relevant" (too soft to actually guide decisions)

After drafting, read the statements back to the group: "Here are the strategy statements taking shape: [list them]. Do these reflect what you've been hearing and deciding, [Lead Link]?"

---

### Section 4: Validate and Stress-Test (15-20 min)

Before finalizing, stress-test the strategy statements against real scenarios.

**Facilitation script**:
> "Let's test these against a few real situations. I'll name a scenario and we'll see if the strategy actually guides the decision."

**Scenarios to test** (generate from the circle's actual work context):
- A common resource allocation dilemma from the current project list
- A recurring tension that has come up in governance or tactical
- A hypothetical future choice that the circle might face

For each scenario: "Given this situation, does [strategy statement] give you clear guidance? If not, what would make it clearer?"

After testing, allow the Lead Link to refine the statements based on what the tests revealed.

---

### Section 5: Finalize and Communicate

**Facilitation script**:
> "Let's state the final strategy. [Lead Link], what are the strategy statements you're adopting for [Circle Name]?"

The Lead Link states the final strategies. Record them precisely.

Then:
> "These strategy statements are now the circle's strategy. They guide how everyone in the circle should prioritize when facing trade-offs. The Secretary will need to update GlassFrog to reflect the new strategy."

**Note for the Secretary**: Strategy statements must be entered into GlassFrog through the UI -- the API does not support strategy write-back.

**Post-meeting**: Offer to draft a brief communication to the circle's members summarizing the new strategy and the rationale behind each statement.

---

## Closing

End the session with a brief closing round -- each person shares a word or reflection on what the session produced.

---

## Common Challenges

**The Lead Link wants consensus**: The process is designed to inform the Lead Link's decision, not create consensus. If the Lead Link seems to be waiting for the group to agree, gently clarify: "You've heard a range of perspectives -- the final call on strategy is yours. What are you deciding?"

**Strategy statements are too vague**: Push toward trade-off framing. "What does 'be a great circle' mean when you have to choose between X and Y? Which do you pick?"

**The circle already has strong strategy that just needs affirming**: Sometimes the session is brief because the current strategy is working. That's fine. "It sounds like the current strategy is still holding. Do you want to affirm it, refine it slightly, or leave it as-is?"

**There's no Lead Link present**: A Strategy meeting without the Lead Link is usually not productive -- they own the output. Suggest rescheduling. If the Lead Link has delegated strategy-setting authority to another role (possible in v5.0), proceed with that role-filler.

**People argue with the strategy after it's decided**: Strategy is a Lead Link authority. Once decided, the appropriate response to disagreement is to process a tension in governance (if the strategy violates constitutional norms) or to raise it with the Lead Link directly. Neither of those happens in this meeting.
