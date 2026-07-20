# 7. Route downstream artifacts by live GlassFrog domains/policies, not a hard-coded table

Date: 2026-07-20

## Status

Accepted

## Context

The "Continuous Organizational-Context Grounding" analysis (org Project #39; design in ip-agent-teams#58) identified two root causes for why AI work sessions drift from organizational intent. The second — the **routing** root cause — is that the **role→system-of-record mapping is unencoded**, so downstream artifacts default to whatever substrate is native to the work's implicit frame (engineering matters → GitHub/ADR/memory; product decisions land in Productboard only when the task is *explicitly* about Productboard). The org systems of record (GlassFrog governance, Productboard strategy) lag the engineering ones, and drift accumulates.

The Phase 4 countermeasure design first proposed encoding this mapping as a **hard-coded routing table** (a static `role/circle → system-of-record` map shipped in the plugin). That framing was reconsidered: a static table drifts the moment governance changes — the exact failure mode this whole effort fights — and it conflicts with the plugin's established stance of reading governance live and org-agnostically rather than caching assumptions (`holacratic-ai-governance` SKILL.md: "Treat governance as mutable — re-query rather than cache assumptions"). It would also duplicate, at lower fidelity, information the system of record already holds.

Two existing facts make a live-derived approach the better fit:

- **The governance-data seam already exists.** [ADR-0005](0005-holacracy-identity-glassfrog-as-first-connector-behind-a-seam.md) established that practice logic targets a named governance-data boundary (resolve actor, list roles/domains/authority) with GlassFrog as the first connector behind it. Routing reads are a natural consumer of that same seam — `list_role_domains` / `list_role_policies` — not a new dependency.
- **Domains already encode the routing signal — verified against the live org (2026-07-20).** A probe of the actual GlassFrog org tree found that roles' **domains directly name their system of record**, several with the system URL inline:
  - The **Product Architecture** role holds domains `[Product Hierarchy (Productboard)](https://integralproductivity.productboard.com)`, `[Products and Features (Productboard)]`, `[Product Insights (Productboard)]`, and `Value Propositions (Strategyzer)`.
  - Governance decisions map to the `All governance records of the Circle` domain and the `GlassFrog Admin` domain → GlassFrog.
  - Finance → QuickBooks domains (`QuickBooks Online account — chart of accounts, transaction records, reports`).
  - Sales/marketing → HubSpot domains (`HubSpot CRM Platform`, `HubSpot Sales/Marketing/Content Hub Configuration`).

  The role→system-of-record mapping is therefore not something the plugin must *invent and maintain* — it is **already present in the live governance data** and already updates through the governance process. A hard-coded table would be a stale copy of it.

This ADR must also honor the [ADR-0004](0004-opt-in-inherited-context-in-context-command.md) scar: a countermeasure must never *claim* grounding it did not actually perform.

## Decision

Encode the role→system-of-record routing as **behavior that derives from live GlassFrog domains/policies through the governance-data seam**, not as a hard-coded table.

1. **Live-derived routing.** To route a downstream artifact, resolve the owning role and read its domains (and, where relevant, policies) via the governance-data seam (`list_role_domains` / `list_role_policies`). Match the domain's stated system of record (including any inline URL) to the target substrate. GlassFrog is the first implementation behind the seam, consistent with ADR-0005.

2. **Live-then-session-cache freshness.** Read live at first need in a session, then cache the resolved routing for the remainder of the session (this also addresses the no-cross-turn-cache gap, holacracy-claude-plugin#36). Re-read on a major pivot (a new circle/role comes into play), consistent with the resolution procedure's Step 5 re-validation. Not pure-live-every-call (unnecessary API load) and not a persisted table (drifts).

3. **Disconnect fallback: name the limit and ask.** When GlassFrog is unavailable, do not silently default to the engineering substrate. Name the constraint ("no live governance — I can't resolve where this should land") and ask the operator to declare the target, matching the plugin's existing graceful-degradation pattern.

4. **Honest by construction.** Routing reasons from live governance data actually read this session; it never asserts a routing (or the grounding behind it) that was not performed. When the domain signal is ambiguous, surface the ambiguity rather than guessing.

This decision governs the implementation of the P1 countermeasure (holacracy-claude-plugin#63) and is consumed by the PreToolUse routing check (holacracy-claude-plugin#64). The approach is decided; the build is deferred to those issues.

## Consequences

- The routing control is **self-updating from the source of record** — it cannot fall out of sync with governance, because it *is* the governance data. This is the "lifestyle change" (root-cause restructure) done in a way that resists the drift it was created to prevent.
- The plugin stays **org-agnostic**: no IP-specific role or system names are baked in. Any Holacracy org whose domains name their systems of record gets routing for free; the mechanism is generic, the data is theirs.
- A dependency on **domain-naming quality** is accepted: routing is only as good as how clearly domains name their system of record. Where a domain is vague, routing degrades to "ask." This is itself a useful signal — a vague domain is a governance tension worth surfacing (it can feed Pattern 3 tension sensing), not a bug in the router.
- The session cache introduces a **bounded staleness window** (within-session governance change before a pivot). Accepted as the freshness/cost balance; the pivot re-read bounds it.
- Routing reads add **governance-data calls** at artifact-creation moments. Bounded by the session cache; scoped to the resolved owning role, not a full-tree scan.
- The internal, IP-specific routing targets (which decisions land in Productboard vs GlassFrog vs GitHub for this org) stay on the internal track (ip-agent-teams#57); this ADR commits only to the *generic mechanism*, keeping the public plugin clean.

## Alternatives considered

- **Hard-coded routing table (original P1 framing).** Rejected: drifts from governance the moment it changes; duplicates at lower fidelity data the live system already holds; bakes org-specific names into an org-agnostic plugin.
- **Pure-live every routing decision (no cache).** Rejected as the default: maximally fresh but adds avoidable governance-data calls at every artifact moment; the session cache + pivot re-read captures nearly all the freshness at a fraction of the cost.
- **Silent default to the engineering substrate on disconnect.** Rejected: it is exactly the substrate-defaulting behavior this ADR exists to correct, and it would route silently rather than honestly.

## What this ADR does NOT do

- It does **not** implement the router. It records the approach; the build is P1 (holacracy-claude-plugin#63) and its consumer PreToolUse check (holacracy-claude-plugin#64).
- It does **not** define the exact domain-string→substrate matching rules (URL parsing, keyword matching, precedence when a role holds multiple system domains). That detail is left to the implementation, to be validated against live domains per the "probe checkable requirements live" discipline.
- It does **not** change how grounding/role-resolution happens (that is the enforcement root cause, Tracks A/B, holacracy-claude-plugin#60/#61). It governs only where downstream artifacts are routed once the owning role is known.
- It does **not** modify governance data or require any change to how the org names its domains. It reads what is there; clearer domain naming improves routing but is a governance choice, not a plugin requirement.
