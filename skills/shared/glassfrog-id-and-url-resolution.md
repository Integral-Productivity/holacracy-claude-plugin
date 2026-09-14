# GlassFrog ID and URL Resolution -- Shared Reference

How to get from something a user hands you -- a pasted URL, a name, a number -- to a v5 record you can actually call. Loaded by any surface that accepts a user-supplied pointer to a GlassFrog item.

This sits in `skills/shared/` rather than inside one skill's `references/` because every project, tension, and triage surface hits the same wall, and `skills/shared/` is what those surfaces already load.

---

## The constraint: web URLs carry legacy numeric IDs that v5 does not expose

A GlassFrog web URL identifies a record by a **legacy numeric ID**:

```
https://app.glassfrog.com/organizations/32215/my/workspace/projects/1966547
```

The v5 API exposes only prefixed IDs -- `proj_<32hex>`, `actn_<32hex>`, `role_<32hex>`, `ten_<32hex>`, `goal_<32hex>`, and so on. **No v5 record carries its legacy numeric ID on any field.** There is no lookup endpoint, and `glassfrog_search` does not index the number.

A URL the user pastes therefore **cannot be resolved to a record programmatically**. Verified against live v5 on 2026-09-14: `glassfrog_get_project` rejects a bare number at the schema level, `glassfrog_search` on the number returns zero items, and neither `glassfrog_list_my_projects` nor `glassfrog_get_project` returns a legacy ID field to match against.

## What to do instead

1. **Ask for the text, not the link.** Request the item's title or description -- one line is usually enough.
2. **Resolve by search.** `glassfrog_search(query, types: ["project", "action"])` matches on description text and returns the prefixed ID plus the owning `role_id`. Quote a distinctive phrase rather than the whole description.
3. **Fall back to the owning role.** If search misses, `glassfrog_list_role_projects` / `glassfrog_list_role_actions` on the plausible role is cheap and exact.

**Do not** page `glassfrog_list_my_projects` hunting for the number. The number is not in the payload, and the response for an org of any size is large enough to blow a context window.

## The second trap: `/projects/<id>` is not only projects

The `/my/workspace/projects/<id>` URL path serves **next-actions as well as projects**. An item the user calls a "task" or a "project" because of where its URL points may be an Action (`actn_<32hex>`) attached to a project.

Confirm which it is before applying a project-shaped rubric. `skills/shared/project-well-formedness.md` judges *projects*: its dimensions assume an outcome with next-actions hanging off it, and they do not transfer cleanly to a single action. When the item turns out to be an action, review its **parent project** instead and treat the action as one of that project's next-actions.

Say the correction out loud when it happens. "The item at that URL is an action, not a project" is information the user needs, not a detail to smooth over.

## Honest framing for the user

This is an API limitation, not a failure to look properly. Name it plainly and ask the one question that unblocks you:

> The GlassFrog v5 API does not expose the legacy numeric ID from that URL, so a link alone cannot be resolved to a record. What is the item's title?

One question beats a dozen speculative calls.
