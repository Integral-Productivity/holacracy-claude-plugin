# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

> Seeded from the agentic-routines area. The broader Holacracy domain (Circle, Role, Core Role, Tension, Tactical, Governance, and the Core Role names) is canonical Holacracy vocabulary defined within the skills themselves; a repo-wide concept map is a `ce-compound-refresh` bootstrap, not yet run here.

## Release channel

### Stable channel
The published release channel installed users actually receive — a long-lived branch every install channel's catalog follows by ref rather than by pinned version, so whatever commit the channel points at *is* the current release for those installs. Distinct from the default branch, which carries in-flight work that has not been released, and from the Org synced copy, which is fed from this channel but does not follow it automatically.

The channel only ever moves forward, and only onto a commit that has been tagged with a release version matching the plugin manifest's declared version; a mismatch aborts the move rather than publishing. Advancement is a fast-forward and is never forced, so a non-fast-forward attempt fails loudly instead of rewinding the channel. Because the channel is advanced by a separate automated step rather than by merging, the default branch can sit arbitrarily far ahead of it — a release can be tagged and announced while the channel, and therefore every installed user, stays on the previous version.

### Promotion
The act of advancing the Stable channel onto a tagged release commit. Promotion is what makes a release reach users; tagging alone does not. It is triggered by the release tag, not by the merge that produced it, and it verifies the version match before moving the channel.

Pre-release versions deliberately do not trigger promotion, so a pre-release can be tagged without publishing to installed users. Because promotion is a distinct step from tagging, "the release shipped" and "users can get it" are separate claims — confirming a release means confirming the channel moved, not that the tag exists. Promotion is not the last gate for every session: those that load the Org synced copy get the release only after that copy accepts it.

### Org synced copy
The organization-hosted copy of the plugin that Claude's hosted surfaces (Cowork, scheduled tasks, and cloud sessions) load, as distinct from a copy a person installs from a catalog. It is refreshed from the release channel by an upload that Claude's plugin validator must accept, so it can sit on an older version while the Stable channel moves on.

A rejected upload gives no signal back to the repository: the copy simply keeps the last version it accepted. The validator enforces limits that the local manifest check does not, such as a maximum length for the plugin and skill descriptions, so a release can pass every repository check and still never reach these sessions. The only reliable evidence of what the copy holds comes from inside a session that loads it.

## Agentic routines

### Routine
A scheduled, draft-only unit of Core Role work the plugin prepares on a cadence and surfaces for a human to review — it never acts on the organization. Distinct from a generic scheduled task: a routine carries Holacratic role identity (it fires as a declared agent acting in a specific role and circle) and the constitutional draft-only safeguard.

A routine runs as a fresh agent session with full tool access, reads the governance data its single resolved role needs, composes a draft, and writes that draft to the Routine ledger. It never files or processes tensions, assigns people, issues rulings, or modifies governance — surfaced candidates are always left for the human to act on.

### Routine ledger
The durable per-actor store a routine writes after each fire, and that the surfaces read — the session-start briefing and the owning role command. It is the source of truth that bridges the scheduler (which fires routines but stores no output) and the session-start briefing (which has no live tool access). Each entry carries scheduling metadata plus a short packet summary, a build timestamp, a Surfacing window, and a pointer to the full draft.

### Surfacing window
The span during which a built routine packet is shown at session start, rather than only on its exact fire day. A window is used because a routine can fire late — when the app was closed at the scheduled time — so the packet should stay visible across the prep-to-meeting period.

## Work-item lifecycle

### Work item
A unit of work the plugin helps a role create and keep healthy in GlassFrog. Each type below moves through the same lifecycle stages, and each stage needs a plugin surface or a tracked gap. [docs/surface-map.md](docs/surface-map.md) shows which command serves each type at each stage.

### Lifecycle stage
One step a work item passes through, from the moment it is written down to the moment it is cleaned up. A stage with no command and no tracking issue is a hidden gap: from July to October 2026 the project readiness stage was one, and nobody could see it.

The two tables below are the closed lists. `scripts/skills-lint.sh` check 13 reads them and fails when the map has no row for a type, no column for a stage, or a row or column that is not named here. A pull request that adds a type or a stage changes this section and the map together.

| Work-item type | Meaning |
|---|---|
| **Tension** | A gap a role senses between what is and what could be, captured for processing. |
| **Project** | An outcome a role commits to achieve, tracked until it is reached or dropped. |
| **Action** | A next physical step a role commits to take, with no further outcome to track. |
| **Checklist item or metric** | A recurring operational check or measure a circle keeps on a role (Art. 3.2). |

| Lifecycle stage | Meaning |
|---|---|
| **Create** | The work item is written down well-formed, at intake. |
| **Readiness** | The work item is checked for form, duplicates, and whether it is still real, then routed. |
| **Quality or disposition** | The work item is judged against its rubric, or turned into its output. |
| **Hygiene sweep** | Stale, superseded, or orphaned work items are found across a circle and cleaned up. |
