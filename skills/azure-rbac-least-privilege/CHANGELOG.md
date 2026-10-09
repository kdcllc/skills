# Changelog

All notable changes to the `azure-rbac-least-privilege` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `azure-rbac-least-privilege/vX.Y.Z`.

Before re-adding with a new tag, read the target version's entry, especially its **Upgrade notes**.

## [Unreleased]

## [1.0.0] - 2026-10-09

### Added

- Imported from [kdcllc/azure-rbac-role-matching-skill at 5f0597f](https://github.com/kdcllc/azure-rbac-role-matching-skill/tree/5f0597f6fa714a86ee306c73cdb86dd0a3b456de/skills/azure-rbac-role-matching). Matcher behaviour and snapshot data (`lastUpdated` 2026-04-20, 495 built-in roles, 18,120 provider operations) are unchanged; earlier history is in that repository's [commit log](https://github.com/kdcllc/azure-rbac-role-matching-skill/commits/master).

### Changed

- Renamed from `azure-rbac-role-matching` to `azure-rbac-least-privilege`.
- Installs from `kdcllc/skills` instead of the Copilot CLI plugin or npm. The package is now private and is loaded by relative path (`require('./scripts/lib/rbac')`) rather than `require('azure-rbac-role-matching-skill')`.
- Commands run with `node scripts/match-roles.js` and `node scripts/validate.js` from the skill folder; the `azure-rbac-role-match` bin is now `azure-rbac-least-privilege`.

### Upgrade notes

- Install from the new repository: `npx skills add kdcllc/skills --skill azure-rbac-least-privilege`. Pin with `#azure-rbac-least-privilege/v1.0.0`.
- Remove the old install (`/plugin uninstall azure-rbac-role-matching` or delete the `azure-rbac-role-matching` skill folder) so agents don't load both.
- Prompts that say "use skill azure-rbac-role-matching" need the new name.
