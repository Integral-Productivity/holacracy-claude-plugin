# Resource Allocation -- Lead Link Reference

This reference provides detailed guidance for the Lead Link's resource allocation work: mapping capacity, making allocation decisions, handling cross-circle requests, and governing your own time in solo-operator contexts. Load it for substantive allocation work or when navigating competing demands on circle resources.

---

## What Resource Allocation Means in Holacracy

**Constitutional basis**: The Lead Link is accountable for allocating the Circle's resources across its various Projects and/or Roles.

Resources in a circle context include:
- **Time and attention**: The most constrained resource in most circles
- **Budget**: Financial resources the circle controls
- **Access and authority**: Permissions, credentials, relationships that enable work
- **External capacity**: Contractors, vendors, or other partners who provide capability

The Lead Link's allocation role is to make explicit decisions about where these resources go -- rather than letting allocation happen by default, urgency, or whoever asks loudest.

**What allocation is not**: The Lead Link does not direct how role-fillers spend their time within their accountabilities. The Lead Link's authority is at the level of the circle's portfolio -- which projects and roles get what share of resources -- not at the task level within a role.

---

## Capacity Mapping

Before making allocation decisions, map the current state of the circle's capacity. This is the foundation for all subsequent allocation work.

### Full Capacity Map Procedure

**Step 1: Load all roles**
```
glassfrog_list_roles(circle_id) -> get full role inventory with accountabilities
```

For each role, estimate accountability weight:
- **High**: Multiple complex ongoing accountabilities; requires significant sustained attention (e.g., a role that is the primary interface with clients)
- **Medium**: Several accountabilities that require regular but not intensive attention
- **Low**: Lightweight role with limited or very specific accountability scope

**Step 2: Load all people and their assignments**
```
glassfrog_list_people -> cross-reference against role list
```

Build a person-to-role map: who fills which roles, and what is their total accountability weight across all assignments.

**Step 3: Load current operational work**
```
glassfrog_list_projects(circle_id) -> count active projects per role
glassfrog_list_checklist_items(circle_id) -> recurring time obligations per role
glassfrog_list_metrics(circle_id) -> reporting obligations per role
```

Active project count is a rough proxy for current load intensity. Combine with accountability weight to get a capacity estimate per person.

**Step 4: Identify capacity status per person**

| Capacity Status | Signal |
|----------------|--------|
| **Over-allocated** | Many roles with high accountability weight; numerous active projects; chronic project stalling |
| **Balanced** | Roles and projects are aligned with available time; projects are progressing |
| **Under-allocated** | Few roles or lightweight accountability; minimal active projects; potentially underutilized capacity |
| **Misallocated** | Total capacity seems fine, but work is concentrated in low-priority areas; strategy-execution gap |

**Step 5: Produce the capacity map**

```
Capacity Map -- [Circle Name] -- [date]
Strategy: [strategy statement]

| Person | Roles Filled | Accountability Weight | Active Projects | Capacity Status |
|--------|-------------|----------------------|-----------------|-----------------|
| [name] | [list]       | H/M/L                | [count]         | [status]        |

Key imbalances:
- [Over-allocated: who, why it matters]
- [Under-allocated: who, potential to redeploy]
- [Vacancies: roles without role-fillers]
- [Strategy misalignment: work in low-priority areas]

Recommended actions:
- [specific reallocation or governance proposal]
```

---

## Making Allocation Decisions

### The Allocation Decision Framework

When a specific allocation question is before the Lead Link -- which project to fund, which role to invest more time in, whether to accept a new external commitment -- apply this framework:

**1. Strategy test**: Which option better serves the circle's current strategy emphasis?

**2. Purpose test**: Which option better serves the circle's purpose?

**3. Commitment test**: Are there existing external commitments that must be honored regardless of preference?

**4. Reversibility test**: Which option leaves more options open? Prefer reversible commitments when uncertain.

**5. Capacity test**: Is there actually capacity available to make this allocation? If not, what gives way?

The output is not a score -- it is a judgment. The framework surfaces what the relevant considerations are so the judgment is grounded rather than reactive.

### Declining a Resource Request

Role-fillers and external parties will sometimes request resources the circle does not have or cannot spare given the strategy. The Lead Link's job is to decline clearly and with reasoning, not to apologize for organizational constraints.

**Decline template**:
> "[Request] requires [resource] that the circle cannot currently allocate without compromising [higher-priority work, per the circle's strategy]. The circle's strategy currently emphasizes [X], which means [Y] takes lower priority. The earliest we could revisit this is [timeframe], or if the strategy context changes, bring it back then."

This response respects the requester while holding the allocation boundary.

### Accepting a New Commitment

When the Lead Link is considering accepting an external commitment (new client, new project, new obligation):

- Map the required resources against current capacity
- Identify what existing work would be crowded out
- Name that trade-off explicitly: "Taking this on means [existing project/role] gets less attention"
- Check against the strategy: does the new commitment serve the strategy emphasis?
- If yes and capacity exists: accept
- If yes but capacity doesn't exist: either decline or make a governance proposal to address the structural capacity problem
- If the new commitment doesn't serve the strategy: default to decline unless there is a compelling reason to update the strategy

---

## Cross-Circle Resource Requests

When other circles (typically the Super-Circle or peer circles) request resources from this circle, the Lead Link manages those requests.

**Requests from the Super-Circle's Lead Link**:
The Super-Circle Lead Link has authority to direct the circle's overall resource allocation as part of the organizational structure. The sub-circle Lead Link's role here is:
1. Understand what is being requested and why
2. Assess the impact on the circle's current commitments
3. If the request conflicts with current strategy, name that tension -- this is the Lead Link's accountability for "removing constraints within the Super-Circle"
4. Comply with the direction while flagging the constraint: "We can do X, but it means Y gets deprioritized. I want to make sure that trade-off is visible."

**Requests from peer circles**:
Peer circles do not have authority over this circle's resources. Requests from peer circles are requests, not directions. The Lead Link evaluates them using the standard allocation framework and responds accordingly.

**When this circle needs resources from another circle**:
The Lead Link surfaces this as a tension to the Super-Circle: "We need [X] from [other circle] to fulfill our purpose. We don't have the direct authority to obtain it. I'm bringing this as a constraint for the Super-Circle to address."

---

## Resource Allocation in Solo-Operator Contexts

In solo-operator contexts, resource allocation is fundamentally time governance. The same person fills multiple roles -- allocation is not about distributing work across people, it is about distributing attention across role identities.

### The Solo-Operator Allocation Problem

The core problem: when one person fills all roles, urgency and habit tend to dominate allocation decisions. The role that produces the most visible outputs, receives the most external pressure, or is simply most energizing gets disproportionate attention. The circle's strategy gets bypassed.

**The Lead Link's discipline in solo-operator allocation**:
- Treat each week's time allocation as a governance act: consciously decide which roles and projects receive time, rather than letting the day decide
- Apply the strategy test to the allocation: "Does how I'm spending my time reflect the strategy's emphasis?"
- Name capacity limits explicitly: a single person cannot fill 15 roles with equal attention; acknowledge which roles are receiving genuine energy and which are formally assigned but practically vacant

### Time Governance Protocol

A practical weekly protocol for solo-operator Lead Links:

**Monday (or start-of-week): allocation review**
1. Load current projects from GlassFrog: `glassfrog_list_projects(circle_id)`
2. Review the strategy statement
3. Allocate the week's available hours across roles and projects using the strategy as the filter
4. Name explicitly what is being deprioritized this week

**End-of-week: allocation audit**
1. Compare actual time spent against the planned allocation
2. Note any drift: what pulled attention away from the plan?
3. Assess: was the drift strategic (a good exception) or reactive (urgency overriding strategy)?
4. If drift is chronic, it signals either that the strategy is wrong, the allocation plan is unrealistic, or a structural problem that needs governance attention

### Blocking time for Lead Link work itself

In solo-operator contexts, Lead Link work -- strategy review, fit assessment, governance tension drafting -- is easy to deprioritize because it feels less urgent than role-level execution. The Lead Link's work *is* organizational work. It deserves dedicated time, not just the scraps left after execution work consumes the day.

A useful heuristic: Lead Link work should receive at least 10-15% of total work time in a healthy solo-operator organization. If it is receiving less, structural problems are accumulating silently.

---

## Allocation Signals and Tensions

These patterns in GlassFrog or conversation should prompt the Lead Link to investigate allocation:

| Signal | Likely Issue |
|--------|-------------|
| Multiple projects stalled with no updates | Role-filler over-allocated or disengaged |
| New projects being created faster than old ones close | Capacity problem; need to prune before adding |
| All projects concentrated in one or two roles | Other roles are under-resourced or the structure doesn't reflect actual work |
| Projects exist in GlassFrog with no assigned role | Governance gap; someone is doing informal work |
| Recurring tactical meeting items with no resolution | Capacity or accountability structure issue; may need governance |
| Strategy says X but projects are mostly Y | Strategy-execution gap; allocation not following strategy |

When these signals appear, distinguish between:
- **Operational fixes**: Adjustable by the Lead Link without governance (re-prioritize, re-assign)
- **Structural fixes**: Require governance (redefine a role, add an accountability, remove a stale project)

---

## Budget Allocation

When the circle controls discretionary budget, the same framework applies:

1. Map current budget allocation against roles and projects
2. Test against strategy: is money going to strategy-aligned work?
3. Identify misallocations: budget spending that doesn't serve the strategy
4. Make explicit decisions about reallocation
5. Communicate changes to affected role-fillers

In most small or solo-operator circles, budget allocation is closely tied to project allocation. The Lead Link's job is to ensure financial decisions are made explicitly and strategy-grounded, not reactively.

**A useful question**: "If we had 20% less budget than we currently have, what would we cut? The answer reveals what we actually consider most valuable -- and whether that matches the strategy."
