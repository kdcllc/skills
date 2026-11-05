# Changelog

All notable changes to the `agent-composer` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `agent-composer/vX.Y.Z`.

## [Unreleased]

## [0.1.0] - 2026-11-02

### Added

- Initial version: interview the user, write a YAML crew spec at `.agent-composer/<name>.crew.yaml`, and generate Claude Code and Cursor agent files plus an orchestrator skill from it.
- Five orchestration patterns (pipeline, router, fan-out, evaluator-optimizer, orchestrator-workers) and three example crews (coding, content, issue triage).
- `scripts/validate.sh` checks the spec (`S` codes) and the generated tree (`T` codes) with python3 and PyYAML, with a manual checklist when PyYAML is missing. `S040` warns on placeholder model IDs.
- `scripts/manifest.sh` records generated-file hashes so re-runs report unchanged, edited, missing, new, and orphaned files, plus `spec-changed` when the spec was edited after the last write.
- Generated orchestrators write the user's request into each root input, save every agent report to the run folder, keep earlier gate cycles as `<step-id>.cycle-<n>.report.md`, check exhaustion before re-running, and write `run-report.md`.
