---
name: checklist-metric-audit
description: >
  Audit a Holacracy circle's operational tracking portfolio -- its checklist items and metrics -- against the circle's purpose, accountabilities, and domains, then propose and (on confirmation) apply improvements. Use this skill whenever the user asks to review, audit, clean up, or improve the checklist items or metrics of a circle or role in GlassFrog; when they say a circle's tactical review feels noisy, redundant, or thin; when they ask "are we tracking the right things," "do our checklists match our accountabilities," or "what's missing from this circle's checklist"; or when a governance/tactical review surfaces that operational tracking has drifted from what the circle is accountable for. Unlike governance edits, checklist items and metrics are operational (Holacracy Constitution Art. 3.2, Tactical Meeting Checklist/Metrics Review), so this skill can apply changes directly through the GlassFrog MCP after per-change confirmation -- no governance proposal required. Pairs with holacratic-ai-governance (Pattern 3 tension sensing), holacracy-lead-link (metrics), and holacracy-secretary (checklists).
status: draft
version: 0.1.0
---
# Checklist & Metric Portfolio Audit

A method for auditing the **operational tracking portfolio** of a Holacracy circle -- its checklist items and metrics -- against what the circle is actually accountable for, and for improving that portfolio without touching governance.

## Why this is its own skill

A circle's checklist items and metrics are the recurring accountability surface reviewed in every Tactical Meeting. Left untended they drift: items accumulate as reactive operational hygiene while the circle's *core* accountabilities go unaffirmed; metrics duplicate checklist items; items sit on the wrong role; frequencies go unset; wording stops being answerable. None of this is caught by governance review, because **checklist items and metrics are not governance**.

That last point is the crux, and it is easy to get wrong. Under the Holacracy Constitution v5.0, the Governance Process (proposals, objections, integration) governs **Roles, Accountabilities, Domains, Policies, and elections**. Checklist items and metrics are **operational** -- reviewed in Tactical Meetings (Art. 3.2, the *Checklist Review* and *Metrics Review* steps) and added, reworded, moved, or removed *outside* governance. GlassFrog reflects this: they are freely editable, no proposal required. So this skill both diagnoses the portfolio **and** can remediate it directly through the GlassFrog MCP -- a scope the governance-editing prohibition does not cover.

The one boundary to respect: the *venue*. Faithful practice is to surface new or changed recurring items in a tactical meeting so the circle sees them (the Secretary maintains the checklist; the Lead Link carries the "Defining metrics for the Circle" accountability). There is no proposal gate, but there is a transparency norm -- announce changes, don't edit silently.

## Required: GlassFrog MCP tools

| Purpose | Tools |
|---|---|
| Read structure | `glassfrog_get_role_context`, `glassfrog_list_sub_roles`, `glassfrog_get_org_tree` |
| Read portfolio | `glassfrog_list_role_checklist_items`, `glassfrog_list_role_metrics` |
| Apply (checklists) | `glassfrog_create_checklist_item`, `glassfrog_update_checklist_item`, `glassfrog_delete_checklist_item` |
| Apply (metrics) | `glassfrog_create_metric`, `glassfrog_update_metric`, `glassfrog_delete_metric` |

If GlassFrog is not connected, run the audit in advisory mode from whatever the user can supply, and name the limit. Do not fabricate portfolio contents.

Resolve actor + circle first via `../shared/actor-and-role-resolution.md`, and announce the resolved scope before auditing.

## Evaluation criteria

A checklist item is a **recurring action a role affirms** (check / no-check) at tactical review. A metric is a **recurring number** a role reports. Judge every item against seven criteria:

1. **Traceable** -- ties to a purpose, accountability, or domain of the circle.
2. **Recurring & discrete** -- a repeatable action/number, not a one-off project.
3. **Affirmable / measurable** -- a checklist item is answerable yes/no and phrased as a completed action ("Reviewed the help desk queue," not "Help Desk"); a metric names a countable quantity.
4. **Cadenced** -- carries an explicit frequency.
5. **Correctly owned** -- sits on the role actually accountable, not piled on the circle root by default.
6. **Right instrument** -- a *behavior* belongs in the checklist; a *quantity* belongs in metrics. Flag count-shaped checklist items and action-shaped metrics.
7. **High-value / low-noise** -- worth the group's attention every cycle; not duplicating another item or metric.

## Method

1. **Load** the circle's purpose, accountabilities, and domains; its sub-roles; and every checklist item and metric on the circle role *and each sub-role* (items are per-role -- enumerate them all, don't assume they live only on the circle root).
2. **Build a coverage matrix.** One row per accountability (and per high-leverage domain). For each, record which checklist items and metrics cover it, and mark **covered / partial / gap**. This is the core finding-generator: gaps are accountabilities with no affirmable recurring surface.
3. **Scan for defects** across the seven criteria: missing frequency; count-shaped checklist items that duplicate a metric; items on the wrong role; noun-phrase (non-affirmable) wording; near-duplicate pairs; metrics with no recent signal.
4. **Draft candidates.** For each gap, draft a candidate checklist item or metric with **owning role, frequency, and affirmable wording**, mapped to the accountability it serves. For each existing item, recommend a disposition: keep / reword / move / merge / convert-to-metric / retire.
5. **Present, then apply on confirmation.** Deliver the audit (matrix + findings + candidates + dispositions) for review. Apply only what the user approves, and treat **destructive** changes (delete, merge) as requiring explicit per-change confirmation -- never merge or delete on an unconfirmed assumption (e.g., "these two items are the same queue" is a judgment for the user, not the auditor).

## GlassFrog application gotchas

These are learned constraints of the current GlassFrog MCP -- encode them so an application step doesn't fail or silently distort intent:

- **Frequency is an enum: `Weekly | Monthly | Quarterly` only.** There is no Daily, Bi-weekly, or Annual. If the intended cadence is bi-weekly, round to Weekly or Monthly and **say which, and why** -- don't drop the item. (Custom frequencies configured in the GlassFrog admin UI may exist but not be selectable via the create/update enum.)
- **There is no role-reassignment field.** `update_checklist_item` / `update_metric` cannot change the owning role. To **move** an item to another role you must **delete it and recreate it on the target role** -- which changes its ID and `created_at`. That's acceptable for a move, but name it, and do the create *before* the delete so nothing is lost if a call fails.
- **Updating an item does not clobber unspecified fields.** Omit `link` to preserve an existing link; pass it only to change it.
- **Verify after applying.** Re-list both the source and target roles' items and confirm the end state matches the approved plan before reporting done.

## Output

Deliver a structured audit: the coverage matrix, findings grouped by type, a candidate-items table (item / owning role / frequency / accountability served / rationale), and a disposition table for existing items. Keep checklist wording as affirmable past-tense actions. When the portfolio uses an emoji-prefix house style, match it. If the circle already has a rich metric set, weigh checklist candidates against it so you propose *behaviors* the metrics don't already quantify -- not redundant counts.

## Boundaries

- **This is not governance.** Do not route checklist/metric changes through a proposal or a governance meeting; that would be a category error (and slower). If an audit finding actually requires a new accountability or domain -- e.g., no role is accountable for something the circle needs -- *that* is a governance tension: surface it and hand off to `/holacracy:capture-tension`, don't try to fix it with a checklist item.
- **Announce, don't edit silently.** Name every change applied, and prefer surfacing new recurring items in a tactical meeting.
- **Respect ownership.** Metrics are the Lead Link's accountability to define; the Secretary maintains the checklist. Operate as advisor/actor to those roles, and say so.
