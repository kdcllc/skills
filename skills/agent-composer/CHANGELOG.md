# Changelog

All notable changes to the `agent-composer` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `agent-composer/vX.Y.Z`.

## [Unreleased]

## [0.2.0] - 2026-11-10

### Changed

- The crew-or-not test in `references/patterns.md` now requires one of four reasons for a crew (context pollution, independent parallel units, tool or prompt conflict, need for an independent verifier), states the token cost of multi-agent runs, says a split by type of work is not a reason, and points to the `orchestration-advisor` skill.
- The interview asks which of the four reasons justifies each additional agent before it asks for roles, and offers one agent or a skill when none holds. Step 1 also reports how many agent files exist and the rough size of their descriptions against Claude Code's 15,000-token warning.
- `references/patterns.md` has a new section, "Patterns this skill does not generate", covering agent teams, message bus and shared state.
- The coding example crew has three agents instead of four: one `implementer` writes the code and the tests for each task and runs them, the `test-writer` is gone, and the `reviewer` judges the changed files against the plan and task briefs without taking the implementer's summary as evidence.

## [0.1.0] - 2026-11-02

### Added

- Initial version: interview the user, write a YAML crew spec at `.agent-composer/<name>.crew.yaml`, and generate Claude Code and Cursor agent files plus an orchestrator skill from it.
- Five orchestration patterns (pipeline, router, fan-out, evaluator-optimizer, orchestrator-workers) and three example crews (coding, content, issue triage).
- `scripts/validate.sh` checks the spec (`S` codes) and the generated tree (`T` codes) with python3 and PyYAML, with a manual checklist when PyYAML is missing. `S040` warns on placeholder model IDs.
- `scripts/manifest.sh` records generated-file hashes so re-runs report unchanged, edited, missing, new, and orphaned files, plus `spec-changed` when the spec was edited after the last write.
- Generated orchestrators write the user's request into each root input, save every agent report to the run folder, keep earlier gate cycles as `<step-id>.cycle-<n>.report.md`, check exhaustion before re-running, and write `run-report.md`.
