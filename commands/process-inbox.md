---
description: Walk through unprocessed tensions on the actor's roles and decide how to process each — archive false positives, mark processed catch-up, edit body, or defer. Surfaces supersession candidates inline.
argument-hint: [circle name, optional]
---

# /holacracy:process-inbox

Review and triage the unprocessed tensions currently on the actor's role backlogs in GlassFrog. This command does not *resolve* tensions — resolution happens in tactical and governance meetings. It clears inbox debt: archive what no longer applies, mark items the user already worked but never marked processed, edit unclear bodies, defer what isn't ready.

## What this command does

1. **Resolve actor + role roster.** Follow `skills/shared/actor-and-role-resolution.md` Steps 1–2: `glassfrog_get_me` for the actor, `glassfrog_list_my_roles` for their full role roster.
2. **Filter to a circle if $ARGUMENTS provided.** If the user named a circle, narrow the roster to roles in that circle. Otherwise, work across all the actor's roles.
3. **Fetch unprocessed tensions per role.** For each role in scope, call `glassfrog_list_role_tensions(role_id, status: "unprocessed")`. Aggregate into a single working list, annotated with the sensing role + circle.

   **Caveat:** `list_role_tensions` is unreliable for same-session reads (propagation/scoping — see `skills/holacratic-ai-governance/references/glassfrog-api-constraints.md`). Tensions filed earlier in *this* session may not appear here. Use `/holacracy:supersession-sweep` with `session` scope (which reads the session-tension cache) for end-of-session review of fresh tensions.
4. **Run a quick supersession pre-scan.** Before walking each tension, apply `skills/shared/tension-triage.md` Step 3 across the working list to detect candidate pairs where one tension may be subsumed by another. Note these as supersession candidates to be raised when their primary surfaces.
5. **Walk each tension with the user.** For each tension in the working list, present a triage block:

   ```
   Tension [N of M] on [Role name] of [Circle name]
   Body:    [tension body]
   Filed:   [created_at, if available]

   [If a supersession candidate is flagged: "May overlap with: [other tension excerpt] (ten_yyy). Apply S.5.5.1d test?"]

   Suggested venue (per triage Step 2): [governance | tactical | either]   (annotation only)

   Process as:
     [a] archive false positive  -> update_tension(status: "archived")
     [p] mark processed          -> update_tension(status: "processed")  (only if already resolved in a meeting outside this session)
     [e] edit body               -> update_tension(body: ...)            (front-load topic; prepend [GOVERNANCE] or [TACTICAL] if you want venue encoded in the record)
     [d] defer / leave           -> no action
     [q] quit                    -> stop processing, leave remaining tensions in place
   ```

6. **Call the appropriate `glassfrog_update_tension`** for the user's decision. Surface any error honestly: `update_tension` failures should not be silently swallowed.
7. **At the end, summarize the session.** Number archived, number marked processed, number body-edited, number deferred. Surface any supersession candidates the user did not act on (offer to run `/holacracy:supersession-sweep`).

## Behaviour

- This command operates on **filed** tensions. To capture a *new* tension, use `/holacracy:capture-tension` (cross-role, out-of-meeting) or `/holacracy:tactical` (in-meeting Secretary capture).
- **Per-tension decision — never batched.** The user can quit at any point (`q`) and the remaining tensions stay unprocessed.
- The "mark processed" option (`p`) is for catch-up only: tensions that were resolved in a real governance or tactical meeting but never marked processed in GlassFrog. Do not use it as a way to clear the inbox; that would lie about whether the tension was actually worked.
- The "archive" option (`a`) is the right path for false positives, no-longer-relevant tensions, and superseded ones. Archive is reversible (the tension still exists with `status: "archived"`); deletion is permanent and this command does not offer it.
- **Meeting venue is annotation, not API field.** The `meeting_type` field is not part of the stable tension schema ([glassfrog-mcp-server#58](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/58)) — there is no API call that routes a tension to "the tactical agenda" or "the governance agenda." The suggested-venue annotation tells the user which meeting to bring this to; if they want the venue encoded in the GlassFrog record, they can use the edit-body option to prepend `[GOVERNANCE]` or `[TACTICAL]` to the body.
- If `glassfrog_list_role_tensions` is unavailable (older MCP server), this command names the constraint and exits gracefully: *"Your GlassFrog MCP server doesn't expose tension listing yet — you'll need to triage the inbox in the GlassFrog UI."*

## What this command does NOT do

- It does not resolve tensions on the user's behalf. Resolution is a meeting activity.
- It does not file proposals or make governance changes.
- It does not delete tensions (use the GlassFrog UI if a tension must be permanently removed; archive is the soft-collapse).
- It does not assume meeting venue for the user — it suggests, the user decides.
- It does not write to GlassFrog without a per-tension human keystroke.

## Why this command exists

The GlassFrog tension inbox tends to grow when the practice of processing tensions falls behind the practice of sensing them. The fastest way for a busy role-filler to keep the inbox useful is to *triage* regularly: archive false positives, mark meeting-day catch-up, edit bodies that no longer scan, surface supersession before the inbox bloats with overlapping items.

This command is the operational surface for that practice — the complement to `/holacracy:capture-tension` (which fills the inbox) and `/holacracy:supersession-sweep` (which deduplicates the inbox).
