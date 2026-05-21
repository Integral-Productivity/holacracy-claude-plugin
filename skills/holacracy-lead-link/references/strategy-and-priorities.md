# Strategy and Priorities -- Lead Link Reference

This reference provides detailed guidance for setting, refining, and communicating circle strategy, and for translating strategy into day-to-day prioritization. Load it when the user needs substantive strategy work, not just a quick framing.

---

## What Strategy Is (and Is Not) in Holacracy

Strategy in Holacracy has a specific meaning that differs from its use in traditional management:

**Strategy in Holacracy**: A heuristic that guides prioritization choices when trade-offs are unavoidable. It answers the question: "When we cannot do everything equally well, what do we emphasize?"

**Not strategy**: Goals, objectives, values, mission, vision, OKRs, quarterly targets, project roadmaps, or anything that can be checked off as completed. These are operational artifacts. Strategy is a persistent lens.

The canonical Holacratic strategy form is: **"Emphasize [X], even at the expense of [Y]."**

This form is powerful because it:
1. **Makes trade-offs visible.** It refuses the fiction that everything is equally important.
2. **Is self-applying.** Anyone in the circle can apply the strategy to a new situation without consulting the Lead Link.
3. **Is falsifiable.** If people disagree about what the strategy requires in a given situation, that's data about whether the strategy is clear enough.
4. **Is reversible.** The Lead Link can change strategy when circumstances change.

---

## Strategy Statement Anatomy

A well-formed strategy statement has three components:

| Component | Description | Example |
|-----------|-------------|---------|
| **Emphasis** | What to invest in, prioritize, protect | "Emphasize learning and experimentation" |
| **Even at the expense of** | What is explicitly deprioritized | "...even at the expense of execution speed" |
| **Scope** | What this applies to (optional; defaults to the whole circle) | "...in product development initiatives" |

**Strong strategy statements:**
- "Emphasize learning velocity, even at the expense of output quality in early iterations."
- "Emphasize client depth over client breadth -- serve fewer clients better rather than more clients shallowly."
- "Emphasize infrastructure reliability, even at the expense of new feature development."
- "Emphasize community trust, even at the expense of rapid scaling."

**Weak strategy statements (and why):**
- "Be excellent in all areas." -> No trade-off named. Not actionable.
- "Focus on growth." -> Growth is a goal, not a heuristic. It doesn't tell you how to choose.
- "Deliver value to customers while managing cost." -> The "while" clause removes the trade-off. What happens when they conflict?

---

## The Strategy Setting Process

### Step 1: Ground in Circle Purpose

Read the circle's purpose statement aloud before any strategy work. Every strategy decision should serve the purpose -- if it doesn't, reconsider.

Ask: "What is the circle here to do, at its most essential? What would be lost if this circle disappeared?"

### Step 2: Surface Current Trade-offs

The current state of the circle's work reveals implicit strategy. Before naming an explicit strategy, surface what the current implicit one is:

- What gets attention? What gets deferred?
- What is consistently over-resourced? What is consistently under-resourced?
- What tensions come up repeatedly in tactical meetings that never quite get resolved?
- What decisions tend to require the Lead Link's input -- what question keeps recurring?

Patterns in these answers reveal what the circle is *actually* optimizing for, regardless of what the strategy statement says.

### Step 3: Identify the Real Choices

Name the genuine trade-offs the circle is navigating. These often take the form of tensions between:

| Pair | Common in circles that... |
|------|--------------------------|
| Speed vs. quality | Ship products or deliver client work |
| Depth vs. breadth | Serve multiple markets or client types |
| Exploration vs. exploitation | Balance innovation with execution |
| Autonomy vs. coordination | Have interdependent roles |
| Growth vs. sustainability | Face scaling pressure |
| Internal capacity vs. external commitments | Mix service and product work |

### Step 4: Draft Candidate Strategies

Generate two or three candidate strategy statements. The goal is not to find the "right" one on the first try -- it is to make the trade-offs explicit enough to react to.

For each candidate:
1. State the heuristic
2. Name a recent real decision the circle faced
3. Apply the heuristic: "Under this strategy, we would have done [X]."
4. Is that the right answer? If not, refine.

Iteration is expected. A good strategy statement rarely emerges fully formed.

### Step 5: Stress-Test Against Live Work

Once a candidate strategy is selected, run it against three to five current projects or decisions:

- "Our Lead Link is dealing with [specific situation]. Under this strategy, the right call is [X]. Does that feel right?"
- "We have [Project A] and [Project B] competing for capacity. This strategy says emphasize [X] even at the expense of [Y]. That means [Project A/B] gets prioritized. Does that track?"

If applying the strategy consistently produces wrong answers, the problem is with the statement, not the situation. Refine until the heuristic is genuinely useful.

### Step 6: Record and Communicate

Once the strategy is finalized:

1. **Record it in GlassFrog**: Strategy is stored in the circle's governance record. The Lead Link cannot update it via API -- update it in the GlassFrog UI. Confirm the current state first: `glassfrog_get_circle(circle_id)` to read the existing strategy field.
2. **Communicate it to circle members**: A strategy no one knows about is not a strategy. Produce a brief communication explaining:
   - What the strategy is
   - What it means in practice (two or three examples)
   - What it explicitly *does not* prioritize and why
3. **Make it available in meetings**: The strategy should be referenced at the start of tactical meetings' triage section, so prioritization decisions can be made with it in view.

---

## Priority Setting

Strategy guides priorities but doesn't automatically produce a prioritized list. The Lead Link's prioritization work translates strategy into ordered action.

### Types of Prioritization

**Circle-level prioritization**: Across the full portfolio of the circle's work, what matters most right now? This is typically revisited quarterly or when the circle's context shifts significantly.

**Tactical prioritization**: In a given week or sprint, given the circle's strategy, what should each role-filler be focusing on? This is a service the Lead Link provides -- it does not replace the role-filler's judgment, but it gives shared context.

**Conflict resolution**: When two role-fillers' work creates a resource conflict, the Lead Link's priority guidance is what resolves it. "The strategy says emphasize X, so [Role A]'s project takes precedence over [Role B]'s for this sprint."

### Priority Framework

Load current projects from GlassFrog and apply this assessment to each:

| Dimension | Question | Score |
|-----------|----------|-------|
| **Strategy alignment** | How directly does this serve the current strategy emphasis? | High / Medium / Low |
| **Purpose alignment** | How directly does this serve the circle's purpose? | High / Medium / Low |
| **External commitment** | Is there an external commitment attached? | Yes (locked) / No (flexible) |
| **Time sensitivity** | Does this become harder to do over time? | Urgent / Normal |
| **Dependencies** | Does other work depend on this? | Blocking / Independent |

Projects scoring High / High with external commitments or dependencies go to the top. Projects scoring Low / Low with no commitments can be deferred or abandoned without significant cost.

### Communicating Priorities

After completing a priority assessment, produce a brief priority memo for the circle:

```
Circle Priority Memo -- [date]

Strategy in effect: [strategy statement]

Current priorities (in order):

1. [Project / Work Area] -- [one sentence rationale tied to strategy]
2. [Project / Work Area] -- [one sentence rationale tied to strategy]
3. [Project / Work Area] -- [one sentence rationale tied to strategy]

Currently deprioritized (and why):
- [Item] -- [brief reason, e.g., "low strategy alignment, no external commitment"]

Next priority review: [proposed date]
```

### Communicating Priority Changes

When the Lead Link changes priorities, circle members need to understand why -- especially when something that felt important is being deprioritized. A brief change notice:

```
Priority update -- [date]

What changed: [brief description]
Why: [strategy reason or new constraint]
What this means for your work: [specific impact, role by role if needed]
```

---

## Strategy in Solo-Operator Contexts

When one person fills most or all roles, strategy setting is simultaneously an organizational discipline and a personal discipline. The risk is that strategy becomes implicit, living only in the person's head as "intuition about what matters."

**The discipline of explicit strategy in solo-operator contexts**:
- Write the strategy down. Even if no one else needs to read it, the act of articulating it forces clarity.
- Apply the "even at the expense of" test to your own weekly decisions: "Am I actually living the strategy, or is urgency hijacking it?"
- Review strategy at regular intervals (monthly is a reasonable minimum). A solo operator's context changes quickly; strategy that was right six months ago may not be right now.

**The role-separation discipline**: When working on strategy, put on the Lead Link hat explicitly. "Right now I'm doing Lead Link work -- setting the conditions under which this circle operates. My view as a role-filler on what I'd prefer to work on is not the same as my Lead Link view on what the circle should emphasize."

---

## Strategy Failure Modes

| Failure Mode | Symptom | Fix |
|-------------|---------|-----|
| Strategy as aspiration | Statement describes desired state, not a trade-off | Rewrite with "even at the expense of" |
| Strategy as laundry list | Three or more emphasis areas with no priority among them | Force the hardest trade-off: if only one emphasis could survive, which? |
| Strategy as secret | Role-fillers make decisions inconsistently; Lead Link is repeatedly consulted | Communicate explicitly; embed in tactical meetings |
| Stale strategy | Current work doesn't resemble what the strategy would predict | Review and update; the world changed |
| Strategy-execution gap | Strategy exists but allocation decisions consistently contradict it | Audit actual allocation against strategy; the gap is a tension to process |
