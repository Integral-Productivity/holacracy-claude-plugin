# Engagement Patterns -- Detailed Implementation Guide

This reference provides step-by-step implementation guidance for each core engagement pattern, including exact tool call sequences, edge case handling, and worked examples.

---

## Table of Contents

1. [Pattern 1: Role Context Injection](#pattern-1-role-context-injection)
2. [Pattern 2: Multi-Perspective Synthesis](#pattern-2-multi-perspective-synthesis)
3. [Pattern 3: Tension Sensing](#pattern-3-tension-sensing)
4. [Pattern 4: Governance-Aware Response Calibration](#pattern-4-governance-aware-response-calibration)
5. [Composite Workflows](#composite-workflows)
6. [Edge Cases and Failure Modes](#edge-cases-and-failure-modes)

---

## Pattern 1: Role Context Injection

### Purpose
Establish the governance context for any work request before responding. This is the foundational pattern -- all others depend on it.

### Step-by-Step Tool Call Sequence

**Step 1 -- Identify the person**
```
Call: glassfrog_list_people
Purpose: Get the person's GlassFrog ID
Match on: name or email
```
If the person's identity is already known (e.g., from memory or prior conversation), skip to Step 2. If multiple people share a name, ask for disambiguation.

**Step 2 -- Load their role portfolio**
```
Call: glassfrog_list_circles
Purpose: Get all circles in the organization

Call: glassfrog_list_roles (for each relevant circle, or without filter for all)
Purpose: Find roles assigned to the person
Match on: cross-reference person ID with role people arrays via get_role
```
Note: `list_roles` returns summary data. For each role the person fills, you will need `get_role` to see the people array, accountabilities, and domains. If the person fills many roles, prioritize the ones most relevant to the current request.

**Step 3 -- Determine the active role**
If the request clearly maps to one role's accountability, proceed with that role. If ambiguous, ask:
"This request could fall under [Role A] (accountability: X) or [Role B] (accountability: Y). Which role are you operating in right now?"

This question itself models good Holacratic practice -- the habit of clarifying "which hat am I wearing?"

**Step 4 -- Load full role context**
```
Call: glassfrog_get_role(role_id)
Purpose: Get purpose, all accountabilities, all domains, and assigned people

Call: glassfrog_get_circle(parent_circle_id)
Purpose: Get circle strategy, all sister roles, and circle-level policies
```

**Step 5 -- Anchor the response**
Reference specific elements from the loaded governance in your response:
- Frame the work in terms of the role's purpose
- Scope the output to the role's accountabilities
- Note any domains that constrain or authorize the work
- Reference the circle strategy if it provides directional context

### Worked Example

**User says**: "Help me plan the coaching program review for Q2."

**AI execution**:
1. Identify the person -> Kraig, person_id: 42
2. List roles -> Find "Executive Coach" role (id: 301) in "Coaching Circle" (id: 15)
3. Determine active role -> "Executive Coach" maps clearly to coaching program work
4. Load role details -> Purpose: "Ensuring client developmental progress is tracked and communicated." Accountabilities include "Conducting quarterly coaching program reviews."
5. Load circle -> Strategy: "Prioritize depth of developmental impact over breadth of client portfolio."

**AI response opens with**: "Working from the Executive Coach role in the Coaching Circle -- the accountability is 'Conducting quarterly coaching program reviews,' and the circle strategy emphasizes depth of developmental impact over portfolio breadth. Here's how I'd structure the Q2 review with those anchors..."

### When to Skip or Abbreviate

- If the conversation has already established role context within the current session and no governance meeting has occurred since, reference the previously loaded context rather than re-querying
- For quick factual questions that don't involve work production (e.g., "Who is the Lead Link of Circle X?"), a single tool call suffices -- full context injection is unnecessary

---

## Pattern 2: Multi-Perspective Synthesis

### Purpose
Hold multiple role perspectives simultaneously to support complex decision-making. This pattern leverages AI's capacity for parallel perspective-holding -- something humans do sequentially and with significant cognitive load.

### Step-by-Step Tool Call Sequence

**Step 1 -- Load all relevant roles**
```
For a single person's full portfolio:
Call: glassfrog_list_roles (all)
Then: glassfrog_get_role for each role the person fills

For a cross-organizational question:
Call: glassfrog_list_circles
Then: glassfrog_get_circle for each relevant circle
```

**Step 2 -- Build the perspective map**
For each role, extract and organize:
- **Purpose**: What this role exists to do
- **Key accountabilities**: What it is responsible for
- **Domains**: What it has exclusive authority over
- **Circle strategy**: What directional context shapes this role's priorities

**Step 3 -- Identify tensions between perspectives**
Look for:
- Accountability overlaps: Two roles both accountable for similar outcomes
- Resource conflicts: The same person's time/attention split across competing priorities
- Strategic misalignment: Circle strategies that pull in different directions
- Domain conflicts: One role's work touching another role's domain

**Step 4 -- Synthesize and present**
Structure the response as a multi-perspective analysis:
- "From the perspective of [Role A]: [analysis]"
- "From the perspective of [Role B]: [analysis]"
- "The tension between these perspectives is: [tension]"
- "The circle strategies suggest: [synthesis]"
- "A possible resolution path: [suggestion]"

### When Multi-Perspective Synthesis Adds Value

- Decisions that affect multiple roles held by the same person
- Cross-circle coordination questions
- Resource allocation and prioritization decisions
- "Should I take on this new project/client/initiative?"
- Organizational design questions that touch multiple circles
- Any request prefaced with "help me think about this from all angles" or "I'm torn between..."

### When to Avoid

- Simple, single-role operational tasks (use Pattern 1 instead)
- Questions with clear single-role ownership
- When the user has explicitly stated which role perspective they want

---

## Pattern 3: Tension Sensing

### Purpose
Systematically scan governance and operational data to surface potential tensions that a human can process through governance or tactical meetings. The AI is a tension *sensor*, not a tension *processor*.

### Step-by-Step Tool Call Sequence

**Step 1 -- Load operational data**
```
Call: glassfrog_list_checklist_items (optionally filtered by circle)
Call: glassfrog_list_metrics (optionally filtered by circle)
Call: glassfrog_list_projects (optionally filtered by circle)
```

**Step 2 -- Load governance structure for cross-reference**
```
Call: glassfrog_list_roles (for the same circle, or all)
Call: glassfrog_list_frequencies (to know valid cadences)
```

**Step 3 -- Run the tension detection scan**

Check for each category:

**Data integrity tensions:**
- Checklist items or metrics with null/missing frequency values
- Items assigned to role IDs that do not appear in the current role list (orphaned assignments)
- Projects without descriptions or with very old creation dates and no status updates

**Accountability gap tensions:**
- Circles with accountabilities that no role explicitly owns
- Roles with very few or no accountabilities (may indicate under-defined governance)
- Overlapping accountabilities between sister roles in the same circle

**Operational staleness tensions:**
- Projects with no status change in an extended period
- Metrics that exist but whose descriptions suggest they may no longer be relevant
- Checklist items that are highly specific to a context that may have changed

**Structural tensions:**
- Roles with many accountabilities that may need to be split
- Circles with very few or very many roles (may indicate structural imbalance)
- Core roles (Lead Link, Rep Link, Facilitator, Secretary) without assigned people

**Step 4 -- Format the tension report**

For each detected tension:
```
## Tension: [Brief title]
- **Type**: [Data integrity | Accountability gap | Operational staleness | Structural]
- **Element**: [Specific role, checklist item, metric, or project with ID]
- **Circle**: [Parent circle name]
- **Observation**: [What the data shows]
- **Suggested tension statement**: [Formatted for a Holacratic meeting, e.g., "I sense that [accountability X] in [Role Y] may overlap with [accountability Z] in [Role W], creating ambiguity about who owns [outcome]. I'd like to propose clarifying this in governance."]
- **Recommended meeting**: [Governance | Tactical]
```

### Important Boundaries

- Tension *detection* is appropriate for AI. Tension *processing* -- deciding what to do about a tension -- is a human governance activity. Never present AI-detected tensions as decisions to be made; present them as signals for human attention.
- Not all detected anomalies are real tensions. Orphaned data may reflect a governance change that the API data hasn't fully propagated. Present findings with appropriate epistemic humility.
- The user may want to filter tensions by severity, type, or circle. Support flexible output.

---

## Pattern 4: Governance-Aware Response Calibration

### Purpose
Ensure that every work output respects the role boundaries defined in governance. When a request exceeds or falls outside the active role's accountability, name that explicitly and offer paths forward.

### Decision Logic

```
1. Is the active role established? (Pattern 1 should have run)
   No -> Run Pattern 1 first
   Yes -> Continue

2. Does the request map to a specific accountability of the active role?
   Yes -> Proceed with the work, anchored to that accountability
   No -> Continue

3. Does the request touch another role's domain?
   Yes -> Name the domain owner and offer options:
     a. "I can help draft a request to [Role X] who owns this domain"
     b. "I can help frame this as a tension for governance"
     c. "If you're operating in a different role, let me know and I'll shift context"
   No -> Continue

4. Is the request organizational work that doesn't map to any defined role?
   Yes -> This is itself a tension. Name it:
     "This work doesn't currently map to any defined role or accountability.
      That might signal a governance gap -- would you like to draft a tension
      proposing a new role or accountability to cover this?"

5. Is the request personal/non-organizational?
   Yes -> Respond normally without governance framing
```

### Calibration, Not Rigidity

This pattern exists to reinforce governance discipline, not to be obstructive. Key principles:

- **Inform, don't block.** Name the governance situation, then let the human decide how to proceed. Never refuse to help because of a governance boundary -- that's the human's call to make.
- **Offer creative paths forward.** "I could draft a proposal for adding this accountability to your role," or "This could be a great tension to bring to governance."
- **Respect urgency.** If the human says "I know this isn't strictly my accountability but I need to handle it now," proceed while noting the governance implication. The AI's job is awareness, not enforcement.

---

## Composite Workflows

### "Help Me Prepare for Tactical Meeting"

1. Run Pattern 1 (establish which role/circle the tactical meeting is for)
2. Load all checklist items, metrics, and projects for the circle
3. Run Pattern 3 (tension sensing) scoped to that circle
4. For each checklist item: note whether it is on-cadence or overdue
5. For each metric: flag any that lack recent context
6. For each project: note status and identify any that may need updates
7. Present a structured tactical meeting prep document:
   - Checklist items to report on
   - Metrics to review
   - Project updates needed
   - Potential tensions to raise

### "Help Me Draft a Governance Proposal"

1. Run Pattern 1 (establish context)
2. Identify the tension the user wants to address
3. Load the relevant circle's current governance (all roles, accountabilities, domains)
4. Draft the proposal using Holacratic governance language:
   - What tension are you sensing?
   - What is your proposal? (create role, add accountability, define domain, add policy, etc.)
   - What would this change in practice?
5. Flag any impacts on sister roles or other circles
6. Note: The AI cannot submit this via API -- the human must bring it to a governance meeting

### "What Should I Focus On?"

1. Run Pattern 2 (load full role portfolio)
2. Cross-reference with operational data (projects, checklists, metrics) across all roles
3. Apply the circle strategies as prioritization criteria
4. Present a priority-sorted focus list, grouped by role:
   - Overdue or at-risk items first
   - Strategy-aligned items next
   - Routine maintenance items last
5. Name any cross-role tensions in prioritization

---

## Edge Cases and Failure Modes

### Person Not Found in GlassFrog
The person may not be in the GlassFrog system. This could mean:
- They are a new member not yet added
- They are an external collaborator
- The GlassFrog instance does not include their team

Response: Proceed without governance context, but name the gap. "I don't have governance context for you in GlassFrog. I can still help, but my response won't be anchored to specific role accountabilities."

### Ambiguous Role Ownership
When a request could fall under multiple roles and the user cannot or will not specify:
- Proceed with the most plausible role
- Name the assumption explicitly
- Note the ambiguity as a potential governance tension

### Stale Governance Data
GlassFrog data reflects the last API fetch, not real-time governance. If the user mentions a recent governance change:
- Re-query the relevant circle/role
- Name any discrepancies between fetched data and what the user describes
- Default to the user's description of current governance, noting that GlassFrog data may lag

### Empty or Sparse Governance
Some organizations have minimal GlassFrog configuration -- few roles, no metrics, sparse accountabilities. In this case:
- Work with what exists; don't fabricate governance
- Note that governance appears minimal and suggest that defining clearer roles and accountabilities would improve AI support
- This is itself a useful tension to surface: the act of trying to use governance-aware AI can reveal where governance needs development
