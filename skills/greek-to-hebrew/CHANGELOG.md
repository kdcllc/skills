# Changelog

All notable changes to the `greek-to-hebrew` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `greek-to-hebrew/vX.Y.Z`.

Before re-adding with a new tag, read the target version's entry, especially its **Upgrade notes**.

## [Unreleased]

## [1.0.0] - 2026-10-11

### Added

- Imported from [kdcllc/bible-study-skills at adcfb0f](https://github.com/kdcllc/bible-study-skills/tree/adcfb0f65c9beff4e97c18bc335848ff170310b3/skills/bible-study-nt-hebrew-trace). The tracing method, tool URLs, and caveats are unchanged; earlier history is in that repository's [commit log](https://github.com/kdcllc/bible-study-skills/commits/master).
- `LICENSE.txt` with the CC BY-SA 4.0 legal code, which the old repository only named in its README.

### Changed

- Renamed from `bible-study-nt-hebrew-trace` to `greek-to-hebrew`.
- Merged the two overlapping workflows in `SKILL.md` into one seven-step procedure with a single report template and a single high/moderate/tentative confidence scale.
- Moved `argument-hint` under `metadata` to match the Agent Skills spec.
- Moved the research notes from the repository's `docs/plan.md` into the skill as `references/methodology.md`, so they install with it.
- Tool instructions say "your web fetch tool" instead of naming `web_fetch`, and the BibleHub book-slug note in `references/tools.md` is reworded.

### Upgrade notes

- Install from the new repository: `npx skills add kdcllc/skills --skill greek-to-hebrew`. Pin with `#greek-to-hebrew/v1.0.0`.
- Remove the old install (the `bible-study-nt-hebrew-trace` skill folder) so agents don't load both.
- Prompts that say "use skill bible-study-nt-hebrew-trace" need the new name.
