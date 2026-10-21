# 17. Live-org evidence stays out of this public repo, and published history is accepted

Date: 2026-10-21

## Status

Accepted

## Context

This repo has been public since it was created on 2026-05-21. It was also used
as a workbench against Integral Productivity's own GlassFrog organization, and
the evidence from those probes went into the files that ship:

- live GlassFrog identifiers: the organization's legacy number in a web URL
  example, a project's legacy number, and three full v5 ids;
- summaries of real tensions with their short ids, ages, and the roles that
  held them;
- the live circle and role structure, and a real Productboard workspace URL.

None of it was a secret, a credential, or client data. A gitleaks scan of all
257 commits found no secret. But it was internal detail that nobody chose to
publish.

Two causes. First, the repo's own discipline asks for every claim to rest on an
observation, and nothing separated "observed in our org" from "safe to
publish". Second, the leak guard in `scripts/evals-harness.test.sh` scanned
only `evals/`, and to forbid the live ids it named them, so the guard itself
published them.

## Decision

1. **Fix the tree, accept the history.** Every live value is removed from
   HEAD. Git history is not rewritten. The values have been public for five
   months, a rewrite breaks the `stable` tags both install channels track
   (ADR-0016), and GitHub keeps old commits reachable by SHA until GitHub
   Support purges them. Kraig chose this on 2026-10-21.
2. **Examples are synthetic.** A skill or doc that needs an example of a role,
   a tension, or a domain uses a made-up one. Real roles and tensions were
   replaced with synthetic names and ids in the same change. Live-org evidence
   belongs in a private repo, such as `governance-decisions`, and is cited here
   only by its lesson.
3. **The guard forbids by digest, over every tracked file.**
   `scripts/leak-denylist-scan.py` hashes candidate tokens and compares them
   with `evals/leak-denylist.sha256`. It never prints a matched value. The
   harness runs it on the repo and proves it can fail on a planted value.

## Consequences

- A digest hides a 32-hex id well but a short number or a phrase poorly: anyone
  can hash a guess. That is acceptable only because those values were already
  public when the list was written. Never add a value to the list that is not
  already public; for a new secret value, the right fix is to keep it out of
  the repo.
- Adding a value to the denylist means hashing it locally and committing only
  the digest.
- The old commits still show the live values. Anyone who reads history can
  find them. This ADR records that as known and accepted.
