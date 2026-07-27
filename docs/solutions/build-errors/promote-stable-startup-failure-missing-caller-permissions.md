---
title: "promote-stable dies in startup_failure when the thin caller omits permissions: contents: write"
date: 2026-07-27
category: build-errors
module: release-tooling
problem_type: build_error
component: tooling
symptoms:
  - "Workflow run ends in `startup_failure` with 0 jobs, no logs, and no annotations"
  - "`gh run view` reports only \"This run likely failed because of a workflow file issue\""
  - "The release tag and GitHub Release are created normally, but `stable` never advances"
  - "A release appears shipped while the marketplace still serves the previous version"
root_cause: missing_permission
resolution_type: config_change
severity: high
related_components:
  - promote-stable
  - reusable-workflows
  - claude-plugin-manifest
tags:
  - github-actions
  - reusable-workflows
  - permissions
  - startup-failure
  - release
  - stable-branch
  - marketplace
---

# promote-stable dies in startup_failure when the thin caller omits `permissions: contents: write`

## Problem

Merging the release PR for `v0.10.0` created the tag and the GitHub Release, but `promote-stable.yml` ended in `startup_failure` before any job ran. `stable` — the ref the public marketplace tracks — stayed on `v0.6.0`, 20 commits and five features behind. The release looked shipped and reached no consumer.

## Symptoms

- The run ends in **`startup_failure`**: 0 jobs, no step logs, no annotations, and nothing exposed through the REST API (`/actions/runs/<id>/jobs` returns an empty array; `check-runs` annotations are empty). The message appears only in the web UI.
- `gh run view <id>` says just *"This run likely failed because of a workflow file issue."*
- Most damaging: **it fails in the wrong direction.** The tag and Release are created normally, so every signal a maintainer normally checks looks healthy. Only `git ls-remote origin refs/heads/stable` reveals that promotion never happened.
- It is **latent**. `promote-stable` fires only on a release tag, so a broken caller looks fine indefinitely — here, for over a month.

## What Didn't Work

- **Suspecting an undeclared secret.** The workflow's own header documents that passing an undeclared secret to a reusable produces exactly this `startup_failure` signature, so that was the first theory. Ruled out: `reusable-promote-stable.yml` does declare `OP_RELEASER_PUBLIC_TOKEN`, verified at the pinned `@v1` ref, not just on `main`.
- **Suspecting the `@v1` pin.** A prior PR had repointed callers from `@main` to `@v1`, making it the obvious suspect. Ruled out on four checks: the reusable's repo is public, the `v1` tag resolves, its YAML parses, and its `workflow_call` contract matches what the caller passes.
- **Reading the run status as the diagnostic.** There is no useful error to find through the API — the rejection happens before the run has jobs to report on. Time spent hunting for a message is wasted; the answer is in comparing the caller's declared permissions against the reusable's.
- **Re-running the failed workflow** (considered, not attempted — it cannot work; see Prevention).

## Solution

Add the block the caller was missing:

```yaml
# .github/workflows/promote-stable.yml
on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'

permissions:
  contents: write   # <-- required; see below

jobs:
  promote:
    uses: Integral-Productivity/reusable-workflows/.github/workflows/reusable-promote-stable.yml@v1
    secrets:
      OP_RELEASER_PUBLIC_TOKEN: ${{ secrets.OP_RELEASER_PUBLIC_TOKEN }}
```

The diagnostic that finds this in one step — compare both sides:

```bash
# what the reusable requests
gh api "repos/<org>/reusable-workflows/contents/.github/workflows/reusable-promote-stable.yml?ref=v1" \
  --jq '.content' | base64 -d | grep -A2 '^permissions:'

# what the caller grants (no output at all = the bug)
grep -A2 '^permissions:' .github/workflows/promote-stable.yml

# and the ceiling the caller inherits by default
gh api repos/<org>/<repo>/actions/permissions/workflow --jq '.default_workflow_permissions'
gh api orgs/<org>/actions/permissions/workflow --jq '.default_workflow_permissions'
```

**Recovery required a new tag, not a re-run.** A tag-triggered workflow resolves its definition **from the pushed ref**, so re-running the failed run replays the same broken file, and moving the tag would desync the already-published Release. The fix landed as a `fix(ci):` commit and the next patch version — `v0.10.1` — carried it. That tag's run promoted cleanly and fast-forwarded `stable` past the stranded `v0.10.0`, which remains a valid tag and Release that was simply never promoted.

**The root-cause fix was upstream.** The reusable never needed `write`: it hands the ip-releaser App token to `actions/checkout` explicitly and the fast-forward push authenticates with those persisted App credentials, so no step uses `GITHUB_TOKEN` for a write. It now requests only `contents: read`, which the org default already grants — so a thin caller needs no `permissions:` block at all, and callers that declare `contents: write` still work, since a caller may grant more than the reusable asks.

## Why This Works

A called reusable workflow **cannot request greater permissions than its caller grants**. Three facts collided:

1. `reusable-promote-stable.yml` declared `permissions: contents: write`.
2. This repo *and* the org both default `default_workflow_permissions` to **`read`**.
3. The caller declared no `permissions:` block, so it inherited that `read` ceiling.

GitHub validates the permission graph at compile time, before scheduling any job — which is why there is no log to read. The `startup_failure` is the validator refusing the graph, not a runtime error.

The regression came from a migration: converting the inlined `promote-stable.yml` into a thin caller of the shared reusable deleted the `permissions` block along with the steps it used to govern. `git show <migration-commit> -- .github/workflows/promote-stable.yml` shows exactly that deletion. The tell that confirms it: every other write-needing caller in the same repo (`auto-merge.yml`, `release-please.yml`, `claude.yml`) carries `contents: write`, and a sibling repo still running the pre-migration inlined version still had it too.

## Prevention

- **When converting a workflow to a thin caller, diff for a removed `permissions:` block.** Inlined steps and a `uses:` job need the same grant; the block is easy to drop with the steps. This is the specific regression to look for in any shared-reusable migration.
- **Audit callers by comparing declared permissions on both sides, not by reading run history.** A green history proves nothing about a caller migrated after the last run. In this incident, three sibling repos were latent for the same reason: their last successful run predated their migration, and none had pushed a tag since.
- **Treat `startup_failure` as a caller-contract question, in this order:** (1) does the caller declare every permission the reusable declares? (2) is a passed secret undeclared in the reusable's `workflow_call.secrets`? (3) does the `uses:` ref resolve and is its repo reachable? The fastest tell for (1) is that a sibling caller in the same repo *has* the block and the broken one doesn't.
- **Prefer fixing the reusable over documenting the caller requirement.** If a reusable authenticates with its own App token, it should request the minimum `GITHUB_TOKEN` scope — then no caller can get this wrong. A canonical usage example in the reusable's header that omits a required block will keep minting broken callers indefinitely; this one did.
- **A tag-only trigger hides breakage until release day.** Anything that fires solely on `push: tags` is untested by ordinary CI. Either exercise it deliberately after changing it, or accept that the next release is the test.
- **Verify the promotion, not just the tag.** After any release, assert the refs actually converged rather than trusting that the tag and Release exist:
  ```bash
  git ls-remote origin refs/heads/stable refs/heads/main refs/tags/vX.Y.Z
  # all three should be the same sha
  ```

## Related Issues

- [`release-please-manifest-vs-tag-semantics.md`](../tooling-decisions/release-please-manifest-vs-tag-semantics.md) — the release-please version-authority learning from the same incident. That one is why `v0.10.0` was being cut at all; this one is why it failed to reach anyone.
- [`docs/adr/0010-release-please-is-the-sole-writer-of-the-plugin-version.md`](../../adr/0010-release-please-is-the-sole-writer-of-the-plugin-version.md) — records that `promote-stable`'s version-match assertion is the enforcement point for the version invariant's tag leg, which is why this workflow running at all is load-bearing.
- [`docs/adr/0002-use-tag-driven-stable-branch-for-marketplace-channel-publication.md`](../../adr/0002-use-tag-driven-stable-branch-for-marketplace-channel-publication.md) — establishes the `stable`-branch publication channel this workflow advances.
