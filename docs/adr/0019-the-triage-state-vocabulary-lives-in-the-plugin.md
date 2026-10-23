# 19. The triage-state vocabulary lives in the plugin

Date: 2026-10-22

## Status

Accepted (2026-10-23, Kraig Parkinson)

Amends [ADR-0018](0018-separate-project-readiness-from-project-quality.md):
replaces the part of its decision 4 that says `glassfrog-config` owns the tag
vocabulary. The rest of decision 4 (state saved as a project tag, archive uses
the project status) is unchanged.

## Context

ADR-0018 decision 4 says the triage-state tag vocabulary is "closed and owned by
`glassfrog-config`". A check of that repository found that its tag vocabulary
covers **role** tags only. Project and action tags are a separate namespace in
GlassFrog, and `glassfrog-config` has no file, sync, or check for them.

The risk the closed list exists for is still real. `glassfrog_set_project_tags`
creates any tag name it is sent, and it replaces the whole tag set. A misspelled
state becomes a new tag that no queue reads, and a write that sends only the new
state deletes the project's other tags. Neither fails loudly.

Two options were considered:

1. Extend `glassfrog-config` with a project-tag vocabulary and a sync. That puts
   the list in a second repository from the only surface that writes it, and
   adds a sync for four names.
2. Keep the list in the plugin, next to the command that writes it, and enforce
   it statically and at write time.

## Decision

The closed list lives in `skills/shared/triage-states.md`. It holds four states
(`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`); archive is
a project status, not a state.

It is enforced twice:

- **At write time.** The shared reference's Step 2 tells every writer to refuse
  a name outside the table before `glassfrog_set_project_tags`, and Step 3 makes
  the write a read-modify-write that keeps non-state tags.
- **Statically.** `scripts/skills-lint.sh` check 11 fails any shipped file that
  names a `needs-*` or `ready-for-*` state found in neither the triage list nor
  the rubric's verdict table, and fails a name that appears in both. The two
  vocabularies stay disjoint because one is written as a tag and the other is
  not.

## Consequences

**Easier**

- The command and its vocabulary change in one pull request, and the lint sees
  both.
- A typo in a skill's prose or example is caught before merge.

**Harder**

- Tags already on live projects are not checked by anything in this repository.
  A tag set by hand in the GlassFrog UI can still be misspelled; a future
  hygiene sweep can report it.
- If another tool starts writing project tags, it must load this list or carry
  its own copy, and the copy can drift. Revisit this ADR if that happens.
