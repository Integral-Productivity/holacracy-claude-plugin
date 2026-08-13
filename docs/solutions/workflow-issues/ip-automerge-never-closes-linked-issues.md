---
module: ci-auto-merge
date: 2026-08-13
problem_type: workflow_issue
component: development_workflow
severity: medium
applies_when: "A claude/* PR with a Closes/Fixes #NNN keyword is merged by app/ip-automerge and the referenced issue stays open, requiring a manual close."
related_components:
  - auto-merge
  - ip-automerge
  - ip-labeler
  - reusable-workflows
tags:
  - auto-merge
  - closing-keywords
  - github-apps
  - ci
---

## Problem

Seven consecutive `app/ip-automerge` merges in this repo (#130→#126, #136→#131,
#144→#132, #153→#127, #154→#148, #156→#149, #157→#151 — see #139) each carried
a valid `Closes #NNN` in both the PR body and the squash commit, and none of
them closed the referenced issue. Every one had to be closed by hand.

## Root Cause

`ip-automerge`'s GitHub App installation deliberately holds no `issues:write`
(confirmed by inspecting the installation directly: `contents:write`,
`metadata:read`, `pull_requests:write` only) — per `ip-bots` ADR-026, the
identity that merges a PR should never also be the identity that closes the
issues it references. This is by design, not a misconfiguration.

The actual fix — a `close-linked-issues` job that resolves
`closingIssuesReferences` via GitHub's own linked-issue graph and closes them
with a separate `ip-labeler` App token — already existed in the public
`Integral-Productivity/reusable-workflows` host that this repo's
`auto-merge.yml` calls (devops-excellence ADR-020/ADR-057/ADR-062's public-host
twin). Every precondition it needs was already provisioned org-wide: the
`OP_LABELER_PUBLIC_TOKEN`/`OP_AUDITOR_PUBLIC_TOKEN` secrets were scoped to
include this repo, the `ip-labeler`/`ip-org-auditor` Apps were installed
org-wide, and the required org variables existed.

The only gap was this repo's `auto-merge.yml` caller itself: it predated the
`close-linked-issues` job, so it triggered on `[opened, synchronize, reopened]`
only (no `closed`, so the job's trigger could never fire) and didn't forward
the two extra secrets the job needs. That caller is byte-identical to the
`template-claude-plugin`/`template-omnifocus-plugin` templates by design, and
every other Tier 3 consumer repo carried the identical gap — this was fleet-wide
template drift, not a holacracy-specific bug.

## Fix

1. `template-claude-plugin#11` and `template-omnifocus-plugin#11` added
   `closed` to the caller's `pull_request.types` and forwarded
   `OP_LABELER_PUBLIC_TOKEN`/`OP_AUDITOR_PUBLIC_TOKEN`.
2. `adopt-standard` (devops-excellence, dispatched manually with
   `repos=holacracy-claude-plugin apply=true`) propagated the updated caller
   into this repo via PR #249.
3. `devops-excellence#542` tracks propagating the same template to the
   remaining Tier 3 consumer repos.

## Verification

This document's own PR carries `Closes #139`. If issue #139 closes when
`app/ip-automerge` merges this PR, the fix is proven end-to-end in this repo —
the same verification pattern devops-excellence's ADR-020 used for its own
fix. See #139 for the observed result.

## Why This Matters

The failure was silent by construction: the keyword was always present and
always correct, so it looked like it should have worked, and nothing logged
why it didn't. `Closes #NNN` at landing is the back half of this org's
file-and-triage discipline (CLAUDE.md's *Closing Tracked Work*) — a merge path
that silently never honors it lets the backlog accrete work that has actually
shipped.

## When to Apply

Diagnosing any repo where an App-merged PR's closing keyword doesn't fire.
Check the merging App's installation permissions directly
(`gh api orgs/<org>/installations`) before assuming a bug in how the keyword
is written — an App deliberately scoped without `issues:write` is a design
decision (ip-bots ADR-026), and the fix is a second, narrower-scoped App
performing the close, not granting the merge identity broader permissions.
