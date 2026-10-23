# Project Triage Gates -- Shared Reference

This is the canonical set of checks a GlassFrog **project** passes through during readiness triage. It is the project twin of `./triage-gates.md`, which is tension-specific; the two are kept apart because callers cite steps by number. Loaded by:

- The `/holacracy:project-triage` slash command, the only surface that writes a triage state.

Triage answers one question per project: **what does this project need next before anyone can act on it?** It does not judge quality. The five critic lenses belong to `/holacracy:review-project`; triage never runs them and never drafts a reframe. See [ADR-0018](../../docs/adr/0018-separate-project-readiness-from-project-quality.md).

Every step **drafts and never writes**. A write happens only after the user confirms that one project, and only in the shape Step 6 sets out.

Run the steps in order. **Stop at the first step that resolves the project.** Steps 1-4 are the reality gates: a project that fails one leaves triage through its GlassFrog `status`, never a tag (`./triage-states.md` Step 1). Step 5 routes the survivors.

---

## Step 1 -- Is the outcome already reached?

**Evidence.** The project's note or description says the outcome shipped, a later project on the same role records it as done, or the user says so. A past-tense title is **not** evidence: projects are titled in past tense as an idiom, and status lives only in the status field.

**Outcome.** Draft `status: completed` with a note line naming the evidence (`Triage <timestamp>: completed -- <evidence>`).

## Step 2 -- Is it a duplicate?

**Evidence.** Another `current` project in scope describes the same outcome. Compare outcomes, not wording.

**Outcome.** Name **one survivor**: the member with a next action, otherwise the older one, otherwise the user's pick. Draft `status: archived` on the other member only, with a note line naming the survivor. Drop the survivor from the rest of the pass, and never close a project whose named survivor was completed or archived earlier in the same pass. Without this rule each member of a pair finds the other and both get archived.

## Step 3 -- Is it superseded?

**Evidence.** A different project, or a role created since, now carries the outcome. As in `./triage-gates.md` Step 4, ask whether this project would still be needed if the other one finished.

**Outcome.** A project counts as superseded **only when its successor already exists**. Draft `status: archived` with a note line naming the successor. Triage has no create-project write: if the successor does not exist yet, the gate passes and Step 5 routes the project to `needs-info` with the missing successor named as the question.

## Step 4 -- Is the owner role gone?

**Evidence.** The project's `role_id` no longer resolves (`glassfrog_get_role_context` returns not found).

**Outcome.** Draft `status: archived` with a note line saying the role was removed. If the work still matters, say so and suggest `/holacracy:capture-tension` for the role that should hold it; triage does not move projects between roles.

**An unfilled role is not a gate failure.** Its work sits with the Circle Lead until the role is filled. Route it at Step 5 to `needs-info`, naming the Circle Lead as the role that decides.

---

## Step 5 -- Route the survivor

A project that passes Steps 1-4 is routed to **exactly one** state from `./triage-states.md` Step 1, in this order:

1. **No next action** (no `current` action whose `parent_project_id` is this project), an outcome the owner must clarify, a missing successor (Step 3), or an unfilled owner role (Step 4) -> `needs-info`. The open question goes in the note line, addressed to the role that must answer it.
2. Otherwise, apply executor-fit (`./project-well-formedness.md` B3) to the next action: if an AI agent can carry it out without further human judgment -> `ready-for-agent`; if it needs a person for judgment, relationship, or access -> `ready-for-human`.

`needs-triage` is written only when the user asks to reopen a project. Deferring writes nothing.

Never write a rubric verdict (`needs-next-action`, `needs-outcome`, and the rest in `./project-well-formedness.md`) or `archived` as a tag. Those are findings and a status; `./triage-states.md` Step 2 refuses any name outside its table.

Read action evidence once per role, not once per project: `glassfrog_list_role_actions(role_id)` returns every action with its `parent_project_id`, `created_at`, and `updated_at`. Group by project.

---

## Step 6 -- The note line and the movement rule

### The note line

Every write carries its reason. Append one line to the project's `note` (read the note first; never overwrite it):

```
Triage 2026-10-23T14:05Z: ready-for-human -- the next action needs a signature from a person
Triage 2026-10-23T14:07Z: needs-info -- which region launches first? (Operations Steward)
Triage 2026-10-23T14:09Z: archived -- duplicate of "Onboarding guide published"
```

The timestamp is UTC, to the minute. The part after `--` is the reason or the open question.

### The write pair

One confirmation, two calls, **note first**:

1. `glassfrog_update_project(project_id, note=<old note + new line>)` -- with `status` in the same call when a gate closes the project.
2. For a state, `glassfrog_set_project_tags(project_id, tag_names=...)` as the read-modify-write in `./triage-states.md` Step 3. The argument is `tag_names`.

If the tag write fails, the note still records the decision; report the failure. The reverse order could leave a tag with no reason.

### Movement

A `needs-info` project is shown again only when it has **moved** since its last triage line:

- its `updated_at` is **more than 10 minutes** after that line's timestamp, or
- an action on it was created or updated after that timestamp.

The 10-minute window absorbs the bump from the triage write itself. Actions are checked separately because adding an action does not bump the project's `updated_at`. This is a heuristic: an owner who answers by editing the project within 10 minutes of the triage write is missed until the next edit. Say so when it matters.

A project tagged `ready-for-agent` or `ready-for-human` is counted and not walked. A project whose note has no triage line but carries a state tag set by hand counts as moved.

---

## Outputs of the gates

| Result | Write (after confirmation) |
|---|---|
| Step 1 fails | note line + `status: completed` |
| Step 2, 3 or 4 fails | note line + `status: archived` |
| Routed at Step 5 | note line, then the state tag (read-modify-write) |
| Deferred | nothing |
