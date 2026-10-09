# Contributing

Read [AGENTS.md](AGENTS.md) first. It has the layout and frontmatter rules that the validator enforces.

## Add a new skill

1. Scaffold the folder:

   ```bash
   bash scripts/new-skill.sh my-new-skill
   ```

   This creates `skills/my-new-skill/SKILL.md` from [templates/SKILL.md.tmpl](templates/SKILL.md.tmpl) with `metadata.version: "0.1.0"`, and `skills/my-new-skill/CHANGELOG.md` from [templates/CHANGELOG.md.tmpl](templates/CHANGELOG.md.tmpl) with a matching `0.1.0` entry. It also prints a README catalog row.

2. Write the `description` (what it does and when to use it, at most 1024 characters) and the instructions. Keep `SKILL.md` under 500 lines; move long material into `references/`, executable helpers into `scripts/`, and templates or static files into `assets/`.
3. Paste the printed row into the Skills table in [README.md](README.md).
4. Optionally add the skill to a domain bundle (see below) and to a grouping in [skills.sh.json](skills.sh.json).
5. Validate:

   ```bash
   bash scripts/validate-skills.sh
   npx skills add . --list
   ```

6. After it merges to `master`, tag the first release with `bash scripts/release-skill.sh my-new-skill 0.1.0` (see [Releases](#releases)).

## Migrate a skill from an existing repo

1. Copy the skill folder from the old repo's `skills/<name>/` into `skills/<name>/` here. Copy only what the skill needs at runtime (`SKILL.md`, `scripts/`, `references/`, `assets/`, `evals/`). Leave behind repo scaffolding such as `.squad/`, `.copilot/skills/`, `CLAUDE.md`, and root `plugin.json` files.
2. Fix the frontmatter so it uses only the six spec fields. For example, move `argument-hint` into `metadata`:

   ```yaml
   metadata:
     argument-hint: "NT reference and target English or Greek word, e.g. Ephesians 2:8 grace"
   ```

   Custom keys like `domain`, `confidence`, and `source` also go under `metadata`.
3. If the skill isn't MIT, set `license` (for example `license: CC-BY-SA-4.0`) and add the full license text as `skills/<name>/LICENSE.txt`.
4. Set `metadata.version` (start at `1.0.0` for a skill that was already in use) and create `skills/<name>/CHANGELOG.md` with an empty `## [Unreleased]` section and a matching `## [1.0.0]` entry that links to the old repo's history. Copy the format from [templates/CHANGELOG.md.tmpl](templates/CHANGELOG.md.tmpl).
5. Fix any paths in the instructions or scripts that assumed the old repo layout (for example a repo-root `scripts/` folder). Rename non-standard subfolders to `scripts/`, `references/`, or `assets/` and update the links.
6. If the old repo had its own content checks (required files, pinned versions, phrases that must not disappear), port them to `scripts/checks/<name>.sh`. Each check takes the repo root as its first argument, exits non-zero on failure, and is run automatically by `scripts/validate-skills.sh`. Scope its greps to the skill's own folders.
7. Add a row to the Skills table in [README.md](README.md), and add the skill to a domain bundle and a `skills.sh.json` grouping if it belongs to one.
8. Run the validator and `npx skills add . --list`.
9. After it merges, tag the first release with `bash scripts/release-skill.sh <name> 1.0.0`.
10. In the old repo, replace the README with a pointer to the new location, for example `npx skills add kdcllc/skills --skill <name>`, then archive the repo on GitHub.

## Domain bundles (Claude Code, Copilot CLI, Codex)

The `kdcllc-skills` plugin in [.claude-plugin/marketplace.json](.claude-plugin/marketplace.json) has no `skills` list, so it loads every folder under `skills/`. Smaller bundles are extra entries that list skills explicitly. Paths must start with `./`, and plugin names must not start with `claude-`, `anthropic-`, or `cc-plugin-`. The existing `kdcllc-azure` bundle looks like this:

```json
{
  "name": "kdcllc-azure",
  "description": "Azure Terraform modules, domain stacks, CI pipelines, and azurerm upgrades, plus least-privilege RBAC role matching",
  "source": "./",
  "strict": false,
  "skills": [
    "./skills/terraform-azure",
    "./skills/terraform-azure-modules",
    "./skills/terraform-azure-pipelines",
    "./skills/terraform-azure-upgrade",
    "./skills/azure-rbac-least-privilege"
  ]
}
```

Users then run `/plugin install kdcllc-azure@kdcllc`. Add a new Azure skill to this list rather than creating a second Azure bundle. The Cursor marketplace schema doesn't allow a `skills` list on an entry, so Cursor keeps the single `kdcllc-skills` plugin.

## skills.sh groupings

[skills.sh.json](skills.sh.json) groups skills on the [skills.sh](https://skills.sh/kdcllc/skills) repo page. Add a new skill to an existing grouping, or add a grouping:

```json
{
  "title": "Azure Terraform",
  "description": "Azure Terraform modules, one-stack-per-domain environments, CI pipelines, and azurerm 5.x upgrades.",
  "skills": ["terraform-azure", "terraform-azure-modules", "terraform-azure-pipelines", "terraform-azure-upgrade"]
}
```

Skills not listed in any grouping appear at the bottom (`"notGrouped": "bottom"`). skills.sh picks up changes the next time someone installs from the repo. There is no submission step; the repo appears on the leaderboard once people install from it.

## Releases

Every skill is versioned and released on its own:

- **Version:** `metadata.version` in `skills/<name>/SKILL.md`, as `MAJOR.MINOR.PATCH`.
- **History:** `skills/<name>/CHANGELOG.md` in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. The `## [Unreleased]` section is always at the top, and the first released `## [X.Y.Z]` heading must equal `metadata.version`. The validator enforces both.
- **Tag:** `<name>/vX.Y.Z`, for example `terraform-azure/v1.0.0`. Pushing the tag triggers [.github/workflows/release.yml](.github/workflows/release.yml), which checks that the tag matches `metadata.version` and creates a GitHub release titled `<name> vX.Y.Z` with that version's changelog section as its notes.

How users get updates:

- `npx skills`, Claude Code, Copilot CLI, Codex, and Cursor install from the default branch unless the user pins a ref. Marketplace entries don't set `version`, so Claude Code tracks the latest commit.
- Users pin one skill with `npx skills add kdcllc/skills#<name>/vX.Y.Z --skill <name>`.
- `gh skill install` uses the latest GitHub release of the repo, which is whichever skill was released last. Because every tag is cut from the tip of `master`, that release contains the current version of every skill.

### Which number to bump

Bump only the skill whose folder changed. A change confined to repo tooling (`scripts/`, `.github/`, `templates/`, the README) ships nothing to users and gets no release.

| Bump | When |
| --- | --- |
| MAJOR | Users must act: renamed or removed files the skill tells agents to copy, a changed layout or naming contract in what the skill generates, a raised minimum tool or provider version, or a changed default. Add an `### Upgrade notes` subsection. |
| MINOR | New capability that keeps existing output valid: a new menu item, template, reference, or optional input. |
| PATCH | Fixes and clarifications that don't change what the skill generates. |

When skills link to each other (like the four `terraform-azure*` skills), a change to one that breaks a sibling's instructions needs a release of both.

### Release steps

1. Write the notes under `## [Unreleased]` in `skills/<name>/CHANGELOG.md`, merge to `master`, and make sure CI is green.
2. On an up-to-date, clean `master`:

   ```bash
   bash scripts/release-skill.sh <name> X.Y.Z
   ```

   The script promotes `## [Unreleased]` to `## [X.Y.Z] - <today>`, bumps `metadata.version`, runs the validator, commits `release: <name> vX.Y.Z`, and creates the annotated tag. If `X.Y.Z` already is the recorded version (a skill's first release), it only validates and tags. It never pushes.
3. Publish by pushing the commit and the tag:

   ```bash
   git push origin master <name>/vX.Y.Z
   ```

Never edit `metadata.version` or create a release tag by hand. `gh skill publish --dry-run` (`gh` 2.90 or newer) is still useful as an extra check, but let the release workflow create the releases. The repo needs the `agent-skills` topic for `gh skill` discovery: `gh repo edit kdcllc/skills --add-topic agent-skills`.
