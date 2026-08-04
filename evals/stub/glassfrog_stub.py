#!/usr/bin/env python3
"""A stdio MCP server that serves one synthetic GlassFrog fixture.

    GLASSFROG_STUB_FIXTURE=evals/fixtures/glassfrog/<name>.json \
    GLASSFROG_STUB_WRITE_LOG=/tmp/writes.jsonl \
      python3 evals/stub/glassfrog_stub.py

WHY A REAL MCP SERVER
---------------------
`run_eval.py` in the skill-creator harness shells out to real `claude -p` with
`cwd=<project root>`, so a project-scoped `.mcp.json` in the eval's temp
directory points here instead of at the live connector. The eval then exercises
the ACTUAL command path -- skill load, tool selection, argument construction --
rather than a simulation of it. A mock at the reasoning layer would test the
prompt and miss everything the plugin actually does wrong.

READS ARE COMPUTED, NOT CANNED
------------------------------
Every response is derived from the fixture's org graph at call time. This is what
lets the stub reproduce the defect in
glassfrog-mcp-server#122: `list_subrole_tensions` is documented recursive -- its
own tool description still says so -- and returns DIRECT CHILDREN ONLY, with
`has_next_page: false` to suppress suspicion. A single root call against the real
org found 21 of 47 tensions.

The stub reproduces that faithfully, on purpose. An eval that asserts a command
sweeps circle-by-circle is worthless against a stub that quietly does the
recursion the real API refuses to do.

WRITES ARE RECORDED AND SUCCEED
-------------------------------
Two golden cases assert write ORDERING -- "write the successor before archiving
the original", "no write without an explicit confirmation" -- and ordering can
only be checked against a log. So writes append `{seq, tool, args}` to the write
log and return a plausible success with a synthetic id.

One write is deliberately NOT accommodating: `update_tension` rejects
`meeting_type` with 422, exactly as the live API does (verified 2026-08-04, see
glassfrog-mcp-server#123 comment 5149496749). A stub that accepted it would let a
skill pass an eval by doing something that fails in production, which is worse
than having no eval.
"""

import json
import os
import sys
from pathlib import Path

PROTOCOL_VERSION = "2024-11-05"
FIXTURE = json.loads(Path(os.environ["GLASSFROG_STUB_FIXTURE"]).read_text())
WRITE_LOG = os.environ.get("GLASSFROG_STUB_WRITE_LOG")
_seq = 0

ROLES = {r["id"]: r for r in FIXTURE["roles"]}
TENSIONS = {t["id"]: t for t in FIXTURE["tensions"]}

READ_TOOLS = {
    "glassfrog_get_me": "Return the authenticated actor, organization and membership.",
    "glassfrog_list_my_roles": "List roles the actor fills.",
    "glassfrog_get_role_context": "Purpose, accountabilities, domains and fillers of a role.",
    "glassfrog_list_role_domains": "Domains owned by a role.",
    "glassfrog_list_role_tensions": "Tensions sensed directly on a role.",
    "glassfrog_list_subrole_tensions": "Tensions sensed on sub-roles of a role (documented recursive).",
    "glassfrog_get_tension": "Fetch one tension by id.",
}
WRITE_TOOLS = {
    "glassfrog_create_tension": "Create a tension on a role. Args: role_id, body.",
    "glassfrog_update_tension": "Update a tension. Args: tension_id, and body and/or status.",
    "glassfrog_create_role_project": "Create a project on a role. Args: role_id, description, status.",
    "glassfrog_create_action": "Create an action. Args: role_id, description, parent_project_id, status.",
}


def record_write(tool, args):
    global _seq
    _seq += 1
    if WRITE_LOG:
        with open(WRITE_LOG, "a") as fh:
            fh.write(json.dumps({"seq": _seq, "tool": tool, "args": args}) + "\n")
    return _seq


def page(items, args, prefix):
    """Cursor pagination matching the live envelope."""
    per_page = args.get("per_page", 50)
    cursor = args.get("cursor")
    if cursor:
        ids = [i["id"] for i in items]
        items = items[ids.index(cursor) + 1:] if cursor in ids else []
    window, rest = items[:per_page], items[per_page:]
    return {
        "items": window,
        "pagination": {
            "per_page": per_page,
            "has_next_page": bool(rest),
            "next_cursor": window[-1]["id"] if window and rest else None,
        },
    }


def handle_tool(name, args):
    actor = FIXTURE["actor"]

    if name == "glassfrog_get_me":
        return {"data": {
            "actor": actor,
            "organization": FIXTURE["organization"],
            "membership": {
                "id": "mem_" + "0" * 32, "type": "membership",
                "actor_id": actor["id"],
                "organization_id": FIXTURE["organization"]["id"],
                "access_level": "admin",
                "created_at": actor["created_at"], "updated_at": actor["updated_at"],
            },
        }}

    if name == "glassfrog_list_my_roles":
        filled = [r for r in FIXTURE["roles"] if r["fillers"]]
        return page(filled, args, "role")

    if name == "glassfrog_get_role_context":
        role = ROLES.get(args.get("role_id"))
        if not role:
            return {"error": {"status": 404, "message": "role not found"}}
        return {"data": role}

    if name == "glassfrog_list_role_domains":
        role = ROLES.get(args.get("role_id"))
        if not role:
            return {"error": {"status": 404, "message": "role not found"}}
        domains = [
            {"id": d["id"], "type": "domain", "description": d["description"],
             "role_id": role["id"], "created_at": actor["created_at"],
             "updated_at": actor["updated_at"]}
            for d in role["domains"]
        ]
        return page(domains, args, "dom")

    if name == "glassfrog_list_role_tensions":
        role_id = args.get("role_id")
        status = args.get("status")
        found = [t for t in FIXTURE["tensions"] if t["role_id"] == role_id
                 and (status is None or t["status"] == status)]
        return page(found, args, "ten")

    if name == "glassfrog_list_subrole_tensions":
        # DIRECT CHILDREN ONLY -- see the module docstring. Reproducing
        # glassfrog-mcp-server#122 is the point, not an oversight.
        parent = args.get("role_id")
        status = args.get("status")
        child_ids = {r["id"] for r in FIXTURE["roles"] if r["parent_role_id"] == parent}
        found = [t for t in FIXTURE["tensions"] if t["role_id"] in child_ids
                 and (status is None or t["status"] == status)]
        return page(found, args, "ten")

    if name == "glassfrog_get_tension":
        tension = TENSIONS.get(args.get("tension_id"))
        if not tension:
            return {"error": {"status": 404, "message": "tension not found"}}
        return {"data": tension}

    if name == "glassfrog_update_tension":
        if "meeting_type" in args:
            # Live behaviour, verified 2026-08-04. Do not "fix" this.
            record_write(name, args)
            return {"error": {
                "status": 422,
                "message": "meeting_type is not writable via the API; set it in the GlassFrog UI",
            }}
        seq = record_write(name, args)
        tension = TENSIONS.get(args.get("tension_id"))
        if not tension:
            return {"error": {"status": 404, "message": "tension not found"}}
        updated = {**tension, **{k: v for k, v in args.items() if k in ("body", "status")}}
        TENSIONS[updated["id"]] = updated
        return {"data": updated, "_stub_write_seq": seq}

    if name in WRITE_TOOLS:
        seq = record_write(name, args)
        prefix = {
            "glassfrog_create_tension": "ten",
            "glassfrog_create_role_project": "proj",
            "glassfrog_create_action": "actn",
        }[name]
        new_id = f"{prefix}_{seq:032x}"
        created = {"id": new_id, "type": prefix, **args, "status": args.get("status", "unprocessed")}
        if prefix == "ten":
            TENSIONS[new_id] = {
                "id": new_id, "type": "tension", "body": args.get("body", ""),
                "status": "unprocessed", "role_id": args.get("role_id"),
                "sensed_by_id": actor["id"],
                "created_at": actor["created_at"], "updated_at": actor["updated_at"],
            }
        return {"data": created, "_stub_write_seq": seq}

    return {"error": {"status": 400, "message": f"stub does not implement {name}"}}


def tool_list():
    def entry(name, desc, props, required):
        return {"name": name, "description": desc,
                "inputSchema": {"type": "object", "properties": props, "required": required}}
    s = {"type": "string"}
    out = []
    for name, desc in READ_TOOLS.items():
        props, required = {}, []
        if "role" in name and name != "glassfrog_list_my_roles":
            props["role_id"] = s
            required = ["role_id"]
        if name == "glassfrog_get_tension":
            props["tension_id"] = s
            required = ["tension_id"]
        if "tensions" in name:
            props["status"] = s
        props.update({"per_page": {"type": "integer"}, "cursor": s})
        out.append(entry(name, desc, props, required))
    for name, desc in WRITE_TOOLS.items():
        props = {"role_id": s, "tension_id": s, "body": s, "status": s,
                 "description": s, "parent_project_id": s, "meeting_type": s}
        out.append(entry(name, desc, props, []))
    return out


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        method, msg_id = msg.get("method"), msg.get("id")

        if method == "initialize":
            result = {"protocolVersion": PROTOCOL_VERSION,
                      "capabilities": {"tools": {}},
                      "serverInfo": {"name": "glassfrog-stub", "version": "1.0.0"}}
        elif method == "tools/list":
            result = {"tools": tool_list()}
        elif method == "tools/call":
            params = msg.get("params", {})
            payload = handle_tool(params.get("name"), params.get("arguments", {}) or {})
            result = {"content": [{"type": "text", "text": json.dumps(payload, indent=2)}],
                      "isError": "error" in payload}
        elif msg_id is None:
            continue  # notification
        else:
            result = {}

        if msg_id is not None:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": msg_id, "result": result}) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
