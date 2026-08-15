# Triage Labels

## The vocabulary is defined once, and not here

The canonical, org-wide triage vocabulary lives in
[`devops-excellence/docs/agents/triage-labels.md`](https://github.com/Integral-Productivity/devops-excellence/blob/main/docs/agents/triage-labels.md).
Repos **consume** that vocabulary; they do not fork it. That file is authoritative for:

- the two **category** roles (`bug`, `enhancement`),
- the six **state** roles (`needs-triage`, `needs-info`, `ready-for-agent`,
  `ready-for-human`, `deferred`, `wontfix`) and what each one means,
- the enrichment axes that layer on top (`priority:*`, `area:*`, `handling:route:*`),
- the lock axis `status:in-progress`, the escalation axis `needs-triage-decision`,
  and the retired label names that must not be reused.

Read it before triaging here. **This file deliberately does not restate the table** —
see [Why this file no longer carries the table](#why-this-file-no-longer-carries-the-table).

## Mapping in this repo: identity

Every canonical role name is the literal label string on
`Integral-Productivity/holacracy-claude-plugin`. When a skill names a role — "apply the
AFK-ready triage label" — use that name verbatim. No translation step.

State labels are **provisioned per repo on first use**; they are not in
`templates/org-labels.json` yet. So a role you need may not exist here. Create it with
the exact name, colour, and description from canonical rather than inventing one —
independently-created labels have already drifted across repos.
[devops-excellence#508](https://github.com/Integral-Productivity/devops-excellence/issues/508)
closes this gap by generating and syncing the full vocabulary.

## Why this file no longer carries the table

It carried one from 2026-06-08 until 2026-08-06, copied from the `mattpocock/skills`
template — down to a left-hand column headed "Label in mattpocock/skills". The copy
rotted, and this repo's own tracker is the evidence.

The table listed five states and omitted `deferred`. Measured on 2026-08-06, actual
usage across all issues here was:

| State | Documented in the old table | Issues using it |
| ----- | --------------------------- | --------------- |
| `ready-for-agent` | yes | 43 |
| `ready-for-human` | yes | 24 |
| **`deferred`** | **no** | **18** |
| `needs-triage` | yes | 6 |
| `needs-info` | yes | 1 |
| `wontfix` | yes | 0 |

`deferred` was the third-most-used state in this repo and appeared nowhere in the file
that exists to tell an agent which states exist. `wontfix`, which the table did list,
had never been used once. The documented vocabulary was inverted relative to practice.

The workaround is visible in the tracker: issues such as
[#67](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/67) and
[#68](https://github.com/Integral-Productivity/holacracy-claude-plugin/issues/68) encode
`[Track B · deferred]` in their **titles**. That is what it looks like when a maintainer
needs a state the documentation does not name — the meaning gets smuggled somewhere
unstructured, where no query can find it.

Canonical moved to six states on 2026-08-04
([devops-excellence c11b0f8](https://github.com/Integral-Productivity/devops-excellence/commit/c11b0f8)),
adding `deferred` and stating that repos consume the vocabulary rather than forking it.
Adding the missing row here would only reset the clock until canonical next moves.
Canonical's own principle — *an enumeration copied into prose is a copy that rots* —
applies to this file, so the table is replaced by a pointer and the next change
propagates by reference.

Filed and resolved under
[reusable-workflows#18](https://github.com/Integral-Productivity/reusable-workflows/issues/18),
which found the same drift in a sibling repo. If you find a third repo restating the
table, that is the defect — replace it with a pointer rather than adding the missing row.
