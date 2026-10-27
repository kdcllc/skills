# Changelog

All notable changes to the `terraform-azure-modules` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `terraform-azure-modules/vX.Y.Z`.

Before re-adding with a new tag, read the target version's entry, especially its **Upgrade notes**.

## [Unreleased]

## [1.0.1] - 2026-10-27

### Fixed

- The `description` no longer contains angle brackets (`<name>` is now `{name}`), so claude.ai syncs it without stripping text.

## [1.0.0] - 2026-10-09

### Added

- Imported from [kdcllc/azure-terraform-skills v2.1.0](https://github.com/kdcllc/azure-terraform-skills/tree/v2.1.0). Behaviour is unchanged from that release; earlier history is in its [CHANGELOG](https://github.com/kdcllc/azure-terraform-skills/blob/v2.1.0/CHANGELOG.md).

### Changed

- `reference.md` moved to `references/reference.md`.

### Upgrade notes

- Install from the new repository: `npx skills add kdcllc/skills --skill terraform-azure-modules`. Pin with `#terraform-azure-modules/v1.0.0`.
