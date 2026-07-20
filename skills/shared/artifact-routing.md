# Artifact Routing — Shared Reference

This document is shared across the holacracy skills. It defines how a skill decides **where a downstream artifact should land** — which system of record a piece of work (a decision, a spec, a record, a report) belongs in — by reading the owning role's live GlassFrog **domains and policies**, rather than defaulting to whatever substrate is native to the work's implicit frame.

Load this when a skill is about to produce or file an artifact whose home is not the conversation itself: a product decision, a strategy note, a governance record, a financial entry, a CRM update, a technical ADR. It is the routing counterpart to `actor-and-role-resolution.md`: that document resolves *which role* is operating; this one resolves *where that role's outputs are governed to live*.

The design decision behind this procedure is recorded in [ADR-0007](../../docs/adr/0007-route-artifacts-by-live-glassfrog-domains-not-a-hardcoded-table.md) (route by live domains, not a hard-coded table) and its implementation-level rules in [ADR-0009](../../docs/adr/0009-artifact-routing-resolver-layered-domain-recognizer.md) (the layered recognizer and multi-domain precedence). This document *is* the resolver those ADRs describe.

---

## Why Live-Derived, Not a Table

The routing root cause the plugin fights is that the **role → system-of-record mapping is unencoded**, so artifacts silently default to the engineering substrate (GitHub, ADRs, memory) even when a product decision belongs in Productboard or a governance record belongs in GlassFrog.

A static `role → system` table shipped in the plugin would drift the moment governance changes — the exact failure this effort exists to prevent — and would bake one org's role names into an org-agnostic plugin.

The better source already exists: **a role's domains name its system of record.** A domain like `[Product Hierarchy (Productboard)](https://…productboard.com)` or `QuickBooks Online account — chart of accounts, transaction records, reports` *is* the mapping, maintained through the governance process, in the system of record itself. Reading it live means the routing control cannot fall out of sync — it *is* the governance data.

This procedure reads that data through the governance-data seam ([ADR-0005](../../docs/adr/0005-holacracy-identity-glassfrog-as-first-connector-behind-a-seam.md)); GlassFrog is the first connector behind it.

---

## The Governance-Data Seam This Uses

Routing reads use the same seam the rest of the plugin targets — no new dependency:

| Seam call | Purpose |
|---|---|
| `glassfrog_list_role_domains(role_id)` | The role's domains — each domain's `description` names or points at a system of record. The primary routing signal. |
| `glassfrog_list_role_policies(role_id)` | The role's policies — secondary signal. Policies often name the tool a domain is exercised through (e.g., "may access HubSpot in read-only mode…") and can disambiguate or corroborate a domain. |

Both are read-only. Routing never writes governance and never modifies a domain — it reads what is there.

Actor/role resolution (`actor-and-role-resolution.md`) runs **first**; routing consumes its resolved role. If no role is resolved yet, resolve it before routing — routing an artifact for an unknown role is ungrounded.

---

## The Routing Resolution Procedure

Run this when a skill is about to produce an artifact whose home is a system of record.

### Step 1 — Confirm the owning role

Routing is scoped to **the role that owns the work**, not the whole org. Usually this is the role resolved by `actor-and-role-resolution.md`. If the artifact is authorized by a *different* role than the one operating (e.g., the actor is advising, or the work maps to a sister role's accountability per Pattern 4), route by *that owning* role — name the shift.

If the owning role is itself ambiguous, that is a governance-rooting question, not a routing question — resolve it via `../holacratic-ai-governance/references/governance-rooting.md` first.

### Step 2 — Read the owning role's domains (and policies) live

Call `glassfrog_list_role_domains(role_id)`. Where the domain signal is thin or needs corroboration, also call `glassfrog_list_role_policies(role_id)`.

Read **live at first need** in the session. Do not assume domains from memory or from a prior session — governance changes.

### Step 3 — Recognize each domain's system of record (layered recognizer)

For each domain `description`, determine the system of record it names, trying these layers in order and stopping at the first that fires. **The domain names its own system** — the recognizer *extracts* that name; it does not match against a closed list of pre-known systems, so a system the plugin has never seen still routes correctly.

- **Layer 1 — Inline URL host (strongest, self-describing).** If the domain string contains a URL, the host names the system. `https://integralproductivity.productboard.com` → **Productboard**. The host *is* the system identity; no prior knowledge needed. Use the registrable domain (e.g., `productboard.com` → Productboard, `app.hubspot.com` → HubSpot), ignoring the org-specific subdomain.

- **Layer 2 — Named system in the domain text.** If no URL, extract the system named in the text — typically a parenthetical `(Strategyzer)`, `(Productboard)`, or a leading proper-noun product name: `QuickBooks Online account — …` → **QuickBooks**; `HubSpot CRM Platform` → **HubSpot**; `Smaply Configuration and Content` → **Smaply**; `GlassFrog Admin` → **GlassFrog**. The extracted proper noun *is* the target substrate label; the plugin need not have heard of it before.

- **Layer 3 — Semantic governance fallback.** If no system is named but the domain is about the org's own **governance records** (e.g., `All governance records of the Circle`, the governance structure itself), the system of record is the connected **governance tool** — GlassFrog, as the governance backend behind the seam. Corroborate against policy text where present (e.g., a "GlassFrog Usage" policy stating "@Secretary may update governance records… as outputs of the governance process").

- **Miss.** If a domain names no system and is not semantically a governance-records domain, it yields **no routing signal** — do not guess a substrate from it. (A domain that *should* name a system of record but doesn't is itself a governance tension worth surfacing — see Vague Domains below.)

### Step 4 — Resolve to a target (multi-domain precedence)

A role often holds **several** system-of-record domains (e.g., a Product Architecture role holding three Productboard domains plus a Strategyzer domain plus a Smaply domain). Return the **set** of recognized substrates, then:

- **One substrate recognized** → route there. Name it: "This is Product Architecture work; its domain names Productboard as the system of record — I'll prepare this for Productboard."
- **Several substrates, and the artifact's nature clearly fits one** → **prefer the obvious match** and say why. A product feature or roadmap item → the Productboard domains; a value-proposition/business-model canvas → the Strategyzer domain; a service blueprint/journey map → the Smaply domain. Name the chosen substrate *and* the fact that others were held but didn't fit the artifact.
- **Several substrates and two-or-more plausibly fit** → **surface the ambiguity and ask.** Do not silently pick. "Product Architecture holds domains in Productboard and Strategyzer, and this could land in either. Which system of record should this go to?"

This is honest by construction (ADR-0007 §Decision.4): the resolver reasons only from domains actually read this session and, when the signal is ambiguous, surfaces the ambiguity rather than guessing.

### Step 5 — Announce the routing (always)

Whenever routing determines where an artifact lands, name it in the response, tied to the governance evidence:

- "Routing this to **Productboard** — it's Product Architecture's system of record for products and features (domain read live from GlassFrog)."
- "This is a governance record, so it belongs in **GlassFrog** — the Circle's governance-records domain."
- "I couldn't resolve a system of record from live governance for this — where should it land?" (disconnect / miss path)

The announcement lets the operator catch a wrong routing before the artifact is built on it — the same discipline as the role-context announcement.

---

## Freshness: Live-Then-Session-Cache

Per ADR-0007 §Decision.2:

- **Read live at first need**, then **cache the resolved routing for the remainder of the session.** Subsequent artifacts for the same role reuse the cached resolution — no repeated seam calls at every artifact moment.
- **Re-read on a major pivot** — a new circle or role comes into play, or the operator signals a governance change. This is the same Step-5 re-validation as `actor-and-role-resolution.md`.
- Not pure-live-every-call (avoidable API load) and not a persisted cross-session table (drifts). The session cache also closes the no-cross-turn-cache gap ([#36](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/36)) for routing specifically.

---

## Disconnect Fallback: Name the Limit and Ask

Per ADR-0007 §Decision.3, when GlassFrog is unavailable:

- **Do not silently default to the engineering substrate.** Silent-default is exactly the drift this procedure exists to correct.
- **Name the constraint and ask:** "GlassFrog isn't connected, so I can't resolve where this should land from live governance. Which system of record should this go to?"
- This matches the plugin's existing graceful-degradation pattern (`actor-and-role-resolution.md`, "When GlassFrog Data Is Unavailable"): don't refuse to operate, name the limit, let the operator declare the target.

---

## Honest by Construction

- Route only from **domains actually read this session.** Never assert a routing (or the governance reading behind it) that was not performed — the [ADR-0004](../../docs/adr/0004-opt-in-inherited-context-in-context-command.md) scar (narrating grounding that did not happen) applies to routing exactly as it does to context.
- When the domain signal is **ambiguous**, surface the ambiguity — do not manufacture certainty.
- When a domain is **vague** (should name a system of record but doesn't clearly), routing degrades to "ask" — and the vagueness is itself a useful signal: a domain that can't tell you where its work lands is a governance tension worth surfacing (feeds Pattern 3 tension sensing), not a bug in the router.

---

## Worked Verification (against the live org, 2026-07-20)

Probed live via `glassfrog_list_role_domains` / `glassfrog_search` to confirm the resolver routes correctly. These are *illustration from one org's live data*, not baked-in routing rules — the plugin ships the mechanism, the org owns the domains.

| Owning role (live) | Domain read live | Recognizer layer | → System of record |
|---|---|---|---|
| Product Architecture | `[Product Hierarchy (Productboard)](https://integralproductivity.productboard.com)` | L1 URL host → `productboard.com` | **Productboard** |
| Product Architecture | `[Products and Features (Productboard)](https://…productboard.com)` | L1 URL host | **Productboard** |
| Product Architecture | `[Product Insights (Productboard)](https://…productboard.com)` | L1 URL host | **Productboard** |
| Product Architecture | `Value Propositions (Strategyzer)` | L2 named system | **Strategyzer** |
| Product Architecture | `Smaply Configuration and Content` | L2 named system (proper noun) | **Smaply** |
| (finance role) | `QuickBooks Online account — chart of accounts, transaction records, reports` | L2 named system | **QuickBooks** |
| (any circle's governance) | `All governance records of the Circle` (+ "GlassFrog Usage" policy) | L3 semantic governance | **GlassFrog** |

**Multi-domain resolution (Step 4) in action:** Product Architecture holds five domains naming three systems (Productboard ×3, Strategyzer, Smaply). The resolver returns `{Productboard, Strategyzer, Smaply}`; a roadmap/feature artifact prefers Productboard (named, and others don't fit); a value-proposition canvas prefers Strategyzer; if an artifact plausibly fits two, it asks.

---

## Cross-Skill Load Guide

| If you're working in… | When routing applies |
|---|---|
| `holacratic-ai-governance` | Whenever a substantive artifact is about to be produced — the operating frame calibrates response *and* routes output. Pairs with Pattern 4 (Governance-Aware Response Calibration). |
| `holacracy-lead-link` | Routing strategy/priority artifacts to the circle's strategy system of record; role-assignment records stay in GlassFrog. |
| `holacracy-secretary` | Governance records → GlassFrog (L3); meeting outputs route by the owning role's domains. |
| `holacracy-facilitator` | Governance-meeting outputs → GlassFrog; process artifacts route by owning role. |
| `holacracy-rep-link` | Tensions carried across circles route to the owning role's backlog; cross-circle records route by domain. |
| Scheduled routines | A routine's artifact routes by its declared acting role's domains — read live at fire time, or, if disconnected, the routine names the limit in its draft rather than defaulting. |

For most artifacts the SKILL.md body plus this procedure's Steps 1–5 are sufficient. The recognizer layers and multi-domain precedence are the parts to re-read when a role holds several system domains or a domain's signal is thin.
