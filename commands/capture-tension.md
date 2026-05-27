---
description: Capture a Holacratic tension to a role's GlassFrog backlog via a draft-and-confirm flow. Cross-role, out-of-meeting surface. Resolves sensing role, applies role-vs-person triage, drafts the body (topic-front-loaded), and files with a single per-tension confirmation.
argument-hint: [tension text, optional]
---

# /holacracy:capture-tension

On-demand entry to the canonical tension capture flow. Dispatches the `tension-capture` subagent, which runs the full B-flow specified in `skills/shared/tension-capture-flow.md`.

This is the **cross-role, out-of-meeting** capture surface. For in-tactical-meeting capture as Secretary, use [`/holacracy:tactical`](./tactical.md) instead — that flow has its own role-scoped, meeting-grounded consent contract (the Secretary captures what a Circle Member just named out loud during triage). Both surfaces call the same `glassfrog_create_tension(role_id, body)` primitive, but they belong to different conversational contexts.

## What this command does

1. **Parse $ARGUMENTS.** If the user passed tension text inline, use it as the seed. If not, ask: *"What tension would you like to capture?"* and wait for input.
2. **Dispatch the `tension-capture` subagent** with the tension text and the dispatch source (`explicit command`). Let the subagent handle Steps 2–8 of `skills/shared/tension-capture-flow.md`:
   - Resolve sensing role via `glassfrog_get_me` + `glassfrog_list_my_roles` (with circle narrowing per conversation context). The target is *any role the actor fills* in the relevant circle — not Core Four only.
   - Apply the role-vs-person triage gate from `skills/shared/tension-triage.md` Step 1. Refuse to file person tensions; surface the IDR / direct-conversation route instead.
   - Draft the body, preserving the user's own words and front-loading the topic in the first sentence (no `label` field on the API, so the body is the only scannable surface).
   - Annotate a suggested meeting venue (governance vs. tactical) per `skills/shared/tension-triage.md` Step 2. This is a user-facing annotation only — there is no `meeting_type` field on tensions in the API ([glassfrog-mcp-server#58](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/58)).
   - Present the per-tension confirmation block.
   - On approval, call `glassfrog_create_tension(role_id, body)` (single call, body-only signature).
   - Capture the response ID into the session-tension cache for end-of-session supersession sweep.
3. **Surface the subagent's structured result** (tension ID, role + circle, suggested venue) and return to the original conversation.

## Behaviour

- This command captures **one tension per invocation**. If the user wants to capture multiple, run it multiple times.
- If the role-vs-person triage gate refuses to file (person tension), this command reports the refusal and the suggested IDR route — it does not silently swallow the request.
- If GlassFrog is not connected, the subagent will offer to draft a plain-text version for manual entry. This command honours that fallback.
- The constitutional safeguard from `skills/shared/tension-capture-flow.md` applies: no file without explicit per-tension confirmation.
- The subagent does not attempt to verify via `glassfrog_list_role_tensions` — same-session list-back is unreliable. The `create_tension` response ID is the only reliable confirmation.

## When to use this command vs. other surfaces

- **`/holacracy:capture-tension`** (this command) — explicit, cross-role, out-of-meeting. Use when you've sensed a tension and want to file it now.
- **Ambient capture** (in `holacratic-ai-governance` Pattern 5) — Claude offers to capture when it detects tension language during other work. Same subagent, same flow; no slash command needed.
- **`/holacracy:tactical`** — Secretary in-tactical-meeting flow. Use when running a Tactical Meeting; backlog-first capture during triage is documented in `skills/holacracy-secretary/SKILL.md`.

All three surfaces call the same `glassfrog_create_tension(role_id, body)` primitive. They differ in conversational shape and consent contract, not in what lands in GlassFrog.

## What this command does NOT do

- It does not process tensions. Marking `status: "processed"` is for `/holacracy:process-inbox` (catch-up only, for tensions actually worked in real meetings).
- It does not delete tensions.
- It does not file proposals or make governance changes.
- It does not batch multiple tensions into one confirmation.

For inbox review of already-filed tensions, use `/holacracy:process-inbox`. For end-of-session deduplication, use `/holacracy:supersession-sweep`.
