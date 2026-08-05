---
module: agentic-routines
date: 2026-08-05
problem_type: tooling_decision
component: tooling
severity: high
applies_when: "Firing background Claude Code sessions programmatically via the Claude_Code_Remote meta MCP's create_trigger, or relying on any create-style MCP tool whose success response does not describe the object it actually built."
related_components:
  - claude-code-remote-mcp
  - scheduled-tasks-mcp
  - github-mcp
tags:
  - mcp
  - claude-code-remote
  - routines
  - triggers
  - parallel-sessions
  - silent-failure
  - probe-live
  - permissions
---

# `create_trigger` fires on time and still does nothing — it builds a weaker routine than the UI

## Context

Three follow-up issues (#171, #71, #159) had disjoint file territories and could run
in parallel, so the plan was to fire three background sessions with
`mcp__Claude_Code_Remote__create_trigger`, one per issue, each carrying a
self-contained prompt.

**Every observable signal said it worked.** All three calls returned trigger ids.
All three fired within 90 seconds of their scheduled time and recorded
`ended_reason: run_once_fired`. Twenty-five minutes later, **not one of the three
branches existed** and nothing had been pushed.

The tool had done exactly what it said, and the sessions it produced could not do
the work.

## Guidance

**A routine created by `create_trigger` is not the same object as a routine created
in the claude.ai routines UI.** Diffing a failed trigger's `job_config` against a
routine in the same account that has worked for weeks shows two fields present in
the working one and absent from the created one:

```
working routine (created via http_api / UI)      create_trigger routine
---------------------------------------------    ----------------------
session_context.sources: [                        session_context: { allowed_tools: [...] }
  {git_repository: {url: ".../praxis"}},          # no sources key at all
  {git_repository: {url: ".../marketplace"}}      # -> fired session has NO repo clone
]
mcp_connections: [GlassFrog, Slack, Supabase…]    # no mcp_connections key at all
                                                  # -> fired session has NO mcp__* tools
```

- **`sources` has no parameter on `create_trigger`.** There is no way to attach a
  repository. A fired session starts with no clone of the repo the prompt talks
  about.
- **`connectors` *is* a parameter, and is easy to omit.** Omitting it is what
  strips `mcp_connections`. In this environment that plausibly removes the GitHub
  tools too — which is how a session opens a PR.

**Only one of the two gets a warning.** The tool appends a connectors warning to
its success payload ("this trigger stores no MCP connectors…"). It says **nothing**
about `sources`. The louder problem is the silent one.

**So: do not use `create_trigger` to dispatch repo work.** Use it for
notification-shaped routines that need no checkout. To actually run parallel
sessions on a repository, either create the routines in the claude.ai routines UI
(which sets `sources` and connectors), or paste the prompt into a session directly.
Pasting is the cheapest reliable path and needs no routine at all.

### A corollary about verification

`ended_reason: run_once_fired` means *the routine fired*. It does not mean the
session accomplished anything, and there is no field that reports that. **Verify a
fired routine against its intended side effect** — the branch, the PR, the commit —
never against its own status field. Firing and succeeding are different
propositions, and only one of them is instrumented.

### Secondary: `-32003 requires approval` is a permission rule, not a server gate

Before any of the above, `create_trigger` returned `MCP error -32003: MCP tool call
requires approval`, with no prompt surfacing in the session. This reads like a
server-side or auth problem and is not one — it is the local permission layer.
Allowlisting the exact tool names in `.claude/settings.local.json` cleared it
immediately:

```json
{"permissions": {"allow": [
  "mcp__<server-id>__create_trigger",
  "mcp__<server-id>__list_environments"
]}}
```

`.claude/settings.local.json` is per-machine and gitignored (see `.gitignore`);
`.claude/settings.json` is the committed, team-wide file. Put permission grants in
the former.

## Why This Matters

The cost is asymmetric and back-loaded. A tool that fails loudly costs one minute.
This one costs the **full latency of the work you thought you dispatched** — here,
twenty-five minutes of waiting before "no branches" became conclusive, on top of
several rounds spent diagnosing the permission error first. Fire five sessions
before a break and you can lose hours to three green checkmarks.

Worse, the failure is invisible from the creating side. Nothing in the trigger
record says "this session has no repository." The only way to see it is to diff
`job_config` against a routine known to work — which requires already suspecting
the problem.

**This is the third instance of the probe-the-live-surface rule in this repo, and
the nastiest shape yet:**

| Entry | Failure shape |
|---|---|
| [`glassfrog-v5-inherited-context-single-call.md`](glassfrog-v5-inherited-context-single-call.md) | Live surface **richer** than the stale doc claimed |
| [`scheduled-tasks-mcp-fires-but-stores-no-output.md`](scheduled-tasks-mcp-fires-but-stores-no-output.md) | Live surface **lacks a capability** you'd assume it had |
| this entry | Live surface **has the capability and reports success**, while building a strictly weaker object than the equivalent UI path |

The first two are discoverable by reading a schema. This one is not: the schema is
accurate, the call succeeds, and the defect lives in the *shape of the thing
created*. Only comparing against a known-good instance reveals it.

## When to Apply

- Before dispatching any background or parallel session programmatically, on this
  MCP or another. Ask what the equivalent UI path sets that the tool cannot.
- Whenever a create-style MCP tool returns success for an object you will not
  inspect again. Fetch it back and diff it against one you know works.
- When an MCP call fails with `-32003`, check the local permission layer before
  concluding the server is unreachable or unauthenticated.
- Generally: **choose a verification signal the failure mode cannot forge.** A
  status field written by the thing being tested is not evidence. This is the same
  principle as `skills-lint.sh`'s mutation cases (a check that cannot fail is not a
  check) and CLAUDE.md's rule against grepping transcripts for the grounding
  directive (an instrument that cannot distinguish injection from quotation is not
  an instrument).

## Examples

What the failed dispatch looked like end to end — every step green, zero output:

```
create_trigger(#171) -> trig_012zKUky…   ✓ created
create_trigger(#71)  -> trig_01JwKNdL…   ✓ created
create_trigger(#159) -> trig_01Q52iyY…   ✓ created

01:00:47  #171 fired   ended_reason: run_once_fired   ✓
01:01:02  #159 fired   ended_reason: run_once_fired   ✓
01:01:06  #71  fired   ended_reason: run_once_fired   ✓

01:25:00  git ls-remote --heads origin 'refs/heads/claude/*'
          -> claude/focused-wu-b77968      (unrelated, months old)
          MISSING: all three expected branches
```

The check that would have caught it before the twenty-five-minute wait — read the
trigger back and assert the fields that make a session able to work:

```bash
# after create_trigger, before trusting it:
#   .job_config.ccr.session_context.sources   must be non-empty for repo work
#   .mcp_connections                          must contain what the prompt needs
```

**Not verified:** the causal chain (no `sources` -> no clone -> nothing to do) is
strong inference from the `job_config` diff plus zero output. The fired sessions'
own transcripts were never read, so it remains possible they failed for an
additional reason. The operational conclusion — don't dispatch repo work this way —
holds either way.
