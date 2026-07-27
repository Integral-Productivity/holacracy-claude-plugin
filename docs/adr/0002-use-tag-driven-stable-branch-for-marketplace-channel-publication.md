# 2. Use tag-driven stable branch for marketplace channel publication

Date: 2026-05-23

## Status

Accepted

Amended by
[ADR-0010](0010-release-please-is-the-sole-writer-of-the-plugin-version.md) —
the release act is now *merging the release-please PR*; release-please writes
`plugin.json`'s version and pushes the tag. The tag-driven `stable` promotion
described below is unchanged.

## Context

This plugin ships through the public
[`Integral-Productivity/marketplace`](https://github.com/Integral-Productivity/marketplace)
catalog. Users install via `/plugin install holacracy@integral-productivity-tools`
and refresh via `/plugin marketplace update integral-productivity-tools`.

The original convention was for the marketplace's `marketplace.json` to
pin each plugin to a specific `version` matching the plugin repo's
`.claude-plugin/plugin.json`. In practice this drifted: the plugin
shipped `0.2.0`, the marketplace listing still said `0.1.0`, and users
got stale builds. The two-step release process (bump in plugin repo,
then bump in marketplace repo) reliably loses its second step.

Claude Code marketplaces support three sourcing models for a `github`
plugin entry: pinned `version`, omit `version` entirely (every commit
becomes a new version), or `ref: "<branch-or-tag>"` to follow a
maintainer-controlled ref. The third pattern is documented as
["release channels"][1].

[1]: https://docs.claude.com/en/docs/claude-code/plugin-marketplaces#version-resolution-and-release-channels

## Decision

We publish releases of this plugin through a `stable` branch advanced
by a tag-driven GitHub Actions workflow.

- The marketplace's `marketplace.json` entry for this plugin sets
  `"ref": "stable"` and omits `version`.
- A release is performed by:
  1. Bumping `version` in `.claude-plugin/plugin.json` and merging to
     `main`.
  2. Pushing a tag `vX.Y.Z` matching the new version.

  (Superseded by
  [ADR-0010](0010-release-please-is-the-sole-writer-of-the-plugin-version.md):
  release-please performs both steps when its release PR is merged. Do not
  hand-bump `plugin.json`.)
- `.github/workflows/promote-stable.yml` listens for
  `v[0-9]+.[0-9]+.[0-9]+` tag pushes, verifies that `plugin.json`'s
  `version` matches the tag (minus the `v` prefix), and fast-forwards
  `refs/heads/stable` to the tagged commit. The push is never forced —
  a non-fast-forward tag fails the run rather than rewinding `stable`.
- Pre-release suffixes (e.g. `v0.2.0-rc.1`) intentionally do not match
  the trigger and do not advance `stable`.

`plugin.json`'s `version` remains the user-visible version (shown by
`/plugin list` etc.); the marketplace simply tracks whichever commit
the maintainer has declared stable.

## Consequences

**Easier**

- Marketplace listing never needs a version bump. The marketplace
  becomes a discovery surface, not a release ledger. Drift like the
  `0.1.0` / `0.2.0` mismatch that motivated this decision becomes
  structurally impossible — there is no version field in the marketplace
  entry to fall behind.
- The release act is unambiguous: pushing `vX.Y.Z` is what publishes.
  No follow-up PR in another repo is needed.
- `main` can carry in-flight work (including breaking changes) without
  immediately affecting installed users — they stay on the last tagged
  release until the next tag.

**Harder**

- Maintainers must remember to push the tag after merging the version
  bump. Until that's automated (e.g. via release-please), the release
  step is manual.
- The plugin repo now has a long-lived branch (`stable`) that should
  never be committed to directly. Branch protection on `stable`
  (push-by-Actions only) is a recommended follow-up.
- An emergency rollback — "revert the last release" — requires either
  shipping a new tag with the reverted code, or temporarily pinning
  `version`/`sha` in the marketplace. The first path is the intended
  one; the second is an escape hatch.

**Risks mitigated by the workflow itself**

- *Drift between tag and `plugin.json`*: the version-match assertion
  fails the run, blocking promotion.
- *Accidental force-push of `stable`*: the workflow uses a plain
  `git push` (no `--force`), so any non-fast-forward attempt fails
  loudly.

**Template propagation**

This pattern becomes the template for the other Integral-Productivity
plugins listed in the public marketplace (`lean-management`,
`model-framework-integration`). Their migrations are tracked as
separate issues in those repos.
