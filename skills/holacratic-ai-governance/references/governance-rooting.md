# Governance Rooting -- Structural Placement of Projects in Holacratic Organizations

This reference defines how to determine where a project belongs in a Holacracy-governed organization's structure: which role should own it, which circle it lives in, and how that placement holds up over the project's lifespan.

---

## What Is Governance Rooting?

In Holacracy, a project is always owned by a specific role -- not a person, not a team, not an informal group. The role's accountabilities define what work it is authorized to do. A project that cannot be traced to a role's accountability is work without organizational authorization -- and that is a governance tension, not just an administrative gap.

"Rooting" a project means anchoring it to the governance structure in a way that makes its authorization explicit. A well-rooted project has:
- A role whose accountability directly authorizes the work
- A circle whose strategy aligns with the project's direction
- A clear picture of what happens to ownership if the project's scope expands

---

## When to Use This Pattern

Load this reference when:
- The user asks "where does this project belong?", "which role should own this?", "how do I root this in governance?", or "where in our structure should X live?"
- A project has just been created or is about to be created and its structural placement is ambiguous
- A project's scope has expanded and its current governance rooting may no longer be sufficient
- Pattern 3 (Tension Sensing) has surfaced an un-rooted or ambiguously-rooted project
- A new initiative is being proposed and the question is which circle should host it

---

## Step-by-Step Procedure

### Step 1 -- Check for Existing Governance Placement

Before making any recommendation, check whether the project already exists in GlassFrog.

```
Call: glassfrog_list_projects (circle_id for the most plausible candidate circle, or all)
Purpose: Determine if the project is already tracked and already rooted
```

If the project already exists: note its current role assignment. The task becomes *confirmation and rationale* -- is this the right home? If the placement looks correct, affirm it with governance reasoning. If it looks wrong, name the tension.

If the project does not exist: proceed to Step 2. The task becomes *recommendation and rationale*.

### Step 2 -- Identify Candidate Circles and Roles

Identify which circle(s) are plausible candidates for the project. Start with the circle most obviously related to the project's domain (technology, product, operations, coaching, etc.). Load its full structure.

```
Call: glassfrog_get_circle(circle_id)
Purpose: Get all roles and the circle's strategy
```

For each role in the candidate circle(s), load full details:

```
Call: glassfrog_get_role(role_id)
Purpose: Get purpose, accountabilities, and domains
```

### Step 3 -- Map Project Activities to Accountabilities

List the project's core activities -- what will actually be *done* in this project? Then assess each candidate role's accountabilities against those activities.

**Semantic alignment tiers:**

- **High**: The accountability's meaning substantially overlaps with the project's work. The accountability language directly names the kind of activity involved, and a Holacracy facilitator would agree without argument that the project belongs here.
- **Medium**: Partial overlap -- some elements of the accountability connect to the project's work, but not all. The project fits the spirit of the accountability, though inference is required to close the gap.
- **Low**: Minimal overlap -- the project is adjacent to the accountability but requires significant stretching to connect. Worth naming when no higher-alignment candidate exists, but not ideal as a primary anchor.
- **None**: The accountability's meaning doesn't overlap with the project's work. The project needs either a different structural home or a governance proposal to create the needed accountability.

High semantic alignment should be the norm. If the best available candidate is medium or low, that is usually a signal that the project either needs a different structural home or the current governance needs a new accountability to grow into.

### Step 4 -- Check Circle Strategy Alignment

Once a candidate role is identified, check whether the parent circle's strategy supports this kind of work.

Holacratic circle strategies are often written as explicit prioritization trade-offs (e.g., "architectural experiments *over* best practice adoption"). Read the strategy as a directional signal:

- **Strong confirmation**: The strategy language explicitly favors the type of work this project represents. Quote the strategy language when presenting the recommendation -- it is the strongest governance evidence available.
- **Neutral**: The project neither aligns with nor contradicts the strategy. It can still live here; note the neutral status.
- **Misaligned**: The project feels like it works *against* the circle's strategic priorities. Name this tension. The project may need a different circle, or the tension may reveal that the strategy itself needs updating.

### Step 5 -- Assess Role Purpose and Circle Purpose Fit

Beyond individual accountabilities, check whether the project fits within the role's *purpose* -- what the role exists to do at a broader level. Purpose defines the spirit; accountabilities define the letter.

A project that fits the spirit but not the letter may be a good candidate for a new accountability to add via governance -- that is itself a useful finding to surface.

Similarly, check the circle's purpose. A circle with a broad purpose (e.g., "shape the corporation toward its organizational purpose") may legitimately host work that no single existing role's accountabilities perfectly cover.

### Step 6 -- Identify the Scope Expansion Tension

Every project has a potential trajectory. Think one phase ahead: as this project matures, what will it produce and who will it affect?

- If the project starts as a focused technical effort but its outputs will eventually influence organizational behavior, it may develop accountability overlap with roles focused on people, process, or culture.
- If deliverables will serve all circles, consider whether the project should eventually move to a more central circle or spawn cross-circle coordination.
- If the project builds infrastructure that other roles will depend on, assess whether a domain claim will eventually be needed.

Name this forward tension explicitly in the recommendation -- not as a reason to delay rooting the project, but as a governance signal to watch as it matures.

### Step 7 -- Produce the Recommendation

A governance rooting recommendation has four components:

1. **Structural placement**: The recommended role and circle, stated plainly.
2. **Accountability rationale**: Which specific accountability(ies) authorize the project's work, quoted or paraphrased from the live governance data.
3. **Strategy alignment**: Whether and how the circle's strategy supports this project. Quote the strategy language when it is a direct match.
4. **Scope expansion tension**: The governance consideration to monitor as the project matures.

Write the recommendation as prose with enough specificity that someone reading it could verify each claim directly in GlassFrog.

---

## Handling Ambiguity

### Multiple Plausible Roles

If two or more roles both have accountabilities that plausibly cover the project's work:

1. Determine which accountability has *higher semantic alignment* -- more direct meaning-overlap, less inferential
2. Check which role's purpose fits better at a conceptual level
3. Check which circle's strategy provides stronger directional support
4. If still ambiguous: name both candidates, explain the trade-offs, and present this as a governance question for the role-filler or Lead Link to decide. Accountability overlap between sister roles may itself be a tension worth processing in governance.

### Project Spans Multiple Circles

If the project's work genuinely spans multiple circles:

1. Identify the circle that owns the *initiating work* -- the phase of work that happens first
2. Root the project in the role closest to that initiating work
3. Note the cross-circle dependencies explicitly and suggest a governance conversation about whether a cross-link or explicit coordination policy is needed

### No Role Fits

If no existing role's accountability covers the project's work:

- Name it clearly: "This project doesn't currently map to any defined role or accountability."
- Frame it as a tension: either the project needs a different home, or someone needs to bring a governance proposal to create the needed accountability
- Suggest which circle is the best structural candidate for a new accountability, based on purpose and strategy alignment

---

## Accountability Mapping Quick Reference

When assessing whether a role's accountability authorizes a project, ask:

| Question | Signal |
|---|---|
| Does the accountability's meaning substantially overlap with the project's work? | High semantic alignment |
| Would a Holacracy facilitator agree without argument that the project belongs here? | High semantic alignment |
| Does connecting the project to the accountability require inference or stretching? | Medium or Low alignment -- worth naming |
| Is there no meaningful overlap between the accountability and the project's activities? | No alignment -- potential governance gap |

---

## Worked Example

**Prompt**: "Where does the Holacracy Skill Integration project belong in our governance structure?"

**Governance rooting recommendation**:

*Check existing placement* -> Project 1941787 already exists in GlassFrog, assigned to the Technology Architecture role (ID 13982026) in the Enterprise Architecture circle (ID 133636). Task shifts to confirmation and rationale.

*Accountability rationale*: The Technology Architecture role holds three accountabilities: "Experimenting with technologies to assess their potential impact on the organization and our purpose," "Curating technologies with high potential for overall impact, efficiency, and effectiveness," and "Proposing how to integrate technologies to support our purpose." The project's six steps are directly authorized: skill trigger redesign and GlassFrog context automation fall under the first accountability; the plugin packaging step falls under the second; and the standing directive and skill hook work fall clearly under the third. **High semantic alignment.**

*Strategy alignment*: The Enterprise Architecture circle strategy explicitly prioritizes "architectural experiments over best practice adoption." There is no established best practice for integrating AI governance awareness into an organizational technology stack -- this project is precisely an architectural experiment. The strategy language provides strong directional confirmation.

*Scope expansion tension*: As the project matures past Step 3 (governance hooks in high-affinity skills), its outputs will begin to shape how all circles interact with AI assistance -- shifting the footprint from technology integration into organizational operating system design. This starts to overlap with the Business Architecture role's mandate to "facilitate evolving the business architecture -- people, process, culture." The current rooting is correct for the build phase. As the integration pattern is validated, a governance proposal should be considered to either add an explicit accountability to Technology Architecture covering AI-governance integration, or establish a coordination mechanism with Business Architecture. **Watch for this before Step 6 (plugin packaging) begins.**
