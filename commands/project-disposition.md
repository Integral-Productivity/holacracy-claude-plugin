---
description: Classify a single GlassFrog project into Matt Pocock's five-state disposition machine (needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix), adapted for projects. Records the disposition in the project's note field and always surfaces a GlassFrog link plus a reminder to apply the matching tag by hand, since the API can tag roles but not projects.
argument-hint: [project name, proj_id, or GlassFrog project URL]
---

# /holacracy:project-disposition

Classify a GlassFrog **project** using the five-state disposition machine adapted from [Matt Pocock's engineering triage skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/triage/SKILL.md): `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. This answers *"who should act on this next, and how"* -- a different question from `/holacracy:review-project`'s *"is this well-formed and well-placed"*. A project can pass the well-formedness rubric entirely and still be `ready-for-human`, because the next-action itself needs judgment, relationship, or access only a person has.

Load `skills/shared/project-disposition-flow.md` at the start -- it is the canonical methodology (state vocabulary, the Triage Note convention, and the tag-limitation handling) this command walks.

## The tag limitation (non-negotiable to surface)

GlassFrog can tag **Roles**, not **Projects** -- there is no API path to attach a tag to a project. Every disposition this command produces is therefore recorded two ways: durably, in the project's `note` field via the Triage Note convention; and manually, by the human, as a GlassFrog tag. **Every output from this command ends with the project's link and an explicit instruction to add the tag by hand.** Do not let this get lost in a longer response -- it is the actual point of the exercise once the note is written.

## What this command does

1. Resolve the target project from `$ARGUMENTS` per `project-disposition-flow.md` Step 1 -- accepts a full GlassFrog URL (preferred, since it lets the final output link back precisely), a `proj_<32hex>` id, or a name to search for. Ask if ambiguous.
2. Gather context per Step 2: the project record (with actions), the owning role's context, and any prior Triage Note already on file.
3. Assess against the five states per Step 3 and present the confirmation block from Step 4. **Never auto-apply** -- the human picks `[a]/[e]/[s]/[q]`.
4. On `[a]`, write the Triage Note to the project's `note` field per Step 5. If the state is `wontfix`, ask separately whether to also set `status: "cancelled"` or `status: "archived"` -- never infer this.
5. Close every response -- success, skip, or quit -- with: the project's GlassFrog link (resolved per the "Resolving the GlassFrog project link" section) and the manual-tag reminder for whichever state was proposed or applied.

## Behaviour

- One project per invocation. For a backlog-wide pass, run it once per project -- there is no sweep mode yet.
- The write is additive to the note (existing content is preserved; the Triage Note is appended), never a replace.
- Never writes `status` without a separate, explicit confirmation -- a disposition write and a lifecycle write are two different asks.
- If GlassFrog's `update_project` call fails, say so plainly and keep the drafted Triage Note in the response so the user can paste it into GlassFrog by hand.
- Consistent with every other write surface in this plugin: per-item confirmation, no batching, no silent writes.

## Why this command exists

The state machine that keeps a GitHub issue tracker triaged -- is this ready for an agent, does it need a human, is it missing information, should we drop it -- is just as useful one GlassFrog project at a time, especially now that AI agents and human role-fillers are both picking up project work from the same backlog. GlassFrog has no native tagging for projects, so this command does the next best thing: it makes the disposition durable in the one writable field that exists (`note`), and it never lets the human forget the one step it can't do for them (the tag).

## What this command does NOT do

- It does not judge well-formedness (outcome / next-action / owner) -- that's `/holacracy:review-project`.
- It does not apply GlassFrog tags -- the API does not support it for projects.
- It does not sweep a backlog -- one project per run.
- It does not change project status except `wontfix`, and even then only on separate explicit confirmation.
