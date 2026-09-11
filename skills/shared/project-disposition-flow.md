# Project Disposition -- Shared Reference

Adapts Matt Pocock's engineering-issue triage methodology (needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix) to a single GlassFrog **project**. This is disposition, not readiness: readiness asks "is this well-formed?" (`project-well-formedness.md`, `/holacracy:review-project`); disposition asks "who should act on this next, and how?" -- the same split [ADR-0011](../../docs/adr/0011-separate-tension-readiness-from-tension-disposition.md) draws between tension readiness and tension disposition, applied to projects. Loaded by `/holacracy:project-disposition`.

Source methodology: [mattpocock/skills -- engineering/triage](https://github.com/mattpocock/skills/blob/main/skills/engineering/triage/SKILL.md), a five-state machine designed for a GitHub issue/PR tracker with native labels, many items, and a maintainer/reporter dynamic. A GlassFrog project is a different shape -- usually one item at a time, no native tags on projects, no "reporter" role -- so this reference keeps the state machine and rewrites the mechanics.

## The tag limitation (read first)

GlassFrog's API can attach tags to **Roles only** (`glassfrog_add_tag_to_role` / `glassfrog_remove_tag_from_role`). There is no `add_tag_to_project` -- verified against the live v5 API 2026-09-02; the Project JSON payload exposes a `tags: []` field but nothing writes to it. This is a hard boundary, not a workaround-pending fix (parallel to the `meeting_type` 422 documented in `triage-gates.md`).

Consequence for every disposition this flow reaches:

1. The state is recorded durably in the project's `note` field (`glassfrog_update_project(project_id, note: ...)`), using the Triage Note convention below.
2. The command's final output **always** includes the direct GlassFrog link to the project and an explicit instruction to apply the matching tag by hand in the GlassFrog UI. This is not optional framing -- it is the only way the five states become visible as GlassFrog tags at all.

## State vocabulary

| State | Meaning (adapted from Matt Pocock) | GlassFrog project status? |
|---|---|---|
| `needs-triage` | Not yet assessed against this state machine | no change |
| `needs-info` | Blocked on a question only the owner/a stakeholder can answer | no change |
| `ready-for-agent` | Concrete, bounded, and something an AI agent could execute without further human judgment | no change (stays `current`) |
| `ready-for-human` | Needs human judgment, relationship, external access, or a decision only a person can make | no change (stays `current`) |
| `wontfix` | Not being pursued | **can** also be written: `status: "cancelled"` or `"archived"` (confirm which with the user -- see Step 5) |

Unlike the tension/project-review state vocabularies elsewhere in this plugin, these five states are not native GlassFrog concepts -- they exist only as (a) the note-field convention below and (b) whatever tag the user applies by hand. Say this plainly when presenting a verdict; don't imply the tag is already live.

## Triage Note convention

Mirrors the `DoD:` trailing-line convention in `project-well-formedness.md`. Append (never overwrite) a block at the end of the project's note:

```
--- Project Disposition (project-disposition, <ISO date>) ---
State: <needs-triage | needs-info | ready-for-agent | ready-for-human | wontfix>
Rationale: <one to three sentences -- why this state>
[If needs-info] Open question: <the specific thing that needs answering, and from whom>
[If ready-for-agent] Suggested first action: <what an agent should do first>
[If ready-for-human] What only a human can do here: <judgment / relationship / access -- be specific>
Manual step required: apply the "<state>" tag to this project in GlassFrog -- the API cannot do this.
```

Keep prior triage entries below a `---` separator rather than deleting them; a project's disposition history is itself useful context on repeat triage.

## Resolving the GlassFrog project link

GlassFrog v5 API IDs (`proj_<32hex>`) are not the same as the numeric ID in the project's web URL (`https://app.glassfrog.com/organizations/<org>/my/workspace/projects/<numeric>`), and **no API call maps between them** (verified 2026-09-02: `glassfrog_search` does not index the numeric ID, and no project field carries it).

1. **If the user supplied a GlassFrog URL when invoking the command** -- use it verbatim in the output. This is the common case and needs no extra work.
2. **If the user supplied a name or `proj_id` instead** -- the output can still name the project precisely (description, owning role, circle) but cannot construct a clickable link from API data alone. Say so, and offer one of:
   - The user pastes the URL from GlassFrog themselves (fastest).
   - If a browser tool with an authenticated GlassFrog session is available, open GlassFrog's project search for the description text and cross-reference the resulting numeric URL against the `proj_id` via `glassfrog_get_project` (org, role, description match) -- the pattern used successfully in this plugin's own dogfooding. Confirm the match with the user before presenting it as the link; a description match is a heuristic, not a guarantee.
3. Never guess a numeric ID.

## Walking a single project

1. **Resolve the project.** From `$ARGUMENTS`: a GlassFrog URL, a `proj_<32hex>` id, or a name to resolve via `glassfrog_list_role_projects(..., q: "<name>")` / `glassfrog_search`. If ambiguous, ask which one (do not guess).
2. **Gather context.** `glassfrog_get_project` (or the `list_role_projects` record with `include: ["actions"]`), the owning role via `glassfrog_get_role_context`, and any prior Triage Note in the project's `note` field.
3. **Assess against the five states.** This is a judgment call informed by, but not identical to, the well-formedness rubric -- a project can be well-formed (has an outcome, a next-action, a clear owner) and still be `ready-for-human` because the next-action itself requires judgment or relationship (precedent: a well-formed project whose next-action was "personally follow up with each incomplete applicant" -- inherently human work). Conversely a thin, under-specified project is usually `needs-triage` or `needs-info`, not `ready-for-agent`, until it's been shaped.
4. **Present the disposition block and confirm before writing:**

   ```
   Project: [description]   (proj_xxx, owned by [Role] of [Circle])
   [If a prior triage note exists: "Previously triaged [date] as [state]."]

   Proposed state: [state]
   Rationale: [why]

   Apply this disposition?
     [a] apply    -> write the Triage Note to the project's note field (Step 5)
     [e] edit     -> change the proposed state or rationale first
     [s] skip     -> no write, leave the project as-is
     [q] quit     -> stop
   ```

5. **On `[a]`, write the note.** `glassfrog_update_project(project_id, note: <existing note>\n\n<Triage Note block>)`. If the state is `wontfix` and the user also wants the project's lifecycle status changed, confirm the target value separately (`cancelled` vs `archived` are both defensible -- cancelled reads as "decided not to do", archived as "soft-collapsed"; ask which the user means) before calling `update_project` a second time with `status:`. Never infer a status change from `wontfix` alone.
6. **Always close with the link + manual-tag reminder**, per "The tag limitation" above -- regardless of which option the user picked in Step 4, if a state was ever presented, restate the tag reminder so it isn't lost.

## Behaviour

- **Single project per invocation.** This reference does not define a backlog-wide sweep. (A future `/holacracy:project-disposition-sweep` could reuse this state machine across a role's or circle's backlog, the way `tension-triage` sweeps circles for `triage-gates.md` -- not built yet.)
- **Note field, not tag field, is the durable record.** Never claim the tag has been applied; the write only ever touches `note` (and, on explicit confirmation, `status` for `wontfix`).
- **Never batch, never auto-write.** Per-decision confirmation, exactly like every other write surface in this plugin.
- **Degrade honestly** if `glassfrog_update_project` fails: surface the error, keep the drafted Triage Note visible so the user can apply it manually if the write keeps failing.
