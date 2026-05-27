# Engagement Patterns -- Detailed Implementation Guide

This reference provides step-by-step implementation guidance for each core engagement pattern, including exact tool call sequences, edge case handling, and worked examples.

---

## Table of Contents

1. [Pattern 1: Role Context Injection](#pattern-1-role-context-injection)
2. [Pattern 2: Multi-Perspective Synthesis](#pattern-2-multi-perspective-synthesis)
3. [Pattern 3: Tension Sensing](#pattern-3-tension-sensing)
4. [Pattern 4: Governance-Aware Response Calibration](#pattern-4-governance-aware-response-calibration)
5. [Pattern 5: Proactive Tension Sensing (in conversation)](#pattern-5-proactive-tension-sensing-in-conversation)
6. [Composite Workflows](#composite-workflows)
7. [Edge Cases and Failure Modes](#edge-cases-and-failure-modes)

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
- **Capture?**: [yes / no / skip]
```

**Step 5 -- Offer per-finding capture**

For each finding in the report, offer the user the option to convert it into a real filed tension via the `tension-capture` subagent. The subagent runs `skills/shared/tension-capture-flow.md` Steps 2–8: it resolves the sensing role from the actor's role roster, applies the role-vs-person triage gate, drafts the body using the report's suggested tension statement as the seed, suggests `meeting_type` per the report's recommendation, and waits for the user's per-tension confirmation before calling `glassfrog_create_tension`.

The user can:

- **Capture one or more** findings -- the subagent runs once per finding the user picks.
- **Treat the whole report as text** -- the original v0.2 behavior. Useful when reviewing en masse before any filing.
- **Skip individual findings** as false positives. Pattern 3 outputs candidate tensions; the user is the final arbiter of which are real.

### Important Boundaries

- Tension *detection* is appropriate for AI. Tension *processing* -- deciding what to do about a tension -- is a human governance activity. The capture-via-subagent path does not blur this: filing a tension as `status: "unprocessed"` is still capture, not processing. Processing happens when a human governance or tactical meeting works the tension.
- Not all detected anomalies are real tensions. Orphaned data may reflect a governance change that the API data hasn't fully propagated. Present findings with appropriate epistemic humility, and never force-capture; the user opts in per finding.
- The user may want to filter tensions by severity, type, or circle. Support flexible output.

---

## Pattern 5: Proactive Tension Sensing (in conversation)

### Purpose

Listen for tension language during ordinary conversation and offer to capture in flow. Where Pattern 3 mines structured governance data for anomalies, Pattern 5 reads the *user's own words* for the felt experience of a gap.

This is the heart of the plugin's "proactive" stance: tensions are surfaced where they emerge -- in the user's framing of their work -- not held back until a periodic audit fires.

### When to invoke

Continuously, while the `holacratic-ai-governance` skill is loaded and the session is in interactive (non-routine) context. There is no separate command to run Pattern 5; it is an ambient attention pattern.

### Trigger phrases

Watch for the conversational shapes that signal a tension is being lived:

- **Recurrence:** "we keep hitting...", "this happens every time...", "the third time this quarter...", "for the Nth time..."
- **Gap framing:** "no one owns...", "there's no clear path...", "the accountability doesn't cover...", "the role wasn't designed for..."
- **Blockage:** "I can't get...", "we're waiting on...", "I need approval but...", "I'm blocked by..."
- **Friction:** "it's frustrating that...", "this is taking way too long because...", "I'm stuck on...", "the process makes me..."
- **Structural misfit:** "the way this is set up...", "this doesn't fit anywhere", "I had to invent a workaround because..."

### Procedure

**Step 1 -- Pause briefly.**

When a trigger phrase appears, complete the immediate exchange (don't cut off the user mid-thought), then pause.

**Step 2 -- Offer to capture.**

Use natural language, not a structured prompt. *"That sounds like a tension worth filing -- want me to draft one?"* Or *"Want me to capture that as a tension before we move on?"*

**Step 3 -- If the user assents, dispatch the subagent.**

Dispatch the `tension-capture` subagent with: the conversational excerpt that surfaced the tension, any circle context already known from the session, and a hint about which role the actor seemed to be operating from. The subagent runs Steps 2–8 of `skills/shared/tension-capture-flow.md`.

**Step 4 -- If the user declines or deflects, drop it.**

Decline takes many shapes: "not now", "let me think about it", "let's keep going", or just continuing to answer the original question. In any case, drop the offer cleanly and resume the original work. Do not re-offer the same tension; if it's real, it will surface again.

**Step 5 -- On subagent return, resume the original work.**

The subagent returns a structured result (tension ID, role/circle, meeting type). Surface it as a one-line acknowledgment and return to the original conversation thread.

### Calibration

Pattern 5 is gentle. The user is *working*, not auditing tensions. One offer per detected tension, no nag, no batching. If the user files three tensions in one session, the supersession sweep at session close catches any overlap.

### When to suppress Pattern 5

- The user is in a focused execution mode (e.g., "stop talking and just do X"). Read the room.
- The conversation is about something other than the user's own work -- e.g., the user is helping someone else, or analyzing a hypothetical. Tensions belong to the lived role-filler; if the user isn't the role-filler, capture is the wrong move.
- The user has just declined a similar offer in this session. Give the pattern a few turns before re-attempting.
- **The user is in an active Tactical Meeting** (invoked `/holacracy:tactical`, or the `holacracy-secretary` skill is the loaded skill driving live tactical capture). The Secretary's "Backlog-first tension capture" in `skills/holacracy-secretary/SKILL.md` is the right surface for in-meeting tension capture — Pattern 5 should not interrupt the meeting flow with parallel offers. Pattern 5 owns everything outside the active tactical-meeting context.

### Session-closing offer

When the user signals session closing ("done for now", "that's it for today", "good enough", "wrapping up"), and tensions were filed during the session, offer:

> *"Before we close -- want me to sweep the tensions filed this session for supersession?"*

If yes, run `/holacracy:supersession-sweep` with the default `session` scope. If no, close normally. Silent when no tensions were filed.

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
