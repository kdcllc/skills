# Changelog

All notable changes to the `orchestration-advisor` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `orchestration-advisor/vX.Y.Z`.

## [Unreleased]

## [0.3.1] - 2026-11-13

### Fixed

- Install steps were hard to find. The new `README.md` in the skill folder shows what the skill does, how to install it (skills.sh, GitHub CLI, Claude Code and Copilot CLI plugins, pinned releases), example prompts, and requirements. The skill's behavior is unchanged.

## [0.3.0] - 2026-11-12

### Added

- Audit mode. After the inspection, the skill asks "Recommend a setup, or audit the existing one?" and suggests an answer from the signals (audit when the project has agents, an `agent-kit` install, crews or orchestrator skills). Audit mode reviews an existing orchestration system, hooks and other enforcers included, and produces a current-vs-recommended comparison.
- A Map step (Step 4) and `references/audit.md`, which describe how to map each system, its tiers, and what enforces each gate, and the audit-mode decision rules.
- `references/report-audit.md`, the chat summary format, save offer and full report for audit mode.
- Seven new inspection keys: `harness_hook_entries`, `git_hook_files`, `rule_files`, `rubric_files`, `command_files`, `harness_config_files` and `orchestrator_skills`.

### Changed

- Step numbering: Map is Step 4, and Decide and Report move to Steps 5 and 6.
- The inspection contract has 25 keys instead of 18. `orchestrator_skills` leaves out the advisor itself.
- `references/patterns.md` adds "Shapes compose": shapes can be combined in one system, and the report names each in play.

## [0.2.0] - 2026-11-11

### Changed

- The inspection script exits with code 3 when a required tool (`find`, `awk`, `sort`, `wc` or `tr`) is not on `PATH`: it prints nothing on standard output and names the missing tool on standard error. `SKILL.md` Step 2 says to use the manual fallback in that case.
- `claude_agent_description_chars` counts bytes (`wc -c`) when `wc -m` fails on the description text, so the script still prints all 18 keys. The contract now states that the character count depends on the locale.
- `references/patterns.md` gives a re-check date for its harness statements (2027-02-10), and the report says the statements may be out of date when it is written after that date.
- Documentation clarifications: `references/signals.md` shows the project-root argument as optional (the current directory is the default), states that any directory-walk error is ignored and can leave a count low without a warning, and lists names containing a newline as a limit of the line-counting keys; `SKILL.md` lists the tools the script requires.
- The inspection script exits with code 1 when the description text cannot be counted (both `wc -m` and `wc -c` failed): it prints nothing on standard output and `inspect.sh: cannot count the description text` on standard error. `SKILL.md` Step 2 says to use the manual fallback in that case.
- `references/signals.md` states that the byte fallback for `claude_agent_description_chars` reads the agent files a second time, so a file that changes during the run can give a count of different text. The manual fallback in `SKILL.md` is now labelled "no bash, or exit code 1 or 3", and the Requirements section sends a missing required tool there too.

### Fixed

- Source attributions in `references/signals.md` (the `agent_files` and `test_paths` rows) and `references/patterns.md` (the split by type of work) now name the specific article behind each statement and mark the remaining parts as inferred.
- `references/patterns.md` dates Cursor's fresh-context subagent support as spot-checked 2026-10-16, as the harness matrix does, and cites the agent teams documentation in the `[9]` form its legend defines.
- The agent teams row of the routing table in `SKILL.md` no longer says "experimental" twice.
- Wording: `references/signals.md` says every key is printed on success (exit code 0), not always; `references/patterns.md` says "Such a split is not a reason for any row" so the sentence names the split by type of work; `SKILL.md` Step 2 says the project-root argument is optional and defaults to the current directory.
- When the description text cannot be counted, the inspection script prints only its own message on standard error, without the error text of `wc -c`. `SKILL.md` Requirements says "one of the required tools" where it sends a missing tool to the manual fallback. `references/patterns.md` says that parallel subagents on GitHub Copilot are not stated in the VS Code documentation (harness matrix, spot-checked 2026-11-11), in place of `not checked`.

## [0.1.0] - 2026-11-10

### Added

- Initial version: a read-only procedure (Detect, Inspect, Ask about the workload, Decide, Report) that recommends one of six orchestration shapes, defaulting to a single agent plus skills, and routes to `agent-kit`, `agent-composer`, folding agents into skills, or installing nothing.
- `references/signals.md` defines the 18 `key=value` signals of the inspection script, their exit codes, skip list, symlink rule, and known undercounts.
- `references/patterns.md` compares the six shapes, maps `agent-composer`'s five patterns onto them, and lists dated sources for every figure and harness statement.
