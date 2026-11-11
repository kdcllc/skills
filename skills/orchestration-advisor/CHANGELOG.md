# Changelog

All notable changes to the `orchestration-advisor` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `orchestration-advisor/vX.Y.Z`.

## [Unreleased]

## [0.1.0] - 2026-11-10

### Added

- Initial version: a read-only procedure (Detect, Inspect, Ask about the workload, Decide, Report) that recommends one of six orchestration shapes, defaulting to a single agent plus skills, and routes to `agent-kit`, `agent-composer`, folding agents into skills, or installing nothing.
- `references/signals.md` defines the 18 `key=value` signals of the inspection script, their exit codes, skip list, symlink rule, and known undercounts.
- `references/patterns.md` compares the six shapes, maps `agent-composer`'s five patterns onto them, and lists dated sources for every figure and harness statement.
