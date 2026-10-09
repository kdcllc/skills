# AGENTS.md

This repository is **kdcllc/skills**, a multi-skill pack distributed through [skills.sh](https://skills.sh) (`npx skills`), the Claude Code plugin marketplace, the Cursor plugin marketplace, and `gh skill`. Everything under `skills/` is published to users.

## Layout rules

- Each skill lives in exactly one folder: `skills/<name>/SKILL.md`. Optional subfolders are `scripts/`, `references/`, and `assets/`.
- Never put a `SKILL.md` at the repository root. The Skills CLI treats it as a single-skill repo and stops looking.
- Never commit `.agents/skills/`, `.claude/skills/`, `.cursor/skills/`, `.github/skills/`, or similar agent skill folders at the root. The Skills CLI scans those too and would publish them.
- Don't add new top-level folders containing `SKILL.md` files. `templates/SKILL.md.tmpl` is deliberately not named `SKILL.md`.

## SKILL.md rules

- Frontmatter may only use the six [Agent Skills spec](https://agentskills.io/specification) fields: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`. Put anything agent-specific (for example `argument-hint`) under `metadata` as a string value.
- `name` must match the folder name: 1-64 characters of lowercase letters, digits, and single hyphens.
- `description` must be 1-1024 characters and say both what the skill does and when to use it.
- `allowed-tools`, if present, is a space-separated string.
- Keep `SKILL.md` under 500 lines. Move detail into `references/` and link to it with relative paths one level deep.
- Skills default to the root MIT license. A skill under another license sets `license` in its frontmatter and ships a `LICENSE.txt` in its folder.

## When adding, renaming, or removing a skill

1. Scaffold with `bash scripts/new-skill.sh <name>` (don't hand-copy the template).
2. Update the Skills table in `README.md`.
3. If the skill belongs to a domain bundle in `.claude-plugin/marketplace.json`, add its `./skills/<name>` path there. The `kdcllc-skills` bundle in both marketplaces picks up every skill automatically.
4. If `skills.sh.json` exists, add the skill to a grouping.
5. Run `bash scripts/validate-skills.sh` and `npx skills add . --list`, and make sure both pass.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the migration and release checklists.
