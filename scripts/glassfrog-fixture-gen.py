#!/usr/bin/env python3
"""Build a synthetic GlassFrog fixture from a scenario spec and captured schemas.

    scripts/glassfrog-fixture-gen.py evals/scenarios/<name>.json
        -> evals/fixtures/glassfrog/<name>.json

WHAT A FIXTURE IS
-----------------
Not a pile of canned per-tool responses. One synthetic *organization* -- actor,
roles with parents and domains, tensions attached to roles -- from which
`evals/stub/glassfrog_stub.py` computes every read response at call time.

That matters for one case in particular. `list_subrole_tensions` is documented
recursive and returns direct children only
(glassfrog-mcp-server#122); a canned-response fixture would encode whichever
answer its author believed, while a computed one lets the stub reproduce the real
traversal depth. The bug has to be reproducible for the circle-sweep eval to mean
anything.

WHY THE SCHEMAS ARE AN INPUT AND NOT AN ARCHIVE
-----------------------------------------------
Every generated object is validated against the captured schema for its type, so
a fixture cannot drift from the real API shape without the generator saying so.
A fixture that has quietly diverged is worse than no fixture: the eval passes and
the shipped skill still breaks against the live API.

DETERMINISTIC IDS
-----------------
`sha256(scenario + ":" + entity_key)`, truncated to 32 hex, prefixed per type.
Regenerating produces byte-identical ids, so an eval assertion can name an id
literally without a regeneration invalidating it.

NO REAL CONTENT, BY CONSTRUCTION
--------------------------------
Every string in a fixture comes from the scenario spec, which is hand-authored
and synthetic. Nothing here reads live GlassFrog. See
`scripts/glassfrog-schema-capture.py` for why the project captures schemas rather
than redacting recorded responses.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCHEMA_DIR = REPO / "evals" / "fixtures" / "schema"
OUT_DIR = REPO / "evals" / "fixtures" / "glassfrog"

DEFAULT_TS = "2026-01-01T00:00:00Z"


def synth_id(prefix: str, scenario: str, key: str) -> str:
    digest = hashlib.sha256(f"{scenario}:{key}".encode()).hexdigest()[:32]
    return f"{prefix}_{digest}"


def _schema_keys(schema_file: str, *path: str) -> set:
    """Key set the captured schema says an object of this type carries."""
    doc = json.loads((SCHEMA_DIR / schema_file).read_text())["schema"]
    for step in path:
        doc = doc[0] if step == "[]" else doc[step]
    return set(doc)


def validate(obj: dict, expected: set, what: str, errors: list) -> None:
    """A generated object must carry exactly the keys the real API returns.

    Both directions matter. Missing keys mean the eval exercises a shape the
    skill will not meet in production; extra keys mean the fixture invents
    affordances the API does not offer, and a skill can pass by relying on one.
    """
    got = set(obj)
    for missing in sorted(expected - got):
        errors.append(f"{what}: missing key '{missing}' the live schema carries")
    for extra in sorted(got - expected):
        errors.append(f"{what}: key '{extra}' is not in the live schema")


# A scenario spec is hand-authored, so a typo'd key would otherwise be silently
# dropped and the author would be left wondering why the fixture lacks the field
# they wrote. Unknown keys are an error, not a shrug.
SPEC_KEYS = {"scenario", "purpose", "organization", "actor", "roles", "tensions"}
ROLE_SPEC_KEYS = {"key", "name", "purpose", "parent", "flags", "accountabilities",
                  "domains", "filled_by_actor", "original_role_id"}
TENSION_SPEC_KEYS = {"key", "on", "status", "created_at", "updated_at", "body"}


def check_spec_keys(obj: dict, allowed: set, what: str, errors: list) -> None:
    for extra in sorted(set(obj) - allowed):
        errors.append(f"{what}: unrecognized spec key '{extra}'")


def build(spec: dict) -> tuple:
    scenario = spec["scenario"]
    errors = []
    check_spec_keys(spec, SPEC_KEYS, "scenario", errors)
    for spec_role in spec.get("roles", []):
        check_spec_keys(spec_role, ROLE_SPEC_KEYS, f"role '{spec_role.get('key', '?')}'", errors)
    for spec_tension in spec.get("tensions", []):
        check_spec_keys(spec_tension, TENSION_SPEC_KEYS,
                        f"tension '{spec_tension.get('key', '?')}'", errors)

    actor = {
        "id": synth_id("per", scenario, "actor"),
        "type": "actor",
        "name": spec["actor"]["name"],
        "email": spec["actor"]["email"],
        "kind": "human",
        "created_at": DEFAULT_TS,
        "updated_at": DEFAULT_TS,
    }
    organization = {
        "id": synth_id("org", scenario, "org"),
        "name": spec.get("organization", "Example Org"),
    }

    role_keys = _schema_keys("list_my_roles.json", "items", "[]")
    tension_keys = _schema_keys("list_role_tensions.json", "items", "[]")

    roles, by_key = [], {}
    for spec_role in spec["roles"]:
        key = spec_role["key"]
        role = {
            "id": synth_id("role", scenario, f"role:{key}"),
            "type": "role",
            "name": spec_role["name"],
            "purpose": spec_role.get("purpose", ""),
            "parent_role_id": None,  # resolved below, once every id exists
            "original_role_id": spec_role.get("original_role_id"),
            "has_subroles": False,   # derived below from actual parentage
            "flags": spec_role.get("flags", []),
            "accountabilities": [
                {
                    "id": synth_id("acct", scenario, f"acct:{key}:{i}"),
                    "description": text,
                    "is_structural": False,
                }
                for i, text in enumerate(spec_role.get("accountabilities", []))
            ],
            "domains": [
                {
                    "id": synth_id("dom", scenario, f"dom:{key}:{i}"),
                    "description": text,
                    "is_structural": False,
                }
                for i, text in enumerate(spec_role.get("domains", []))
            ],
            "fillers": [actor] if spec_role.get("filled_by_actor") else [],
            "tags": [],
        }
        validate(role, role_keys, f"role '{key}'", errors)
        roles.append(role)
        by_key[key] = role

    for spec_role in spec["roles"]:
        parent = spec_role.get("parent")
        if not parent:
            continue
        if parent not in by_key:
            errors.append(f"role '{spec_role['key']}': unknown parent '{parent}'")
            continue
        by_key[spec_role["key"]]["parent_role_id"] = by_key[parent]["id"]
        by_key[parent]["has_subroles"] = True

    tensions = []
    for spec_tension in spec.get("tensions", []):
        key = spec_tension["key"]
        on = spec_tension["on"]
        if on not in by_key:
            errors.append(f"tension '{key}': unknown role '{on}'")
            continue
        body = spec_tension["body"]
        if not 1 <= len(body) <= 5000:
            errors.append(
                f"tension '{key}': body is {len(body)} chars; the API accepts 1-5000"
            )
        tension = {
            "id": synth_id("ten", scenario, f"ten:{key}"),
            "type": "tension",
            "body": body,
            "status": spec_tension.get("status", "unprocessed"),
            "role_id": by_key[on]["id"],
            "sensed_by_id": actor["id"],
            "created_at": spec_tension.get("created_at", DEFAULT_TS),
            "updated_at": spec_tension.get("updated_at", DEFAULT_TS),
        }
        validate(tension, tension_keys, f"tension '{key}'", errors)
        tensions.append(tension)

    fixture = {
        "scenario": scenario,
        "note": "Synthetic. Generated by scripts/glassfrog-fixture-gen.py from "
                "evals/scenarios/. Contains no data from any real organization.",
        "purpose": spec.get("purpose", ""),
        "actor": actor,
        "organization": organization,
        "roles": roles,
        "tensions": tensions,
        "key_map": {
            **{f"role:{k}": v["id"] for k, v in by_key.items()},
            **{
                f"ten:{t['key']}": synth_id("ten", scenario, f"ten:{t['key']}")
                for t in spec.get("tensions", [])
            },
        },
    }
    return fixture, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("spec", help="path to a scenario spec under evals/scenarios/")
    parser.add_argument("--out", help="output path (default: evals/fixtures/glassfrog/<scenario>.json)")
    parser.add_argument("--stdout", action="store_true", help="write to stdout instead of a file")
    args = parser.parse_args()

    spec = json.loads(Path(args.spec).read_text())
    fixture, errors = build(spec)

    if errors:
        for err in errors:
            print(f"ERROR {err}", file=sys.stderr)
        print(
            f"{len(errors)} problem(s); no fixture written. A fixture that does not "
            f"match the captured schema would let an eval pass against a shape the "
            f"live API never returns.",
            file=sys.stderr,
        )
        return 1

    text = json.dumps(fixture, indent=2) + "\n"
    if args.stdout:
        sys.stdout.write(text)
    else:
        out = Path(args.out) if args.out else OUT_DIR / f"{fixture['scenario']}.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text)
        print(f"wrote {out.relative_to(REPO) if out.is_relative_to(REPO) else out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
