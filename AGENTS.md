# AGENTS.md

This repository is **kdcllc/skills**, a multi-skill pack distributed through [skills.sh](https://skills.sh) (`npx skills`), the Claude Code plugin marketplace, the Cursor plugin marketplace, and `gh skill`. Everything under `skills/` is published to users.

## Layout rules

- Each skill lives in exactly one folder: `skills/<name>/SKILL.md`, with a `CHANGELOG.md` beside it. Optional subfolders are `scripts/`, `references/`, and `assets/`.
- Never put a `SKILL.md` at the repository root. The Skills CLI treats it as a single-skill repo and stops looking.
- Never commit `.agents/skills/`, `.claude/skills/`, `.cursor/skills/`, `.github/skills/`, or similar agent skill folders at the root. The Skills CLI scans those too and would publish them. The gitignored agent-kit dogfood instance (see below) is the only thing that may exist there.
- Don't add new top-level folders containing `SKILL.md` files. `templates/SKILL.md.tmpl` is deliberately not named `SKILL.md`.
- Skill-specific content guards live in `scripts/checks/<name>.sh`. `scripts/validate-skills.sh` runs every one of them with the repo root as the first argument. Scope their greps to the skill's own folders. When you edit a skill that has a guard, keep the guarded files, pins, and phrases intact, or update the guard in the same change.

## SKILL.md rules

- Frontmatter may only use the six [Agent Skills spec](https://agentskills.io/specification) fields: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`. Put anything agent-specific (for example `argument-hint`) under `metadata` as a string value.
- `name` must match the folder name: 1-64 characters of lowercase letters, digits, and single hyphens.
- `description` must be 1-1024 characters and say both what the skill does and when to use it.
- `allowed-tools`, if present, is a space-separated string.
- Keep `SKILL.md` under 500 lines. Move detail into `references/` and link to it with relative paths one level deep.
- Skills default to the root MIT license. A skill under another license sets `license` in its frontmatter and ships a `LICENSE.txt` in its folder.

## Versioning rules

- Every skill carries its own version in `metadata.version` (`MAJOR.MINOR.PATCH`, quoted) and its own `skills/<name>/CHANGELOG.md`. The changelog keeps an `## [Unreleased]` section at the top, and its first released `## [X.Y.Z]` heading must equal `metadata.version`.
- When you change a skill's folder, add a line under `## [Unreleased]` in that skill's changelog. Don't bump `metadata.version` yourself. Follow [skills/skill-versioning/SKILL.md](skills/skill-versioning/SKILL.md) for how to write entries, pick a bump, and release; `bash skills/skill-versioning/scripts/skill-status.sh` shows which skills need an entry or a release.
- Releases go through `bash scripts/release-skill.sh <name> X.Y.Z`, which bumps the version, commits, and creates the tag `<name>/vX.Y.Z`. Never hand-edit versions or create release tags manually, and never push tags unless the user asks.

## When adding, renaming, or removing a skill

1. Scaffold with `bash scripts/new-skill.sh <name>` (don't hand-copy the template). It creates both `SKILL.md` and `CHANGELOG.md`.
2. Update the Skills table in `README.md`.
3. If the skill belongs to a domain bundle in `.claude-plugin/marketplace.json` (for example `kdcllc-azure`), add its `./skills/<name>` path there. The `kdcllc-skills` bundle in both marketplaces picks up every skill automatically.
4. Add the skill to a grouping in `skills.sh.json`.
5. Run `bash scripts/validate-skills.sh` and `npx skills add . --list`, and make sure both pass.

## agent-kit dogfood

This repo runs its own [agent-kit](skills/agent-kit/README.md) orchestration. `bash scripts/agent-kit/self-install.sh` emits the instance (`.claude/`, `.cursor/skills|agents|rules/`, `_kit/`, `_loop/`, `_goals/`, `orchestration-kit.manifest.json`); all of it is gitignored and regenerated, so never edit or commit it. Edit `skills/agent-kit/` instead and re-run self-install. `_memory/records/` is tracked and immutable: add records with `_kit/memory.sh add`, never edit existing ones. Kit maintainer docs and tests live in `docs/agent-kit/` and `tests/agent-kit/`; run `bash tests/agent-kit/run-all.sh` after changing `skills/agent-kit/`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the migration and release checklists.
