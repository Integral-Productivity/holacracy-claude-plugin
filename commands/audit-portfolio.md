---
description: Audit a circle's checklist items and metrics against its purpose, accountabilities, and domains, then propose and (on confirmation) apply improvements. Operational, not governance — applies changes directly via GlassFrog after per-change confirmation.
argument-hint: [circle name to audit, optional]
---

# /holacracy:audit-portfolio

Run a **checklist & metric portfolio audit** on a circle. The command primes scope; the underlying `checklist-metric-audit` skill carries the method.

## What this command does

1. **Resolve actor + circle scope** via `skills/shared/actor-and-role-resolution.md` (`glassfrog_get_me`, `glassfrog_list_my_roles`).
   - If `$ARGUMENTS` was provided, treat it as a circle-name hint and validate it against the actor's roster; if the actor holds no role in that circle, name the mismatch and offer Observer mode.
   - If the actor operates in exactly one circle relevant to the request, proceed silently.
   - If several, ask which circle to audit.
2. **Announce the resolved scope** before auditing: `Auditing the checklist & metric portfolio of **[Circle Name]**`.
3. **Hand off to `checklist-metric-audit`** for the audit itself -- load purpose/accountabilities/domains, enumerate checklist items and metrics on the circle role and every sub-role, build the coverage matrix, surface findings, and draft candidate items and dispositions.

## The one thing this command insists on

Checklist items and metrics are **operational, not governance** (Holacracy Constitution Art. 3.2 -- Tactical Meeting Checklist/Metrics Review). This command therefore **applies approved changes directly** through the GlassFrog MCP -- it does not open a governance proposal. Two guardrails hold:

- **Per-change confirmation for destructive edits.** Deletes and merges require explicit approval per item; never merge or delete on an unconfirmed assumption.
- **Governance escalation when warranted.** If a gap actually needs a new accountability or domain (no role is accountable for something the circle needs), that is a governance tension -- hand off to `/holacracy:capture-tension`, don't paper over it with a checklist item.

## Behaviour

- If GlassFrog is not connected, run advisory-only from what the user supplies and name the limit.
- This command primes scope and produces the audit; it applies changes only after the user approves specific candidates and dispositions.
