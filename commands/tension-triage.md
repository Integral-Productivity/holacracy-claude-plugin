---
description: Assess whether each unprocessed tension on the actor's roles is ready to be processed — archive false positives, edit unclear bodies, surface authority the actor already holds, flag supersession, defer the rest. Readiness only; disposition belongs to /holacracy:process-tension.
argument-hint: [circle name, optional]
---

# /holacracy:tension-triage

Walk the unprocessed tensions on the actor's role backlogs in GlassFrog and decide, for each one, **whether it is ready to be processed**. That is the whole job.

Triage answers *"is this tension well-formed, non-duplicate, and still real?"* It does not answer *"what does this tension become?"* — that is `/holacracy:process-tension`'s question, and the two are separated deliberately ([ADR-0011](../docs/adr/0011-separate-tension-readiness-from-tension-disposition.md)). Conflating them is why this command's predecessor, `/holacracy:process-inbox`, shipped with a five-item list of things it refused to do, four of which its users kept needing.

The readiness verdicts are: archive what no longer applies, edit bodies that no longer scan, name authority the actor already holds, flag supersession, defer what isn't ready.

## What this command does

1. **Resolve actor + role roster.** Follow `skills/shared/actor-and-role-resolution.md` Steps 1–2: `glassfrog_get_me` for the actor, `glassfrog_list_my_roles` for their full role roster.

2. **Filter to a circle if $ARGUMENTS provided.** If the user named a circle, narrow to roles in that circle. Otherwise, work across all the actor's roles.

3. **Sweep circle by circle, not role by role.** For each circle in scope (`has_subroles == true`), call `glassfrog_list_subrole_tensions(circle_role_id, status: "unprocessed")` and union the results.

   **`list_subrole_tensions` is not recursive.** It is documented as recursive but returns direct children only, and `has_next_page: false` actively suppresses suspicion — a single call at the org root found 21 of 47 tensions, silently omitting 55%. Sweeping every circle and unioning is the workaround. Against this org that is **18 calls versus 81** for a per-role `list_role_tensions` sweep. See [glassfrog-mcp-server#122](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/122).

   **Recommended pattern:** delegate the sweep to a subagent that returns a compact table (tension id, role, circle, body excerpt, created_at) rather than raw JSON. On a backlog of this size the raw responses will otherwise dominate the main context window before triage has begun.

   **Caveat:** same-session reads are unreliable (propagation/scoping — see `skills/holacratic-ai-governance/references/glassfrog-api-constraints.md`). Tensions written earlier in *this* session may not appear. Use `/holacracy:supersession-sweep` with `session` scope for end-of-session review of fresh tensions.

4. **Run the authority pre-scan.** Before walking the list, apply `skills/shared/triage-gates.md` **Step 1** across it: for each tension, does the authority that would resolve it already exist — as a domain the sensing role holds, or as a role created since the tension was filed?

   Do this first because it changes outcomes more than anything else in the pass. On the 2026-08-01 run it fired five times across 35 tensions and **changed the disposition every time**; roughly a third of the backlog was work waiting on permission the role-filler already held. Note the hits and raise each one when its tension surfaces.

5. **Run a supersession pre-scan.** Apply `skills/shared/triage-gates.md` Step 4 across the working list to detect pairs where one tension may be subsumed by another. Note these as candidates to be raised when their primary surfaces.

6. **Walk each tension with the user.** For each tension, present a readiness block:

   ```
   Tension [N of M] on [Role name] of [Circle name]
   Body:    [tension body]
   Filed:   [created_at, if available]

   [If the authority pre-scan flagged it: "◎[Role] already holds [domain / accountability].
    This may not need a meeting at all — see [c]."]

   [If a supersession candidate is flagged: "May overlap with: [other tension excerpt]
    (ten_yyy). Apply S.5.5.1d test?"]

   Suggested venue (per gates Step 3): [governance | tactical | either]   (annotation only)

   Ready to process, or not:
     [a] archive false positive  -> update_tension(status: "archived")
     [e] edit body               -> update_tension(body: ...)
     [c] authority already held  -> name it; offer conversion; archive on confirmation
     [p] mark processed          -> update_tension(status: "processed")  (catch-up only — see below)
     [d] defer / leave           -> no action
     [q] quit                    -> stop, leave remaining tensions in place
   ```

7. **Call the appropriate `glassfrog_update_tension`** for the user's decision. Surface any error honestly: `update_tension` failures must not be silently swallowed.

8. **Summarize at the end.** Number archived, edited, resolved-by-existing-authority, marked processed, deferred. Surface any supersession candidates the user did not act on (offer `/holacracy:supersession-sweep`). If the pass flagged tensions as ready-to-process, say so plainly and name the next surface.

## Behaviour

- This command operates on **existing** tensions. To capture a *new* one, use `/holacracy:capture-tension` (cross-role, out-of-meeting) or `/holacracy:tactical` (in-meeting Secretary capture).
- **Per-tension decision — never batched.** The user can quit at any point (`q`) and the remaining tensions stay unprocessed.
- **`[c]` is a reading, not an automation.** Recognising that authority already exists is an interpretation; acting on it is a write. Name what the role holds, offer the conversion, and let the user decide. Never convert or archive without an explicit keystroke.
- **Edit-body (`[e]`) is what *makes* a tension ready.** Front-load the topic in the first sentence; partition a blended tension per gates Step 2; prepend `[GOVERNANCE]` or `[TACTICAL]` if the user wants the venue encoded in the record.
- **Archive (`[a]`) is reversible** — the tension still exists with `status: "archived"`. Deletion is permanent and this command does not offer it. When a tension is superseded *structurally*, write the successor first, then archive: archiving alone can drop a live exposure no other record carries.
- **Meeting venue is annotation, not an API field.** `meeting_type` is exposed in the `update_tension` schema and returned in every response, but **the write is rejected with 422** — alone, with `status`, and with `body`; the identical call minus the field succeeds. It is settable in the GlassFrog UI only. See [glassfrog-mcp-server#123 (comment)](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/123#issuecomment-5149496749), which corrects that issue's body. The `[GOVERNANCE]`/`[TACTICAL]` body prefix is not a workaround for a stale constraint — it is the only mechanism the API offers.
- If `glassfrog_list_subrole_tensions` is unavailable (older MCP server), fall back to a per-role `glassfrog_list_role_tensions` sweep and say that the pass will cost more calls. If neither is available, name the constraint and exit gracefully: *"Your GlassFrog MCP server doesn't expose tension listing yet — you'll need to triage the backlog in the GlassFrog UI."*

### On `[p] mark processed`

`processed` is currently reserved for **catch-up only**: tensions resolved in a real governance or tactical meeting but never marked in GlassFrog. Do not use it to clear the backlog; that would lie about whether the tension was actually worked.

This option is on loan. Once `/holacracy:process-tension` ships ([#160](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/160)) it moves there, along with a wider and more honest rule — a tension is `processed` when it has produced a durable output, whether in a prior meeting or in the session at hand. It lives here in the meantime so that meeting-day catch-up does not require the GlassFrog UI.

## Where this command stops

Triage decides readiness. It does not decide disposition — it will not write a proposal, convert a tension to a project or action, or repair the artifact a tension complains about. Those are outputs, and outputs are `/holacracy:process-tension`'s job.

That boundary is the point of the command, not a limitation of it. But it is a boundary with a gap in it right now: **`/holacracy:process-tension` has not shipped yet** ([#160](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/160)). Until it does, a tension this command marks ready has no automated next surface. Say so honestly rather than quietly widening scope to fill the gap — that quiet widening is exactly what produced the conflation this split exists to undo.

For the one case where a disposition surface already exists — a tension that should become a project — hand off to `/holacracy:capture-project`.

## Why this command exists

The GlassFrog tension backlog grows when the practice of processing tensions falls behind the practice of sensing them. The fastest way for a busy role-filler to keep it useful is to *triage* regularly: notice work you can already do, archive false positives, edit bodies that no longer scan, surface supersession before the backlog bloats with overlapping items.

It is the readiness surface in a four-stage architecture — the complement to `/holacracy:capture-tension` (which fills the backlog), `/holacracy:supersession-sweep` (which deduplicates it), and `/holacracy:process-tension` (which drains it).
