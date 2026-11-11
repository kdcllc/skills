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
- While you work on a change, add a line under `## [Unreleased]` in the changelog of every skill whose folder you change. [skills/skill-versioning/SKILL.md](skills/skill-versioning/SKILL.md) says how to write entries.
- Before a pull request is opened or updated for review, prepare the release of every skill whose folder the pull request changes:
  1. Pick the bump (MAJOR, MINOR, or PATCH) with the table in [skills/skill-versioning/SKILL.md](skills/skill-versioning/SKILL.md).
  2. Set `metadata.version` in `skills/<name>/SKILL.md` to the new version.
  3. In `skills/<name>/CHANGELOG.md`, insert `## [X.Y.Z] - YYYY-MM-DD` directly under `## [Unreleased]`, so Unreleased is empty and the notes sit under the new heading. The date is the day the pull request is opened.
  4. Name the new versions in the pull request description.
- One bump per skill per pull request. Later commits on the same pull request add their notes under the same `## [X.Y.Z]` heading, and raise the bump only if they add an entry with a higher impact. If another pull request released the same skill first, rebase and pick the next version again.
- A change confined to repository tooling (`scripts/`, `tests/`, `.github/`, `templates/`, `docs/`, root files) changes no skill folder and bumps nothing.
- `agent-kit` also updates its install pin and emit goldens in the same pull request, because they encode the version and its tests check them. Follow [docs/agent-kit/guide/contributing.md § Version and releases](docs/agent-kit/guide/contributing.md#version-and-releases).
- After the merge, the workflow `.github/workflows/tag-on-merge.yml` runs `scripts/tag-released-skills.sh`, which creates and pushes the tag `<name>/vX.Y.Z` for every skill whose recorded version has no tag yet. The workflow then starts the release workflow for each tag. Nobody tags by hand. `bash scripts/release-skill.sh <name> X.Y.Z` on `master` is the manual fallback when the workflow did not run or failed; it only validates and tags, because the version is already recorded. Agents never create or push release tags unless the user asks.
- This rule takes precedence over Workflow 2 (release a skill, only when the user asks) in [skills/skill-versioning/SKILL.md](skills/skill-versioning/SKILL.md). Here, opening a pull request that changes a skill is the request to prepare its release, and the merge to `master` creates the tag through the workflow above. Creating or pushing a tag by hand still needs the user.
- `bash skills/skill-versioning/scripts/skill-status.sh` shows where each skill stands. Before the bump it shows which skills changed and have notes under Unreleased. After the bump it shows the new VERSION ahead of LAST_TAG, UNRELEASED 0, and the NEXT text `record changes under Unreleased`. Here that means the release is prepared and waits for its tag after the merge, not that notes are missing.

## When adding, renaming, or removing a skill

1. Scaffold with `bash scripts/new-skill.sh <name>` (don't hand-copy the template). It creates both `SKILL.md` and `CHANGELOG.md`.
2. Update the Skills table in `README.md`.
3. If the skill belongs to a domain bundle in `.claude-plugin/marketplace.json` (for example `kdcllc-azure`), add its `./skills/<name>` path there. The `kdcllc-skills` bundle in both marketplaces picks up every skill automatically.
4. Add the skill to a grouping in `skills.sh.json`.
5. Run `bash scripts/validate-skills.sh` and `npx skills add . --list`, and make sure both pass.

## agent-kit dogfood

This repo runs its own [agent-kit](skills/agent-kit/README.md) orchestration. `bash scripts/agent-kit/self-install.sh` emits the instance (`.claude/`, `.cursor/skills|agents|rules/`, `_kit/`, `_loop/`, `orchestration-kit.manifest.json`); those paths are gitignored and regenerated, so never edit or commit them. `_memory/work/` (goal/research scratch) and `_memory/loop/` (loop state) are gitignored in this repo and written by the orchestrator and loop (self-install only seeds a missing `_memory/loop/backlog.md`). Edit `skills/agent-kit/` instead and re-run self-install. `_memory/records/` is tracked and immutable: add records with `_kit/memory.sh add`, never edit existing ones. Curated research briefs live in tracked `_memory/research/` and are edited only through the research and feature workflows (unlike immutable `_memory/records/`). Kit maintainer docs and tests live in `docs/agent-kit/` and `tests/agent-kit/`; run `bash tests/agent-kit/run-all.sh` after changing `skills/agent-kit/`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the migration and release checklists.
