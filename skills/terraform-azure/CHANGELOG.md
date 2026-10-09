# Changelog

All notable changes to the `terraform-azure` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `terraform-azure/vX.Y.Z`.

Before re-adding with a new tag, read the target version's entry, especially its **Upgrade notes**.

## [Unreleased]

## [1.0.0] - 2026-10-09

### Added

- Imported from [kdcllc/azure-terraform-skills v2.1.0](https://github.com/kdcllc/azure-terraform-skills/tree/v2.1.0). Behaviour is unchanged from that release; earlier history is in its [CHANGELOG](https://github.com/kdcllc/azure-terraform-skills/blob/v2.1.0/CHANGELOG.md).
- Operator guide and end-to-end walkthroughs ship with the skill: [references/using-the-pack.md](references/using-the-pack.md) and [references/deep-dive.md](references/deep-dive.md).

### Changed

- Module and stack templates moved from `templates/` to `assets/templates/`.

### Upgrade notes

- Install from the new repository: `npx skills add kdcllc/skills --skill terraform-azure`. Pin with `#terraform-azure/v1.0.0`.
- If you pinned `kdcllc/azure-terraform-skills#v2.1.0`, the content is the same; only the repository, the template path, and the version number changed.
