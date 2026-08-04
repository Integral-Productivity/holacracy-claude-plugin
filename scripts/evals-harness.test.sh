#!/usr/bin/env bash
# Regression tests for the behavioural-eval fixture harness:
# scripts/glassfrog-schema-capture.py, scripts/glassfrog-fixture-gen.py, and
# evals/stub/glassfrog_stub.py.
#
# Run: bash scripts/evals-harness.test.sh
# No framework — plain asserts. Exits non-zero on first failure.
#
# THE GUARD THAT MATTERS MOST
# ---------------------------
# Section 2 is the leak guard. Everything else here protects correctness; that
# section protects a real organization's data from a public repository.
#
# #170 originally proposed recording live responses and redacting them. Probing
# the live API showed why that was wrong: one `list_my_roles` record carries
# `fillers[].name` and `fillers[].email` — PII repeated across all 81 roles —
# plus purposes, accountabilities and domains that together read as a map of the
# org's strategy. A redaction pass fails by missing a field, and a missed field
# is published. Capturing schemas and generating content has no such failure
# mode, and section 2 is what proves the property holds rather than assuming it.
#
# A leak is also not undone by a later commit: it is in git history. So this runs
# against the whole of evals/, not just files a given change touched.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
CAPTURE="$HERE/glassfrog-schema-capture.py"
GEN="$HERE/glassfrog-fixture-gen.py"
STUB="$REPO/evals/stub/glassfrog_stub.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
CASES=0
pass() { CASES=$((CASES + 1)); }

FIXTURE="$REPO/evals/fixtures/glassfrog/authority-already-held.json"
key() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['key_map'][sys.argv[2]])" "$FIXTURE" "$1"; }

# Drive the stub with a here-doc of JSON-RPC lines; print each result payload.
stub_call() {  # stdin = jsonrpc lines, $1 = write log path (optional)
  GLASSFROG_STUB_FIXTURE="$FIXTURE" \
  GLASSFROG_STUB_WRITE_LOG="${1:-}" \
    python3 "$STUB"
}

# ---------------------------------------------------------------------------
# 1. Schema capture erases every scalar.
# ---------------------------------------------------------------------------
cat > "$TMP/real.json" <<'JSON'
{"data":{"actor":{"name":"Kraig Parkinson","email":"kraig@example.com","kind":"human"},
 "counts":{"roles":81,"active":true},"nothing":null}}
JSON
python3 "$CAPTURE" --tool probe < "$TMP/real.json" > "$TMP/schema.json" \
  || fail "capture failed on a well-formed response"
grep -qiE "kraig|example\.com|81" "$TMP/schema.json" \
  && fail "capture leaked a real value into its output"
python3 -c "
import json,sys
s=json.load(open('$TMP/schema.json'))['schema']['data']
assert s['actor']['email']=='string', s
assert s['counts']['roles']=='integer', s
assert s['counts']['active']=='boolean', s   # bool must not be typed integer
assert s['nothing']=='null', s
" || fail "capture produced wrong type names"
pass

# 1b. Optionality survives: a key on only some array elements is typed |absent.
printf '{"items":[{"a":"x","b":"y"},{"a":"z"}]}\n' > "$TMP/opt.json"
python3 "$CAPTURE" < "$TMP/opt.json" \
  | python3 -c "
import json,sys
b=json.load(sys.stdin)['schema']['items'][0]['b']
assert 'absent' in b, b" \
  || fail "capture lost field optionality when merging array elements"
pass

# 1c. --assert-clean is the primitive the leak guard leans on, so it must be
#     able to FAIL. A schema with a real value in it has to be rejected.
printf '{"schema":{"email":"kraig@example.com"}}\n' > "$TMP/dirty.json"
python3 "$CAPTURE" --assert-clean < "$TMP/dirty.json" >/dev/null 2>&1 \
  && fail "--assert-clean passed a schema containing a real value"
python3 "$CAPTURE" --assert-clean < "$TMP/schema.json" >/dev/null 2>&1 \
  || fail "--assert-clean rejected a genuinely clean schema"
pass

# ---------------------------------------------------------------------------
# 2. LEAK GUARD — nothing under evals/ carries real organizational data.
# ---------------------------------------------------------------------------
# Emails. The single highest-value signal: every role record carries one.
if grep -rEn '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$REPO/evals/" \
     | grep -v '@example\.invalid' | grep -v '@example\.com' | grep -q .; then
  grep -rEn '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$REPO/evals/" \
    | grep -v '@example\.invalid' | grep -v '@example\.com'
  fail "an email address that is not a reserved example domain appears under evals/"
fi
pass

# The real organization's own strings. If any of these appear in a fixture,
# something was recorded that should have been generated.
for needle in "Integral Productivity" "Kraig Parkinson" "integralproductivity" \
              "Crisis Response Protocol" "Coaching Session Data" "Strategyzer"; do
  grep -rqF "$needle" "$REPO/evals/fixtures/" "$REPO/evals/scenarios/" 2>/dev/null \
    && fail "real organizational string '$needle' appears in a fixture or scenario"
done
pass

# Live ids. Synthetic ids are sha256-derived, so a *specific* live id appearing
# would mean a recorded response leaked through.
for live_id in role_81f4328624e445ba8edc8812f74dec7b \
               per_9419ceadf6214513abc93651183ce957 \
               org_13a747d808864b1c99fe7f47c3a5bc34; do
  grep -rqF "$live_id" "$REPO/evals/" 2>/dev/null \
    && fail "live GlassFrog id $live_id appears under evals/"
done
pass

# Every committed schema is clean by its own checker.
for f in "$REPO"/evals/fixtures/schema/*.json; do
  python3 "$CAPTURE" --assert-clean < "$f" >/dev/null 2>&1 \
    || fail "committed schema $(basename "$f") contains a non-type leaf"
done
pass

# ---------------------------------------------------------------------------
# 3. Fixture generation.
# ---------------------------------------------------------------------------
# Deterministic: same spec, byte-identical output, so eval assertions can name
# an id literally without a regeneration invalidating them.
python3 "$GEN" "$REPO/evals/scenarios/authority-already-held.json" --stdout > "$TMP/g1.json" \
  || fail "generator failed on the shipped scenario"
python3 "$GEN" "$REPO/evals/scenarios/authority-already-held.json" --stdout > "$TMP/g2.json"
diff -q "$TMP/g1.json" "$TMP/g2.json" >/dev/null || fail "generator is not deterministic"
diff -q "$TMP/g1.json" "$FIXTURE" >/dev/null \
  || fail "committed fixture is stale — regenerate it from its scenario"
pass

# A typo'd spec key must be an error. Silently dropping it would leave the author
# wondering why the fixture lacks the field they wrote — and, worse, would let a
# scenario that *looks* like it models a case quietly not model it.
python3 - "$GEN" "$TMP" <<'PY' || fail "generator silently ignored an unrecognized scenario key"
import json, subprocess, sys
gen, tmp = sys.argv[1], sys.argv[2]
spec = {"scenario": "bad", "actor": {"name": "A", "email": "a@example.invalid"},
        "roles": [{"key": "r", "name": "R", "invented_key": "nope"}]}
open(f"{tmp}/bad.json", "w").write(json.dumps(spec))
r = subprocess.run([sys.executable, gen, f"{tmp}/bad.json", "--stdout"], capture_output=True)
sys.exit(0 if r.returncode != 0 and b"unrecognized spec key" in r.stderr else 1)
PY
pass

# And the generated OBJECT is validated against the captured schema, so a fixture
# cannot drift from the real API shape. Prove that path fires by corrupting the
# schema the generator validates against.
python3 - "$GEN" "$REPO" "$TMP" <<'PY' || fail "generator did not validate generated objects against the captured schema"
import json, shutil, subprocess, sys
gen, repo, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
target = f"{repo}/evals/fixtures/schema/list_role_tensions.json"
shutil.copy(target, f"{tmp}/backup.json")
try:
    doc = json.load(open(target))
    doc["schema"]["items"][0]["a_field_the_api_does_not_return"] = "string"
    json.dump(doc, open(target, "w"))
    r = subprocess.run([sys.executable, gen,
                        f"{repo}/evals/scenarios/authority-already-held.json", "--stdout"],
                       capture_output=True)
    ok = r.returncode != 0 and b"the live schema carries" in r.stderr
finally:
    shutil.copy(f"{tmp}/backup.json", target)
sys.exit(0 if ok else 1)
PY
pass

# The 1-5000 character body constraint is a real API limit.
python3 - "$GEN" "$TMP" <<'PY' || fail "generator accepted an over-long tension body"
import json, subprocess, sys
gen, tmp = sys.argv[1], sys.argv[2]
spec = {"scenario": "long", "actor": {"name": "A", "email": "a@example.invalid"},
        "roles": [{"key": "r", "name": "R"}],
        "tensions": [{"key": "t", "on": "r", "body": "x" * 5001}]}
open(f"{tmp}/long.json", "w").write(json.dumps(spec))
r = subprocess.run([sys.executable, gen, f"{tmp}/long.json", "--stdout"], capture_output=True)
sys.exit(0 if r.returncode != 0 and b"1-5000" in r.stderr else 1)
PY
pass

# ---------------------------------------------------------------------------
# 4. The stub.
# ---------------------------------------------------------------------------
PRODUCT_CIRCLE="$(key role:product-circle)"
PRODUCT_ARCH="$(key role:product-architecture)"
PLATFORM_SUB="$(key role:platform-sub)"
TEN_DOMAIN="$(key ten:domain-held)"
TEN_GRANDCHILD="$(key ten:grandchild)"

# 4a. list_subrole_tensions is NOT recursive — glassfrog-mcp-server#122.
#     A sweep from the top must MISS the grandchild tension. If the stub ever
#     "helpfully" recursed, an eval asserting circle-by-circle sweeping would
#     pass while the shipped command silently lost 55% of a real backlog.
out="$(printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"glassfrog_list_subrole_tensions","arguments":{"role_id":"%s","status":"unprocessed"}}}\n' \
        "$PRODUCT_CIRCLE" | stub_call)"
echo "$out" | grep -qF "$TEN_GRANDCHILD" \
  && fail "stub recursed into grandchildren; it must reproduce the non-recursive live behaviour (#122)"
echo "$out" | grep -qF "$TEN_DOMAIN" \
  || fail "stub did not return a direct child's tension"
# ...and the grandchild IS reachable when its own parent is swept.
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"glassfrog_list_subrole_tensions","arguments":{"role_id":"%s"}}}\n' \
  "$(python3 -c "import json;d=json.load(open('$FIXTURE'));print([r['parent_role_id'] for r in d['roles'] if r['id']=='$PLATFORM_SUB'][0])")" \
  | stub_call | grep -qF "$TEN_GRANDCHILD" \
  || fail "stub failed to return a tension on a direct child of the swept role"
pass

# 4b. Pagination envelope matches the live shape.
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"glassfrog_list_subrole_tensions","arguments":{"role_id":"%s","per_page":1}}}\n' \
  "$PRODUCT_CIRCLE" | stub_call \
  | python3 -c "
import json,sys
p=json.loads(json.load(sys.stdin)['result']['content'][0]['text'])
assert len(p['items'])==1, p['items']
assert p['pagination']['has_next_page'] is True, p['pagination']
assert p['pagination']['next_cursor']==p['items'][0]['id'], p['pagination']" \
  || fail "stub pagination envelope does not match the live shape"
pass

# 4c. meeting_type is rejected with 422 — verified live 2026-08-04. A stub that
#     accepted it would let a skill pass by doing something that fails in
#     production, which is worse than having no eval at all.
# The payload is a JSON string nested inside the JSON-RPC envelope, so it has to
# be parsed rather than grepped — a grep for '"status": 422' silently never
# matches the escaped form, and a test that cannot fail is not a test.
_status() {  # stdin = one jsonrpc line -> prints the payload's error status, or "ok"
  python3 -c "
import json,sys
p=json.loads(json.load(sys.stdin)['result']['content'][0]['text'])
print(p['error']['status'] if 'error' in p else 'ok')"
}
got="$(printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"glassfrog_update_tension","arguments":{"tension_id":"%s","meeting_type":"governance"}}}\n' \
        "$TEN_DOMAIN" | stub_call | _status)"
[ "$got" = "422" ] || fail "stub returned '$got' for meeting_type; the live API 422s it"
# The same call minus the field succeeds — the contrast is the finding.
got="$(printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"glassfrog_update_tension","arguments":{"tension_id":"%s","status":"archived"}}}\n' \
        "$TEN_DOMAIN" | stub_call | _status)"
[ "$got" = "ok" ] || fail "stub returned '$got' for an update_tension call carrying no meeting_type"
pass

# 4d. Writes are logged IN ORDER with arguments intact. Two golden cases assert
#     ordering — successor before archive, and no write before confirmation —
#     and neither is checkable without this log.
LOG="$TMP/writes.jsonl"; : > "$LOG"
{
  printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"glassfrog_create_tension","arguments":{"role_id":"%s","body":"successor cites the archived original"}}}\n' "$PRODUCT_ARCH"
  printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"glassfrog_update_tension","arguments":{"tension_id":"%s","status":"archived"}}}\n' "$TEN_DOMAIN"
} | stub_call "$LOG" >/dev/null
python3 -c "
import json
rows=[json.loads(l) for l in open('$LOG')]
assert [r['seq'] for r in rows]==[1,2], rows
assert rows[0]['tool']=='glassfrog_create_tension', rows[0]
assert rows[1]['tool']=='glassfrog_update_tension', rows[1]
assert rows[1]['args']['status']=='archived', rows[1]
assert 'successor' in rows[0]['args']['body'], rows[0]
" || fail "stub write log lost ordering or arguments"
pass

# 4e. A read must never appear in the write log, or 'no write without
#     confirmation' becomes unassertable.
LOG2="$TMP/reads.jsonl"; : > "$LOG2"
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"glassfrog_list_my_roles","arguments":{}}}\n' \
  | stub_call "$LOG2" >/dev/null
[ -s "$LOG2" ] && fail "a read call was recorded in the write log"
pass

# 4f. tools/list advertises every tool the stub implements, and initialize
#     answers — without both, claude -p never reaches the tools at all.
printf '%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
                  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | stub_call | python3 -c "
import json,sys
msgs=[json.loads(l) for l in sys.stdin]
assert msgs[0]['result']['serverInfo']['name']=='glassfrog-stub', msgs[0]
names={t['name'] for t in msgs[1]['result']['tools']}
for required in ('glassfrog_get_me','glassfrog_list_my_roles','glassfrog_list_subrole_tensions',
                 'glassfrog_create_tension','glassfrog_update_tension'):
    assert required in names, (required, sorted(names))" \
  || fail "stub initialize/tools-list handshake is incomplete"
pass

echo "evals-harness.test.sh: $CASES cases passed"
