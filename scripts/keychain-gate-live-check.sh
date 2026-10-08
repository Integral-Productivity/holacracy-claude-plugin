#!/usr/bin/env bash
# Live verification of the #318 Keychain auth gate on macOS (issue #319).
#
# Run:  bash scripts/keychain-gate-live-check.sh [--runs N] [--out FILE]
#                                                [--config-dir DIR] [--lock-test]
# Exit: 0 every check that ran passed, 1 a check failed, 2 usage/environment.
#
# OPERATOR-LOCAL. It reads the real login Keychain, which no CI runner has and
# which an agent session's permission classifier rightly refuses to touch. Run
# it yourself, in Terminal, on the Mac the gate is meant to work on.
#
# WHAT IT NEVER DOES
# ------------------
# Print, store, or pass a token anywhere visible. The Keychain item goes from
# `security ... -w` straight into a python3 pipe that reports only its SHAPE:
# which keys exist, whether each glassfrog entry's accessToken is non-empty,
# whether it has a refresh token, whether it has expired. Never a value, never
# the hash half of an mcpOAuth key, never the name of a non-glassfrog server.
# The report is written to be pasted into a public issue and ADR-0008 A6.
#
# THE CHECKS (numbered as in #319 and its follow-up comment)
# ----------------------------------------------------------
#   1  Keychain path alone opens the gate. Stronger than #319 step 1: the
#      credentials file is pointed at /nonexistent, so a pass cannot come from
#      the file. Plus the item's redacted structure (#319 AC4 needs it if this
#      fails).
#   2  HOLACRACY_GROUNDING_KEYCHAIN=off withholds (the stale file alone).
#   3  Hot-path cost: the hook N times down five gate paths, interleaved,
#      median per run. This is the number ADR-0008 A6 lacks.
#   4  CLAUDE_CONFIG_DIR: a non-default config dir gets its own Keychain
#      item, "Claude Code-credentials-" + sha256(dir)[:8]. Lists service NAMES
#      only (`dump-keychain` without -d). With --config-dir, checks that the
#      expected item exists and that the hook reads it.
#   5  Locked keychain (--lock-test only; it locks your login keychain, which
#      other apps will notice). The first live run showed a plain read raises
#      the unlock dialog and blocks (8.5 s). The hook now checks the lock state
#      first and caps the read at 1 s; this verifies both against the real
#      locked keychain, judged on time.
#
# Every hook run unsets every HOLACRACY_GROUNDING_* variable first, so an
# override in your shell (or exported from settings.json into this terminal)
# cannot make a check pass.

set -uo pipefail

usage() {
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

RUNS=20
OUT=""
CONFIG_DIR=""
LOCK_TEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) [[ $# -ge 2 ]] || usage; RUNS="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || usage; OUT="$2"; shift 2 ;;
    --config-dir) [[ $# -ge 2 ]] || usage; CONFIG_DIR="$2"; shift 2 ;;
    --lock-test) LOCK_TEST=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || { echo "--runs must be a positive integer" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks-handlers/session-start.sh"
SERVICE="Claude Code-credentials"
NOCRED="/nonexistent/holacracy-319/.credentials.json"

[[ "${OSTYPE:-}" == darwin* ]] || { echo "macOS only: this verifies the Keychain path." >&2; exit 2; }
for bin in security python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing: $bin" >&2; exit 2; }
done
[[ -r "$HOOK" ]] || { echo "hook not found: $HOOK" >&2; exit 2; }

FAILED=0
REPORT=""
say() { printf '%s\n' "$*" >&2; }
rec() { REPORT+="$*"$'\n'; }
verdict() { # verdict <PASS|FAIL|INFO> <text>
  [[ "$1" == FAIL ]] && FAILED=1
  rec "- **$1** $2"
  say "  [$1] $2"
}

# Run the hook with every HOLACRACY_GROUNDING_* cleared, then the given
# assignments applied. Prints directive|conditional|none. (`conditional` was
# `withheld` before #332: a failed gate now emits the tool-conditional form.)
hook_outcome() {
  local -a clear=()
  local v
  while IFS= read -r v; do clear+=(-u "$v"); done < <(compgen -e | grep '^HOLACRACY_GROUNDING_' || true)
  local out
  out="$(env ${clear[@]+"${clear[@]}"} "$@" bash "$HOOK" </dev/null 2>/dev/null)"
  if [[ "$out" == *"role-grounding check (conditional directive)"* ]]; then echo conditional
  elif [[ "$out" == *"Holacracy plugin: role-grounding directive"* ]]; then echo directive
  else echo none
  fi
}

# Reads the store on stdin; prints its redacted shape. No values, ever.
read -r -d '' SHAPE_PY <<'PY'
import json, sys, time
raw = sys.stdin.read()
if not raw.strip():
    print("  (empty: no item, or the read was refused)"); sys.exit(3)
try:
    d = json.loads(raw)
except Exception as e:
    print("  (not JSON: %s)" % type(e).__name__); sys.exit(4)
if not isinstance(d, dict):
    print("  (top level is %s, not an object)" % type(d).__name__); sys.exit(4)
print("  top-level keys: " + ", ".join(sorted(d.keys())))
m = d.get("mcpOAuth")
if not isinstance(m, dict):
    print("  mcpOAuth: %s" % ("absent" if m is None else type(m).__name__)); sys.exit(5)
others = 0
found = False
authed = False
for key, e in m.items():
    server = str(key).split("|", 1)[0]
    name = e.get("serverName") if isinstance(e, dict) else None
    if "glassfrog" not in (str(name or server)).lower():
        others += 1
        continue
    found = True
    if not isinstance(e, dict):
        print("  glassfrog entry: %s, not an object" % type(e).__name__); continue
    tok = e.get("accessToken")
    exp = e.get("expiresAt")
    expired = False
    if isinstance(exp, (int, float)):
        secs = exp / 1000.0 if exp > 1e11 else float(exp)
        expired = secs <= time.time()
        expiry = "%s, %s" % ("ms" if exp > 1e11 else "s", "expired" if expired else "valid")
    else:
        expiry = "absent" if exp is None else type(exp).__name__
    print("  glassfrog entry (key '%s|<hash>'):" % server)
    print("    fields: " + ", ".join(sorted(e.keys())))
    print("    serverName names glassfrog: %s" % ("glassfrog" in str(name or "").lower()))
    print("    accessToken: %s" % ("non-empty string" if isinstance(tok, str) and tok.strip()
                                    else ("empty string" if isinstance(tok, str) else type(tok).__name__)))
    print("    refreshToken present: %s" % bool(e.get("refreshToken")))
    print("    expiresAt: %s" % expiry)
    # Same rule as the gate: a non-empty token, and not expired without a refresh token.
    if isinstance(tok, str) and tok.strip() and not (expired and not e.get("refreshToken")):
        authed = True
print("  other mcpOAuth entries: %d" % others)
sys.exit(0 if authed else (7 if found else 6))
PY

# argv: hook, runs, no-file path. Prints one "label<TAB>median" line per path,
# interleaved to cancel drift. Five paths, because two (off vs auto) cannot
# separate the Keychain from python3's start-up: in the first live run they
# differed by 1.3 ms while `security` alone took 41 ms (#319).
read -r -d '' TIME_PY <<'PY'
import os, statistics, subprocess, sys, time
hook, runs, nofile = sys.argv[1], int(sys.argv[2]), sys.argv[3]
base = {k: v for k, v in os.environ.items() if not k.startswith("HOLACRACY_GROUNDING_")}
g = "HOLACRACY_GROUNDING_"
modes = [
    ("override on: no store read", dict(base, **{g + "ASSUME_GLASSFROG": "on"})),
    ("Keychain off, no file", dict(base, **{g + "KEYCHAIN": "off", g + "CREDENTIALS_FILE": nofile})),
    ("Keychain off, real file", dict(base, **{g + "KEYCHAIN": "off"})),
    ("Keychain on, no file", dict(base, **{g + "KEYCHAIN": "on", g + "CREDENTIALS_FILE": nofile})),
    ("default (auto)", dict(base)),
]
t = {m: [] for m, _ in modes}
for _ in range(runs):
    for m, env in modes:
        s = time.perf_counter()
        subprocess.run(["bash", hook], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, env=env, timeout=30)
        t[m].append((time.perf_counter() - s) * 1000)
for m, _ in modes:
    print("%s\t%.1f" % (m, statistics.median(t[m])))
PY

read -r -d '' SECURITY_TIME_PY <<'PY'
import statistics, subprocess, sys, time
svc, runs = sys.argv[1], int(sys.argv[2])
t = []
for _ in range(runs):
    s = time.perf_counter()
    subprocess.run(["security", "find-generic-password", "-s", svc, "-w"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    t.append((time.perf_counter() - s) * 1000)
print("%.1f" % statistics.median(t))
PY

service_names() {
  security dump-keychain 2>/dev/null \
    | grep -o '"svce"<blob>="Claude Code[^"]*"' \
    | sed 's/^"svce"<blob>=//' | sort -u
}

rec "## #319 live check -- $(date -u +%Y-%m-%dT%H:%MZ)"
rec ""
rec "- macOS $(sw_vers -productVersion 2>/dev/null || echo '?'), plugin $(tr -d '[:space:]' < "$ROOT/version.txt" 2>/dev/null || echo '?') at \`$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')\`, Claude Code $(claude --version 2>/dev/null | head -1 || echo '?')"
for f in "$HOME/.claude/settings.json" ${CLAUDE_CONFIG_DIR:+"$CLAUDE_CONFIG_DIR/settings.json"}; do
  if [[ -r "$f" ]] && grep -q 'HOLACRACY_GROUNDING_ASSUME_GLASSFROG' "$f"; then
    rec "- NOTE: \`$f\` still sets HOLACRACY_GROUNDING_ASSUME_GLASSFROG. This script bypasses it; the manual fresh-session check below does not, so remove it first."
  fi
done
rec ""

# ---- 1 ----------------------------------------------------------------------
say ""
say "== 1. Keychain path alone (file pointed at /nonexistent) =="
say "   macOS may show a Keychain access dialog now. If it does, note it: AC1"
say "   requires that a SessionStart hook triggers none. Choose Deny to keep the"
say "   result honest; Always Allow would make every later run look clean."
rec "### 1. Keychain path alone opens the gate"
o="$(hook_outcome HOLACRACY_GROUNDING_KEYCHAIN=on HOLACRACY_GROUNDING_CREDENTIALS_FILE="$NOCRED")"
if [[ "$o" == directive ]]; then
  verdict PASS "Keychain only (file disabled): directive injected"
else
  verdict FAIL "Keychain only (file disabled): got \`$o\`, expected \`directive\`"
fi
o="$(hook_outcome)"
if [[ "$o" == directive ]]; then
  verdict PASS "defaults (auto): directive injected"
else
  verdict FAIL "defaults (auto): got \`$o\`, expected \`directive\`"
fi
read -r -p "   Did a Keychain dialog appear during check 1? [y/N] " ans
if [[ "$ans" =~ ^[Yy] ]]; then
  verdict FAIL "a Keychain authorization dialog appeared on the hook's read"
else
  verdict PASS "no Keychain authorization dialog"
fi
rec ""
rec "Redacted structure of \`$SERVICE\` (shape only, no values):"
rec '```'
shape="$(security find-generic-password -s "$SERVICE" -w 2>/dev/null | python3 -c "$SHAPE_PY")"
rc=$?
rec "$shape"
rec '```'
say "$shape"
if [[ $rc -eq 0 ]]; then
  verdict PASS "item parses and holds an authenticated glassfrog entry"
else
  verdict FAIL "item shape differs from what the parser expects (rc=$rc; 6 = no glassfrog entry, 7 = entry not authenticated) -- AC4: fix the parser against the structure above"
fi
rec ""

# ---- 2 ----------------------------------------------------------------------
say ""
say "== 2. Keychain off: the file alone =="
rec "### 2. HOLACRACY_GROUNDING_KEYCHAIN=off"
cred="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
if [[ -e "$cred" ]]; then
  rec "- file: \`${cred/#$HOME/~}\`, last modified $(stat -f '%Sm' -t '%Y-%m-%d' "$cred")"
else
  rec "- file: \`${cred/#$HOME/~}\` absent"
fi
o="$(hook_outcome HOLACRACY_GROUNDING_KEYCHAIN=off)"
if [[ "$o" == conditional ]]; then
  verdict PASS "Keychain off: conditional directive emitted"
else
  verdict FAIL "Keychain off: got \`$o\`, expected \`conditional\` (if the file is fresh and valid this is not a gate bug -- say so in the issue)"
fi
rec ""

# ---- 3 ----------------------------------------------------------------------
say ""
say "== 3. Hot-path cost ($RUNS runs per mode, interleaved) =="
rec "### 3. Hot-path cost"
rec "| path | median ms / session start |"
rec "|---|---|"
T=()
while IFS=$'\t' read -r label ms; do
  rec "| $label | $ms |"
  T+=("$ms")
done < <(python3 -c "$TIME_PY" "$HOOK" "$RUNS" "$NOCRED")
sec_ms="$(python3 -c "$SECURITY_TIME_PY" "$SERVICE" "$RUNS")"
rec "| \`security find-generic-password\` alone | $sec_ms |"
if [[ ${#T[@]} -eq 5 ]]; then
  vs_file="$(python3 -c "print('%+.1f' % (${T[4]} - ${T[2]}))")"
  vs_none="$(python3 -c "print('%+.1f' % (${T[4]} - ${T[0]}))")"
  verdict INFO "default path costs $vs_file ms vs the file-only path, $vs_none ms vs no store read (medians of $RUNS); record in ADR-0008 A6"
else
  verdict FAIL "timing produced ${#T[@]} of 5 rows"
fi
rec ""

# ---- 4 ----------------------------------------------------------------------
say ""
say "== 4. CLAUDE_CONFIG_DIR and the Keychain service name =="
rec "### 4. Keychain service names (names only)"
names="$(service_names)"
total="$(printf '%s\n' "$names" | grep -c . | tr -d ' ')"
profiles="$(printf '%s\n' "$names" | grep -c 'credentials-[0-9a-f]\{8\}"' | tr -d ' ')"
rec "- $total item(s) named \`Claude Code-credentials*\`, $profiles of them per-profile"
if [[ -n "$CONFIG_DIR" ]]; then
  # Same derivation as the hook's _keychain_service. Compared against the
  # expected NAME, never a before/after diff: the first live run's "before"
  # snapshot came back with 1 of 464 names and reported 463 as new.
  expected="Claude Code-credentials-$(printf '%s' "$CONFIG_DIR" | shasum -a 256 | cut -c1-8)"
  say "   Expected per-profile item: $expected"
  if ! printf '%s\n' "$names" | grep -qxF "\"$expected\""; then
    say "   Not present yet. In ANOTHER terminal run:"
    say "     CLAUDE_CONFIG_DIR=$CONFIG_DIR claude"
    say "   then authenticate glassfrog via /mcp, exit, and press Enter here."
    read -r -p "   Press Enter when done... " _
    names="$(service_names)"
  fi
  if printf '%s\n' "$names" | grep -qxF "\"$expected\""; then
    verdict PASS "\`$CONFIG_DIR\` keeps its own item, \`$expected\` (sha256 of the literal dir, first 8 hex)"
    o="$(hook_outcome CLAUDE_CONFIG_DIR="$CONFIG_DIR" HOLACRACY_GROUNDING_CREDENTIALS_FILE="$NOCRED")"
    if [[ "$o" == directive ]]; then
      verdict PASS "hook under that CLAUDE_CONFIG_DIR reads its own item: directive"
    else
      verdict FAIL "hook under that CLAUDE_CONFIG_DIR: got \`$o\` -- it is not reading \`$expected\`"
    fi
  else
    verdict FAIL "no item named \`$expected\` after authenticating under \`$CONFIG_DIR\` -- the naming scheme is not sha256(dir)[:8]; capture the new name"
  fi
else
  verdict INFO "not exercised (pass --config-dir DIR to test a non-default profile)"
fi
rec ""

# ---- 5 ----------------------------------------------------------------------
# With the login keychain LOCKED, a `security find-generic-password` from a GUI
# session raises the macOS unlock dialog and blocks until it is answered: the
# first live run measured 8491 ms and a password dialog (#319). So the question
# is not only "does the hook return" but "which probe can tell the keychain is
# locked WITHOUT prompting", so the hook can skip the read. Each candidate runs
# against the locked keychain under a 10 s cap, and you report whether a dialog
# appeared. Press Cancel on any dialog: entering the password unlocks the
# keychain and invalidates every probe after it.
say ""
say "== 5. Locked login keychain =="
rec "### 5. Locked login keychain"
KC="$HOME/Library/Keychains/login.keychain-db"

# argv: label, then the command. Runs it with stdout DISCARDED (a probe that
# did read the item must not print it), 10 s cap. Prints "<ms> <rc>".
read -r -d '' PROBE_PY <<'PY'
import subprocess, sys, time
s = time.perf_counter()
try:
    p = subprocess.run(sys.argv[1:], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE, timeout=10)
    rc = str(p.returncode)
except subprocess.TimeoutExpired:
    rc = "timeout"
print("%.0f %s" % ((time.perf_counter() - s) * 1000, rc))
PY

# Lock state from the Security framework (SecKeychainGetStatus). A status
# query, not an item read. Prints "locked" / "unlocked" / "error:<rc>".
read -r -d '' STATUS_PY <<'PY'
import ctypes, ctypes.util, sys
sec = ctypes.cdll.LoadLibrary(ctypes.util.find_library("Security"))
kc = ctypes.c_void_p(); st = ctypes.c_uint32()
if sec.SecKeychainOpen(ctypes.c_char_p(sys.argv[1].encode()), ctypes.byref(kc)) != 0:
    print("error:open"); sys.exit(1)
rc = sec.SecKeychainGetStatus(kc, ctypes.byref(st))
print("error:%d" % rc if rc else ("unlocked" if st.value & 1 else "locked"))
PY

if [[ $LOCK_TEST -eq 1 ]]; then
  say "   This LOCKS your login keychain. Other apps (including running Claude"
  say "   sessions) may prompt or fail until you unlock it again at the end."
  say "   For EVERY dialog that appears during the probes, press Cancel."
  read -r -p "   Lock it now? [y/N] " ans
  if [[ "$ans" =~ ^[Yy] ]]; then
    security lock-keychain "$KC"
    rec "| probe (keychain locked) | ms | result | dialog? |"
    rec "|---|---|---|---|"

    say ""
    say "   Probe: SecKeychainGetStatus via python3 ctypes"
    st="$(python3 -c "$STATUS_PY" "$KC" 2>&1 | tail -1)"
    read -r -p "   Did a keychain dialog appear for this probe? (Cancel it if so) [y/N] " ans
    d=no; [[ "$ans" =~ ^[Yy] ]] && d=YES
    rec "| SecKeychainGetStatus (ctypes) | - | $st | $d |"
    say "   -> $st, dialog=$d"

    # The hook itself, as shipped in this checkout. Judged on TIME, not on the
    # dialog question: while the keychain is locked every running Claude Code
    # session asks for it too, so a dialog on screen cannot be pinned to one
    # process. A hook that skipped the read finishes in ~150 ms; one that read
    # and hit the 1 s limit takes ~1 s; one with no limit waits for Cancel.
    say ""
    say "   Probe: the hook (this checkout), keychain locked"
    hres="$(python3 -c "$PROBE_PY" env -u HOLACRACY_GROUNDING_KEYCHAIN_LOCKED \
      -u HOLACRACY_GROUNDING_ASSUME_GLASSFROG bash "$HOOK")"
    read -r hms hrc <<<"$hres"
    read -r -p "   Did a NEW dialog appear the moment this probe ran? (Cancel it) [y/N] " ans
    hd=no; [[ "$ans" =~ ^[Yy] ]] && hd=YES
    rec "| the hook (this checkout) | $hms | $hrc | $hd |"
    if [[ "$hms" == timeout ]] || [[ "$hms" -ge 1500 ]]; then
      verdict FAIL "locked keychain: hook took ${hms} ms -- neither the lock check nor the time limit held"
    elif [[ "$hms" -ge 500 ]]; then
      verdict FAIL "locked keychain: hook took ${hms} ms -- the time limit caught it, but the lock check did not skip the read"
    else
      verdict PASS "locked keychain: hook returned in ${hms} ms without reading the keychain"
    fi
    if [[ "$st" == locked ]]; then
      verdict PASS "SecKeychainGetStatus reports the keychain locked"
    else
      verdict FAIL "SecKeychainGetStatus reported \`$st\` for a locked keychain"
    fi

    say ""
    say "   Unlocking -- enter your login password when prompted:"
    security unlock-keychain "$KC"
  else
    verdict INFO "skipped at the prompt"
  fi
else
  verdict INFO "not exercised (pass --lock-test)"
fi
rec ""

# ---- manual corroboration ----------------------------------------------------
rec "### Manual: a real fresh session"
rec "- [ ] With HOLACRACY_GROUNDING_ASSUME_GLASSFROG removed from settings.json, a fresh \`claude\` session in another repo opens with the role-grounding directive (not the conditional form)."
rec ""

say ""
say "================ report ================"
printf '%s' "$REPORT"
if [[ -n "$OUT" ]]; then
  printf '%s' "$REPORT" > "$OUT"
  say "(written to $OUT)"
fi
exit "$FAILED"
