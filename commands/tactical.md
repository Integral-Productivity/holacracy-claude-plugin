---
description: Prime Secretary scope for an in-meeting Tactical capture session. Resolves actor + Secretary role, optionally loads a pre-tactical-prep packet, and operates MCP-first for durable tension capture.
argument-hint: [circle name to focus on, optional]
---

# /holacracy:tactical

Open this session in **in-meeting Tactical capture** mode as Secretary of a specific circle. The command primes context; the underlying `holacracy-secretary` skill carries the meeting flow.

## What this command does

1. **Resolve actor + Secretary scope** via the procedure in `skills/shared/actor-and-role-resolution.md`. Concretely: call `glassfrog_get_me` and `glassfrog_list_my_roles`, then resolve which circle's Secretary role this session covers.
   - If `$ARGUMENTS` was provided, treat it as a circle-name hint. Validate it against the actor's role roster; if the actor doesn't fill Secretary in that circle, name the mismatch and ask.
   - If the actor fills Secretary in exactly one circle, proceed silently with that one.
   - If the actor fills Secretary in multiple circles and no hint was given, ask which.
   - If the actor fills Secretary in zero circles, offer Observer mode (explain how the role works) or Advisor mode (support someone else's Secretary).
2. **Announce the resolved context** before doing anything else: `Operating as **Secretary of [Circle Name]**`. This is non-negotiable -- a Secretary working in several circles needs to see which one's record this capture lands in.
3. **Surface the pre-tactical-prep packet (ledger-first).** Read the routine ledger (`${HOLACRACY_ROUTINE_LEDGER:-~/.claude/holacracy/routines.jsonl}`) and find the entry titled `holacracy/secretary/pre-tactical-prep/<circle>` for the resolved circle -- the same ledger the session-start hook reads, so both surfacing paths agree (see ADR-0006). If an entry has a recent built packet, surface its `packet_summary` and read the full draft from `packet_path`, noting the `built_at` freshness. If no entry exists, **pull-build the packet now**: run the routine inline (see `skills/holacracy-secretary/references/pre-tactical-prep-routine.md`) so the agenda is still assembled, just without the proactive head start. Only if the build itself can't run (GlassFrog unavailable) say so -- "No pre-tactical-prep packet, and I can't build one without live governance data" -- and continue.
4. **Hand off to `holacracy-secretary`** for the meeting flow itself. The skill already covers the seven-step Holacracy Constitution S.3 process, the Tactical Meeting output template, and the Gap Analysis procedure. Do not duplicate that content here.

## Capture discipline (the one thing this command insists on)

This command operates **MCP-first**, not GlassFrog-UI-first. Tensions sensed during triage are captured to the role backlog at the moment they surface -- via `glassfrog_create_tension(role_id, body)` -- not queued in the GlassFrog meeting triage panel.

Why: meeting-UI tension queues are ephemeral. If the meeting times out, queued items are lost. The role backlog is durable. See the **Backlog-first tension capture** subsection in `skills/holacracy-secretary/SKILL.md` for the full pattern. The current `glassfrog_create_tension(role_id, body)` signature is the stable shape -- `label` and `meeting_type` were dropped from the schema ([glassfrog-mcp-server#58](https://github.com/Integral-Productivity/glassfrog-mcp-server/issues/58), resolved).

## Behaviour

- If GlassFrog is not connected, the Secretary skill's existing "I don't have live governance data" path handles it. This command does not re-handle disconnect.
- If the user starts narrating a tactical meeting before the resolution has been announced, complete the announcement first, then resume.
- This command primes context. It does not advance into capture on its own -- it waits for the user's first capture input (a check-in, an agenda item, a tension) before producing meeting output.
