# Changelog entries and manual releases

Companion to [SKILL.md](../SKILL.md). Read this when writing a changelog entry you are unsure how to phrase, when adopting versioning for a skill that has none, or when the repo has no `scripts/release-skill.sh`.

## Changelog file shape

```markdown
# Changelog

All notable changes to the `<name>` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `<name>/vX.Y.Z`.

## [Unreleased]

### Changed

- Stack templates set `resource_provider_registrations = "none"` by default.

### Upgrade notes

- Existing stacks keep `"legacy"`; set it explicitly before re-copying `providers.tf`.

## [1.2.0] - 2026-11-02

### Added

- ...
```

Rules:

- `## [Unreleased]` is always the first `##` heading, even when empty.
- Released headings are `## [X.Y.Z] - YYYY-MM-DD`, newest first. The newest one equals `metadata.version` in `SKILL.md`.
- Category headings, in this order, only when used: `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`, then `### Upgrade notes`.
- `### Upgrade notes` appears only when someone who installed the previous version must act. It says exactly what to do.

## Writing an entry

Write for the person who installed the skill, not for the reviewer of the diff. Name the behaviour or file they will notice, not the commit.

| Weak | Better |
| --- | --- |
| Updated SKILL.md | The menu now asks for the resource group layout before creating a stack. |
| Fixed typo | (no entry; see below) |
| Refactored references | Moved the abbreviation table to `references/naming.md`; `SKILL.md` links to it. |
| Bumped pins | Pipelines pin Terraform `1.15.9` (was `1.15.8`). |

Skip an entry for changes nobody installing the skill would notice: whitespace, typo fixes that don't change meaning, comment-only edits in scripts. When in doubt, write one line.

One entry per user-visible change. When a later edit in the same Unreleased cycle reverses or refines an earlier one, edit the existing entry instead of adding a second.

## Adopting versioning for an existing skill

For a skill with no `metadata.version` or no `CHANGELOG.md`:

1. Add to the frontmatter, merging into an existing `metadata:` block if there is one:

   ```yaml
   metadata:
     version: "1.0.0"
   ```

   Use `1.0.0` when the skill is already in use, `0.1.0` when it is new or experimental.
2. Create `CHANGELOG.md` in the skill folder with an empty `## [Unreleased]` and a `## [<version>] - <today>` entry. For an imported or long-lived skill, say where it came from and link earlier history.
3. Tag that version as its first release (see below). Tagging an already-recorded version needs no commit.

## Releasing without a release script

Do this only when the user asked for a release and the repo has no `scripts/release-skill.sh`. Every step is local; nothing is pushed.

1. Check preconditions: on the default branch, `git status --porcelain` is empty, and `git tag --list "<name>/vX.Y.Z"` prints nothing.
2. Confirm `X.Y.Z` is newer than the current `metadata.version` and that `## [Unreleased]` has entries.
3. In `CHANGELOG.md`, insert `## [X.Y.Z] - <today>` directly under `## [Unreleased]`, so the existing notes now sit under the new heading and Unreleased is empty again.
4. Set `metadata.version: "X.Y.Z"` in `SKILL.md`.
5. Run the repo's validator if it has one.
6. Commit only those two files: `git commit -m "release: <name> vX.Y.Z" -- skills/<name>/SKILL.md skills/<name>/CHANGELOG.md`.
7. Tag: `git tag -a "<name>/vX.Y.Z" -m "<name> vX.Y.Z"`.
8. Tell the user the publish command, `git push origin <branch> <name>/vX.Y.Z`, and run it only if they ask.

## Pinning a released skill

Consumers pin one skill to one release with the tag as a git ref:

```bash
npx skills add <owner>/<repo>#<name>/vX.Y.Z --skill <name>
```

A tag pins the whole repository at that commit, so each pinned skill needs its own `npx skills add`.
