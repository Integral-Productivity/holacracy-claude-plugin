#!/usr/bin/env python3
"""Run a behavioural eval case against the plugin and emit skill-creator gradings.

    scripts/run-behavioural-eval.py --case evals/cases/tension-triage/evals.json \
                                    --out benchmarks/2026-08-05T00-00-00

Produces the directory tree `scripts/aggregate_benchmark.py` (from the
skill-creator plugin) consumes:

    <out>/eval-<suite>-<id>/eval_metadata.json
    <out>/eval-<suite>-<id>/<config>/run-<k>/grading.json
    <out>/eval-<suite>-<id>/<config>/run-<k>/timing.json
    <out>/eval-<suite>-<id>/<config>/run-<k>/cost.json
    <out>/eval-<suite>-<id>/<config>/run-<k>/outputs/{transcript.md,writes.jsonl,metrics.json,events.jsonl}

`<suite>` is the case file's directory name. It is part of the key because
`eval_id` is unique only within one case file, and without it two suites'
eval 0 land in the same directory (#201). The tree stays FLAT — the
aggregator globs `eval-*` directly under `<out>`.

WHY THIS EXISTS RATHER THAN `run_eval.py`
-----------------------------------------
skill-creator's `run_eval.py` is the *triggering* detector: it returns a boolean
for whether a skill fired, which is Tier 3's question (#172). `aggregate_benchmark.py`,
`agents/grader.md` and the eval viewer are reusable as-is; the runner that
produces `grading.json` had to be built. See ADR-0012's 2026-08-04 amendment.

What is borrowed from `run_eval.py` is its subprocess shape: real `claude -p`
with `CLAUDECODE` stripped from the environment, so the eval exercises the actual
command path -- skill load, tool selection, argument construction -- rather than a
simulation of it.

HERMETIC BY CONSTRUCTION
------------------------
The `with_skill` / `without_skill` delta is worthless if the operator's own
globally-installed copy of this plugin leaks into the `without_skill` leg. Four
things close that off, and all four are load-bearing:

    CLAUDE_CONFIG_DIR=<empty>  a fresh empty directory per run, so no installed
                               plugin, user setting, hook or memory is visible
    cwd=<sandbox>              a temp directory OUTSIDE this checkout, so
                               CLAUDE.md auto-discovery finds nothing to walk up to
    --plugin-dir <repo>        the only route by which the plugin enters the
                               session, given the three neighbours above
    --strict-mcp-config        the stub is the only MCP server; the plugin's own
                               .mcp.json (which points at the live production
                               connector) is ignored

Without `--strict-mcp-config` an eval could reach the real GlassFrog. That is not
a performance concern; it is the reason evals do not run against the live org at
all (see evals/README.md).

WHY NOT `--bare`, WHICH THIS USED TO PASS
-----------------------------------------
`--bare` bought the hermeticity above in one flag, and it also collapsed the
built-in tool set to `Bash, Edit, Read`. **There is no `Skill` tool in that set**,
so no skill could ever be invoked, in either configuration, whatever
`--plugin-dir` loaded. Graded run 31058151548 recorded zero `Skill` invocations
across all three `with_skill` runs; the one run that scored reached the shared
spec by `find /` and `cat` instead, because `Bash` was the only instrument it had
(#226). `--tools default` does not undo it — under `--bare` the set is clamped
regardless. Every with/without delta produced before this change was two runs of
the base model.

`--bare` also skipped the plugin's own SessionStart hook. It is now live in
`with_skill`, and that is deliberate: the eval measures the plugin as a user
installs it, hook included. Read a with/without delta as "what installing this
plugin does", not "what a skill's prose does".

WHAT THE CONTROL CAN AND CANNOT REACH
-------------------------------------
`without_skill` used to be reachable anyway: the checkout sits at a discoverable
absolute path on the same disk in both configurations, and a `find /` gets to it.
`EVAL_TOOLS` therefore withholds `Bash`, `Glob`, `Grep` and `Write`, and
`contamination_error` fails any control run whose visible tool calls name the
checkout.

That is a reduction, not a proof. `Task` is offered — `/holacracy:capture-tension`
dispatches a subagent and withholding it would measure a crippled plugin — and a
subagent's own tool calls do not surface in the parent event stream, so a control
run that delegated a filesystem search would not be caught. Stated rather than
papered over: an unverifiable claim in this docstring is what let #226 sit.

MECHANICAL VERSUS JUDGED ASSERTIONS
-----------------------------------
An assertion carrying a `check` object is evaluated in Python against the stub's
write log. Ordering claims -- "write the successor before archiving the original",
"no write without an explicit confirmation" -- are only checkable against a log,
and checking them deterministically means they cost no tokens and cannot drift
between nightly runs. Everything else is graded by a model pass over the
transcript.

That split matters for the flakiness rule in evals/README.md: a case whose
stddev is wide is a defect in the case. Moving every deterministic claim out of
the judged set is the cheapest available reduction in variance.
"""

# `X | None` annotations are 3.10+, and `python3` on a stock macOS box is the
# 3.9 that ships with the Xcode command line tools. Deferring annotations keeps
# this runnable there — a contributor whose local run dies on a syntax error
# learns nothing about the eval.
from __future__ import annotations

import argparse
import functools
import hashlib
import json
import os
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
STUB = REPO / "evals" / "stub" / "glassfrog_stub.py"

# The namespace every command and skill this plugin ships is registered under.
# Read from the manifest rather than hard-coded, so a rename cannot leave the
# plugin-loaded check silently asserting a namespace nobody publishes.
PLUGIN_NAME = json.loads(
    (REPO / ".claude-plugin" / "plugin.json").read_text())["name"]

# The built-in tools an eval session may use. `Skill` is the point of the list:
# without it the plugin's skills are unreachable however they are loaded (#226).
# `Task` is here because /holacracy:capture-tension dispatches a subagent.
# `Bash`, `Glob`, `Grep` and `Write` are deliberately absent — see the module
# docstring's note on what the control can reach.
EVAL_TOOLS = "Skill,Task,Read"

# The stub must register under the same server name as the real connector in
# .mcp.json, or every `mcp__glassfrog__*` tool name the skills were written
# against fails to resolve and the eval measures a plumbing error.
MCP_SERVER_NAME = "glassfrog"

# Overridable so the regression suite can drive every path in this file with a
# fake executor and no API key. Nothing else in here knows the difference.
CLAUDE_BIN = os.environ.get("BEHAVIOURAL_EVAL_CLAUDE_BIN", "claude")

DEFAULT_CONFIGS = ("with_skill", "without_skill")


# ---------------------------------------------------------------------------
# Cache key computation
#
# WHY THIS EXISTS
# ----------------
# The nightly graded tier re-executes and re-grades every (case, config) leg
# every night, whether or not anything that could move its result has
# changed. A stable, content-addressed key per leg is the precondition for a
# change-aware skip: two runs with the same key are runs of the identical
# leg, and a skip decision (a later unit) can trust that equality without
# re-deriving it from a git diff each time.
#
# WHAT GOES INTO THE KEY, AND WHY EACH PIECE
# -------------------------------------------
# Eleven inputs, each independently capable of moving a leg's result:
#
#   case content       the eval's own prompt, assertions, ground truth and
#                       fixture path -- editing any of them is editing the
#                       question being asked
#   skill version       skills-lint.sh check 4 (scripts/skills-lint.sh:286)
#                       already enforces that a skill's `version:` field moves
#                       when its content does. Reusing that field as a cache
#                       input (rather than hashing the skill's own directory
#                       tree directly) is a session-settled decision: it
#                       piggybacks on an existing enforcement mechanism
#                       instead of adding a second, independent one that could
#                       drift out of sync with the first.
#   shared references   check 4 explicitly EXCLUDES skills/shared/ from its
#                       diff (`grep -v '^skills/shared/'`), so a shared file
#                       can change with no skill's version field moving. This
#                       hashes the shared files a skill actually loads,
#                       discovered the same way skills-lint.sh check 1 proves
#                       a load path resolves (see discover_shared_references).
#   commands/*.md       every eval's `surface` field names a slash command
#                       (e.g. `/holacracy:capture-tension`), implemented here
#                       -- not under skills/<dir>, so nothing above hashes it.
#                       Hashed as one whole-directory digest rather than a
#                       per-surface mapping, matching the with_skill
#                       skill_versions precedent of over- rather than
#                       under-invalidating (R4).
#   agents/*.md          a command can dispatch a subagent (e.g.
#                       capture-tension.md -> the tension-capture subagent),
#                       which can itself load skills/shared/*.md content no
#                       skills/<dir>/{SKILL.md,references/*.md} ever cites --
#                       content discover_shared_references cannot see because
#                       it only treats those two locations as citing files.
#                       Same whole-directory-digest treatment as commands/.
#   fixture             the synthetic org state the case exercises
#   harness script       run-behavioural-eval.py itself participates in
#                       producing a leg's result -- it drives execution,
#                       decides what counts as an error, and grades. Deliberately
#                       NOT eval-report.py, a post-hoc renderer that never runs
#                       during execution or grading and so cannot move a
#                       leg's result.
#   runs                 the requested repeat count
#   model                the requested model id
#   stub                 evals/stub/glassfrog_stub.py, which the MCP server
#                       in every leg actually is
#   cli version           the invoked Claude Code CLI binary's own version
#                       (`claude --version`), independent of anything in this
#                       repo -- a CLI behaviour change can move a result with
#                       nothing here having changed at all
#
# CACHE_KEY_INPUT_CLASSES below is a narrower, DELIBERATELY SHORTER list: the
# file-tree globs among the eleven, not the runtime values (runs/model/cli
# version) or the fixture. Planning Contract KTD2 originally fixed five
# entries (skills/**, skills/shared/**, evals/cases/**, evals/stub/**,
# scripts/run-behavioural-eval.py); commands/** and agents/** were added after
# code review found the with_skill/without_skill eval surfaces are actually
# implemented in commands/*.md (+ dispatched agents/*.md), which nothing
# above ever hashed -- a real evaled-behaviour change there left every cache
# key untouched. This is the ONE canonical enumeration a completeness check
# (scripts/cache-key-completeness-check.sh, R7) asserts against -- a static
# assertion design, not a git-diff scan. Extending compute_cache_key to a new
# sensitive input class must extend this constant in the same change, or the
# later check has nothing to catch the drift with (R4). NOTE: hooks/ and
# hooks-handlers/ can also run during a with_skill session (the plugin's own
# SessionStart hook is live there per #227) and are NOT yet in this list --
# a deliberately scoped, disclosed gap (see evals/README.md), not an
# oversight; KTD2 already settled that a general "which files can move this
# leg's result" detector is unimplementable, so a wholly new sensitive class
# still depends on a human noticing it during review, same as before this
# fix.
# ---------------------------------------------------------------------------

CACHE_KEY_INPUT_CLASSES = (
    "skills/**",
    "skills/shared/**",
    "commands/**",
    "agents/**",
    "evals/cases/**",
    "evals/stub/**",
    "scripts/run-behavioural-eval.py",
)

_BACKTICK_MD_RE = re.compile(r"`([A-Za-z0-9_./-]+\.md)`")
_SKILL_VERSION_RE = re.compile(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$", re.MULTILINE)


def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    return _sha256_hex(path.read_bytes())


def skill_declared_version(skill_dir: Path) -> str:
    """The skill's declared `version:` frontmatter field.

    Raises rather than substituting a default: a skill directory whose
    SKILL.md carries no semver version is a data problem skills-lint.sh check
    3 already flags, and silently treating it as "unversioned" would let a
    cache key mask exactly the drift this whole mechanism exists to catch.
    """
    skill_md = skill_dir / "SKILL.md"
    text = skill_md.read_text()
    match = _SKILL_VERSION_RE.search(text)
    if not match:
        raise ValueError(f"{skill_md}: no semver 'version:' field in frontmatter")
    return match.group(1)


def discover_shared_references(skill_dir: Path, repo: Path) -> list[Path]:
    """Which skills/shared/*.md files does this skill actually load?

    Replicates skills-lint.sh check 1's (`check_links`) resolution rule
    EXACTLY, rather than reimplementing a looser one: a backticked path is
    resolved relative to (a) the citing file's own directory, or (b) the repo
    root -- nothing more permissive. This repo shipped nine broken shared-file
    load paths under a looser reading once already (see this repo's
    CLAUDE.md); a shallower resolver here would under-hash a skill whose
    references/ file cites shared/ content one level deeper than SKILL.md
    does, which is exactly that failure mode reproduced inside the cache key.

    Citing files searched: the skill's own SKILL.md, and every `*.md` file
    directly under its `references/` directory (mirroring check 1's `_live_md`
    population, scoped to one skill). Bare filenames with no slash are
    skipped, matching check 1: `SKILL.md` in prose names a concept, not a
    path.
    """
    citing_files = []
    skill_md = skill_dir / "SKILL.md"
    if skill_md.exists():
        citing_files.append(skill_md)
    refs_dir = skill_dir / "references"
    if refs_dir.is_dir():
        citing_files.extend(sorted(refs_dir.glob("*.md")))

    shared_root = (repo / "skills" / "shared").resolve()
    found: set[Path] = set()
    for citing in citing_files:
        text = citing.read_text()
        for target in _BACKTICK_MD_RE.findall(text):
            if "/" not in target:
                continue  # bare filename: a concept, not a path (check 1 parity)
            candidate = citing.parent / target
            if not candidate.exists():
                candidate = repo / target
                if not candidate.exists():
                    continue  # unresolvable: check 1's finding, not this function's
            resolved = candidate.resolve()
            try:
                resolved.relative_to(shared_root)
            except ValueError:
                continue  # resolves, but not under skills/shared/
            found.add(resolved)
    return sorted(found)


def claude_cli_version(claude_bin: str | None = None) -> str:
    """The invoked Claude Code CLI binary's version -- `claude --version`, NOT
    this harness script's own version.

    A leg's result can move when the CLI itself changes (a new default tool
    behaviour, a flag's semantics shifting) independently of anything in this
    repo, so the cache key must be sensitive to it. Read once per invocation
    of this runner rather than once per leg: the binary does not change
    mid-run, and shelling out per leg would be a wasted process spawn
    repeated across the whole matrix.
    """
    claude_bin = claude_bin or CLAUDE_BIN
    try:
        proc = subprocess.run([claude_bin, "--version"], capture_output=True,
                              text=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError) as exc:
        raise RuntimeError(f"could not determine the {claude_bin} CLI version: {exc}") from exc
    version = (proc.stdout or proc.stderr or "").strip()
    if not version:
        raise RuntimeError(f"{claude_bin} --version produced no output")
    return version


def compute_cache_key(case: dict, *, skill_dirs: list[Path] = (), fixture_path: Path,
                       runs: int, model: str | None, cli_version: str,
                       stub_path: Path | None = None, runner_path: Path | None = None,
                       repo: Path = REPO) -> str:
    """A stable, content-addressed cache key for one (case, config) leg.

    Hashes exactly the eleven inputs documented in the section header above
    -- the list is treated as exhaustive by design (R4): adding a new input
    that could move a result is a required edit here, not an optional
    enhancement, so a cache hit never masks an actual change.

    `skill_dirs` is the set of skill directories this specific leg exercises
    -- resolving WHICH skill(s) a given case's surface engages is a decision
    for the caller (a case-to-skill mapping is not part of what this function
    computes), so an empty tuple is valid for a leg that engages none (e.g. a
    without_skill control leg, or a case whose fixture-only assertions never
    reach skill content).

    commands/*.md and agents/*.md are hashed under the SAME condition as
    skill_dirs being non-empty, rather than via a separate parameter: a
    without_skill leg never passes --plugin-dir (execute()'s config ==
    "with_skill" branch), so it can never load a command or dispatch a
    subagent, exactly the same reason resolve_skill_dirs_for_leg returns []
    for that config. Piggybacking on skill_dirs' presence avoids adding a
    second, independent with_skill signal that could drift from the first.

    Deliberately does not fold `config` (with_skill / without_skill) into the
    hash: the caller already keys the on-disk cache by config as a directory
    component, and the natural way a config leg differs -- which skill_dirs
    it passes, and by extension whether commands/agents apply -- already
    flows through the hash via that parameter.
    """
    stub_path = stub_path or STUB
    runner_path = runner_path or Path(__file__).resolve()

    skill_versions = sorted(
        f"{d.name}={skill_declared_version(d)}" for d in skill_dirs)
    shared_paths = sorted({
        p for d in skill_dirs for p in discover_shared_references(d, repo)
    })
    shared_digest = _sha256_hex(
        "".join(_sha256_file(p) for p in shared_paths).encode())

    commands_paths = sorted((repo / "commands").glob("*.md")) if skill_dirs else []
    commands_digest = _sha256_hex(
        "".join(_sha256_file(p) for p in commands_paths).encode())
    agents_paths = sorted((repo / "agents").glob("*.md")) if skill_dirs else []
    agents_digest = _sha256_hex(
        "".join(_sha256_file(p) for p in agents_paths).encode())

    components = {
        "case": _sha256_hex(json.dumps(case, sort_keys=True).encode()),
        "skill_versions": skill_versions,
        "shared_refs": shared_digest,
        "commands": commands_digest,
        "agents": agents_digest,
        "fixture": _sha256_file(fixture_path),
        "runner": _sha256_file(runner_path),
        "runs": runs,
        "model": model,
        "stub": _sha256_file(stub_path),
        "cli_version": cli_version,
    }
    canonical = json.dumps(components, sort_keys=True, default=str)
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:32]
    return f"leg_{digest}"


# ---------------------------------------------------------------------------
# Cache index: storage, lookup, and the skip/execute decision (U2 + U3)
#
# WHAT THIS ADDS ON TOP OF compute_cache_key
# -------------------------------------------
# compute_cache_key (above) answers "what is this leg's key" -- a pure
# function of its inputs. This section answers "given that key, do we need to
# run the leg again tonight", by consulting a small JSON index that persists
# ACROSS nightly runs. The index lives outside this checkout, on a dedicated
# `eval-cache-index` branch this script never has to know about -- the
# workflow checks it out to a path and hands that path in via --cache-index
# (see .github/workflows/skills-eval.yml). This script only ever sees a path
# on disk; it has no git awareness of its own.
#
# CACHING IS OPT-IN, NOT A DEFAULT
# ---------------------------------
# --cache-index is None unless a caller passes it. Every EXISTING caller of
# this script -- the regression suite chief among them, which invokes the
# same case/config repeatedly across different plans and expects fresh
# execution every time -- must see IDENTICAL behaviour to before this file
# existed. Defaulting caching on would silently break that: a second
# invocation with the same case would read the first invocation's stored
# result instead of running the plan it was just given. So every function
# below is inert unless the caller opts in by passing --cache-index.
#
# BOUNDED LIFETIME (U3, R8)
# --------------------------
# A cache entry's freshness is judged against `now` (real time by default, or
# --now for a synthetic clock in tests -- the same affordance this repo's
# other alarm scripts use, e.g. release-latency-alarm.py). An entry is usable
# only if it is BOTH successful and younger than --cache-max-age-days
# (default 7): a leg whose key never changes is still forced back through a
# real execution at least once a week, so "nothing on disk changed" cannot
# turn into "never re-verified against live model behaviour" (R8).
#
# THE `_run_summary` KEY (U5, R6)
# ---------------------------------
# Every entry keyed `leg_<32hex>` is a per-leg cache record (see
# compute_cache_key). A skip never rewrites the entry it reuses, so by the
# time a run finishes, the stored entries alone cannot say which legs THIS
# run actually skipped versus executed -- only what the entry's last WRITE
# looked like, possibly nights ago. main() tracks that distinction itself as
# it goes (`cache_run_legs`) and stamps it into the index under the single
# reserved key `_run_summary` right before the index is saved. The leading
# underscore keeps it unambiguous against the `leg_` prefix: any reader that
# only knows to look for `leg_*` entries skips it for free, and a reader
# built before this key existed simply never looks for it. It is overwritten
# whole every run -- it describes the run that just finished, not a running
# total -- and scripts/eval-report.py's cache-summary section is its only
# consumer.
# ---------------------------------------------------------------------------

DEFAULT_CACHE_MAX_AGE_DAYS = 7


def load_cache_index(path: Path) -> dict:
    """Read the leg cache index, tolerating absence or corruption.

    A missing file is the ordinary case on the very first nightly run, or the
    first run after the eval-cache-index branch is created (R3): every leg
    simply has no entry and executes. A corrupt file -- a bad manual edit, a
    partial write from an interrupted job -- is treated the same way rather
    than raising: a broken index must degrade to "cache nothing tonight",
    never to a crashed nightly run.
    """
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return {}
    return data if isinstance(data, dict) else {}


def save_cache_index(path: Path, index: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")


def resolve_skill_dirs_for_leg(config: str, repo: Path = REPO) -> list[Path]:
    """Which skills/<dir> a leg's cache key should be sensitive to.

    without_skill legs exercise no skill content -- an empty list is the
    documented-valid input for exactly that case (see compute_cache_key's
    docstring: "an empty tuple is valid for a leg that engages none"). A
    with_skill leg can reach any skill this plugin ships: the case files'
    `skill` field names the PLUGIN ("holacracy"), not a skills/<dir>, and
    there is no per-case mapping onto a narrower set. Rather than guess one,
    this hashes every shipped skill directory, which is coarser than a
    precise per-case mapping would be but never UNDER-hashes -- a change to
    any skill invalidates every with_skill cache entry, and over-invalidating
    is the safe direction to be wrong in.
    """
    if config != "with_skill":
        return []
    skills_root = repo / "skills"
    if not skills_root.is_dir():
        return []
    return sorted(
        p for p in skills_root.iterdir()
        if p.is_dir() and p.name != "shared" and (p / "SKILL.md").exists())


def _parse_iso_as_utc(value: str) -> datetime:
    """Parse an ISO8601 timestamp, treating a tz-naive one as UTC.

    Shared by cache_entry_is_usable (a stored entry's last_executed) and
    main()'s --now handling (the synthetic clock tests use) -- both need the
    identical "naive means UTC" rule, and having it in one place means a
    later change to that rule cannot apply to only one call site by mistake.
    Raises ValueError/TypeError on an unparseable value, same as
    datetime.fromisoformat -- each caller decides for itself whether that
    should crash (main()'s --now, a test-only input worth failing loudly on)
    or degrade gracefully (cache_entry_is_usable, a stored value that must
    never turn a malformed entry into a crashed nightly run).
    """
    parsed = datetime.fromisoformat(value)
    return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed


def cache_entry_is_usable(entry: dict | None, *, now: datetime, max_age_days: int) -> bool:
    """R3-R6 plus R8: is a stored entry fresh enough to skip re-execution?

    False whenever any of the following holds, each corresponding to one of
    the plan's skip/execute decision-tree cases:

      entry not a dict                 malformed index entry, treated as absent
      not entry["successful"]          the prior attempt errored (R4/R6)
      no/unparseable last_executed     a malformed entry, treated as absent
      last_executed is in the future   clock skew/bad edit; never "permanently fresh"
      now - last_executed >= max_age   the entry is stale (R5, U3's R8)
      entry["grading"] missing summary/models   the shape the skip branch and
                                        record_leg_bookkeeping() require to
                                        reuse this entry without crashing

    Only a successful, well-shaped entry executed within the window returns
    True (case 6 in the plan's decision tree). This is the ONLY place that
    combines these checks, so a later change to the freshness rule -- or to
    what shape a reused entry must have -- has one function to edit rather
    than every call site. The index lives on an unprotected branch (KTD1),
    so a hand-edited or older/newer-script-written entry can have any shape;
    every check here exists to keep a malformed entry a cache miss rather
    than an unhandled exception that aborts the rest of the nightly run.
    """
    if not isinstance(entry, dict) or not entry.get("successful"):
        return False
    last_executed = entry.get("last_executed")
    if not last_executed:
        return False
    try:
        executed_at = _parse_iso_as_utc(last_executed)
    except (ValueError, TypeError):
        return False
    age = now - executed_at
    if age < timedelta(0) or age >= timedelta(days=max_age_days):
        return False
    grading = entry.get("grading")
    return (isinstance(grading, dict)
            and isinstance(grading.get("summary"), dict)
            and isinstance(grading.get("models"), dict))


def record_leg_bookkeeping(grading: dict, config: str, executors: set, analyzers: set,
                           executors_by_config: dict) -> None:
    """Update the run-wide bookkeeping sets from one leg's grading dict.

    Shared between the skip and execute branches of main()'s per-config loop
    -- a skipped leg's stored result must feed executors/analyzers/
    executors_by_config exactly as a freshly executed one would, or a cached
    leg silently vanishes from run_metadata.json and from the
    same-executor-model check that reads executors_by_config afterwards.
    """
    for which, seen in (("executor", executors), ("analyzer", analyzers)):
        name = grading["models"].get(which)
        if name:
            seen.add(name)
    executor = grading["models"].get("executor")
    if executor:
        executors_by_config.setdefault(config, set()).add(executor)


# ---------------------------------------------------------------------------
# Workspace
# ---------------------------------------------------------------------------

def mcp_config(fixture: Path, write_log: Path) -> dict:
    """The single MCP server a run is permitted to see."""
    return {
        "mcpServers": {
            MCP_SERVER_NAME: {
                "command": sys.executable,
                "args": [str(STUB)],
                "env": {
                    "GLASSFROG_STUB_FIXTURE": str(fixture),
                    "GLASSFROG_STUB_WRITE_LOG": str(write_log),
                },
            }
        }
    }


def probe_stub(fixture: Path, write_log: Path) -> tuple[bool, str]:
    """Start the stub exactly as a run would and complete the MCP handshake.

    The generated config is the most likely thing to break silently: a bad
    interpreter path, a fixture that moved, an env key the stub does not read.
    A run that fails this way still produces a transcript, and the transcript
    reads like the skill declining to call any tools. Probing first turns that
    into an explicit error.
    """
    cfg = mcp_config(fixture, write_log)["mcpServers"][MCP_SERVER_NAME]
    handshake = (
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n'
        '{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n'
    )
    try:
        proc = subprocess.run(
            [cfg["command"], *cfg["args"]],
            input=handshake,
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, **cfg["env"]},
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, f"stub failed to start: {exc}"

    lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
    if len(lines) < 2:
        return False, f"stub did not answer the handshake (stderr: {proc.stderr.strip()[:400]})"
    try:
        init, listing = json.loads(lines[0]), json.loads(lines[1])
        name = init["result"]["serverInfo"]["name"]
        tools = {t["name"] for t in listing["result"]["tools"]}
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        return False, f"stub handshake was not parseable: {exc}"
    if not tools:
        return False, "stub advertised no tools"
    return True, f"{name}: {len(tools)} tools"


# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

def build_command(prompt: str, config: str, cfg_path: Path, model: str | None) -> list[str]:
    cmd = [
        CLAUDE_BIN,
        "-p", prompt,
        "--tools", EVAL_TOOLS,
        "--output-format", "stream-json",
        "--verbose",
        "--strict-mcp-config",
        "--mcp-config", str(cfg_path),
        "--permission-mode", "bypassPermissions",
    ]
    if config == "with_skill":
        cmd += ["--plugin-dir", str(REPO)]
    if model:
        cmd += ["--model", model]
    return cmd


def session_env(config_dir: Path) -> dict:
    """The environment one eval session runs under.

    CLAUDECODE is stripped for the same reason run_eval.py strips it: the guard
    exists to stop two interactive terminals fighting, and a subprocess is not
    that. CLAUDE_CODE_SIMPLE was what `--bare` set; it is stripped so an
    inherited value cannot reimpose the mode this runner just stopped using.

    CLAUDE_CONFIG_DIR is the hermeticity lever. Pointed at an empty directory it
    hides every installed plugin, user setting, hook and memory file — the job
    `--bare` used to do, without also taking the `Skill` tool away with it.
    """
    env = {k: v for k, v in os.environ.items()
           if k not in ("CLAUDECODE", "CLAUDE_CODE_SIMPLE")}
    env["CLAUDE_CONFIG_DIR"] = str(config_dir)
    return env


def init_event(events: list) -> dict | None:
    for event in events:
        if event.get("type") == "system" and event.get("subtype") == "init":
            return event
    return None


def session_shape_error(events: list, config: str) -> str | None:
    """Did this session have the shape its configuration claims?

    The harness could not previously tell "the plugin did not load" from "the
    plugin loaded and changed nothing" — both produce a plausible transcript and
    a scoreable grading. That is how #226 survived four graded runs. These three
    conditions are read off the `system/init` event, cost nothing, and fail the
    run rather than scoring it.
    """
    init = init_event(events)
    if init is None:
        return ("the session emitted no init event, so neither its tool set nor "
                "its plugin state could be verified")

    if "Skill" not in set(init.get("tools") or []):
        return ("the session had no Skill tool, so no skill could be invoked no "
                "matter what --plugin-dir loaded (#226). Tools offered: "
                + ", ".join(sorted(t for t in (init.get("tools") or [])
                                   if not t.startswith("mcp__"))))

    registered = [c for c in (init.get("slash_commands") or [])
                  if c.startswith(PLUGIN_NAME + ":")]
    if config == "with_skill":
        if not registered:
            return (f"--plugin-dir registered no {PLUGIN_NAME}: command, so "
                    f"with_skill is behaviourally the base model and its delta "
                    f"against the control measures nothing (#226)")
    elif registered:
        return (f"the {PLUGIN_NAME} plugin leaked into {config}: "
                f"{', '.join(registered[:3])} … — the control is not a real absence")
    return None


def probe_session(config: str, timeout: int = 120) -> tuple[bool, str]:
    """Start a real session and read its init event, then stop it.

    The CLI emits `system/init` BEFORE it authenticates — the session that
    exposed #226 reported its full tool set and command list and only then said
    "Not logged in". So the two conditions that made the graded tier meaningless
    are observable for free, on any laptop, with no API key and no model turn:
    whether a `Skill` tool exists at all, and whether `--plugin-dir` registers
    anything. That is the whole reason this is wired into `--validate-only`
    rather than left to the nightly job — #226 needed four paid runs and an
    artifact download to notice, and it did not have to.

    The process is killed the moment init arrives, so a machine that DOES hold
    ANTHROPIC_API_KEY is not billed for a turn either.
    """
    sandbox = Path(tempfile.mkdtemp(prefix="holacracy-probe-"))
    config_dir = sandbox / "claude-config"
    workdir = sandbox / "work"
    config_dir.mkdir()
    workdir.mkdir()
    cfg_path = sandbox / "mcp-config.json"
    cfg_path.write_text(json.dumps({"mcpServers": {}}))

    try:
        proc = subprocess.Popen(
            build_command("probe", config, cfg_path, None),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            cwd=str(workdir), env=session_env(config_dir))
    except OSError as exc:
        shutil.rmtree(sandbox, ignore_errors=True)
        return False, f"could not run {CLAUDE_BIN}: {exc}"

    init = None
    deadline = time.time() + timeout
    try:
        while init is None:
            remaining = deadline - time.time()
            if remaining <= 0:
                break
            # select rather than a plain read loop: a CLI that emitted nothing
            # would otherwise hang the probe, and a hung preflight in CI is
            # worse than the defect it looks for.
            if not select.select([proc.stdout], [], [], remaining)[0]:
                break
            line = proc.stdout.readline()
            if not line:
                break
            try:
                event = json.loads(line.strip())
            except json.JSONDecodeError:
                continue
            if event.get("type") == "system" and event.get("subtype") == "init":
                init = event
    finally:
        proc.kill()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        shutil.rmtree(sandbox, ignore_errors=True)

    if init is None:
        return False, f"no init event arrived within {timeout}s, so the session shape is unknown"
    problem = session_shape_error([init], config)
    if problem:
        return False, problem
    builtins = sorted(t for t in (init.get("tools") or []) if not t.startswith("mcp__"))
    registered = [c for c in (init.get("slash_commands") or [])
                  if c.startswith(PLUGIN_NAME + ":")]
    return True, (f"tools: {', '.join(builtins)}; "
                  f"{PLUGIN_NAME} commands registered: {len(registered)}")


def contamination_error(events: list, config: str) -> str | None:
    """Did a control run reach the plugin's content on disk?

    Reading the checkout is how with_skill's skills load their `references/`,
    so this applies to the control legs only. Run-1 of graded run 31058151548
    did exactly this: `find /` located the checkout and `cat` supplied the
    shared spec, which made that leg's score a fact about the filesystem rather
    than about the plugin.
    """
    if config == "with_skill":
        return None
    for event in events:
        if event.get("type") != "assistant":
            continue
        for block in (event.get("message", {}).get("content") or []):
            if block.get("type") != "tool_use":
                continue
            if str(REPO) in json.dumps(block.get("input", {})):
                return (f"{config} reached the plugin checkout on disk via "
                        f"{block.get('name')}, so it measured 'was --plugin-dir "
                        f"passed' rather than 'was the content unavailable'")
    return None


def execute(prompt: str, config: str, run_dir: Path, fixture: Path,
            model: str | None, timeout: int) -> dict:
    """Run one (eval, config, run) and capture everything it produced."""
    outputs = run_dir / "outputs"
    outputs.mkdir(parents=True, exist_ok=True)
    write_log = outputs / "writes.jsonl"
    write_log.touch()

    cfg_path = run_dir / "mcp-config.json"
    cfg_path.write_text(json.dumps(mcp_config(fixture, write_log), indent=2))

    ok, detail = probe_stub(fixture, write_log)
    if not ok:
        return {"error": detail, "events": [], "duration": 0.0}
    # The probe opens the log file; a handshake issues no writes, so it stays
    # empty. Truncate anyway rather than assume it.
    write_log.write_text("")

    # The session runs in a throwaway sandbox rather than in run_dir, because
    # run_dir lives under --out and --out lives inside this checkout on CI. A cwd
    # inside the repo would hand every run the repo's own CLAUDE.md through
    # auto-discovery, and hand the control a path to the plugin it is supposed
    # not to have.
    sandbox = Path(tempfile.mkdtemp(prefix="holacracy-eval-"))
    if REPO == sandbox or REPO in sandbox.parents:
        shutil.rmtree(sandbox, ignore_errors=True)
        return {"error": f"the sandbox {sandbox} is inside the checkout; set TMPDIR "
                         f"outside {REPO} or the run is not hermetic",
                "events": [], "duration": 0.0}
    config_dir = sandbox / "claude-config"
    workdir = sandbox / "work"
    config_dir.mkdir()
    workdir.mkdir()

    started = time.time()
    try:
        proc = subprocess.run(
            build_command(prompt, config, cfg_path, model),
            capture_output=True, text=True, timeout=timeout,
            cwd=str(workdir), env=session_env(config_dir),
        )
    except subprocess.TimeoutExpired:
        return {"error": f"timed out after {timeout}s", "events": [],
                "duration": time.time() - started}
    except OSError as exc:
        return {"error": f"could not run {CLAUDE_BIN}: {exc}", "events": [],
                "duration": time.time() - started}
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    duration = time.time() - started
    events = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    if not events:
        return {"error": f"no stream-json events (exit {proc.returncode}; "
                         f"stderr: {proc.stderr.strip()[:400]})",
                "events": [], "duration": duration}

    # A session that ended in error still emits a well-formed event stream. The
    # most common one is auth: CI supplies ANTHROPIC_API_KEY, and a run whose
    # environment lacks it gets a single "Not logged in" turn with is_error set.
    # Left unread, that run scores a green pass on every NEGATIVE assertion,
    # because a model that never ran issued no forbidden write.
    for event in reversed(events):
        if event.get("type") != "result":
            continue
        if event.get("is_error"):
            detail = str(event.get("result") or event.get("subtype") or "unknown").strip()
            hint = ""
            if "not logged in" in detail.lower() or "login" in detail.lower():
                hint = (" — the session authenticates with ANTHROPIC_API_KEY; note that "
                        "CLAUDE_CONFIG_DIR is redirected to an empty sandbox, so a login "
                        "stored in the operator's own config dir is not visible")
            return {"error": f"the session reported an error: {detail[:300]}{hint}",
                    "events": events, "duration": duration}
        break

    # Did the session have the shape its configuration claims? Checked before
    # the tool-call condition below, because a with_skill leg that never loaded
    # the plugin can still make plenty of tool calls and score — which is
    # exactly the state that went unnoticed for four graded runs (#226).
    shape = session_shape_error(events, config)
    if shape:
        return {"error": shape, "events": events, "duration": duration}

    reached = contamination_error(events, config)
    if reached:
        return {"error": reached, "events": events, "duration": duration}

    # Every case in this tier drives a GlassFrog-backed surface, and none of them
    # can be answered without at least resolving the actor's roles. A run that
    # called nothing did not exercise the MCP path, so the write log is empty for
    # a reason that has nothing to do with the skill's judgement.
    made_a_call = any(
        block.get("type") == "tool_use"
        for event in events if event.get("type") == "assistant"
        for block in (event.get("message", {}).get("content") or [])
    )
    if not made_a_call:
        return {"error": "the run made no tool calls, so it never exercised the "
                         "GlassFrog path; no assertion about tool use is supported by it",
                "events": events, "duration": duration}

    return {"error": None, "events": events, "duration": duration}


def render_transcript(events: list, prompt: str) -> tuple[str, dict]:
    """Flatten the event stream into a readable transcript plus tool metrics.

    The grader reads the transcript, so a tool call has to survive into it with
    its arguments. A transcript that records only assistant prose would let an
    assertion about *which tool was called with what* be graded on the model's
    own narration of what it did.
    """
    lines = [f"# Eval transcript\n", f"## Prompt\n\n{prompt}\n"]
    tool_calls: dict[str, int] = {}
    errors = 0
    step = 0

    for event in events:
        kind = event.get("type")
        if kind == "assistant":
            step += 1
            lines.append(f"\n## Step {step} — assistant\n")
            for block in event.get("message", {}).get("content", []) or []:
                if block.get("type") == "text" and block.get("text", "").strip():
                    lines.append(block["text"].strip() + "\n")
                elif block.get("type") == "tool_use":
                    name = block.get("name", "?")
                    tool_calls[name] = tool_calls.get(name, 0) + 1
                    args = json.dumps(block.get("input", {}), indent=2, sort_keys=True)
                    lines.append(f"**Tool call:** `{name}`\n\n```json\n{args}\n```\n")
        elif kind == "user":
            for block in event.get("message", {}).get("content", []) or []:
                if block.get("type") != "tool_result":
                    continue
                body = block.get("content")
                if isinstance(body, list):
                    body = "".join(b.get("text", "") for b in body if isinstance(b, dict))
                body = str(body or "")
                if block.get("is_error"):
                    errors += 1
                lines.append(f"**Tool result** ({'error' if block.get('is_error') else 'ok'}):\n\n"
                             f"```\n{body[:4000]}\n```\n")
        elif kind == "result":
            if event.get("is_error"):
                errors += 1
            text = event.get("result")
            if isinstance(text, str) and text.strip():
                lines.append(f"\n## Final response\n\n{text.strip()}\n")

    transcript = "\n".join(lines)
    metrics = {
        "tool_calls": tool_calls,
        "total_tool_calls": sum(tool_calls.values()),
        "total_steps": step,
        "errors_encountered": errors,
        "transcript_chars": len(transcript),
    }
    return transcript, metrics


def usage_tokens(events: list) -> int:
    for event in reversed(events):
        if event.get("type") != "result":
            continue
        usage = event.get("usage") or {}
        total = sum(int(usage.get(k, 0) or 0) for k in
                    ("input_tokens", "output_tokens",
                     "cache_creation_input_tokens", "cache_read_input_tokens"))
        if total:
            return total
    return 0


def raw_usage(events: list) -> dict:
    """Both usage structures off the last result event, copied verbatim.

    `usage_tokens` above sums four fields into one integer, which is why cache
    reads and cache creations are indistinguishable in everything downstream of
    it: the ratio between them is the number that says whether caching works,
    and it is destroyed at the point of capture. This returns the objects
    instead, unaltered.

    Verbatim is load-bearing rather than lazy. A fixed field list silently
    drops whatever the API adds next -- the 1-hour cache tier already reports a
    nested `cache_creation` breakdown that a flat list would discard -- and the
    whole point of storing raw is that a derivation-rule change can be re-run
    over retained artifacts instead of costing another graded run. Deriving
    named figures from this is `scripts/eval-cost.py`'s job, not this
    function's; nothing here interprets, renames, or sums.

    `usage` and `modelUsage` disagree on key convention (snake_case vs
    camelCase) because they come from different layers upstream. Both are kept
    as-is; normalizing here would be interpretation.
    """
    for event in reversed(events):
        if event.get("type") != "result":
            continue
        return {
            "usage": event.get("usage"),
            "model_usage": event.get("modelUsage"),
            "total_cost_usd": event.get("total_cost_usd"),
        }
    return {"usage": None, "model_usage": None, "total_cost_usd": None}


@functools.lru_cache(maxsize=1)
def cli_version() -> str | None:
    """The CLI that produced this run's figures, resolved once per process.

    A benchmark that cannot name its CLI cannot be compared across one (#237):
    two `claude` binaries on the same machine differ in which events they emit,
    and CI installs latest on every run while a laptop pins whatever it has.
    The same argument `evals/benchmark.json` already makes for the model.

    Cached because a graded run makes ~48 executor calls and the answer cannot
    change mid-run; shelling out per run would add 48 subprocesses for a
    constant. `lru_cache` rather than a hand-rolled global: the tri-state
    sentinel that does the same job needs two `type: ignore`s and appears
    nowhere else in this repo's scripts.

    Returns None rather than a guess whenever the answer is not trustworthy --
    an unidentifiable CLI must stay legibly absent, the same discipline
    `observed_model` applies one field over. The exit status is part of that:
    `subprocess.run` does not raise on a non-zero exit without `check=True`, so
    a binary that prints a usage error to stdout and exits 2 would otherwise be
    recorded as the version string.
    """
    try:
        proc = subprocess.run([CLAUDE_BIN, "--version"], capture_output=True,
                              text=True, timeout=30)
    except (subprocess.SubprocessError, OSError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


# The event types observed_model() actually reads (system for the init model,
# assistant for message.model, result for modelUsage). `user` events carry tool
# results, which are already rendered into transcript.md and are typically the
# bulkiest part of a stream -- dropping them is a deliberate size reduction,
# not an oversight. Kept as a module constant so the filter and the function it
# serves cannot silently drift apart.
EVENTS_WORTH_KEEPING = ("system", "assistant", "result")


def write_events(path: Path, events: list) -> None:
    """Persist the events observed_model() can be re-derived from (#221).

    Without this, a question like "did modelUsage name an auxiliary model
    rather than the one that answered" can only be settled by spending another
    graded run -- the raw stream a completed run parsed is gone the moment the
    process exits, and only the already-derived `grading.json` survives. Full
    events were considered and rejected: the `user` events include tool
    results, which are the largest single piece of most sessions and are
    already retained via transcript.md, so this filters to the three types
    `observed_model` actually reads and nothing else.
    """
    kept = [e for e in events if e.get("type") in EVENTS_WORTH_KEEPING]
    path.write_text("\n".join(json.dumps(e) for e in kept))


def observed_model(events: list) -> str | None:
    """Which model actually answered, read off the stream rather than requested.

    `--model` is a workflow_dispatch input that is usually BLANK, meaning "the
    CLI default". Recording the request therefore records an empty string on
    exactly the runs a reader most needs to identify, and a benchmark that
    cannot name its model makes a model upgrade indistinguishable from a skill
    regression -- which is what #173's alarm would then misattribute (#203).

    Three independent places in a real stream carry it, tried in this order:

      1. an assistant event's `message.model` -- the model on the turn that
         actually answered
      2. the result event's `modelUsage`, keyed by model name
      3. the system init event's `model`

    `modelUsage` is NOT primary, despite billing the API most directly (#222).
    Diagnostic run 32055798335 (dispatched once #221 gave a completed run
    somewhere to keep its raw events) settled this with real evidence: every
    `without_skill` leg across all four eval cases billed an auxiliary
    `claude-haiku-4-5-20251001` alongside the requested `claude-sonnet-5`, with
    haiku listed FIRST in `modelUsage` -- yet every single `assistant` event in
    every one of those same runs had `message.model == "claude-sonnet-5"`. The
    auxiliary call never produced a visible turn; `modelUsage`'s first-key
    heuristic named the model that did not do the work, which is exactly why
    every graded run since #243 pinned `--model` still failed the "did the arms
    run on the same model" check for nine consecutive nights. `with_skill` legs
    never billed the auxiliary model at all, so the two orderings previously
    agreed by coincidence on that leg and diverged only on the control.

    Returns None when none of them is present, and the caller records that as
    JSON null. An unresolvable model must stay legibly absent: substituting a
    guess is the same defect as the `<model-name>` placeholder, one layer down.
    """
    for event in events:
        if event.get("type") == "assistant":
            name = (event.get("message") or {}).get("model")
            if name:
                return str(name)
    for event in reversed(events):
        if event.get("type") == "result":
            for name in (event.get("modelUsage") or {}):
                if name:
                    return str(name)
    for event in events:
        if event.get("type") == "system" and event.get("model"):
            return str(event["model"])
    return None


# ---------------------------------------------------------------------------
# Mechanical checks over the write log
# ---------------------------------------------------------------------------

def read_writes(write_log: Path) -> list[dict]:
    if not write_log.exists():
        return []
    rows = []
    for line in write_log.read_text().splitlines():
        line = line.strip()
        if line:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return sorted(rows, key=lambda r: r.get("seq", 0))


def matches(row: dict, matcher: dict) -> bool:
    if "tool" in matcher and row.get("tool") != matcher["tool"]:
        return False
    args = row.get("args", {}) or {}
    for key, want in (matcher.get("args_contain") or {}).items():
        if args.get(key) != want:
            return False
    for key, pattern in (matcher.get("args_match") or {}).items():
        if not re.search(pattern, str(args.get(key, "")), re.I):
            return False
    return True


def describe(rows: list[dict]) -> str:
    if not rows:
        return "the write log is empty"
    return "; ".join(f"#{r.get('seq')} {r.get('tool')} {json.dumps(r.get('args', {}), sort_keys=True)[:180]}"
                     for r in rows)


def run_check(check: dict, writes: list[dict], transcript: str) -> tuple[bool, str]:
    """Evaluate one mechanical assertion. Returns (passed, evidence)."""
    kind = check.get("kind")

    if kind == "no_writes":
        return (not writes,
                "No write reached the stub." if not writes
                else f"Writes were issued: {describe(writes)}")

    if kind == "no_write_of":
        hits = [w for w in writes if matches(w, check.get("match", {"tool": check.get("tool")}))]
        return (not hits,
                "No matching write was issued." if not hits
                else f"Matching writes: {describe(hits)}")

    if kind == "write_present":
        hits = [w for w in writes if matches(w, check["match"])]
        return (bool(hits),
                f"Matched: {describe(hits)}" if hits
                else f"No write matched {json.dumps(check['match'], sort_keys=True)}. "
                     f"Log: {describe(writes)}")

    if kind == "write_ordering":
        first = [w for w in writes if matches(w, check["first"])]
        then = [w for w in writes if matches(w, check["then"])]
        if not then:
            # Nothing to order against. Ordering assertions must not pass by
            # vacuity — that is how "successor before archive" would score green
            # on a run that did nothing at all.
            return False, (f"No write matched the `then` side "
                           f"{json.dumps(check['then'], sort_keys=True)}, so ordering could "
                           f"not be observed. Log: {describe(writes)}")
        if not first:
            return False, (f"`then` writes occurred ({describe(then)}) but no `first` write "
                           f"matching {json.dumps(check['first'], sort_keys=True)} preceded them.")
        earliest_first = min(w["seq"] for w in first)
        earliest_then = min(w["seq"] for w in then)
        ok = earliest_first < earliest_then
        return ok, (f"first at seq {earliest_first}, then at seq {earliest_then}. "
                    f"Log: {describe(writes)}")

    if kind == "transcript_matches":
        hit = re.search(check["pattern"], transcript, re.I | re.S)
        return (bool(hit),
                f"Matched {check['pattern']!r} at offset {hit.start()}." if hit
                else f"Pattern {check['pattern']!r} not found in the transcript.")

    return False, f"unknown mechanical check kind {kind!r}"


# ---------------------------------------------------------------------------
# Judged assertions
# ---------------------------------------------------------------------------

GRADER_SCHEMA = {
    "type": "object",
    "properties": {
        "expectations": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "passed": {"type": "boolean"},
                    "evidence": {"type": "string"},
                },
                "required": ["text", "passed", "evidence"],
            },
        }
    },
    "required": ["expectations"],
}

GRADER_PROMPT = """You are grading a transcript against a list of expectations.

Apply the grading contract from the skill-creator grader agent:

- PASS only when the transcript carries clear evidence the expectation is true
  AND that evidence reflects genuine task completion rather than surface
  compliance. An assistant that *says* it checked something has not checked it;
  look for the tool call.
- FAIL when there is no evidence, when evidence contradicts the expectation,
  when the expectation cannot be verified from what is here, or when the
  assertion is technically satisfied but the underlying outcome is wrong.
- No partial credit. The burden of proof to pass is on the expectation.
- Cite specific text for every verdict.

GROUND TRUTH (what a correct run does; the assistant did not see this):
{ground_truth}

EXPECTATIONS:
{expectations}

WRITE LOG (every write the assistant issued, in order; empty means none):
{writes}

TRANSCRIPT:
{transcript}

Return one entry per expectation, in the order given.
"""


def grade_judged(assertions: list[dict], transcript: str, writes: list[dict],
                 ground_truth: str, model: str | None,
                 timeout: int) -> tuple[list[dict], str | None, dict]:
    """Returns (verdicts, the model that actually graded them, the cost record).

    The analyzer model is reported separately from the executor's because they
    are separately substitutable -- `--model` sets both today, but a benchmark
    that names only one cannot say which half of a delta moved.

    The third return value exists because this pass has THREE terminal states
    and two of them look identical from outside:

      not_invoked  no judged assertions -- no API call, so a structural zero
      failed       the except branch below -- the call was made and BILLED,
                   including a `timeout`-second generation that produced
                   nothing readable, and its usage is unrecoverable
      ok           usage available

    Recording the first two as the same null under-reports spend on exactly the
    runs that wasted it, which is backwards for a cost ledger. The `failed`
    branch returns before `payload` is ever assigned, so there is no usage
    object on that path even in principle -- the honest record is "cost
    incurred, amount unknown", not zero.
    """
    if not assertions:
        return [], None, {"status": "not_invoked", "reason": "no judged assertions",
                          "usage": None, "model_usage": None, "total_cost_usd": None}

    prompt = GRADER_PROMPT.format(
        ground_truth=ground_truth or "(none recorded)",
        expectations="\n".join(f"{i + 1}. {a['text']}" for i, a in enumerate(assertions)),
        writes=json.dumps(writes, indent=2) if writes else "(empty)",
        transcript=transcript[:120000],
    )
    cmd = [
        CLAUDE_BIN, "-p", prompt,
        "--output-format", "json",
        "--json-schema", json.dumps(GRADER_SCHEMA),
        "--tools", "",
    ]
    if model:
        cmd += ["--model", model]

    # The grader gets the same empty-config sandbox as the executor. It has no
    # tools and no plugin, but it would otherwise inherit the operator's global
    # CLAUDE.md and hooks — and a grader reading this repo's own CLAUDE.md would
    # be told what the runner is supposed to conclude.
    sandbox = Path(tempfile.mkdtemp(prefix="holacracy-grader-"))
    config_dir = sandbox / "claude-config"
    workdir = sandbox / "work"
    config_dir.mkdir()
    workdir.mkdir()

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=timeout, env=session_env(config_dir),
                              cwd=str(workdir))
        payload = json.loads(proc.stdout)
        result = payload.get("result", payload)
        if isinstance(result, str):
            result = json.loads(result)
        graded = result["expectations"]
    except (subprocess.SubprocessError, OSError, json.JSONDecodeError,
            KeyError, TypeError) as exc:
        # A grader that cannot be reached must not silently pass the run. Every
        # judged assertion fails with the reason attached.
        #
        # `failed`, never a zero: reaching here means the subprocess was
        # launched, so the call was billed whatever it returned -- a
        # TimeoutExpired at the full timeout is a complete generation that was
        # paid for and thrown away. `payload` is unbound on this path, so the
        # amount is genuinely unknown rather than absent.
        return ([{"text": a["text"], "passed": False,
                  "evidence": f"grader unavailable: {exc}"} for a in assertions],
                None,
                {"status": "failed", "reason": str(exc),
                 "usage": None, "model_usage": None, "total_cost_usd": None})
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    # `--output-format json` emits the result object itself rather than a
    # stream, so it is handed to observed_model as a one-event stream.
    analyzer = observed_model([dict(payload, type="result")]) \
        if isinstance(payload, dict) else None

    out = []
    for i, assertion in enumerate(assertions):
        entry = graded[i] if i < len(graded) else {}
        out.append({
            "text": assertion["text"],
            "passed": bool(entry.get("passed", False)),
            "evidence": str(entry.get("evidence", "grader returned no entry for this expectation")),
        })
    # `--output-format json` returns the result object itself, so the usage
    # structures sit at its top level rather than on a result event.
    return out, analyzer, {
        "status": "ok",
        "reason": None,
        "usage": payload.get("usage") if isinstance(payload, dict) else None,
        "model_usage": payload.get("modelUsage") if isinstance(payload, dict) else None,
        "total_cost_usd": payload.get("total_cost_usd") if isinstance(payload, dict) else None,
    }


# ---------------------------------------------------------------------------
# One run
# ---------------------------------------------------------------------------

def run_once(case: dict, config: str, run_dir: Path, model: str | None,
             timeout: int, grade: bool) -> dict:
    fixture = REPO / case["fixture"]
    if not fixture.exists():
        raise SystemExit(f"fixture not found: {fixture}")

    started = time.time()
    outcome = execute(case["prompt"], config, run_dir, fixture, model, timeout)
    transcript, metrics = render_transcript(outcome["events"], case["prompt"])
    if outcome["error"]:
        transcript += f"\n## Execution error\n\n{outcome['error']}\n"

    outputs = run_dir / "outputs"
    (outputs / "transcript.md").write_text(transcript)
    writes = read_writes(outputs / "writes.jsonl")
    metrics["output_chars"] = len(transcript)
    metrics["writes"] = len(writes)
    (outputs / "metrics.json").write_text(json.dumps(metrics, indent=2))
    write_events(outputs / "events.jsonl", outcome["events"])

    mechanical, judged_specs = [], []
    for assertion in case["assertions"]:
        if "check" in assertion:
            if outcome["error"]:
                # A run that did not execute is evidence for nothing, and every
                # NEGATIVE check would otherwise pass on it vacuously: an empty
                # write log genuinely contains no forbidden write. That is the
                # "did nothing, scored green" shape this whole tier exists to
                # catch, so failing is structural here rather than per-check.
                passed, evidence = False, f"the run did not execute: {outcome['error']}"
            else:
                passed, evidence = run_check(assertion["check"], writes, transcript)
            mechanical.append({"text": assertion["text"], "passed": passed,
                               "evidence": evidence, "mechanical": True})
        else:
            judged_specs.append(assertion)

    analyzer_model = None
    if outcome["error"]:
        judged = [{"text": a["text"], "passed": False,
                   "evidence": f"not graded — the run did not execute: {outcome['error']}"}
                  for a in judged_specs]
        grader_cost = {"status": "not_invoked",
                       "reason": f"the run did not execute: {outcome['error']}",
                       "usage": None, "model_usage": None, "total_cost_usd": None}
    elif grade:
        judged, analyzer_model, grader_cost = grade_judged(
            judged_specs, transcript, writes,
            case.get("ground_truth", ""), model, timeout)
    else:
        judged = [{"text": a["text"], "passed": False,
                   "evidence": "grading disabled (--no-grade)"} for a in judged_specs]
        grader_cost = {"status": "not_invoked", "reason": "grading disabled (--no-grade)",
                       "usage": None, "model_usage": None, "total_cost_usd": None}

    # Preserve the case's own assertion order so a grading.json reads against
    # the case file it came from.
    by_text = {e["text"]: e for e in mechanical + judged}
    expectations = [by_text[a["text"]] for a in case["assertions"] if a["text"] in by_text]

    passed = sum(1 for e in expectations if e["passed"])
    total = len(expectations)
    elapsed = time.time() - started

    timing = {
        "executor_duration_seconds": round(outcome["duration"], 2),
        "total_duration_seconds": round(elapsed, 2),
        "total_tokens": usage_tokens(outcome["events"]),
    }
    (run_dir / "timing.json").write_text(json.dumps(timing, indent=2))

    # The cost record: raw only, both passes, never blended.
    #
    # Separate from timing.json rather than folded into it because the raw
    # usage is the expensive-to-rebuild half -- it exists only while a graded
    # run is in flight, and rebuilding it costs another paid run -- while
    # timing.json is derivable from a clock. Keeping it its own artifact also
    # keeps the derivation out of this file entirely: scripts/eval-cost.py
    # reads this and computes the named figures, so an unrecognised field can
    # be stored here without any risk of it reaching an arithmetic path.
    #
    # The executor's usage is recorded whether or not the run errored. A
    # session that died mid-way still billed for what it generated, and
    # discarding that on the error path would under-report exactly the runs
    # that spent money for nothing.
    executor_cost = raw_usage(outcome["events"])
    executor_cost["status"] = "failed" if outcome["error"] else "ok"
    executor_cost["reason"] = outcome["error"]
    cost = {
        "schema": 1,
        "cli_version": cli_version(),
        "eval_name": case["eval_name"],
        "config": config,
        "passes": {"executor": executor_cost, "grader": grader_cost},
    }
    (run_dir / "cost.json").write_text(json.dumps(cost, indent=2))

    grading = {
        "eval_name": case["eval_name"],
        "config": config,
        # What actually answered, not what was asked for. `model` below is the
        # request and is null on every default-model run; these two are read off
        # the streams. Recorded per run rather than only in the manifest so a
        # single run's grading.json stays self-describing when it is read alone.
        # Derived from the events rather than returned by execute(), because
        # execute() has six exit paths and three of them carry a real event
        # stream: a session that errored, or made no tool calls, still ran a
        # model, and a failed run is exactly when knowing which one matters.
        "models": {
            "requested": model,
            "executor": observed_model(outcome["events"]),
            "analyzer": analyzer_model,
        },
        "expectations": expectations,
        "summary": {
            "passed": passed,
            "failed": total - passed,
            "total": total,
            "pass_rate": round(passed / total, 4) if total else 0.0,
        },
        "execution_metrics": metrics,
        "timing": timing,
        "execution_error": outcome["error"],
    }
    (run_dir / "grading.json").write_text(json.dumps(grading, indent=2))
    return grading


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def load_case_file(path: Path) -> dict:
    doc = json.loads(path.read_text())
    for i, case in enumerate(doc.get("evals", [])):
        for field in ("eval_id", "eval_name", "prompt", "fixture", "assertions"):
            if field not in case:
                raise SystemExit(f"{path}: eval #{i} is missing required field '{field}'")
        for assertion in case["assertions"]:
            if "text" not in assertion:
                raise SystemExit(f"{path}: {case['eval_name']} has an assertion with no 'text'")
            if "discriminating" not in assertion:
                raise SystemExit(
                    f"{path}: assertion {assertion['text'][:60]!r} does not declare "
                    f"`discriminating`. An assertion that passes with the skill disabled "
                    f"measures nothing; declaring it is how that stays visible.")
            if assertion["discriminating"] is False and "why_kept" not in assertion:
                raise SystemExit(
                    f"{path}: non-discriminating assertion {assertion['text'][:60]!r} has no "
                    f"`why_kept`. The only defensible reason to keep one is that it is a "
                    f"floor that must hold in every configuration.")
    return doc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--case", action="append", required=True,
                        help="path to an evals/cases/<surface>/evals.json (repeatable)")
    parser.add_argument("--out", required=True, help="benchmark output directory")
    parser.add_argument("--runs", type=int, default=1, help="runs per (eval, config)")
    parser.add_argument("--configs", default=",".join(DEFAULT_CONFIGS),
                        help="comma-separated configs to run")
    parser.add_argument("--eval-name", help="run only the eval with this name")
    parser.add_argument("--model", default=None)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--no-grade", action="store_true",
                        help="skip the judged pass; mechanical checks still run")
    parser.add_argument("--validate-only", action="store_true",
                        help="validate the case files, probe each fixture, and probe "
                             "each config's session shape, then exit")
    parser.add_argument("--no-session-probe", action="store_true",
                        help="skip the session-shape probe under --validate-only "
                             "(it needs the real `claude` binary on PATH)")
    parser.add_argument("--cache-index", default=None,
                        help="path to a JSON file used as the change-aware cache index "
                             "for the graded loop. Omit to disable caching entirely -- "
                             "every leg executes fresh, exactly as before this flag "
                             "existed. The workflow points this at a checkout of the "
                             "dedicated eval-cache-index branch; this script has no git "
                             "awareness of its own.")
    parser.add_argument("--cache-max-age-days", type=int, default=DEFAULT_CACHE_MAX_AGE_DAYS,
                        help="force a fresh execution at least this often even when a "
                             "leg's cache key has not changed (R8)")
    parser.add_argument("--now", default=None,
                        help="ISO8601 timestamp to treat as the current time for cache "
                             "freshness decisions; defaults to the real time. A test-only "
                             "affordance for deterministic cache-lifetime assertions, same "
                             "shape as this repo's other alarm scripts' --now.")
    args = parser.parse_args()

    configs = [c.strip() for c in args.configs.split(",") if c.strip()]
    out_root = Path(args.out)
    failures = 0

    # Cache index: opt-in (only when --cache-index is passed), and inert under
    # --validate-only -- that preflight is a wholly separate path that never
    # reaches the per-config loop below, and it must stay unaffected by any of
    # this (R5): a `--no-session-probe` caller has promised itself no `claude`
    # binary is needed, and claude_cli_version() would break that promise.
    # cli_version is read once here rather than once per leg -- the binary
    # does not change mid-run, and shelling out per leg would be a wasted
    # process spawn repeated across the whole matrix (see claude_cli_version's
    # own docstring).
    cache_index_path: Path | None = None
    cache_index: dict | None = None
    cli_version: str | None = None
    cache_now: datetime | None = None
    if args.cache_index and not args.validate_only:
        cache_index_path = Path(args.cache_index)
        cache_index = load_cache_index(cache_index_path)
        cli_version = claude_cli_version()
        cache_now = (_parse_iso_as_utc(args.now) if args.now
                    else datetime.now(timezone.utc))

    # The session-shape preflight. Free, keyless, and the thing that would have
    # caught #226 before four graded runs were spent on a harness measuring the
    # base model against itself.
    if args.validate_only and not args.no_session_probe:
        for config in configs:
            ok, detail = probe_session(config)
            print(f"{'ok  ' if ok else 'FAIL'} session shape [{config}]: {detail}")
            failures += 0 if ok else 1
    # Sets, not single values. One benchmark spanning two models is a real
    # condition -- a mid-run default change, or a fallback -- and collapsing it
    # to one name would hide exactly the thing the recording exists to expose.
    executors: set[str] = set()
    analyzers: set[str] = set()
    # Per config as well as overall. The overall set answers "which models
    # appear"; only the per-config split answers "did the two arms run on the
    # same one", which is the question a delta depends on.
    executors_by_config: dict = {}
    # U5: this run's OWN record of which branch each leg actually took. A
    # stored `leg_<hash>` entry's `successful`/`last_executed` describe the
    # state as of whenever it was last WRITTEN, not "was this leg reused
    # THIS run" -- a skip never rewrites its entry (see the cache-hit branch
    # below), so by the time the run ends there is no way to tell "still
    # valid from three nights ago" apart from "reused tonight" by reading
    # stored entries alone. This list is recorded regardless of whether
    # caching is enabled; it is simply empty when it is not.
    cache_run_legs: list[dict] = []

    for case_path in args.case:
        doc = load_case_file(Path(case_path))
        # `eval_id` is unique only WITHIN a case file — every file numbers its
        # evals from 0 — so keying the output directory on it alone made two
        # cases from different files collide, and the second silently
        # overwrote the first. A whole surface vanished from a green benchmark
        # that reported the remainder as the complete suite (#201).
        #
        # The case file's directory name is the natural qualifier. The name
        # must stay FLAT and keep the `eval-` prefix: aggregate_benchmark.py
        # discovers results with `benchmark_dir.glob("eval-*")` directly under
        # the benchmark dir, so a nested <suite>/eval-<id> layout would make
        # every eval invisible to aggregation instead.
        suite = Path(case_path).parent.name
        for case in doc["evals"]:
            if args.eval_name and case["eval_name"] != args.eval_name:
                continue

            fixture = REPO / case["fixture"]
            if not fixture.exists():
                print(f"ERROR {case['eval_name']}: fixture not found: {case['fixture']}",
                      file=sys.stderr)
                failures += 1
                continue

            if args.validate_only:
                log = out_root / f"probe-{suite}-{case['eval_id']}.jsonl"
                log.parent.mkdir(parents=True, exist_ok=True)
                ok, detail = probe_stub(fixture, log)
                log.unlink(missing_ok=True)
                print(f"{'ok  ' if ok else 'FAIL'} {case['eval_name']}: {detail}")
                failures += 0 if ok else 1
                continue

            eval_dir = out_root / f"eval-{suite}-{case['eval_id']}"
            eval_dir.mkdir(parents=True, exist_ok=True)
            # The SAME collision, one layer up. #201 qualified the directory
            # name; this field kept the bare number, and the aggregator reads
            # it verbatim into every `runs[]` row and into
            # `metadata.evals_run`. So two suites' eval 0 became two rows keyed
            # `(0, <config>, <run>)` with no field telling them apart, and a
            # four-eval suite reported three ids (#244).
            #
            # Qualified HERE rather than by post-processing the aggregated
            # output, which is what #244 proposed. That works only because the
            # aggregator never coerces this value -- it is a plain
            # `json.load(mf).get("eval_id", eval_idx)` -- so the qualified form
            # flows through untouched and no seam in the workflow has to
            # re-derive the suite from the directory name.
            #
            # `eval_id_local` and `suite` are kept alongside so a reader of the
            # artifact can recover the suite-local number without parsing the
            # composite back apart. The aggregator ignores both.
            (eval_dir / "eval_metadata.json").write_text(json.dumps({
                "eval_id": f"{suite}-{case['eval_id']}",
                "eval_id_local": case["eval_id"],
                "suite": suite,
                "eval_name": case["eval_name"],
                "surface": doc.get("surface"),
                "fixture": case["fixture"],
                "ground_truth": case.get("ground_truth", ""),
            }, indent=2))

            for config in configs:
                # The skip/execute decision is made ONCE per (case, config)
                # leg -- i.e. once per iteration of this loop, wrapping the
                # entire run-range loop below -- not once per run. The key
                # already folds `runs` in as one of its nine inputs, so every
                # run within a leg shares one decision.
                cache_key = None
                cache_entry = None
                if cache_index is not None:
                    skill_dirs = resolve_skill_dirs_for_leg(config)
                    cache_key = compute_cache_key(
                        case, skill_dirs=skill_dirs, fixture_path=fixture,
                        runs=args.runs, model=args.model, cli_version=cli_version)
                    cache_entry = cache_index.get(cache_key)

                if cache_key is not None and cache_entry_is_usable(
                        cache_entry, now=cache_now, max_age_days=args.cache_max_age_days):
                    # Case 6: a fresh, successful result already exists for
                    # this leg's current key. Reuse it for every one of this
                    # leg's runs -- no run_once, no touching run_dir, no
                    # subprocess of any kind. That is the entire savings this
                    # unit exists to produce.
                    cache_run_legs.append({"case": case["eval_name"], "config": config,
                                           "cache_hit": True})
                    stored_grading = cache_entry["grading"]
                    record_leg_bookkeeping(stored_grading, config, executors,
                                           analyzers, executors_by_config)
                    summary = stored_grading["summary"]
                    for run in range(1, args.runs + 1):
                        print(f"{case['eval_name']} / {config} / run-{run}: "
                              f"{summary['passed']}/{summary['total']}  "
                              f"[cache hit, last executed "
                              f"{cache_entry.get('last_executed', '?')}]")
                    continue

                # Cases 3-5: no entry for the current key, a stored entry
                # whose result was not successful, or a stored entry that has
                # aged past --cache-max-age-days. Execute the leg exactly as
                # this loop always has.
                leg_gradings = []
                for run in range(1, args.runs + 1):
                    run_dir = eval_dir / config / f"run-{run}"
                    if run_dir.exists():
                        shutil.rmtree(run_dir)
                    run_dir.mkdir(parents=True)
                    grading = run_once(case, config, run_dir, args.model,
                                       args.timeout, not args.no_grade)
                    if cache_key is not None:
                        # Tagged only when caching is enabled, so a run that
                        # never opted into the cache index sees an identical
                        # grading.json to before this unit existed. U5 (a
                        # later unit) reads this to tell a cached leg from a
                        # freshly executed one; written back to the file run_once
                        # already wrote, so the on-disk artifact matches what
                        # gets folded into the cache index below.
                        grading["cache_hit"] = False
                        (run_dir / "grading.json").write_text(json.dumps(grading, indent=2))
                    leg_gradings.append(grading)
                    record_leg_bookkeeping(grading, config, executors,
                                           analyzers, executors_by_config)
                    summary = grading["summary"]
                    note = f"  [{grading['execution_error']}]" if grading["execution_error"] else ""
                    print(f"{case['eval_name']} / {config} / run-{run}: "
                          f"{summary['passed']}/{summary['total']}{note}")

                if cache_key is not None:
                    # "Successful" here means the leg's runs all EXECUTED
                    # cleanly (no execution_error) -- not that every assertion
                    # passed. A leg that ran correctly but failed a real
                    # assertion is still a trustworthy result to reuse; a leg
                    # that crashed, timed out, or never made a tool call is
                    # not evidence of anything and must not be cached as if
                    # it were (this mirrors run_once's own treatment of
                    # execution_error for mechanical checks, and matches R3's
                    # framing of "a prior attempt under the current key
                    # failed"). The most recent run's grading is stored as
                    # the leg's representative result -- what a skip reuses
                    # and prints next time.
                    leg_successful = all(g["execution_error"] is None for g in leg_gradings)
                    cache_index[cache_key] = {
                        "last_executed": cache_now.isoformat(),
                        "successful": leg_successful,
                        "grading": leg_gradings[-1],
                        "case": case["eval_name"],
                        "config": config,
                    }
                    cache_run_legs.append({"case": case["eval_name"], "config": config,
                                           "cache_hit": False})
                    if cache_index_path is not None:
                        # Saved after EVERY fresh write, not only at the very
                        # end of the run -- a leg that just executed and cost
                        # real API time must survive a crash or timeout in a
                        # later leg. Cheap: the index is small JSON, and a
                        # cache hit never reaches this branch, so a quiet
                        # night with mostly-skipped legs writes rarely.
                        save_cache_index(cache_index_path, cache_index)

    if not args.validate_only:
        (out_root / "run_metadata.json").write_text(json.dumps({
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "cases": args.case,
            "configs": configs,
            "runs_per_config": args.runs,
            # `model` is what was ASKED for and is null on every run that took
            # the CLI default, which is most of them. The two lists below are
            # what actually answered, read off the event streams. The Aggregate
            # step in skills-eval.yml stamps them into benchmark.json, where
            # aggregate_benchmark.py otherwise writes the literal string
            # "<model-name>" and has no flag to override it (#203).
            "model": args.model,
            "executor_models": sorted(executors),
            "analyzer_models": sorted(analyzers),
            "graded": not args.no_grade,
            "executor_models_by_config": {c: sorted(m) for c, m
                                          in sorted(executors_by_config.items())},
        }, indent=2))

        # Final save: every fresh leg already persisted itself as it ran (see
        # the incremental save above), so this mainly stamps _run_summary
        # (below) into the file -- the one thing that has to wait until every
        # leg has reported in. It also covers the all-cache-hit case, where
        # the incremental save above never fires because nothing executed.
        # cache_index_path is None whenever --cache-index was not passed, so
        # this whole block is a no-op for every existing caller of this script.
        if cache_index_path is not None:
            # U5 (R6): this run's hit/miss accounting, stamped into the SAME
            # index file under a key that can never collide with a
            # `leg_<hash>` entry (see compute_cache_key) -- a reader that
            # only knows the `leg_` prefix can skip it outright, and an
            # older reader that predates this key simply never looks for it.
            # Overwritten whole every run (it describes tonight, not a
            # running total), so scripts/eval-report.py's cache-summary
            # section always reflects the run that just finished rather than
            # some earlier night's leftovers.
            cache_index["_run_summary"] = {
                "generated_at": cache_now.isoformat(),
                "hits": sum(1 for leg in cache_run_legs if leg["cache_hit"]),
                "misses": sum(1 for leg in cache_run_legs if not leg["cache_hit"]),
                "legs": cache_run_legs,
            }
            save_cache_index(cache_index_path, cache_index)

        # The arms must have run on the SAME executor model, or the delta
        # between them is a fact about the models rather than about the plugin.
        #
        # This is not hypothetical. Graded run 31229964963 answered every one of
        # the 12 `with_skill` executions with claude-opus-5[1m] and every one of
        # the 12 `without_skill` executions with claude-haiku-4-5 — a perfect
        # confound with the configuration, because `--model` was blank and each
        # session chose for itself. It reported +0.13 in the plugin's favour and
        # the treatment arm is the one that got the stronger model. The loop runs
        # `with_skill` first for every eval, so the bias has a fixed direction.
        #
        # Reported AFTER run_metadata.json is written: the evidence is what makes
        # the failure actionable, and a run that fails here has still done all the
        # work, so throwing its record away would be the expensive kind of tidy.
        distinct = {m for models in executors_by_config.values() for m in models}
        if len(distinct) > 1:
            print("ERROR: the configurations did not run on the same executor "
                  "model, so their delta measures the models and not the plugin. "
                  "Pass --model to pin it.", file=sys.stderr)
            for config in sorted(executors_by_config):
                print(f"  {config}: {', '.join(sorted(executors_by_config[config]))}",
                      file=sys.stderr)
            failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
