---
module: release-tooling
date: 2026-07-27
problem_type: tooling_decision
component: tooling
severity: high
applies_when: "Adopting, reconfiguring, or repairing release-please in a repo — especially re-baselining .release-please-manifest.json, adding an extra-files target that a human convention already owns, or diagnosing why a plugin's visible version looks stale or is about to move backwards."
related_components:
  - release-please
  - promote-stable
  - claude-plugin-manifest
tags:
  - release-please
  - versioning
  - single-source-of-truth
  - conventional-commits
  - changelog
  - github-actions
  - claude-plugin
---

# release-please's manifest is a baseline, not a history — and `extra-files` silently takes ownership

## Context

This repo ran two competing owners of one number for five feature PRs.
`release-please-config.json` (`release-type: simple`) tracked the version in
`.release-please-manifest.json` (0.6.0) and `version.txt` (0.6.0), while
`.claude-plugin/plugin.json` `$.version` had been hand-bumped to 0.10.0. The
pending release PR had computed 0.7.0 from the manifest and would have rewritten
`plugin.json` on merge — **downgrading** the publicly advertised version.
Compounding it, `stable` (the ref the marketplace tracks) was 20 commits behind
`main` at v0.6.0, so five shipped features had reached no consumer.

The decision that came out of it is
[ADR-0010](../../adr/0010-release-please-is-the-sole-writer-of-the-plugin-version.md).
What follows is the *mechanics* — the part that is genuinely hard to derive and
that the next person re-baselining a manifest will need. Verified against
release-please 17.x source (`googleapis/release-please-action@v5` pins
`release-please ^17.6.0`).

## Lessons

### 1. `extra-files` is an ownership transfer, not a convenience

Adding

```json
"extra-files": [
  { "type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version" }
]
```

made release-please the writer of a field that an existing human convention
([ADR-0002](../../adr/0002-use-tag-driven-stable-branch-for-marketplace-channel-publication.md))
already claimed. Nothing warns you. The two writers simply fight, and
release-please wins at release time — including by writing a *lower* number than
the one already published.

**Rule: adding an `extra-files` target obliges you to amend whatever document
told humans to write that field, in the same change.** If you skip that, every
agent and contributor reading the stale doc reproduces the drift faithfully. The
root cause here was documentary, not disciplinary.

### 2. The manifest sets the next version; the *tag* bounds the changelog

These are two separate resolutions, and conflating them is the trap.

- **Version baseline** comes from `.release-please-manifest.json`, read from HEAD
  of the target branch (`src/manifest.ts`, `parseReleasedVersions`). The next
  version is `bump(manifestVersion, conventionalCommits)`.
- **Changelog range** comes from the newest GitHub Release / tag *whose version
  equals the manifest value*. The Release scan explicitly requires
  `tag.version === manifestVersion`.

Our stalled release PR's body read `compare/v0.6.0...v0.7.0` — manifest 0.6.0
gave the 0.7.0 bump, and the `v0.6.0` **tag** gave the lower bound. Two lookups,
one number in common.

**So hand-editing the manifest forward is the trap.** Set the manifest to 0.10.0
while the newest tag is `v0.6.0` and: the Release scan rejects `v0.6.0` (version
mismatch), tag-backfill hunts a nonexistent `v0.10.0`, release-please synthesizes
a fake Release from the manifest, and `needsBootstrap` flips true. That disables
the commit-range early-exit, so `commitsAfterSha(commits, undefined)` returns
**every** commit up to `commitSearchDepth` (default 500) — and your next
changelog entry becomes the repo's entire history.

If you must re-baseline the manifest to a version that has no matching tag,
either create the tag *and* the GitHub Release to match, or pin the range floor
with `last-release-sha` (a real prior release exists, you just cannot match it)
or `bootstrap-sha`. Then remove the pin once a matching tag exists — it is inert
afterwards but will confuse the next reader.

### 3. `Release-As:` is the one-shot escape hatch — a footer, not a config field

`Release-As: X.Y.Z` short-circuits *ahead of* the manifest-derived bump
(`src/strategies/base.ts`), forcing that exact version into `version.txt`, the
manifest, every `extra-files` target, the tag, and the release PR title. It is
how you land a specific version **without ever editing a version file**, which
keeps the single-writer invariant intact even during a re-baseline. And because
the manifest stays put, the `v<old>` tag still matches, `needsBootstrap` stays
false, and the changelog range stays tight — the exact opposite of lesson 2's
failure.

Constraints that actually bite:

- It must parse as a conventional-commit **footer**: blank line before the
  trailer block, its own line, canonical `Token: value`. Case-insensitive.
- **Put it last, with nothing after it.** The note is captured with continuation
  semantics, so a following line risks the parsed text becoming
  `0.10.0\nCo-Authored-By: …` and failing `Version.parse`. In particular, do not
  leave a `🤖 Generated with [Claude Code]` line after it — that is not
  trailer-shaped.
- A `BEGIN_COMMIT_OVERRIDE` block anywhere in the message replaces the message
  and discards the footer.
- **It must land in whatever text becomes the squash commit body**, and in this
  org that differs by merge path. `reusable-auto-merge.yml@v1` merges `claude/*`
  branches with `gh pr merge --auto --squash --subject … --body "$PR_BODY"`, so
  the squash body is the **PR body**. A human merge instead uses the repo setting
  `squash_merge_commit_message: COMMIT_MESSAGES` = the branch commit message.
  Put the footer at the tail of **both**, and keep the branch to one commit — with
  two or more, a `COMMIT_MESSAGES` squash prefixes each subject with `* ` and
  strands the footer mid-message.
- It is **one-shot**: it stops applying once that commit is behind the new
  release tag. That self-cleaning property is the point.

The config-file `release-as` key looks equivalent and is not: it is **sticky**,
pinning every subsequent release to that version until someone removes it.
Prefer the footer.

### 4. An already-open release PR is updated in place — don't close it

The release branch name carries no version
(`release-please--branches--main--components--holacracy`), so when the computed
version changes, release-please force-pushes that same branch and retitles the
same PR. Closing it *without* the `autorelease: snooze` label doesn't skip
anything — a fresh PR opens on the next push to `main`. Applying `snooze`
suppresses the regeneration you may be depending on. There is no
`autorelease: closed` / `skipped` semantic; the full label set is
`autorelease: pending | tagged | snapshot | snooze`.

### 5. Read the PR title, not the run status

`release-please.yml` here is soft-failing by design: if the ip-releaser App
credentials or the 1Password PEM are unavailable, it emits a `::warning::` and
**exits 0**. A green run therefore does not mean a release PR was produced or
updated. The observable that matters is the PR's title and `updatedAt`.

### 6. Pre-1.0 bump semantics are a config choice, not a SemVer given

`bump-minor-pre-major: false` + `bump-patch-for-minor-pre-major: false` (this
repo) means plain SemVer: `feat:` → minor, breaking → 1.0.0. Repos that set
these `true` behave differently. Don't carry the intuition across repos.

### 7. `release-type: simple` requires `version.txt`

It is not a stray file to tidy away; release-please writes it every release.

### 8. An unmerged release PR is a root cause, not an annoyance

Ours sat open for a month. The shipped version froze, `stable` fell 20 commits
behind, and hand-bumping `plugin.json` became the only way to make the version
*look* right. Automation that isn't merged is indistinguishable from automation
that isn't there. Auto-merge coverage for the release branch is part of the
mechanism, not polish — and note that `gh pr merge --auto` waits only on
**required** status checks, so a guard that isn't required can be outrun.
