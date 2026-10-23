# Security policy

## Report a vulnerability privately

Do not open a public issue for a security problem.

Use GitHub's private reporting form: <https://github.com/Integral-Productivity/holacracy-claude-plugin/security/advisories/new>.
Only the maintainers can read what you send there.

Include:

- what the problem is, and which file, command, or hook it affects;
- the steps to reproduce it;
- what an attacker could do with it.

We aim to answer within 7 days. We will tell you when a fix ships, and we
credit reporters in the advisory unless you ask us not to.

## Scope

In scope:

- the skills, commands, agents, and hooks in this repository;
- the scripts and GitHub workflows in this repository;
- any leak of credentials or live organization data in this repository or its
  history.

Out of scope for this repository:

- the hosted GlassFrog Extended MCP server
  (`ipllc-glassfrog-mcp-server.vercel.app`). It is a separate project. Use the
  same private form and say that the report is about the server; we will route it.
- GlassFrog itself. Report problems in GlassFrog to HolacracyOne.

## Supported versions

Only the latest release on the `stable` branch gets security fixes.
