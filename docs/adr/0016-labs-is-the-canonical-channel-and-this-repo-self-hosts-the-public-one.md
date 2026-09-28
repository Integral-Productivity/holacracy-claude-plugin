# 16. Labs is the canonical channel, and this repo self-hosts the public one

Date: 2026-09-28

## Status

Accepted

Amends [ADR-0002](0002-use-tag-driven-stable-branch-for-marketplace-channel-publication.md):
replaces its named marketplace (`Integral-Productivity/marketplace`,
`integral-productivity-tools`) with the two channels below. Its release
mechanics — a `stable` branch advanced by a tag, catalog entries with
`"ref": "stable"` and no `version` — are unchanged and now bind both channels.

## Context

ADR-0002 (2026-05-23) said this plugin ships through the public
`Integral-Productivity/marketplace` catalog, installed as
`holacracy@integral-productivity-tools`. README.md said the same. Both were
false by the time #234 was filed: that catalog is `"plugins": []`. The plugin
had moved, deliberately, to the labs marketplace; nobody updated this repo's
docs, and nothing checked them. Anyone following the README got an empty
marketplace.

The move was later written down in `marketplace-internal`'s ADR-0003
(2026-09-03), which sorts every Integral Productivity plugin by three gates.
Holacracy is "not core — Holacracy is not IP's method → portable → labs
(Domain)". The labs README calls Domain plugins "terminal by design": they do
not graduate to the core catalog. So listing this plugin in the core catalog,
as ADR-0002 assumed, is not a doc fix; it would reverse ADR-0003.

As of this ADR the registrations are (read directly from each catalog, #235):

| Catalog | Lists `holacracy`? |
| --- | --- |
| `marketplace` (`integral-productivity-tools`, public) | No — empty by design |
| `marketplace-internal` (`integral-productivity-internal`, private) | No — removed in its #45 |
| `marketplace-labs` (`integral-productivity-labs`, **private**) | Yes, `ref: stable` |

That leaves a public, MIT-licensed plugin installable only by people with
access to a private repo. The README's fallback — "add this repo directly to
your plugin sources" — did not work either: the repo carried no catalog, so
`/plugin marketplace add` found nothing to add.

Two options were weighed on #234. **A**: list the plugin in the public core
catalog. **B**: accept labs as canonical and fix the docs. The operator chose
B. B alone would leave no public install path, so this ADR adds one.

## Decision

1. **`integral-productivity-labs` is the canonical channel** for Integral
   Productivity. It is where the organisation installs from, and the channel
   the version-skew alarm expects.
2. **This repo serves itself as a one-plugin public catalog**:
   `.claude-plugin/marketplace.json`, catalog name
   `integral-productivity-holacracy`, one entry sourced from this repo at
   `ref: stable` with no `version`. Anyone can run
   `/plugin marketplace add Integral-Productivity/holacracy-claude-plugin`.
   Its source is `github` + `ref: stable`, not a relative `./` path, because a
   relative path follows whatever ref the marketplace was added from (usually
   `main`) and would bypass the release channel.
3. **The core `Integral-Productivity/marketplace` does not list this plugin.**
   Moving it there is a graduation under `marketplace-internal` ADR-0003 and
   the labs graduation rule, not a docs change here.
4. **README's Install section is a checked claim.** `scripts/install-channel-check.sh`
   reads every `/plugin marketplace add` channel it names and fails unless that
   catalog lists `holacracy` from this repo at `stable` with no `version`, and
   unless every channel has a matching `/plugin install holacracy@<catalog>`
   line. `scripts-test.yml` checks the self-hosted channel on every PR;
   `install-channel-check.yml` checks labs daily and on README or catalog
   changes, with a read-only `ip-org-auditor` token (ADR-0013: a second
   consumer of an existing credential, not a new one).
5. **Install from one channel, not both.** The README says so. Two
   registrations are two answers to "which version am I on" — the #122
   failure.

## Consequences

**Easier**

- The documented install works, for org members and for everyone else.
- Both channels follow `stable`, so a release reaches both at once. There is
  no second catalog to bump; ADR-0002's "a marketplace is a discovery surface,
  not a release ledger" holds for both.
- A README that drifts from the catalogs fails CI instead of failing users.
  The check replays #234 in its own test suite.

**Harder**

- There are two registrations of one plugin. That is deliberate — they serve
  different audiences — but an operator who adds both reproduces #122's
  ambiguity. The README warning is the only guard.
- The labs check depends on the `ip-org-auditor` App having Contents: read on
  `marketplace-labs`. Until it does, `install-channel-check.yml` is red with a
  message naming the gap. That is correct behaviour — the canonical channel is
  unmeasured — but it is a standing red until someone grants the access.
- The self-hosted catalog carries a `description` that can drift from
  `plugin.json`'s. Nothing checks that; it is cosmetic.

**Risks accepted**

- The public channel is this repo, so a public user's install depends on this
  repo staying public and `stable` staying protected. Both are already true
  for labs installs, which clone the same repo at the same ref.
