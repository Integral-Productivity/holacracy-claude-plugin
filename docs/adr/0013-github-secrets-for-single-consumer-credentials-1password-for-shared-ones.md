# 13. GitHub secrets for single-consumer credentials, 1Password for shared ones

Date: 2026-08-05

## Status

Accepted

Extends the org-level ADR-045 (`devops-excellence`). ADR-045 governs *how* a
credential reaches a public repo once you have decided it lives in 1Password —
scoped vault tokens only, never the whole-vault `OP_SERVICE_ACCOUNT_TOKEN`, and
never inline-expanded into a `run:` script body. It does not answer the prior
question: whether a given credential belongs in 1Password at all. This ADR
answers that, for this repo.

## Context

[ADR-0012](0012-test-the-skills-not-just-the-scaffolding.md) established the
behavioural eval tier and named its unpaid cost plainly under **Harder**:
"Tiers 2 and 3 need `ANTHROPIC_API_KEY` in CI, which is a new secret and a new
standing cost." Issue #183 is the bill coming due — `evals/benchmark.json` ships
with every statistic `null` because no graded run can happen without that
credential, and #173's regression alarm has nothing to compare against until it
does.

Provisioning it surfaced a question this repo had never recorded an answer to.
Its workflows already use 1Password, so "put it in 1P like everything else" reads
as the consistent choice. Looking at what is actually there says otherwise.

**The inventory.** This repo holds **zero** repository-level secrets. All four
credentials its workflows consume arrive from the organization store:
`CLAUDE_CODE_OAUTH_TOKEN`, `OP_SERVICE_ACCOUNT_TOKEN`, `OP_AUTOMERGE_PUBLIC_TOKEN`,
`OP_RELEASER_PUBLIC_TOKEN`. Three of those four are 1Password plumbing rather than
end credentials — tokens whose only purpose is to fetch another secret.

**What 1Password is actually carrying here.** Exactly one credential:
the `ip-releaser` GitHub App private key, read at
[`.github/workflows/release-please.yml`](../../.github/workflows/release-please.yml)
line 105 as `op read "op://ip-automation/ip-releaser/private_key"`. That key has
the properties the vault exists to serve — many consumer repos, central rotation,
and a value nobody should paste per-repo. It is also the sharpest edge in the
repo: a multi-line PEM landing in a step output on a *public* runner, mitigated by
a hand-rolled per-line `::add-mask::` loop, because GitHub's mask directive is
line-oriented and a single mask on a multi-line value leaks every line after the
first.

**What the vault route costs on a public repo.** Under ADR-045 a public repo
cannot receive the whole-vault token at all; it gets scoped tokens on
`ip-automation-public`. So routing `ANTHROPIC_API_KEY` through 1P means: a new
vault item, a new scoped service-account token, that token added as a GitHub
secret, the 1P CLI installed in the `graded` job, and an `apiKeyHelper` wired up
because [`scripts/run-behavioural-eval.py`](../../scripts/run-behavioural-eval.py)
line 229 records that `claude --bare` reads only `ANTHROPIC_API_KEY` or an
`apiKeyHelper`. The chain gets longer and still terminates in a GitHub secret.
You do not remove a secret; you substitute one.

It also adds a failure mode to a job that currently has a clean one.
[`.github/workflows/skills-eval.yml`](../../.github/workflows/skills-eval.yml)
gates its graded tier on a single condition — key present or absent — and on
absence emits a notice and succeeds, because a workflow that goes red nightly
until someone performs a manual act trains people to ignore a red workflow. A 1P
read introduces a third state, *unreachable*: expired token, missing item, or 1P
outage. `release-please.yml` carries an explicit soft-failure contract for exactly
those three, and the consequence is recorded in
[`docs/solutions/tooling-decisions/release-please-manifest-vs-tag-semantics.md`](../solutions/tooling-decisions/release-please-manifest-vs-tag-semantics.md):
a green run of that workflow does not mean it did its job. That is a real cost,
and it is worth paying for a credential shared across repos. It is not worth
paying for one consumer.

**Where the risk actually is.** The instinct to reach for the vault treats
*storage location* as the safety lever. For this credential it is not. The
Anthropic key is billed per token, so its failure mode is spend, not access.
Two facts bound it better than any storage choice:

- `skills-eval.yml` triggers only on `schedule` and `workflow_dispatch` — there is
  no `pull_request` trigger, so a fork PR can never reach the secret, and
  `workflow_dispatch` requires write access. This matters more than it might
  appear: the eval runner invokes the model with `--permission-mode bypassPermissions`.
- A key minted inside its own Anthropic Console workspace with a monthly limit
  caps a leak in dollars and revokes in one click, touching nothing else.

Neither of those improves if the key is fetched from a vault instead of read from
a secret.

## Decision

**Route a credential by its consumer count, not by habit.**

1. **One consumer, one repo → a GitHub secret, directly.** No vault indirection.
   `ANTHROPIC_API_KEY` is set as a **repository** secret on this repo. It is read
   only by the `graded` job of `skills-eval.yml`, which already reads
   `secrets.ANTHROPIC_API_KEY` and needs no change.

2. **Many consumers, or a need for central rotation and a read audit trail →
   1Password.** The `ip-releaser` PEM is the standing example. On a public repo
   this is always via a *scoped* vault token on `ip-automation-public`, never the
   whole-vault `OP_SERVICE_ACCOUNT_TOKEN`, per ADR-045.

3. **Prefer a repository secret over an organization secret for a single-repo
   consumer.** The org store is the right home for something several repos read;
   putting a single-repo credential there creates an org-wide credential whose
   repository-access list is one more thing to scope correctly. That scoping is
   not hypothetical — a repo missing from `OP_AUTOMERGE_PUBLIC_TOKEN`'s allowed
   list produced an auto-merge path that reported green and silently never merged
   (#92). A repo secret has no such list to get wrong.

4. **Bound the blast radius at the credential, not at the store.** A billed API
   key is minted in its own provider-side workspace with a spend limit, so a leak
   or a runaway loop is capped and independently revocable. For this repo that
   means the eval key lives in its own Anthropic Console workspace.

5. **Keep the absent-credential path single-valued.** A job that degrades
   gracefully on a missing secret must not silently acquire a second way to fail.
   If a credential ever does move to 1P, the consuming job has to distinguish
   *absent* from *unreachable* and report them differently — reporting health it
   did not measure is the failure `CLAUDE.md`'s grounding-readout section, and
   both operator-local alarms' exit-`2` behaviour, exist to prevent.

6. **Revisit on the second consumer.** The moment a second repo or workflow needs
   the same Anthropic credential, clause 2 applies and it moves to a scoped vault
   item. Consumer count is the trigger, and it is checkable rather than a matter
   of taste.

## Consequences

**Easier**

- Provisioning is one act in one place. No vault item, no scoped token, no CLI
  install step, no `apiKeyHelper`, and no new soft-failure branch in a nightly job.
- The graded job keeps a two-state contract — key present or absent — which is
  what lets it succeed-with-a-notice instead of going red every night until a
  human acts.
- The next credential is a lookup rather than a debate. The rule was previously
  inferable only from prose in *other* repos' workflow comments; it now has a
  local home.
- Blast radius is bounded by something that actually bounds it. A spend cap
  limits the realistic damage from this credential far more than storage choice
  does.

**Harder**

- Rotation is manual and unaudited. There is no expiry on a GitHub secret, no
  record of reads, and rotating means a human re-pastes a value. For a
  spend-capped, single-consumer key that is an acceptable trade; for a credential
  with real access scope it would not be, which is what clause 2 is for.
- Two mechanisms now coexist in one repo, and the distinction is a judgment about
  consumer count rather than a mechanical check. Clause 6 makes the trigger
  checkable, but nothing enforces it — a second consumer could quietly appear.
- This repo stops being a zero-repo-secret repo. Anyone auditing credential
  surface has one more place to look than the org store alone.

**Risks accepted**

- A leaked key is billable until noticed. Accepted because the workspace cap
  converts an unbounded loss into a known monthly maximum, and because the secret
  is unreachable from fork PRs — `skills-eval.yml` has no `pull_request` trigger.
- The rule is stated, not enforced. No lint or workflow asserts that a
  multi-consumer credential has migrated to 1P. Writing one would mean teaching
  CI to count consumers across repos, which costs more than the failure it
  prevents at this scale.
