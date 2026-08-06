# 14. Eval hermeticity comes from config-dir isolation, not from `--bare`

Date: 2026-08-06

## Status

Accepted. Amends [ADR-0012](0012-test-the-skills-not-just-the-scaffolding.md), which
established the graded behavioural tier but did not specify how a session is
isolated.

## Context

The graded tier compares a `with_skill` session against a `without_skill` one.
The delta is only meaningful if two things hold: the treatment leg genuinely has
the plugin, and the control leg genuinely does not.

`scripts/run-behavioural-eval.py` bought both with `claude --bare`, whose
documented job is to skip hooks, plugin sync, auto-memory and `CLAUDE.md`
discovery. It does that. It also clamps the built-in tool set to
`Bash, Edit, Read` — and **there is no `Skill` tool in that set**. `--tools
default` does not restore it; under `--bare` the set is clamped regardless.

So no skill could be invoked in either leg, whatever `--plugin-dir` loaded.
Graded run 31058151548 recorded zero `Skill` invocations across all three
`with_skill` runs of `/holacracy:capture-tension`. The single run that scored
(3/5) reached the shared spec through `find /` and `cat` — the checkout sits at a
discoverable absolute path on the same disk in both configurations, and `Bash`
was the only instrument the session had. Both legs were the base model, and every
delta the tier had produced compared it against itself
([#226](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/226)).

Two properties of that failure matter more than the flag:

1. **The harness could not represent the state.** "The plugin did not load" and
   "the plugin loaded and changed nothing" produce identical artifacts — a
   well-formed transcript, real tool calls, a scoreable `grading.json`. A null
   result and a broken instrument were indistinguishable, which is why four paid
   runs went by without anyone noticing.
2. **The docstring asserted what it did not check.** It said `--plugin-dir` was
   "the ONLY way the plugin enters the session, so omitting it is a real absence
   rather than a hope", and `CLAUDE.md` repeated it. The claim was checkable at
   session start for free, and was never checked.

## Decision

**Hermeticity comes from the environment, not from a mode flag.** Each eval
session runs with:

- `CLAUDE_CONFIG_DIR` pointed at a fresh empty directory — no installed plugin,
  user setting, hook or memory is visible
- `cwd` in a temp sandbox **outside** this checkout, so `CLAUDE.md`
  auto-discovery has nothing to walk up to
- `--tools Skill,Task,Read` — `Skill` because it is the point, `Task` because
  `/holacracy:capture-tension` dispatches a subagent, and no `Bash`/`Glob`/
  `Grep`/`Write` because a control leg with a shell reaches the checkout
- `--plugin-dir` and `--strict-mcp-config`, unchanged

**The session's shape is verified, not asserted.** Three conditions are read off
the `system/init` event and treated as execution failures: no `Skill` tool, a
`with_skill` leg with no `holacracy:` command registered, a control leg with one.
A fourth fails any control run whose visible tool calls name the checkout.

**The verification also runs at the cheapest possible tier.** The CLI emits
`system/init` *before* it authenticates. `--validate-only` therefore starts a
real session per config, reads the tool list and the registered commands, and
kills the process: no API key, no model turn, no cost, on any laptop.

## Consequences

**The plugin's SessionStart hook is now live in `with_skill`.** `--bare` skipped
it. This is accepted rather than worked around: the eval measures the plugin as a
user installs it. Read a delta as *what installing this plugin does*, not *what a
skill's prose does* — the distinction matters for
[#172](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/172),
which is about description triggering specifically.

**A local graded run still needs `ANTHROPIC_API_KEY`.** Credentials are scoped to
the config directory, so redirecting it hides an interactive login exactly as
`--bare` did. Unchanged, but now the error says so. The free preflight is the
compensation: the questions that actually go stale are answerable without a key.

**Every measurement taken before this change is void.** Not suspect — void. It
compared two runs of the base model. `evals/benchmark.json` remains unmeasured,
and [#183](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/183)
must seed it from a run taken after this. The premise of
[#202](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/202)
— a case scoring 5/5 in both configurations — is most likely an artifact of this
defect and should be re-derived before it is treated as a fact about the case.

**The control is reduced, not proven.** `Task` is offered, and a subagent's own
tool calls do not surface in the parent event stream, so a control run that
delegated a filesystem search would not be caught. Stated in the runner's
docstring rather than papered over: an unverifiable claim in the file that
documents the harness is the mechanism by which #226 survived.
