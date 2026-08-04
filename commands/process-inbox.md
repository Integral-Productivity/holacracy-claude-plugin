---
description: Deprecated alias for /holacracy:tension-triage. Dispatches to it and names the new command once.
argument-hint: [circle name, optional]
---

# /holacracy:process-inbox — deprecated

This command has been renamed to **`/holacracy:tension-triage`**.

## What to do

1. Tell the user, once, in a single line:

   > `/holacracy:process-inbox` is now `/holacracy:tension-triage` — running it for you.

   Say it once and move on. Do not explain the rename, do not ask whether to proceed, and do not repeat the notice on subsequent tensions.

2. Run [`commands/tension-triage.md`](./tension-triage.md) with `$ARGUMENTS` passed through unchanged.

## Why the rename

Two reasons, recorded in [ADR-0011](../docs/adr/0011-separate-tension-readiness-from-tension-disposition.md):

- **"Process" was the wrong verb.** The command assessed readiness; it never decided what a tension became. Disposition now belongs to `/holacracy:process-tension`, and the names had to stop overlapping.
- **"Inbox" was borrowed.** The GlassFrog concept is a role's durable tension backlog, not a mail-shaped queue.

The old name is kept as an alias because both are shipped on the `stable` branch the public marketplace tracks. It will be removed in a future major release.
