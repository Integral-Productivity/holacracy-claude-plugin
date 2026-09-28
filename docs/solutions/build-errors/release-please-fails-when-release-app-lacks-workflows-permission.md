---
title: "release-please fails with 'Resource not accessible by integration' when the release adds a workflow file and the App lacks workflows"
date: 2026-09-28
category: build-errors
module: release-tooling
problem_type: build_error
component: tooling
symptoms:
  - "release-please fails at `Creating 1 releases for pull #N` with `Resource not accessible by integration` on `POST /repos/…/releases`"
  - "The release PR is merged and `main` carries the new version, but no tag or GitHub Release exists"
  - "`stable` stays on the previous version, so no install channel serves the release"
  - "Every step before the release call passes: the 1Password PEM read, the App-token mint, the config fetch"
root_cause: missing_permission
resolution_type: config_change
severity: high
related_components:
  - release-please
  - ip-releaser
  - promote-stable
tags:
  - github-actions
  - github-app
  - permissions
  - release
  - stable-branch
  - workflows-permission
---

# release-please fails with "Resource not accessible by integration" when the release adds a workflow file and the App lacks `workflows`

## Problem

The `v0.20.0` release PR (#308) merged, but release-please could not create the GitHub Release. No tag was cut, `promote-stable.yml` never fired, and `stable` stayed on `v0.19.1` for about 15 hours. The feature in that release (#307, the Option B install channels) reached no one. The same workflow and the same `ip-releaser` App had released `v0.19.1` 50 minutes earlier. Tracked in #310.

## Symptoms

- The `Run release-please` step fails right after `✔ Creating 1 releases for pull #308` with:
  ```
  ##[error]release-please failed: Resource not accessible by integration - https://docs.github.com/rest/releases/releases#create-a-release
  ```
- Every earlier step passes: the PEM read and `actions/create-github-app-token` both succeed.
- Re-runs and later pushes to `main` fail identically (4 failures across 3 commits).
- **Nothing alarms.** Once the release PR has merged there is no open release PR, so `release-pr-age-check.sh` treats "`stable` behind `main`" as a warning on exit 0. The only reliable tell is `git ls-remote origin refs/tags/vX.Y.Z refs/heads/stable`.

## What Didn't Work

Each of these was a reasonable first theory. Each was ruled out with evidence, in this order:

- **The installation's Contents permission.** It was already read & write, and the installation covered all repos. (An App's settings page shows *requested* permissions and the installation page shows *granted* ones, so check the installation. Here both were fine.)
- **A tag ruleset.** None exists. `GET /repos/…/rulesets?includes_parents=true` listed five rulesets, all `target: branch`. The one that looked likely, org ruleset 19336583, covers only `refs/heads/stable`, lists ip-releaser as an `always` bypass actor, and was last changed weeks earlier.
- **Tool drift.** `googleapis/release-please-action@v5` is an unpinned tag, so it could have moved between runs. It had not: the passing run and the failing runs all logged `release-please version: 17.6.0`.
- **The token mint.** `release-please.yml` mints with no `owner`, `repositories` or `permission-*` inputs, so the token carries the installation's full granted set. The workflow was unchanged since August.

## Solution

Grant the release App **Workflows: Read and write**, accept the permission update on the org installation, and re-run the failed release-please run. The re-run succeeded with no other change, and `v0.20.0` and `v0.21.0` then shipped and promoted.

The step that found it: when credentials, rulesets and tool version match between a passing and a failing run, **diff what is being released**:

```bash
git diff --name-status <prev-release-tag> <prev-release-target> -- .github/workflows   # passing range
git diff --name-status <prev-release-target> <failing-release-target> -- .github/workflows   # failing range
```

Here the passing range only **modified** `auto-merge.yml`. The failing range **added** `install-channel-check.yml`. That was the one content difference.

## Why This Works

Creating a GitHub Release for a tag that does not exist yet creates the tag. GitHub refuses a GitHub App any ref creation that brings in changes to `.github/workflows/` unless the App holds the `workflows` permission, and the Releases API reports that as the generic `Resource not accessible by integration`.

`ip-releaser` was documented and provisioned as `contents:write` only. That worked for every earlier release in this repo, including one whose range *modified* a workflow file. The v0.20.0 range was the first to *add* one, and it failed at once. The observed boundary is added versus modified. This is a working account from the evidence, not a documented GitHub rule. The decisive fact is that granting `workflows` and changing nothing else fixed it.

## Prevention

- **A release App needs `workflows`, not only `contents`.** Any repo whose releases can include a new workflow file will hit this on that release. `ip-releaser` is shared by every plugin repo; its documented scope in `devops-excellence` was updated (devops-excellence#745).
- **A PR that adds a workflow file is a release-path change.** Adding `.github/workflows/*.yml` to a plugin repo changes what the *next release* must be allowed to tag. After merging one, watch the next release-please run.
- **Verify convergence after every release, not just the release PR merge:**
  ```bash
  git ls-remote origin refs/tags/vX.Y.Z refs/heads/stable refs/heads/main
  ```
- **Diagnose by elimination, cheapest first:** installation-granted permissions, then rulesets (`includes_parents=true`, check `target`), then tool version in the logs, then a diff of the release ranges. The last step found it; the first three only narrowed the field.
- **The release alarm has a blind spot here.** "`stable` behind `main` with no open release PR" is a warning on exit 0 (CLAUDE.md § The alarms, #108). This incident went unalarmed for about 15 hours because of it. Whether it should become an alarm is an open question recorded on #310.

## Related Issues

- [`promote-stable-startup-failure-missing-caller-permissions.md`](promote-stable-startup-failure-missing-caller-permissions.md): the other way a release looks merged but never reaches `stable`. There the tag exists and promotion fails; here the tag is never created.
- [`release-please-manifest-vs-tag-semantics.md`](../tooling-decisions/release-please-manifest-vs-tag-semantics.md): how release-please decides what it is releasing.
- [`docs/adr/0010-release-please-is-the-sole-writer-of-the-plugin-version.md`](../../adr/0010-release-please-is-the-sole-writer-of-the-plugin-version.md): release-please owns the release act, which is why its App's permissions are on the critical path.
