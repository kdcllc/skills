# Changelog

All notable changes to the `skill-versioning` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `skill-versioning/vX.Y.Z`.

## [Unreleased]

## [0.1.0] - 2026-10-09

### Added

- Workflow for recording each skill change under `## [Unreleased]` in that skill's `CHANGELOG.md`.
- Workflow for picking the MAJOR, MINOR, or PATCH bump and cutting a per-skill release tagged `<name>/vX.Y.Z`, using `scripts/release-skill.sh` when the repo has one.
- `scripts/skill-status.sh`, a read-only report of each skill's version, latest tag, pending changes, and next step.
- `references/changelog-and-release.md` with entry-writing guidance, adopting versioning for an existing skill, and manual release steps.
