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

6. After it merges to `master`, the tag-on-merge workflow tags the first release, because version `0.1.0` is already recorded and has no tag (see [Releases](#releases)). `bash scripts/release-skill.sh my-new-skill 0.1.0` is only the fallback when the workflow did not run or failed.

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
9. After it merges, the tag-on-merge workflow tags the first release, because the version is already recorded and has no tag. `bash scripts/release-skill.sh <name> 1.0.0` is only the fallback when the workflow did not run or failed.
10. In the old repo, replace the README with a pointer to the new location, for example `npx skills add kdcllc/skills --skill <name>`, then archive the repo on GitHub.

## Working on agent-kit (dogfood)

This repo dogfoods the [agent-kit](skills/agent-kit/README.md) skill: feature work on any skill here can run through `/feature` and the evaluator gates. After cloning, emit the local instance:

```bash
bash scripts/agent-kit/self-install.sh
```

It copies `skills/agent-kit/` into `.claude/skills/` and `.cursor/skills/`, then emits agents, skills, `ORCHESTRATION.md`, `_kit/`, and `_loop/` from [tests/agent-kit/fixtures/self-answers.json](tests/agent-kit/fixtures/self-answers.json). Everything it writes is gitignored; `scripts/validate-skills.sh` only rejects agent skill folders that contain tracked files. Re-run it after editing anything under `skills/agent-kit/templates/` or `skills/agent-kit/bin/`, and never edit the emitted copies. `_memory/` is the exception: its records are tracked and immutable.

Kit-specific maintainer material lives outside the skill folder so it never ships: the developer guide in [docs/agent-kit/](docs/agent-kit/guide/README.md) (start with [contributing.md](docs/agent-kit/guide/contributing.md)), research briefs in `_memory/research/`, and the test suites in [tests/agent-kit/](tests/agent-kit/). `scripts/checks/agent-kit.sh` runs the fast instance-free checks inside the validator; run the full suite before opening a pull request that touches `skills/agent-kit/`:

```bash
bash tests/agent-kit/run-all.sh
```

## Working on agent-composer

`scripts/checks/agent-composer.sh` guards agent-composer's files and pinned phrases and runs inside `scripts/validate-skills.sh`. `tests/agent-composer/run.sh` is its fixture suite (bash, python3, and PyYAML; cases that need PyYAML skip when it is missing); `.github/workflows/agent-composer.yml` runs it when a push to `master` or a pull request touches `skills/agent-composer/`, `tests/agent-composer/`, the guard, or the workflow. Run it before opening a pull request that touches `skills/agent-composer/`:

```bash
bash tests/agent-composer/run.sh
```

## Working on orchestration-advisor

`scripts/checks/orchestration-advisor.sh` guards orchestration-advisor's files, headings, shape names, and signal keys and runs inside `scripts/validate-skills.sh`. `tests/orchestration-advisor/run.sh` is its fixture suite (bash only; cases that need `jq` or `git` skip when the tool is missing); `.github/workflows/orchestration-advisor.yml` runs it when a push to `master` or a pull request touches `skills/orchestration-advisor/`, `tests/orchestration-advisor/`, the guard, or the workflow. Run it before opening a pull request that touches `skills/orchestration-advisor/`:

```bash
bash tests/orchestration-advisor/run.sh
```

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
- **Tag:** `<name>/vX.Y.Z`, for example `terraform-azure/v1.0.0`. After a merge to `master`, [.github/workflows/tag-on-merge.yml](.github/workflows/tag-on-merge.yml) creates and pushes the tag for every recorded version that has none. [.github/workflows/release.yml](.github/workflows/release.yml) is started by that workflow, or by a tag a person pushes by hand. It checks that the tag matches `metadata.version` and creates a GitHub release titled `<name> vX.Y.Z` with that version's changelog section as its notes.

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

1. While you work, write the notes under `## [Unreleased]` in `skills/<name>/CHANGELOG.md` for every skill whose folder you change.
2. Before the pull request is opened or updated for review, for every skill whose folder it changes:

   - pick the bump with the table above;
   - set `metadata.version` in `skills/<name>/SKILL.md` to the new version;
   - insert `## [X.Y.Z] - YYYY-MM-DD` directly under `## [Unreleased]` in `skills/<name>/CHANGELOG.md`, so Unreleased is empty and the notes sit under the new heading. The date is the day the pull request is opened;
   - name the new versions in the pull request description.

   One bump per skill per pull request: later commits add their notes under the same heading and raise the bump only if they add an entry with a higher impact. If another pull request released the same skill first, rebase and pick the next version again.

   After the bump, `bash skills/skill-versioning/scripts/skill-status.sh` shows the new VERSION ahead of LAST_TAG, UNRELEASED 0, and the NEXT text `release prepared (tag <name>/vX.Y.Z pending)`.

   `.github/workflows/validate.yml` runs `scripts/check-skill-versions.sh` against the base branch on every pull request and fails it when a changed skill folder lacks a higher version, the matching dated heading or an empty Unreleased section. Run the same check locally with `bash scripts/check-skill-versions.sh origin/master`.
3. Merge to `master`. [.github/workflows/tag-on-merge.yml](.github/workflows/tag-on-merge.yml) then creates and pushes the tag `<name>/vX.Y.Z` for each newly recorded version and starts `release.yml` for it. There is no manual step.
4. Fallback, when the tag does not exist yet (the workflow did not run, or failed before pushing it): on an up-to-date, clean `master`, run

   ```bash
   bash scripts/release-skill.sh <name> X.Y.Z
   git push origin <name>/vX.Y.Z
   ```

   Because `X.Y.Z` already is the recorded version, the script only validates and creates the annotated tag. It never pushes, and it stops if the tag already exists. A tag pushed by a person starts `release.yml` by itself.

   When the tag was pushed but its release was not started, the script stops on "tag already exists". Start the release with `gh workflow run release.yml --ref <name>/vX.Y.Z`.

   If a pull request was merged without a bump, the same command bumps as well: it promotes `## [Unreleased]` to `## [X.Y.Z] - <today>`, sets `metadata.version`, runs the validator, commits `release: <name> vX.Y.Z`, and creates the tag. Push the commit and the tag together, as the script prints:

   ```bash
   git push origin master <name>/vX.Y.Z
   ```

The tag-on-merge workflow runs on every push to `master` that touches `skills/`, and can be started by hand on `master`. It runs `scripts/tag-released-skills.sh --push`, and its job summary lists the tags it created and, for a release that was not started, the command to start it. `tests/release/run.sh` is the suite for `scripts/tag-released-skills.sh`, `scripts/check-skill-versions.sh` and the `skill-status.sh` states (bash and git only); it runs in `.github/workflows/validate.yml`. Run it after changing any of them:

```bash
bash tests/release/run.sh
```

**`agent-kit` has more files to update.** Its install pin and emit test goldens encode the version, and its tests check them, so the same pull request that sets the version also updates those files. The steps are in [docs/agent-kit/guide/contributing.md](docs/agent-kit/guide/contributing.md#version-and-releases).

Never create a release tag by hand (the fallback in step 4 is the only case), and never edit `metadata.version` outside a pull request that changes that skill. `gh skill publish --dry-run` (`gh` 2.90 or newer) is still useful as an extra check, but let the release workflow create the releases. The repo needs the `agent-skills` topic for `gh skill` discovery: `gh repo edit kdcllc/skills --add-topic agent-skills`.
