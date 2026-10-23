# Contributing

Thank you for helping. This plugin is a set of Markdown skills, commands, and
agents that Claude loads at runtime. **The Markdown is the product**, so we test
it like code.

## Before you start

- For a bug, open an issue with the **Bug report** form.
- For a new skill, command, or behaviour, open an issue with the **Feature
  request** form first. Agree the scope there before you write a pull request.
- For a security problem, do **not** open an issue. Follow [SECURITY.md](SECURITY.md).

## Make a change

1. Fork the repository and create a branch from `main`.
2. Make your change. [CLAUDE.md](CLAUDE.md) explains the layout, the shared
   references, and the conventions the lint enforces.
3. If you change a skill's content (its `SKILL.md` or anything under its
   `references/`), increase the `version:` in that skill's frontmatter.
4. Do **not** edit the plugin version in `.claude-plugin/plugin.json`,
   `version.txt`, or `.release-please-manifest.json`. release-please writes
   those. A CI check fails any pull request that edits them.
5. Run the offline checks:

   ```bash
   bash scripts/skills-lint.sh
   bash scripts/skills-lint.test.sh
   bash scripts/evals-harness.test.sh
   ```

6. Write a [Conventional Commit](https://www.conventionalcommits.org/) message:
   `fix:` for a bug fix, `feat:` for a new capability, `docs:` for
   documentation only. The type sets the next release number.
7. Open a pull request and fill in the template.

## Rules that protect people

- **No real organization data.** Do not put real role names, circle names,
  people, tensions, GlassFrog IDs, or API responses in any file, issue, or pull
  request. This repository is public. Use synthetic examples. See
  [ADR-0017](docs/adr/0017-live-org-evidence-stays-out-of-this-public-repo.md).
- **No credentials.** Never commit an API key or token, also not in a test
  fixture.
- **Keep the constitutional safeguard.** A skill must not write governance to
  GlassFrog without explicit human confirmation.

## Constitution text and licensing

Your contribution is licensed under the MIT License (see [LICENSE](LICENSE)).
The exception is text that quotes or closely adapts the Holacracy Constitution:
that text is under CC BY-SA 4.0. If you add such text, follow the steps in
[NOTICE](NOTICE). Prefer to cite the article and section and to describe the
rule in your own words.

## Conduct

Everyone who takes part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
