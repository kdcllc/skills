# Inspection signals

This file is the output contract of `scripts/inspect.sh`. The script reads a project and prints signals; it changes nothing. [../SKILL.md](../SKILL.md) Step 2 runs it and Step 5 reads the values.

Sources cited below by number are listed in [patterns.md](patterns.md) under Sources. Figures move as models improve; they are guidance, not pass/fail rules.

## Invocation and output format

```bash
bash <skill-dir>/scripts/inspect.sh [project-root]
```

With no argument the script inspects the current directory.

- Output: one `key=value` line per key, on standard output, in the order of the table below. On success (exit code 0) every key is printed.
- Values are non-negative integers or the literal `unknown`. By the definitions below, only `mcp_servers`, `tracked_files` and `harness_hook_entries` can be `unknown`.
- No other lines are printed on standard output.

```text
harness_claude=1
harness_cursor=0
harness_copilot=0
harness_codex=1
agent_kit_installed=0
composer_crews=0
agent_files=3
claude_agent_files=3
claude_agent_description_chars=612
claude_agent_description_tokens_est=153
skill_files=5
mcp_servers=2
test_paths=1
ci_workflows=2
lint_configs=1
typecheck_configs=1
package_manifests=1
tracked_files=214
harness_hook_entries=3
git_hook_files=1
rule_files=4
rubric_files=2
command_files=2
harness_config_files=1
orchestrator_skills=1
```

(The values above are an illustration of the format, not a measurement.)

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success. All 25 lines were printed. |
| 1 | The description text could not be counted (both `wc -m` and `wc -c` failed). Nothing is printed on standard output; the message `inspect.sh: cannot count the description text` is printed on standard error. |
| 2 | The argument is not an existing directory, or more than one argument was given. |
| 3 | A required tool (`find`, `awk`, `sort`, `wc` or `tr`) is not on `PATH`. Nothing is printed on standard output; a message naming the missing tool is printed on standard error. |

## Keys

"Basis" says whether the bearing on the decision is documented by a named source or inferred.

| Key | How it is computed | Bearing on the decision | Basis |
| --- | --- | --- | --- |
| `harness_claude` | 1 when `.claude/` or `CLAUDE.md` exists at the root, else 0 | Selects which harness-support statements in patterns.md apply | Documented: agent-kit harness matrix (agent-definition and rules rows, verified 2026-08-18) |
| `harness_cursor` | 1 when `.cursor/` exists, else 0 | Same | Documented: agent-kit harness matrix (verified 2026-08-18) |
| `harness_copilot` | 1 when `.github/copilot-instructions.md` or `.github/agents/` exists, else 0 | Same | Documented: agent-kit harness matrix (verified 2026-08-18) |
| `harness_codex` | 1 when `.codex/` or `AGENTS.md` exists, else 0 | Same, but weak when only `AGENTS.md` exists | Inferred: several harnesses read `AGENTS.md`, so the file alone does not show Codex is in use |
| `agent_kit_installed` | 1 when `orchestration-kit.manifest.json` exists at the root, else 0 | An evaluator-gated orchestrator is already installed; do not recommend installing it again, and count its agents as intended | Documented: agent-kit writes this manifest (agent-kit SKILL.md) |
| `composer_crews` | Count of `.agent-composer/*.crew.yaml` | Custom crews already exist; check each against the four reasons in SKILL.md Step 5 | Documented: agent-composer writes specs at this path (agent-composer SKILL.md) |
| `agent_files` | Number of distinct agent names across `.claude/agents`, `.cursor/agents`, `.github/agents` and `.codex/agents`. A name is the file name of a `.md` or `.toml` file directly inside one of those folders with its `.agent.md`, `.md` or `.toml` suffix removed (the longest matching suffix). The same name in two harness folders counts once | How many agents exist, and so how many descriptions to read for overlap and knowledge-only agents. A count of distinct agents, not of files | Merging specialists that touch the same data or are often called together, and turning their prompts into skills: documented (Source 2, 2026-10-22). Knowledge in skills in place of specialist agents: documented (Source 4, 2026-01-22). Reading overlapping descriptions as that signal, and any threshold on the count: inferred |
| `claude_agent_files` | Count of `.md` files directly inside `.claude/agents` | The set of files the two description keys below cover | Documented: Claude Code subagents documentation (Source 7, checked 2026-11-10) |
| `claude_agent_description_chars` | Total characters of the single-line `description:` frontmatter value across the files counted in `claude_agent_files`, with surrounding quotes removed. For a block value (`description: >` or `description: \|`) only the text on the `description:` line itself is counted, so the indicator line counts only its own characters (1 for `>`) and continuation lines count nothing. Characters are counted as `wc -m` counts them, so the count depends on the locale the script runs in. When `wc -m` fails on the text (bytes that are not valid in that locale), bytes are counted instead (`wc -c`). The byte fallback reads the agent files a second time, so a file that changes during the run can give a count of different text. A file with no `description:` adds 0 | Input to the estimate below; not compared with anything by itself | Documented: same as below |
| `claude_agent_description_tokens_est` | `claude_agent_description_chars` divided by 4, rounded down | Compared only with Claude Code's 15,000-token startup warning for combined custom subagent descriptions | The 15,000-token warning: documented, Claude Code subagents documentation (Source 7, checked 2026-11-10). The divide-by-4 conversion: inferred, a rough approximation and not a tokenizer count |
| `skill_files` | Number of distinct skill names across `.claude/skills`, `.cursor/skills`, `.github/skills`, `.agents/skills` and `.codex/skills`. A name is the name of a directory that directly contains a file named `SKILL.md`, at any depth under one of those roots. The same name under two roots counts once | Shows how much knowledge already lives in skills; with few skills and many knowledge-only agents, folding is the likely recommendation | Skills as the place for knowledge: documented (Source 4, 2026-01-22). Reading the count this way: inferred |
| `mcp_servers` | Number of keys under `mcpServers` in `.mcp.json` and `.cursor/mcp.json`, plus keys under `servers` in `.vscode/mcp.json`. 0 when none of the three files exists. `unknown` when at least one exists and `jq` is missing or a file is not valid JSON | Context for the "tool or prompt conflict" reason. It counts servers, not tools, so it is a proxy only | Inferred |
| `test_paths` | Count of directories named `test`, `tests`, `__tests__` or `spec` at depth 1 or 2 | An executable check may exist for a verifier to run; several may point to separately testable units. Confirm with workload answers 2 and 4 | A verifier needs explicit evaluation criteria: documented (Source 1, 2026-04-10). A verifier that runs the test suite needs no implementation context: documented (Source 3, 2026-01-23). A directory count as a proxy for such a check, and the check being fast: inferred |
| `ci_workflows` | Count of `.github/workflows/*.yml` and `*.yaml`, plus 1 for each of `.gitlab-ci.yml` and `azure-pipelines.yml` that exists at the root | Checks already run by a command; a verifier can lean on them | Inferred |
| `lint_configs` | Count of root files matching `.eslintrc*`, `eslint.config.*`, `biome.json`, `ruff.toml`, `.ruff.toml`, `.flake8`, `.golangci.yml`, `.golangci.yaml`, `.shellcheckrc` | Deterministic checks exist; prefer running them over adding a review agent for the same job | Inferred |
| `typecheck_configs` | Count of root files named `tsconfig.json`, `mypy.ini`, `pyrightconfig.json` | Same as `lint_configs` | Inferred |
| `package_manifests` | Count of files named `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml` or matching `*.csproj`, to depth 4 | More than one may point to separable units. Direction only; confirm with workload answer 2 | Inferred: no validated metric |
| `tracked_files` | `git ls-files` line count when the root is inside a git work tree and `git` is available, else `unknown` | Rough repository size. Direction only; never a reason by itself to add agents | Inferred: no validated metric |
| `harness_hook_entries` | Number of hook handler entries in harness hook configs. In `.claude/settings.json` and `.claude/settings.local.json`: for every event under the top-level `hooks` object, the length of every matcher group's `hooks` array, summed. In `.cursor/hooks.json`: for every event under the top-level `hooks` object, the length of its array, summed. 0 when none of the three files exists. `unknown` when at least one exists and `jq` is missing, or any existing one is not valid JSON (same rule as `mcp_servers`) | Hooks enforce gates in the harness; feeds the enforcement inventory of the Map step (SKILL.md). Every suggested change must name the enforcer that covers the affected gate afterwards (audit.md, Enforcer rule) | Documented: harness matrix, edit-hook rows (`PreToolUse` in `.claude/settings.json`, `preToolUse` in `.cursor/hooks.json`, verified per vendor hook docs). The count as a measure of enforcement: inferred |
| `git_hook_files` | Sum of: regular files directly inside `.git/hooks/` whose name does not end in `.sample` (only when `.git` is a directory); regular files directly inside `.husky/` (`.husky/_` is not entered); 1 for each of `lefthook.yml`, `.lefthook.yml`, `lefthook.yaml`, `.lefthook.yaml`, `.pre-commit-config.yaml` that exists at the root | Git-level checks outside the harness; feeds the enforcement inventory of the Map step | Inferred: not in the harness matrix; the paths are those the git, husky, lefthook and pre-commit tools use |
| `rule_files` | Count of files `.cursor/rules/**/*.mdc`, `.claude/rules/**/*.md` and `.github/instructions/**/*.instructions.md`, any depth, symbolic links followed. Files, not distinct names: rules in different harnesses are different files | Path-scoped rules steer agents and act as soft enforcement; feeds the enforcement inventory of the Map step | Documented: harness matrix, Rules/instructions row and Path-scoped guidance row (`.claude/rules/`, `.mdc`, `.github/instructions/*.instructions.md`) |
| `rubric_files` | Count of regular `.md` files at any depth under a directory named `rubrics` or `criteria` inside `.claude`, `.cursor`, `.github`, `.codex` or `.agents`, plus the number of distinct skill names (same roots and distinct-name rule as `skill_files`) ending in `-criteria` or `-rubric` | Evaluation criteria are the enforcer of verifier gates; feeds the enforcement inventory of the Map step | Inferred: a name-based heuristic; no harness defines a rubric path |
| `command_files` | Count of files `.claude/commands/**/*.md`, `.cursor/commands/**/*.md` and `.github/prompts/**/*.prompt.md`, symbolic links followed | Manual entry points of orchestration systems; lists files the Map step must read | Documented: harness matrix, Manual-only prompt file row |
| `harness_config_files` | Count of regular files directly inside `.claude/`, `.cursor/` or `.codex/` with suffix `.json`, `.jsonc`, `.yaml`, `.yml` or `.toml`, excluding `settings.json`, `settings.local.json`, `hooks.json` and `mcp.json` (counted elsewhere) | Model routing, environment and Codex config files; lists files the Map step must read | Inferred: no harness defines these names |
| `orchestrator_skills` | Number of distinct skill names (same roots and rule as `skill_files`) whose `SKILL.md` matches, case-insensitively, `subagent`, `sub-agent`, `task tool` or `spawn`, leaving out any skill whose frontmatter `name:` is `orchestration-advisor` (quotes and surrounding spaces ignored) | Heuristic for "this skill launches other agents"; feeds the suggested answer of the mode question at the end of Step 2 (SKILL.md). It only suggests a mode; the user chooses | Inferred: word match |

## Directory walks

**Skip list.** The directory walks for `skill_files`, `test_paths`, `package_manifests` and the rubric directories of `rubric_files` skip directories named `.git`, `node_modules`, `vendor`, `dist`, `build` and `.venv`.

**Symlink rule.**

- The walks for `agent_files`, `claude_agent_files` and `skill_files` follow symbolic links. A skill folder linked from one harness root to another is therefore found, and the distinct-name rule counts it once.
- The walks for `test_paths` and `package_manifests` do not follow symbolic links.
- The walks for `rule_files`, the rubric directories of `rubric_files`, and `command_files` follow symbolic links, apply no skip list for `rule_files` and `command_files`, and apply the skip list for the rubric walk. The `rubric_files` and `orchestrator_skills` skill-name parts use the `skill_files` walk (symbolic links followed, skip list applied).
- The `git_hook_files` and `harness_config_files` lookups read one folder level, do not follow symbolic links, and enter no subfolder (`.husky/_` included). `.git/hooks` is read only when `.git` is a directory.
- An error during a directory walk (a symbolic-link cycle, an unreadable directory) does not make the script fail: the script ignores the error and counts what it found, so a count can be low without a warning.

## Why some keys are shaped this way

- **The description keys are Claude Code only.** The 15,000-token startup warning is a Claude Code limit on Claude Code's own custom subagents (Source 7, checked 2026-11-10). The estimate is compared with nothing else, so descriptions in other harness folders are not measured.
- **`agent_files` and `skill_files` count distinct names.** A project mirrored to two harnesses (the same agents under `.claude/agents` and `.cursor/agents`, for example) is not counted twice.
- **`harness_codex` is inferred.** Several harnesses read `AGENTS.md`, so `harness_codex=1` from that file alone does not show Codex is in use. Ask the user.

## Known undercounts

- Codex agents declared only as `[agents.<name>]` tables in `.codex/config.toml` are not counted in `agent_files`.
- A skill folder named like a skipped directory (`build`, `dist`, `vendor`) is not counted in `skill_files`.
- Copilot and Codex hook configs are not counted in `harness_hook_entries`, and hooks declared in user-level settings are not counted.
- Rubric files in folders with other names than `rubrics` or `criteria` (and skills not named `*-criteria` or `*-rubric`) are not counted in `rubric_files`.

## Known overcounts

- `orchestrator_skills` matches words, so a skill that only mentions subagents, a task tool or spawning counts, whether or not it launches any agent.
- `orchestrator_skills` leaves out any skill whose frontmatter `name:` is `orchestration-advisor`, so the advisor does not count itself; a renamed copy of it counts.

## Limits of the signals

- Package independence, coupling and repository size have no validated metric. `package_manifests` and `tracked_files` give direction only, and no signal measures coupling.
- A code-ownership file is a warning sign for org-chart agent designs, not a reason to add agents. The script does not look for one.
- A file or directory name that contains a newline character is counted as more than one entry by every key that counts lines of `find` output: `agent_files`, `claude_agent_files`, `skill_files`, `test_paths`, `package_manifests`, `git_hook_files`, `rule_files`, `rubric_files`, `command_files` and `harness_config_files`.
- The signals cannot see the workload. The six questions in SKILL.md Step 3 carry at least as much weight as any value here.
