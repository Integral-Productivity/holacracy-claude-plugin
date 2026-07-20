# 9. The artifact-routing resolver recognizes a domain's system of record by a layered, self-describing recognizer

Date: 2026-07-20

## Status

Accepted

## Context

[ADR-0007](0007-route-artifacts-by-live-glassfrog-domains-not-a-hardcoded-table.md) decided *that* downstream artifacts route by **live GlassFrog domains/policies** rather than a hard-coded `role → system-of-record` table, and it deliberately left two implementation questions open (ADR-0007 §"What this ADR does NOT do"):

1. **The exact domain-string → substrate matching rules** — URL parsing vs. keyword matching, and how much prior knowledge of systems the resolver needs.
2. **Precedence when a role holds multiple system-of-record domains.**

This ADR records how the resolver (built as `skills/shared/artifact-routing.md`, holacracy-claude-plugin#63) resolves both, and is bounded by ADR-0007's non-negotiables: read live through the governance-data seam ([ADR-0005](0005-holacracy-identity-glassfrog-as-first-connector-behind-a-seam.md)); live-then-session-cache freshness; name-the-limit-and-ask on disconnect; honest-by-construction (reason only from governance read this session; surface ambiguity rather than guess — the [ADR-0004](0004-opt-in-inherited-context-in-context-command.md) scar).

The rules were validated against the live org (probed 2026-07-20 via `glassfrog_list_role_domains` / `glassfrog_search`, per ADR-0007's "probe checkable requirements live" discipline). The probe confirmed a decisive property: **domains are self-describing.** They name their own system of record — as an inline URL host (`https://…productboard.com`), a parenthetical (`(Strategyzer)`), or a leading proper noun (`QuickBooks Online account — …`) — and governance-records domains name the governance tool semantically. The Product Architecture role alone holds five domains naming three distinct systems (Productboard ×3, Strategyzer, Smaply), exercising the multi-domain case directly.

## Decision

### 1. Layered, extract-don't-match recognizer

For each domain `description`, recognize the system of record by trying layers in order, stopping at the first that fires. The recognizer **extracts** the system the domain names; it does **not** match against a closed list of pre-known systems — so a system the plugin has never seen (e.g., Smaply) still routes correctly.

- **Layer 1 — inline URL host.** If the string contains a URL, its registrable host names the system (`productboard.com` → Productboard), ignoring the org-specific subdomain. Strongest and self-describing.
- **Layer 2 — named system in text.** Otherwise extract the named system from the text — a parenthetical `(Strategyzer)` or a leading proper-noun product name (`QuickBooks Online account…`, `HubSpot CRM Platform`, `Smaply Configuration…`, `GlassFrog Admin`). The extracted proper noun *is* the target-substrate label.
- **Layer 3 — semantic governance fallback.** If no system is named but the domain is about the org's own **governance records/structure**, the system of record is the connected governance tool (GlassFrog), corroborated by policy text where present.
- **Miss.** A domain naming no system and not semantically governance-records yields **no routing signal**; the resolver does not invent one.

This was chosen over **URL-host-only** (would force "ask" on the many live system-of-record domains that name the system in text without a URL — Strategyzer, QuickBooks, Smaply) and over **keyword-only** (drops the strongest signal, the explicit host). The layered form degrades to "ask" only when *all* layers miss.

The extract-don't-match framing keeps the plugin org-agnostic in a way a system-name lookup table would not: the only thing resembling a registry is a small **host→label / proper-noun→label normalization** for display, never a `role → system` map. The role→system link stays entirely in live governance.

### 2. Multi-domain precedence: return-set, prefer-obvious-else-ask

When a role holds several system-of-record domains, the resolver returns the **set** of recognized substrates and then:

- **one substrate** → route there and name it;
- **several, one clearly fits the artifact's nature** → prefer that one, naming both the choice and that other domains were held but didn't fit;
- **several, ≥2 plausibly fit** → surface the ambiguity and ask; never silently pick.

This was chosen over **always-ask** (noisier — prompts even when the artifact kind disambiguates cleanly) and over **single-best-guess ranking** (violates ADR-0007's honest-by-construction: it would assert a routing the governance signal did not unambiguously support). The artifact-kind preference is a lightweight guideline, not a coded ranking — no over-built scoring machinery in this first slice.

### Scope

This is the **resolver + its verification only**. The PreToolUse enforcement hook that *consumes* the resolver (D3, holacracy-claude-plugin#64) is a separate, blocked-by unit and is **not** built here. Org-specific routing targets stay on the internal track (ip-agent-teams#57); this ADR and the resolver commit only to the generic mechanism.

## Consequences

- The resolver handles every routing signal shape present in live governance (URL, parenthetical, proper-noun, semantic-governance) with a single ordered procedure, and names its uncertainty honestly when none fire.
- Because it extracts rather than matches, adding a new SaaS system to the org requires **no plugin change** — a newly-named domain routes on first read. The plugin stays org-agnostic; the data stays the org's.
- A dependency on **domain-naming quality** is accepted (as ADR-0007 already noted): a vague domain degrades routing to "ask," which is surfaced as a governance tension rather than hidden.
- The first slice ships the resolver as a documented procedure (`skills/shared/artifact-routing.md`) wired into the `holacratic-ai-governance` operating frame. Enforcement (a hook that *blocks* on mis-routing) is deferred to #64 by design — this unit proves the resolution is correct before anything is made to depend on it.

## Alternatives considered

- **URL-host-only matching.** Rejected: forces unnecessary "ask" on live system-of-record domains that name the system in text without a URL.
- **Keyword-only matching (no URL parsing).** Rejected: discards the strongest, self-describing signal (the host) and mishandles domains whose system appears only in the URL.
- **Closed system-name registry.** Rejected: a pre-known-systems lookup is a smaller version of the drift-prone table ADR-0007 rejected; extract-don't-match avoids it entirely.
- **Always-ask on multi-domain / single-best-guess ranking.** Rejected respectively as too noisy and as dishonest (asserting an unsupported routing).

## What this ADR does NOT do

- It does **not** build the PreToolUse routing-enforcement hook (holacracy-claude-plugin#64) — resolver + verification only.
- It does **not** bake in org-specific routing targets; those stay on the internal track (ip-agent-teams#57).
- It does **not** change actor/role resolution ([`actor-and-role-resolution.md`](../../skills/shared/actor-and-role-resolution.md)); it consumes the role that procedure resolves.
- It does **not** revisit ADR-0007's freshness, disconnect, or honesty commitments — it implements them.
