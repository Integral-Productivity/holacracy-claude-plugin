---
title: "Claude's upload validator rejects over-long descriptions, so the org's synced plugin copy stops updating while stable moves on"
date: 2026-10-16
category: build-errors
module: release-tooling
problem_type: build_error
component: tooling
symptoms:
  - "Scheduled Cowork runs stamp an old plugin version (v0.22.0) in their SessionStart text for days after newer releases shipped"
  - "`stable`, the tag, and the GitHub Release all show the new version; nothing in this repo's CI is red"
  - "A fix that merged and released (#335 in 0.22.2) is never observed in a real Cowork session"
  - "`claude plugin validate` passes on an over-limit manifest"
root_cause: missing_validation
resolution_type: tooling_addition
severity: high
related_components:
  - promote-stable
  - claude-plugin-manifest
  - skills-lint
tags:
  - release
  - stable-branch
  - marketplace
  - silent-failure
  - claude-plugin
  - cowork
  - upload-limits
  - version-skew
---

# Claude's upload validator rejects over-long descriptions, so the org's synced plugin copy stops updating while stable moves on

## Problem

Cowork-remote and cloud sessions do not load the plugin from `stable`. They
load the organization's claude.ai copy, and that copy only takes a release that
Claude's plugin upload validator accepts. From 0.22.1 to 0.24.0 every release
carried descriptions over the validator's limits. The org copy stayed at 0.22.0
for over a week while `stable` advanced normally ([#368](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/368)).

## Symptoms

- Per #368 and its follow-up comment, the daily kaizen scheduled task (a
  Cowork-remote session bound to Claude Desktop) reported
  `holacracy-claude-plugin v0.22.0` on 2026-10-09 and again on 2026-10-14, the
  sixth run in a row. 0.22.2 had been tagged on 2026-10-08.
- Everything this repo can see was green: release-please tagged each version,
  `promote-stable.yml` fast-forwarded `stable`, and the release-latency alarm
  had nothing to report.
- Per #377, `claude plugin validate` passes on a manifest whose description is
  over the upload limit, so no repository check could flag it.

## What Didn't Work

- **Looking at `stable`.** `git log origin/stable` showed every release commit,
  0.22.2 through 0.24.0. The usual "merged is not shipped" suspects (a tag
  that was never cut, as in
  [#310](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/310),
  and a promotion that never ran, as in
  [#108](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/108))
  were both ruled out. This failure sits
  one gate further downstream.
- **Reading the scheduled session's transcript.** A Cowork scheduled session
  bound to a trusted device refuses `list_events` from another cloud session
  (`elevated_session_untrusted_device`). The plugin list that session loaded
  cannot be read from elsewhere. The evidence had to come from a session that
  loads the same org copy.
- **Suspecting a scheduled-run-only pin.** The issue framed this as "merged
  fixes do not reach scheduled cloud sessions". The scheduled runs were simply
  the only regular observer. Every session that loads the org copy was equally
  stale.

## Solution

1. **Find the channel.** In a cloud session, the plugin lives under
   `~/.claude/plugins/synced/<org-id>_<uuid>/holacracy/`. Beside it,
   `holacracy.meta.json` names `marketplace_name: marketplace-labs`, and
   `manifest.json` holds a server-side entry for the plugin: an opaque version
   counter (for example `"0013"`) and an `updatedAt` timestamp. That
   timestamp is when the org copy last accepted an upload, which is the fact
   that matters.
2. **Find why it stopped.** Measure the descriptions at each tag:

   ```bash
   for t in v0.22.0 v0.22.2 v0.24.0 v0.24.1; do
     git show $t:.claude-plugin/plugin.json \
       | python3 -c 'import json,sys; print(sys.argv[1], len(json.load(sys.stdin)["description"]))' $t
   done
   ```

   Every tag through v0.24.0 printed 1282, and the `checklist-metric-audit`
   skill description was 1240. Claude's upload validator rejects a
   `plugin.json` description over 500 characters and a `SKILL.md` description
   over 1024.
3. **Trim, release, confirm.** PR #377 cut the plugin description to 464 and
   the skill description to under 1024. 0.24.1 was tagged at 2026-10-15 21:29Z.
   The synced manifest's `updatedAt` reads 2026-10-15T23:14Z, and the cloud
   session that investigated #368 on 2026-10-16 had its SessionStart hook stamp
   v0.24.1.
4. **Gate it.** `scripts/skills-lint.sh` check 8 now fails on either limit.
   Its parser handles plain, quoted, wrapped, and `>` / `|` block descriptions,
   and it reports an unreadable file as a finding rather than length 0. In
   `scripts/skills-lint.test.sh`, cases 8, 8b, 8d, and 8e each seed one defect
   (skill over 1024, plugin over 500, wrapped plain description, unreadable
   file) and assert it fails the lint and passes only with check 8 skipped.
   Case 8c asserts a description exactly at the limit still passes.

## Why This Works

The upload validator is the only gate between `stable` and the org copy, and
it fails silently from this repo's side: nothing comes back to GitHub, and the
org copy keeps serving the last version it accepted. `claude plugin validate`
checks the manifest schema, not these length limits, so CI had no way to see
the problem. Moving the limit into the per-PR lint puts the rejection before
merge, where it is loud.

One link is unverified. 0.22.0 also had a 1282-character description, yet it
reached the org copy. The likely reading is that the validator started enforcing
the limits between the 0.22.0 and 0.22.1 releases (tagged 2026-10-05 and
2026-10-06). Upload times are not visible from here, so this is unconfirmed.
The limits themselves come from #377's account of the validator, not from the
validator's own documentation.

## Prevention

- **Keep check 8 green.** Do not raise its limits to make a long description
  pass. Trim the description.
- **"Shipped" has four gates for Cowork and cloud sessions:** released (tag),
  promoted (`stable`), accepted by the upload validator (org copy updated),
  and loaded (the SessionStart version stamp). The first two are visible from
  GitHub. The third is visible only from inside a cloud session, through
  `manifest.json`'s `updatedAt`.
- **Verify a fix in a real Cowork session before closing its issue.** A tag
  and a green `stable` do not prove the org copy moved.
- **Open gap:** `scripts/plugin-version-skew-check.sh` probes four channels
  (transcripts, desktop-app copy, plugin cache, recorded install) but not the
  org synced copy, so it could not have caught this.

## Related Issues

- [#368](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/368): the stale-version report this doc resolves.
- [promote-stable-startup-failure-missing-caller-permissions.md](promote-stable-startup-failure-missing-caller-permissions.md): a release that never reaches `stable`. This doc is the next gate downstream.
- [release-please-fails-when-release-app-lacks-workflows-permission.md](release-please-fails-when-release-app-lacks-workflows-permission.md): a release that never gets its tag.
- [ADR-0008](../../adr/0008-session-injected-honest-grounding-directive.md): the version stamp that made the symptom visible, and the skew check's channel list.
- [ADR-0016](../../adr/0016-labs-is-the-canonical-channel-and-this-repo-self-hosts-the-public-one.md): the labs channel the org copy is sourced from.
