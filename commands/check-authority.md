---
description: Authority lookup against the Holacracy Constitution and the plugin's authority-boundaries reference. Answer "can X do Y?" or "who has authority over Z?"
argument-hint: <scenario in plain language>
---

# /holacracy:check-authority

Answer a Holacratic authority question by reasoning from the Constitution and the plugin's `skills/shared/authority-boundaries.md` reference.

## What this command does

1. **Resolve actor context** (if not already done this session) via the procedure in `skills/shared/actor-and-role-resolution.md`. This matters because the user's scenario may name "I" or "my Lead Link" and resolution gives you the right circle/role to bind those to.
2. **Load `skills/shared/authority-boundaries.md`** -- the canonical cross-role authority reference.
3. **Parse the scenario** in $ARGUMENTS (or ask the user if none provided). Identify:
   - Which actor is proposing to act?
   - What action are they proposing?
   - Whose role or domain does the action touch?
   - Is this happening in a meeting context or outside?
4. **Apply the decision tree**:
   - Is this Process authority (Facilitator), Records/Interpretation authority (Secretary), Organizational authority (Lead Link), or Representation authority (Rep Link)?
   - Does it require Governance, or is it Operational? Use the "Requires Governance vs. Operational" tables in `authority-boundaries.md`.
   - Does it touch a Domain? Check the Domain Authority section.
   - Is the role-filler autonomy principle relevant? Apply it strictly.
5. **State a clear ruling**:
   - "Yes -- this is within [Role]'s authority because [reason], per `authority-boundaries.md` section [Section]."
   - "No -- this would violate [principle], because [reason]. The correct path is [governance proposal / role assignment / etc.]."
   - "It depends -- if [condition], then [outcome A]; if [other condition], then [outcome B]."
6. **Always cite** the specific section of `authority-boundaries.md` and (where applicable) the Holacracy Constitution provision (e.g., S.4.1.2 for Domain authority).
7. **Always close with a plain-language summary** in the format from `holacracy-secretary` SKILL.md (Plain Language Summary).
8. **Note appeal paths**: any party who disagrees with this reading can appeal to the Super-Circle Secretary for a formal constitutional ruling.

## Behaviour

- This command produces an **informational reading**, not a binding constitutional ruling. Only the Secretary can issue a binding ruling. Be explicit about this in the response.
- If the scenario is genuinely ambiguous, name the ambiguity and ask the clarifying question rather than guessing.
- If the scenario reveals a *governance gap* (e.g., "no one has authority over this") rather than an authority *boundary issue*, surface that as a tension worth processing.

## When to recommend escalation to a formal Secretary ruling

- The scenario describes a recurring pattern (suggests need for a precedent).
- The scenario involves disagreement between two Circle Members about interpretation.
- The scenario touches Core Role authority interactions (these are the most appeal-prone).

In those cases, suggest the user invoke `holacracy-secretary` to issue a formal ruling.
