# Changelog

All notable changes to the `agent-composer` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `agent-composer/vX.Y.Z`.

## [Unreleased]

## [0.3.2] - 2026-11-13

### Fixed

- `validate spec` no longer stops with an internal `TypeError` when a step `id` is a list or mapping in a spec with more than one agent. It now reports the step-id finding (`S006`).

## [0.3.1] - 2026-11-13

### Fixed

- Install steps were hard to find. The new `README.md` in the skill folder shows what the skill does, how to install it (skills.sh, GitHub CLI, Claude Code and Copilot CLI plugins, pinned releases), example prompts, and requirements. The skill's behavior is unchanged.

## [0.3.0] - 2026-11-12

### Added

- An agent can set `run: inline` in the crew spec. A knowledge-only worker then runs inside the orchestrator, which follows a generated role file at `<skill folder>/roles/<agent-id>.md` with its own tools, instead of spawning a subagent. No agent file is written for it, and a gate's re-run of an inline step runs inline again.
- Spec checks `S041` to `S043` reject an inline agent that is not a worker, has a tier other than `inherit`, or sits in `parallel` or `dispatch.workers`. `S044` warns about a knowledge-only worker that runs as a subagent and suggests `run: inline`; it skips an agent a gate re-runs and a duplicate agent id. `S027` is not repeated beside `S042` for the same agent.
- Tree check `T014` reports a leftover agent file for an agent that switched to `run: inline`, and `T015` reports a role file that is not valid UTF-8. The tree checks also expect each role file and apply the marker, leftover-token and collision checks to it.
- The interview asks, for each worker role, whether it needs its own tools, model tier or isolation, and proposes `run: inline` when it does not. `references/writing-agents.md` says when a role should stay a subagent.

## [0.2.1] - 2026-11-11

### Fixed

- The coding example crew's `reviewer` now lists `task-brief.md` in its `inputs` beside `tasks.yaml`, and its instructions name that file (the user's request) and each task's entry in `tasks.yaml` in place of "the task briefs", which named no file the reviewer was given.
- The coding example crew's `implementer` no longer writes `implementation-summary.md`, which every parallel task overwrote. It lists the changed files, the commands run and their results in its final report, which the orchestrator saves per task as `<workdir>/<run-id>/plan.<task-id>.report.md`; the `reviewer` reads those reports to find which files changed.

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
