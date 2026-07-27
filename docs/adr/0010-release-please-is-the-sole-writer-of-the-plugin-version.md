# 10. release-please is the sole writer of the plugin version

Date: 2026-07-27

## Status

Accepted

Amends [ADR-0002](0002-use-tag-driven-stable-branch-for-marketplace-channel-publication.md):
supersedes its manual release-act steps, keeps its tag-driven `stable`
promotion.

## Context

[ADR-0002](0002-use-tag-driven-stable-branch-for-marketplace-channel-publication.md)
(Accepted 2026-05-23) established a **manual** release act: bump `version` in
`.claude-plugin/plugin.json`, merge to `main`, push a tag `vX.Y.Z`;
`promote-stable.yml` verifies that `plugin.json`'s version matches the tag and
fast-forwards `stable`. ADR-0002 named release-please only as *future*
automation — "Until that's automated (e.g. via release-please), the release step
is manual" — and its Consequences correctly predicted the failure mode:
maintainers forget the tag. They did, three times (`v0.2.1`, `v0.2.2`, `v0.3.0`
all merged untagged).

release-please was then bolted on (`7f9c463`, #19) with `release-type: simple`.
That configuration made release-please the writer of
`.release-please-manifest.json` and `version.txt`, and — decisively — listed
`.claude-plugin/plugin.json` `$.version` as an `extra-files` target, so
release-please now rewrites the very field ADR-0002 told humans to bump.
**That authority transfer was never recorded anywhere.** No ADR amended
ADR-0002, and `CLAUDE.md` § Versioning still read "bump plugin version when the
bundle shape changes" — with a second copy of the same instruction at the end of
§ GlassFrog MCP.

What followed was not carelessness; it was the system working exactly as
documented. Five consecutive feature PRs (#70, #77, #87, #88, #99) hand-bumped
`plugin.json` 0.6.0 → 0.10.0 while `.release-please-manifest.json` and
`version.txt` stayed at 0.6.0. Two diverging sources of truth for one number.
The pending release PR (#54) had computed 0.7.0 from the manifest and would have
rewritten `plugin.json` on merge, **downgrading** the publicly advertised
version (#100). Nothing in CI could object: #99 was auto-merged by
`ip-automerge` on a green build.

A second factor amplified the first. Release PR #54 sat open and unmerged for a
month, so the *shipped* version never advanced: `stable` — the ref the public
marketplace tracks (`ref: "stable"`, per ADR-0002) — remained at `caef648` =
v0.6.0, **20 commits behind `main`**. Five shipped features had reached zero
consumers while `plugin.json` advertised 0.10.0. When the automated path
visibly is not moving, hand-bumping feels like the only way to make the version
"look right." Any fix that addresses only the hand-bumping and not the stalled
release PR leaves that pressure in place.

## Decision

**release-please is the sole writer of this plugin's version.** Humans and
agents never hand-edit `.release-please-manifest.json`, `version.txt`, or
`.claude-plugin/plugin.json` `$.version`.

1. **Invariant.** At every commit on `main`:
   `.release-please-manifest.json["."]` == `version.txt` ==
   `.claude-plugin/plugin.json $.version` — and, once a release has been
   promoted, == the latest `vX.Y.Z` tag.
2. **Contributor protocol.** Describe the change with a Conventional Commit and
   never set a version. The type drives the bump: `fix:` → patch, `feat:` →
   minor, `feat!:` / `BREAKING CHANGE:` → major (this repo sets
   `bump-minor-pre-major: false`, so a breaking change takes 0.x to 1.0.0). A
   bundle-shape change is expressed as `feat:`, not as an edited number.
3. **The release act is merging the release PR**, not pushing a tag. This
   supersedes ADR-0002 § Decision steps 1–2. release-please writes all three
   version files plus `CHANGELOG.md`, creates the `vX.Y.Z` tag, and thereby
   fires the promotion path.
4. **ADR-0002's tag-driven `stable` promotion stands unchanged.** The
   marketplace entry still sets `"ref": "stable"` and omits `version`;
   `promote-stable.yml` still asserts `plugin.json $.version` == tag before
   fast-forwarding; pre-release suffixes still do not advance `stable`; the push
   is still never forced. This ADR changes only *who writes the version and
   pushes the tag*. That assertion is now also the enforcement point for the
   invariant's tag leg.
5. **Forcing a specific version** is done with a one-shot `Release-As: X.Y.Z`
   commit footer, never by editing a file. The `release-as` key in
   `release-please-config.json` is rejected: it is sticky and pins every
   subsequent release until someone remembers to remove it.
6. **Skill `version:` frontmatter remains hand-maintained.** It is a separate,
   per-skill number outside release-please's scope.
7. **Enforcement is layered.** `.github/workflows/version-authority.yml` fails
   any PR that changes an owned field — exempting the `release-please--*` branch
   and the `ip-releaser[bot]` actor, with a `version-override` label as escape
   hatch — and separately asserts the three-file invariant.
   `promote-stable.yml` enforces the tag leg. `CLAUDE.md` § Versioning states
   the convention so that agents reading it reproduce the right behavior instead
   of the bug.

## Consequences

**Easier**

- One source of truth. The 0.6.0-vs-0.10.0 class of drift becomes
  CI-detectable at PR time rather than discovered at release time.
- Versioning stops being a judgment call. "Does this change the bundle shape?"
  is replaced by "what Conventional Commit type is this?" — a question the
  contributor already has to answer.
- Agents reading `CLAUDE.md` now get instructions that match the tooling. The
  root cause of this incident was documentary, so the primary fix is
  documentary.
- No forgotten tags. ADR-0002's predicted failure mode is closed by
  construction: the tag is a product of merging the release PR.

**Harder**

- The release PR becomes load-bearing. If it sits unmerged, the visible version
  stops advancing and the pressure to hand-bump returns. Keeping it moving —
  auto-merge coverage for the `release-please--*` branch, which lives in the
  shared public reusable and not in this repo — is now a real operational
  requirement, tracked separately.
- Re-baselining the manifest is delicate. release-please takes the next version
  from the manifest but bounds the changelog by the newest *tag* whose version
  equals it, so pointing the manifest at a version that has no matching tag can
  regenerate a whole-history `CHANGELOG.md`. Captured in
  [`docs/solutions/tooling-decisions/release-please-manifest-vs-tag-semantics.md`](../solutions/tooling-decisions/release-please-manifest-vs-tag-semantics.md).
- The guard is a repo-local workflow, diverging from the tier3 template's
  all-thin-callers shape. `ci.yml` and `validate-plugin.yml` are thin callers to
  `Integral-Productivity/reusable-workflows` with no room for repo-local steps,
  and `auto-merge.yml` is byte-identical to the template by design. Promoting
  the guard into the public reusable, so every `*-claude-plugin` repo inherits
  it, is a follow-up.
- The guard only bites once it is a **required** status check. `main` carries no
  ruleset today and `gh pr merge --auto` waits only on required checks, so a
  non-required guard can be outrun by auto-merge on a `claude/*` branch — the
  exact path that produced #99. Configuring that ruleset is a settings act, not
  a file change.

**Risks accepted**

- The `version-override` label lets a human bypass the guard. This is
  deliberate: a guard that can permanently wedge a release is worse than one
  that can be consciously overridden. Overrides are visible on the PR and
  annotated in the run log.
- A `pull_request`-scoped check cannot see a direct push to `main`, which is
  currently possible. The invariant job's `push: main` trigger is the backstop
  — it catches the resulting state even though it cannot block the push.
