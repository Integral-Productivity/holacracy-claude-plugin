# GlassFrog ID and URL Resolution -- Shared Reference

How to get from something a user hands you -- a pasted URL, a name, a number -- to a v5 record you can actually call. Loaded by any surface that accepts a user-supplied pointer to a GlassFrog item.

This sits in `skills/shared/` rather than inside one skill's `references/` because every project, tension, and triage surface hits the same wall, and `skills/shared/` is what those surfaces already load.

---

## The constraint: web URLs carry legacy numeric IDs, and only one connector returns them

A GlassFrog web URL identifies a record by a **legacy numeric ID**:

```
https://app.glassfrog.com/organizations/32215/my/workspace/projects/1966547
```

The v5 API identifies records only by prefixed IDs -- `proj_<32hex>`, `actn_<32hex>`, `role_<32hex>`, `ten_<32hex>`, `goal_<32hex>`, and so on. What you can do with the legacy number depends on which connector the session has. There are two:

- **GlassFrog Extended** -- the plugin's own MCP connector, key `glassfrog-extended`, tools such as `glassfrog_get_project` and `glassfrog_list_role_projects`.
- **Official GlassFrog MCP** -- tools such as `glassfrog_getProject`.

Verified live on 2026-10-08 (#353):

- **Forward (v5 ID to web URL) works on GlassFrog Extended only.** Pass `include_legacy_id: true` and the record comes back with `legacy_id` and `web_url` (plus `role_projects_url` for projects). Hand the user the returned `web_url` verbatim; **never construct a URL from `legacy_id`** or from a number the user pasted. `glassfrog_get_project(proj_..., include_legacy_id: true)` returned `legacy_id: 1821228` and a `web_url` ending `/my/workspace/projects/1821228?tab=workspace_projects`. The flag is accepted by `glassfrog_get_project`, `glassfrog_list_role_projects`, `glassfrog_list_role_actions`, `glassfrog_get_action`, `glassfrog_list_my_projects`, and `glassfrog_get_me`.
- **Reverse (pasted URL to record) has no lookup on either connector.** No tool takes a legacy ID as input, the v5 OpenAPI spec has no legacy parameter, and `glassfrog_search("1821228")` returns nothing on both Extended and Official -- search does not index the number. On Extended the number can be *matched* by scanning lists with the flag on; it cannot be *looked up*.
- **The Official GlassFrog MCP supports neither direction.** `glassfrog_getProject` returns no `legacy_id`, `web_url`, or `role_projects_url`, and the v5 spec's Project schema has no such field. Once #340 makes Official the default connector, an Official-only session is back to the old constraint: resolve by title only, and offer no links.

**All of the Extended behaviour is transitional.** The tool documents that `include_legacy_id` retires when the v3 API retires. Do not build anything that assumes it lasts.

The 2026-09-14 verification -- `glassfrog_get_project` rejects a bare number at the schema level, `glassfrog_search` on the number returns zero items, and no list or get returns a legacy ID field -- still holds for search, for the get tools' input, and for the Official MCP. It was superseded for Extended's output on 2026-10-08, when `include_legacy_id` was found.

## What to do instead

1. **Ask for the text, not the link.** Request the item's title or description -- one line is usually enough. This is the cheapest path on every connector.
2. **Resolve by search.** `glassfrog_search(query, types: ["project", "action"])` matches on description text and returns the prefixed ID plus the owning `role_id`. Quote a distinctive phrase rather than the whole description.
3. **Fall back to the owning role.** If search misses, `glassfrog_list_role_projects` / `glassfrog_list_role_actions` on the plausible role is cheap and exact.
4. **Without a title, run a bounded scan on GlassFrog Extended.** List with `include_legacy_id: true` and match on `legacy_id`. **Scan actions as well as projects** (`glassfrog_list_role_actions`), because a `/my/workspace/projects/<id>` URL can name an action (#293; see below). **Omit the `status` filter** -- one call per role then returns every status (`current`, `someday`, `completed`, `archived` all came back unfiltered on both `glassfrog_list_role_projects` and `glassfrog_list_role_actions`, verified 2026-10-08, #357). Do not pass `status: "current"`: the 2026-10-08 probe record was `someday`, and a current-only scan reports "not found" falsely. Do not loop over statuses either; the filter takes one value, so that multiplies the calls for nothing. Keep the scan bounded, widening one step at a time:
   - First, the actor's own roles: `glassfrog_list_my_projects`, plus the actions on those roles.
   - Then at most **one** candidate role or circle the user names, and only after asking.
   - If that misses, **stop and ask for the title again.** Do not sweep the org: it pulls other people's records into context to find one item, and it is the context blowout the warning below describes.

   Unlike a browser cross-reference, the scan is deterministic -- but it is the fallback, which is why the title comes first. On the Official MCP there is no scan; the title is the only path.

**Do not** page `glassfrog_list_my_projects` or role lists across the org hunting for the number. Without `include_legacy_id: true` the number is not even in the payload; with it, the response is larger still. Either way, an org-wide page is large enough to blow a context window -- the flag does not change that, which is why step 4 is bounded.

## The second trap: `/projects/<id>` is not only projects

The `/my/workspace/projects/<id>` URL path serves **next-actions as well as projects**. An item the user calls a "task" or a "project" because of where its URL points may be an Action (`actn_<32hex>`) attached to a project.

Confirm which it is before applying a project-shaped rubric. `skills/shared/project-well-formedness.md` judges *projects*: its dimensions assume an outcome with next-actions hanging off it, and they do not transfer cleanly to a single action. When the item turns out to be an action, review its **parent project** instead and treat the action as one of that project's next-actions.

Say the correction out loud when it happens. "The item at that URL is an action, not a project" is information the user needs, not a detail to smooth over.

## Honest framing for the user

This is an API limitation, not a failure to look properly. Name it plainly and ask the one question that unblocks you:

> GlassFrog has no lookup from the number in that URL to a record, so the link alone does not tell me which item it is. What is the item's title?

On GlassFrog Extended you may add that, if the user does not know the title, you can scan their projects and actions for the matching number instead.

One question beats a dozen speculative calls.
