---
name: skill-versioning
description: >-
  Keeps every skill in a multi-skill repository (skills/<name>/SKILL.md) on its
  own semantic version and changelog. Records each change to a skill folder
  under ## [Unreleased] in that skill's CHANGELOG.md, picks the MAJOR, MINOR,
  or PATCH bump, and cuts per-skill releases tagged <name>/vX.Y.Z without
  pushing. Use after editing, adding, or importing files under skills/<name>/,
  and when the user asks to version a skill, update a changelog, bump or release
  a skill, tag a skill release, or check which skills need a release.
license: MIT
metadata:
  version: "0.1.0"
---

# Skill Versioning

Each skill folder carries its own version and history, so a change to one skill never forces a release of the others:

- **Version:** `metadata.version` in `skills/<name>/SKILL.md`, quoted `MAJOR.MINOR.PATCH`.
- **History:** `skills/<name>/CHANGELOG.md` in Keep a Changelog format, `## [Unreleased]` first. The newest released heading equals `metadata.version`.
- **Release:** an annotated git tag `<name>/vX.Y.Z` on the commit that set that version.

## When to use

- You just changed files under `skills/<name>/` (instructions, references, scripts, assets) in a repo that follows this layout.
- The user asks to update a changelog, bump, version, release, or tag a skill, or asks what needs releasing.
- A skill is missing `metadata.version` or `CHANGELOG.md`.

## When not to use

- Changes only outside `skills/` (repo scripts, CI, README, marketplace manifests). Those ship nothing to installers and get no entry.
- Single-skill repos with one repo-wide version; follow that repo's own release process.

## Check the current state

Run the bundled status script from the repo root (read-only):

```bash
bash <this-skill>/scripts/skill-status.sh            # every skill
bash <this-skill>/scripts/skill-status.sh my-skill   # one skill
```

`<this-skill>` is this skill's folder. Its `NEXT` column says what each skill needs: record changes, release, tag a first release, adopt versioning, or nothing.

## Workflow 1: record a change (always, after editing a skill)

Do this in the same change as the edit, for every skill folder you touched. Do **not** bump `metadata.version` here.

1. List touched skills: `git status --porcelain -- skills/` (plus committed changes on the branch, if any).
2. For each, open `skills/<name>/CHANGELOG.md` and add a line under `## [Unreleased]`, inside the right category heading (`### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`). Create the heading if it's missing.
3. If people who already installed the skill must act (renamed file they copy, changed default, raised minimum tool version), add or extend `### Upgrade notes` with the exact action.
4. If the change breaks instructions in a sibling skill that links into this one, fix the sibling and record it in the sibling's changelog too.
5. If the skill has no `metadata.version` or `CHANGELOG.md`, adopt versioning first (see [references/changelog-and-release.md](references/changelog-and-release.md)).

Entries describe what someone using the skill will notice, in one line each. Skip pure typo or whitespace fixes. Guidance and examples: [references/changelog-and-release.md](references/changelog-and-release.md).

## Workflow 2: release a skill (only when the user asks)

1. Run the status script. Release only skills whose Unreleased section has entries, or a first release whose version is already recorded.
2. Pick the bump from the highest-impact entry since the last release:

   | Bump | When |
   | --- | --- |
   | MAJOR | Anything under `### Upgrade notes`, `### Removed`, or a breaking `### Changed`: users must act or existing output stops being valid. |
   | MINOR | `### Added` or a backwards-compatible `### Changed`: new capability, existing output still valid. |
   | PATCH | Only `### Fixed`, `### Security`, or clarifications that don't change what the skill produces. |

   Below `1.0.0`, a breaking change bumps MINOR instead of MAJOR.
3. State the proposed `<name> X.Y.Z` and the reason in one line, and get the user's confirmation before tagging.
4. Make sure the changelog notes are committed and the tree is clean, on the default branch.
5. Release:
   - If the repo has `scripts/release-skill.sh`, run `bash scripts/release-skill.sh <name> X.Y.Z`. It promotes Unreleased, bumps the version, validates, commits, and tags. If `X.Y.Z` is already the recorded version, it only validates and tags.
   - Otherwise follow the manual steps in [references/changelog-and-release.md](references/changelog-and-release.md).
6. Report the tag and the publish command (`git push origin <branch> <name>/vX.Y.Z`). Push only if the user asks.

## Rules

- Never edit `metadata.version` by hand outside a release, and never create or move a release tag by hand when a release script exists.
- Never push commits or tags unless the user asks.
- Never release a skill whose folder hasn't changed since its last tag.
- One version per skill. Don't sync versions across skills to make them match.

## Quality checklist

- [ ] Every touched `skills/<name>/` has a matching line under `## [Unreleased]`.
- [ ] Entries sit under the right category, and breaking changes have `### Upgrade notes`.
- [ ] `metadata.version` equals the newest released `## [X.Y.Z]` heading.
- [ ] The repo's validator passes (for example `bash scripts/validate-skills.sh`).
- [ ] Releases were confirmed by the user and nothing was pushed without being asked.
