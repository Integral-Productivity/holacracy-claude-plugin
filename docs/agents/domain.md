# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This is a **single-context** repo: one `CONTEXT.md` (when it exists) plus `docs/adr/` at the root.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The producer skill (`/grill-with-docs`) creates `CONTEXT.md` lazily when terms or decisions actually get resolved. (`docs/adr/` already exists here.)

## File structure

Single-context repo:

```
/
├── CONTEXT.md                         ← created lazily by /grill-with-docs
├── docs/adr/
│   ├── 0001-record-architecture-decisions.md
│   ├── 0002-use-tag-driven-stable-branch-for-marketplace-channel-publication.md
│   └── 0003-glassfrog-tension-api-adoption.md
└── skills/
```

ADRs use 4-digit zero-padded numbering (`NNNN-`), managed by `adr-tools` (`.adr-dir` points at `docs/adr`).

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/grill-with-docs`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0002 (tag-driven stable branch for marketplace publication) — but worth reopening because…_
