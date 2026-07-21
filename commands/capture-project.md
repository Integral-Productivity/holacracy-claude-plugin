---
description: Capture a well-formed Holacratic project to a role's GlassFrog backlog via a draft-and-confirm flow. Soft-gates on the well-formedness rubric's Family A (outcome-framed / first next-action / clear owner), teaching the missing element with a drafted fix rather than hard-blocking. Files additively — the project plus its first next-action — with a single per-project confirmation, then a light skippable goal-link nudge. The capture-time twin of /holacracy:review-project.
argument-hint: [project text, optional]
---

# /holacracy:capture-project

On-demand entry to the canonical project capture flow. Dispatches the `project-capture` subagent, which runs the full P-flow specified in `skills/shared/project-capture-flow.md`.

This is the **capture-time guardrail** for GlassFrog projects: it helps a role-filler state a project as an outcome with a first next-action *as they file it*, so the backlog fills with actionable work instead of thin stubs. It is the twin of [`/holacracy:review-project`](./review-project.md) — where review-project cleans up under-specified projects after the fact (the "belt"), this command prevents them at intake (the "lifestyle change"). Both load the same rubric, `skills/shared/project-well-formedness.md`, so "well-formed" means one thing across the plugin.

## What this command does

1. **Parse $ARGUMENTS.** If the user passed project text inline, use it as the seed. If not, the subagent will ask for the outcome (*"What outcome do you want this role to move toward?"*).
2. **Dispatch the `project-capture` subagent** with the project text and the dispatch source (`explicit command`). Let the subagent handle Steps 2–8 of `skills/shared/project-capture-flow.md`:
   - Resolve the owner role via `glassfrog_get_me` + `glassfrog_list_my_roles` (with circle narrowing per conversation context). The target is *any role the actor fills* in the relevant circle.
   - Soft-gate on the well-formedness rubric's **Family A** (A1 outcome-framed, A2 has a first next-action, A3 clear owner). For each missing element, present a drafted fix plus a one-line teaching of why it matters — never a hard block.
   - Draft the outcome-framed project description and a concrete first next-action.
   - Present the single per-project confirmation block.
   - On approval, file additively: `glassfrog_create_role_project(role_id, description, status: "current")`, then `glassfrog_create_action(role_id, description, parent_project_id: <new project>, status: "current")` for the first next-action. Trust the returned ids; no list-back.
   - Offer a light, skippable goal-link nudge (`glassfrog_link_goal_supporting_project`) only when the owner role has goals; skip silently otherwise.
3. **Surface the subagent's structured result** (project ID, first-action ID, owner role + circle, goal-link status) and return to the original conversation.

## Behaviour

- This command captures **one project per invocation**. If the user wants to capture multiple, run it multiple times.
- The soft-gate **teaches but never enforces**: if the user chooses to file something still activity-framed, that is their call — the teaching happened. The command never hard-blocks and never pushes the user to the GlassFrog UI.
- The additive write chain is ordered: the project is created first (returning its `proj_xxx` id), then the first next-action is attached to it via `parent_project_id`. A failure at either step is surfaced honestly — the command does not silently swallow a write error.
- The subagent does not attempt to verify via `glassfrog_list_role_projects` — same-session list-back is unreliable. The `create_role_project` / `create_action` response ids are the only reliable confirmation.
- The constitutional safeguard from `skills/shared/project-capture-flow.md` applies: no file without explicit per-project confirmation.
- If GlassFrog is not connected, the subagent will offer to draft a plain-text version for manual entry. This command honours that fallback.

## When to use this command vs. other surfaces

- **`/holacracy:capture-project`** (this command) — capture-time. Use when you're filing a *new* project and want it well-formed from the start.
- **[`/holacracy:review-project`](./review-project.md)** — after-the-fact. Use to review *existing* projects against the full rubric (Family A **and** Family B), with adversarial critics, advisory reframes, and additive fixes.
- **Ambient capture** *(future)* — Claude offers to capture when it detects project-shaped language during other work. Same subagent, same flow; no slash command needed.

## What this command does NOT do

- It does not review, reframe, re-own, or archive *existing* projects. That is `/holacracy:review-project`'s job.
- It does not run Family B checks — no scope-authority ruling, no assignment-fit judgment. Those are often premature at a project's birth and belong to review-project.
- It does not hard-block, force perfection, or push the user to the GlassFrog UI.
- It does not delete projects.
- It does not file proposals, tensions, or governance changes.
- It does not batch multiple projects into one confirmation.
