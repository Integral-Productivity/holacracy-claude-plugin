#!/usr/bin/env python3
"""Turn a real GlassFrog MCP response into a schema carrying no real values.

    scripts/glassfrog-schema-capture.py --tool list_my_roles < response.json
    scripts/glassfrog-schema-capture.py --assert-clean < schema.json

WHY THIS IS A FILTER AND NOT A CLIENT
-------------------------------------
It reads stdin. It does not speak to GlassFrog. The MCP server is OAuth-protected
and its tools are available to an *agent session*, not to an arbitrary script, so
"capture" means: a human (or an agent with the connector) obtains one response and
pipes it through here. The tool's whole job is type erasure.

That split is also the safety property. The real response exists only in a pipe
and whatever temporary file the operator used; the only thing that reaches the
repository is the output of this program, which by construction contains no values.

WHY SCHEMA AND NOT REDACTED VALUES
----------------------------------
#170 originally said "record live responses, redact tension bodies." Probing the
live API showed that far too narrow. One `list_my_roles` record carries
`fillers[].name` and `fillers[].email` -- real PII repeated across all 81 roles --
plus `purpose`, `accountabilities[].description` and `domains[].description`,
which together are a readable map of the organization's strategy. Redacting all
of that means substituting essentially every string in the payload, at which
point the only thing genuinely recorded is the schema.

So capture the schema and generate the content. A redaction pass fails by missing
a field, and a missed field publishes an email to a public repository. This has no
equivalent failure mode: there is no path by which a real value reaches the output.

WHAT IS PRESERVED
-----------------
Key names, nesting, and the presence/absence of every field -- which is the part
that carries the value. A field that appears on only some array elements is typed
`<type>|absent`, so optionality survives. That is exactly the class of surprise
schema capture exists to find.

Array cardinality is deliberately NOT preserved: arrays collapse to a single
merged element schema. How many roles the real org has is not schema, and the
scenario spec decides cardinality for generated fixtures anyway.
"""

import argparse
import json
import sys

SCALARS = {
    type(None): "null",
    bool: "boolean",
    int: "integer",
    float: "number",
    str: "string",
}
# Every token a leaf is permitted to be, including the union forms merging
# produces. --assert-clean is the leak guard's primitive: if a leaf is not in
# here, something that is not a type name survived into the schema.
VALID_LEAF_TOKENS = set(SCALARS.values()) | {"absent", "unknown"}


def _merge_token(a: str, b: str) -> str:
    """Union two type tokens, order-independent and idempotent."""
    if a == b:
        return a
    return "|".join(sorted(set(a.split("|")) | set(b.split("|"))))


def _merge(a, b):
    """Union two schemas produced by schema_of()."""
    if isinstance(a, dict) and isinstance(b, dict):
        out = {}
        for key in sorted(set(a) | set(b)):
            if key in a and key in b:
                out[key] = _merge(a[key], b[key])
            else:
                # Present on one element and not the other: optionality is real
                # schema information and must survive.
                present = a.get(key, b.get(key))
                out[key] = (
                    _merge_token(present, "absent")
                    if isinstance(present, str)
                    else present
                )
        return out
    if isinstance(a, list) and isinstance(b, list):
        if not a:
            return b
        if not b:
            return a
        return [_merge(a[0], b[0])]
    if isinstance(a, str) and isinstance(b, str):
        return _merge_token(a, b)
    # Shape disagreement (e.g. object here, string there). Keep the richer side
    # rather than silently dropping structure.
    return a if isinstance(a, (dict, list)) else b


def schema_of(value):
    """Replace every scalar with the name of its type."""
    if isinstance(value, dict):
        return {k: schema_of(v) for k, v in sorted(value.items())}
    if isinstance(value, list):
        if not value:
            return []
        merged = schema_of(value[0])
        for element in value[1:]:
            merged = _merge(merged, schema_of(element))
        return [merged]
    # bool before int: bool is a subclass of int in Python and would otherwise
    # be typed "integer", losing a real distinction.
    for py_type, name in SCALARS.items():
        if type(value) is py_type:
            return name
    return "unknown"


def leaks(node, path="$"):
    """Yield paths whose leaf is not a type token. Empty means clean."""
    if isinstance(node, dict):
        for key, child in node.items():
            yield from leaks(child, f"{path}.{key}")
    elif isinstance(node, list):
        for child in node:
            yield from leaks(child, f"{path}[]")
    elif isinstance(node, str):
        if any(part not in VALID_LEAF_TOKENS for part in node.split("|")):
            yield path, node
    else:
        yield path, repr(node)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tool", help="tool name, recorded in the output header")
    parser.add_argument(
        "--assert-clean",
        action="store_true",
        help="read a schema on stdin and exit non-zero if any leaf is not a type name",
    )
    args = parser.parse_args()

    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"stdin is not valid JSON: {exc}", file=sys.stderr)
        return 2

    if args.assert_clean:
        found = list(leaks(payload.get("schema", payload)))
        for path, value in found:
            print(f"LEAK {path} = {value!r}", file=sys.stderr)
        if found:
            print(f"{len(found)} non-type leaf value(s)", file=sys.stderr)
            return 1
        print("schema is clean: every leaf is a type name")
        return 0

    schema = schema_of(payload)

    # Self-check before writing. A bug in schema_of() that let a value through
    # would otherwise be discovered by a human reading a committed file, which
    # is one commit too late.
    found = list(leaks(schema))
    if found:
        for path, value in found:
            print(f"LEAK {path} = {value!r}", file=sys.stderr)
        print("refusing to emit: type erasure did not fully apply", file=sys.stderr)
        return 1

    json.dump(
        {
            "tool": args.tool or "unknown",
            "note": "Type names only. Generated by scripts/glassfrog-schema-capture.py; never hand-edited with real values.",
            "schema": schema,
        },
        sys.stdout,
        indent=2,
        sort_keys=False,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
