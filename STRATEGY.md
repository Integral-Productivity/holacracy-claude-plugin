---
name: Holacracy Claude Plugin
last_updated: 2026-06-17
---

# Holacracy Claude Plugin Strategy

## Target problem

Holacracy competence is scarce, slow to develop, often poorly modeled, and usually poorly executed despite good intentions. Led and facilitated well it's an actively developmental practice — but under stress, errors go uncorrected and routines fall apart. This is one inseparable developmental loop: modeling good practice in the moment is how competence actually builds, across anyone filling any role (core or not) with limited Holacracy experience.

## Our approach

Develop, don't replace. Every interaction is scaffolding that builds the practitioner's competence over time — modeling good practice in the moment and correcting in a way that teaches rather than creating dependence. The explicitly rejected alternative is automating the role away. The primary mechanism: an always-on co-pilot present at the point of work, in-flow, so correction and routine-holding happen in the moment instead of in a periodic training session.

## Who it's for

**Primary customer:** A governance champion holding the line — the person responsible for the org's Holacracy practice quality across circles. They're hiring the plugin to keep the practice from decaying and to raise the floor for under-resourced role-fillers.

**Primary user:** Someone not fully resourced to embody their Holacracy role(s) — new to it, too busy or distracted to keep up, or too early in developmental maturity to appreciate and sustain it. They're hiring the plugin to energize their role(s) competently in the moment, without a coach on call.

## Key metrics

_Honest measurement note: this is a public, open-source plugin with no central telemetry today. Capture→processing and routine adherence are computable from a user's own GlassFrog data; the other two need a proxy or longitudinal tracking that must be set up deliberately._

- **Declining correction-dependence** — over time a user needs the co-pilot _less_ for the same class of error, making the correct move unprompted. The truest signal of development over dependence (qualitative/proxy at first).
- **Tension capture→processing ratio** — share of captured tensions that actually get processed (acted, archived, converted), not just filed. Guards against the vanity of "tensions captured"; regresses when capture outruns follow-through.
- **Routine adherence across circles** — are the practice's routines kept: meetings on cadence, checklists/metrics current, backlogs cleared? The governance-champion's health metric; lagging, org-level, regresses under stress.
- **Continued practice at N months** — orgs and people still actively practicing Holacracy 3/6/12 months in. The direct counter to "it falls apart under stress" — survival, not usage.

## Tracks

### In-flow role co-piloting

Always-on co-pilots present at the point of work — the four Core Roles today, any role over time — via slash commands, meeting support, and session hooks.

_Why it serves the approach:_ It is the presence mechanism that delivers developmental scaffolding in the moment of real work.

### Governance-data grounding (GlassFrog-first)

The connector seam to real org structure: skills target a governance-data boundary — resolve actor, list roles/domains/authority, list and create tensions — with GlassFrog as the first and only implementation today (its MCP ships built-in, alongside actor/role resolution, authority lookups, the API constraints, and v3→v4 maturation). Built so the backend can be repointed or swapped without touching the practice skills.

_Why it serves the approach:_ Correction only lands and earns trust when it's specific to _this_ org's real roles and authority — and keeping that grounding behind a seam keeps the developmental practice from being locked to any one SaaS.

### Tension lifecycle

Capture → triage → process → supersede, with the human-confirmation safeguard intact.

_Why it serves the approach:_ It turns in-the-moment sensing into durable correction without crossing into auto-action — the developmental loop made concrete.

### Proactive practice-holding

Agentic routines that prep, audit, and surface drift on a schedule (pre-tactical prep, post-tactical anti-pattern audits, weekly self-audit).

_Why it serves the approach:_ It's how routines stop falling apart under stress — the AI helps hold them so the human can keep developing.

## Not working on

- Auto-acting on the org's behalf — the AI drafts for human review; it never auto-files proposals, auto-issues rulings, or auto-assigns roles.
- Automated tension _processing_ — the plugin captures and triages tensions, but deciding and resolving them stays with the human.
- Replacing the role-holder — even as AI agents begin to hold roles, the bet stays developmental, not substitutional.
- Building our own governance record-keeping system — we connect to existing ones (GlassFrog today) through a connector seam, not replace them.
