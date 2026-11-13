# Outcome eval set for agent-kit

This directory is the frozen contract for an outcome eval set. It compares two ways of doing the same small coding task: a baseline arm that gets only the request, and a kit arm that gets the request inside a project where agent-kit has been emitted and the request is run through `/feature`. Each task is graded by a hidden grader that looks only at the resulting project files.

Everything here is plain Bash and Python 3 standard library. The self-test needs no network and no `claude` binary. Real runs cost money and are described under "Running real evals".

## Layout

```
tests/agent-kit/evals/
  README.md          this contract
  answers.json       agent-kit answers used by the kit arm
  run.sh             runs one arm over the tasks and writes results.jsonl
  report.sh          turns one or more results.jsonl files into a markdown report
  selftest.sh        offline self-test (no network, no claude binary)
  lib/stub-cli.sh    stand-in for the claude CLI, used only by the self-test
  tasks/NN-slug/
    task.md          metadata, prompt and decisions
    seed/            the starting project (Python 3 standard library only)
    solution/        overlay that turns the seed into a passing project
    grade/
      grade.sh       the hidden grader (plus any hidden test files under grade/)
```

No file in the tree is named `SKILL.md`, and no folder is named `.claude`, `.cursor`, `.agents` or `.github`. The repository publishes every `SKILL.md` it finds and scans such folders, so the eval tree must not contain them. The kit arm creates `.claude/` only inside a scratch copy outside the repository.

## Task format

`task.md` starts with a metadata list, then two sections:

```
- id: NN-slug
- category: <one of the 10 categories>
- size: trivial|small|medium

## Prompt
<the request given to both arms>

## Decisions
- <one Phase 1 answer per line>
```

- `## Prompt` is the request given to both arms. It contains no repository paths and does not mention graders.
- `## Decisions` holds the Phase 1 answers for the kit arm, one `- ` line each. The kit prompt passes them as the user's confirmed answers. `## Decisions` only answers process questions the kit asks at Phase 1 (scope confirmations, phases, choices among options the prompt already allows); it must not add a requirement or a fact that `## Prompt` and the project files do not contain.
- Seeds are Python 3 standard-library projects. Their own tests run with `python3 -m unittest discover -s tests -t .` from the project root and pass on the seed.
- `solution/` is an overlay. Its files are copied over the seed at the same relative paths. A file listed in an optional `solution/.delete` (one relative path per line) is removed.

## Categories

The 10 categories and the task ids tasks 03 and 04 use. The `NN` prefix of a task id is the category number.

- `01-trivial-fix`: a one-line fix; measures whether the kit adds cost to work that needs none.
- `02-bug-fix`: find and fix a defect from a symptom; measures diagnosis.
- `03-small-feature`: add one function or option with tests; measures plain feature delivery.
- `04-multi-file-rename`: rename a symbol across several files; measures completeness.
- `05-spec-edge-cases`: implement a spec whose edge cases are easy to miss; measures requirement coverage.
- `06-write-tests`: add tests to untested code without changing it; measures test quality.
- `07-refactor`: restructure code while keeping behaviour; measures regression safety.
- `08-scope-trap`: a request next to tempting unrelated problems; measures staying in scope.
- `09-signature-change`: change a function signature and update every caller; measures ripple handling.
- `10-error-handling`: add input validation and clear errors; measures defensive behaviour.

## Grader interface

```
bash grade/grade.sh <project-dir>
```

- It runs with cwd anywhere.
- It never modifies `<project-dir>` except inside a `mktemp -d` copy.
- It prints one line per check, `CHECK pass <name>` or `CHECK fail <name>`, then `GRADE pass` or `GRADE fail`.
- Exit codes: 0 when every check passes, 1 when any check fails, 2 on a grader error (missing project dir).
- Every grader includes one no-regression check: the project's `tests/` pass and their test count is not below the seed's.
- Graders judge only seed-relative paths. They ignore `.claude/`, `_kit/`, `_loop/`, `_memory/`, `CLAUDE.md`, `AGENTS.md`, `.gitignore`, `.gitattributes`, `orchestration-kit.manifest.json`, and tool caches anywhere in the tree (`__pycache__/`, `*.pyc`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/`), plus `.DS_Store` and `.coverage` files anywhere in the tree. "Changed" means a seed file modified or deleted, or a new file outside those paths.
- Graders never rely on git history. Any seed hashes they need are kept under `grade/`.
- Python 3 standard library only.

## run.sh

```
bash tests/agent-kit/evals/run.sh --arm baseline|kit [options]
```

| Option | Default | Meaning |
|--------|---------|---------|
| `--arm baseline\|kit` | none (required) | Which arm to run. A missing or other value prints usage on stderr and exits 2. |
| `--tasks id[,id…]` | all task directories, in id order | Tasks to run. |
| `--runs N` | `3` | Runs per task; an integer of at least 1 (`--runs 0` is a usage error). |
| `--model ID` | `claude-sonnet-5-5` | Model passed to the CLI. |
| `--budget-usd X` | `5` | Per-run budget passed as `--max-budget-usd`. |
| `--timeout S` | `1800` | Per-run timeout in seconds, an integer of at least 1. |
| `--label NAME` | the arm name | Label recorded in each row and used by `report.sh`. |
| `--kit-src DIR` | `skills/agent-kit` relative to the repo root | Kit source for the emit step. Used only by `--arm kit`. |
| `--out DIR` | `_memory/work/evals/<label>-<UTC YYYYmmddTHHMMSSZ>/` under the repo root | Output directory. |
| `--keep` | off (scratch projects are removed) | Keep scratch projects. |

Environment:

- `EVAL_CLI`: the CLI to run. Default `claude`. It may hold a command with arguments, split on spaces, so the command and its script path must not contain spaces.
- `EVAL_TASKS_DIR`: the task root. Default `tests/agent-kit/evals/tasks` under the repo root. The self-test points it at scratch task trees.

Paths the runner uses (the task root, `answers.json`, the default kit source) resolve relative to the script's own directory.

Exit codes:

- 0: every run was executed and graded (passing or failing).
- 2: usage error.
- 3: a run could not be set up (seed copy or kit emit failed). The runner stops at once, records no row for that run, and keeps the rows already written.
- Sourcing `fixture-root.sh` exits 1 before any run when the run-level temp directory is unusable.

### Per-run procedure

0. Before any git or emit call, the runner sources `tests/agent-kit/lib/fixture-root.sh` with `REPO_ROOT` set and `FIXTURE_TMPDIR` set to a run-level `mktemp -d` outside the repository. Empty or in-repository scratch paths are refused. The repo-locating `GIT_*` variables are unset, and global and system git config are off for the runner, `emit.sh` and the CLI. After each `git init` the runner calls `assert_fixture_repo <scratch>`; a failure counts as a setup failure (exit 3). Commit identity comes from exported `GIT_AUTHOR_*` and `GIT_COMMITTER_*` variables. No file under `tests/agent-kit/evals/` writes a repository-level git user setting, which `tests/agent-kit/templates/git-isolation.sh` scans for.
1. Scratch is `mktemp -d "$FIXTURE_TMPDIR/run.XXXXXX"` (`assert_fixture_repo` refuses a path outside `FIXTURE_TMPDIR`). `FIXTURE_TMPDIR` is removed at exit unless `--keep` is given, in which case the runner prints its path. Copy `seed/` into scratch, run `git init`, and commit everything as the base.
2. Kit arm only: run `bash <kit-src>/bin/emit.sh --root <scratch> --kit <kit-src> --answers <evals dir>/answers.json`, then commit. The base is this post-emit commit for the kit arm and the seed commit for baseline.
3. Run the CLI with cwd set to scratch:

   ```
   $EVAL_CLI -p "<prompt>" --output-format json --model <model> --max-budget-usd <budget> \
     --permission-mode acceptEdits --allowedTools "Read Edit Write Glob Grep Bash Agent Skill TodoWrite" \
     --setting-sources project --strict-mcp-config --no-session-persistence
   ```

   The CLI's stdin is `/dev/null`, so it never reads the terminal. The environment of the CLI has `EVAL_TASKS_DIR`, `OLDPWD` and these 18 Claude session variables removed: `CLAUDECODE`, `CLAUDE_EFFORT`, `CLAUDE_PID`, `CLAUDE_AGENT_SDK_VERSION`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_EMIT_STARTUP_TIMING`, `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING`, `CLAUDE_CODE_ENABLE_TASKS`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `CLAUDE_CODE_MESSAGING_SOCKET`, `CLAUDE_CODE_MESSAGING_TOKEN`, `CLAUDE_CODE_QUESTION_PREVIEW_FORMAT`, `CLAUDE_CODE_SESSION_ATTENDED`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_STARTUP_FAILURE_RESULTS`, `CLAUDE_CODE_SSE_PORT`. It is an explicit denylist because a stale keep-list would silently break authentication, while a missed session variable only leaks; no credential, TLS, proxy or provider variable is removed. To re-take the list, run `env | grep -E '^CLAUDE' | cut -d= -f1` inside a Claude Code session. The runner never uses `--dangerously-skip-permissions`. It runs under `timeout <S>` when `timeout` exists, or `gtimeout` when `timeout` is absent. Stdout goes to `<out>/<task>/<run>/cli.json` and stderr to `cli.stderr`.
4. After the CLI exits, copy `grade/` to a separate `mktemp -d` under `FIXTURE_TMPDIR` (removed with it) and run `bash <that>/grade.sh <scratch>`, with output to `grade.txt`. A grader that exits 2 (or any code other than 0 and 1) gives a row with `pass` false and the checks counted from its output; the runner continues and its own exit code does not change.
5. Remove tool caches from scratch (`__pycache__/`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/`, `*.pyc`), run `git -C <scratch> add -A` (gitignored paths stay excluded), then write `changes.txt`: the `git diff --cached --stat <base>` output, then a line `--- paths ---`, then `git diff --cached --name-only <base>` (one path per line).
6. Append one JSONL row to `<out>/results.jsonl`.

`grade/` and `solution/` are never copied into scratch.

## Prompts

The `## Prompt` text is taken with leading and trailing blank lines trimmed.

Baseline prompt: the `## Prompt` text, one blank line, then this fixed paragraph.

> You are working without a user. Do not ask questions; make reasonable decisions and finish the work. Do not push or open pull requests.

Kit prompt: `/feature ` followed by the `## Prompt` text, one blank line, this fixed headless preamble, one blank line, the line `Decisions:`, then the `## Decisions` lines verbatim.

> No user is available. The lines below under Decisions are the user's confirmed Phase 1 answers: record them in the goal and continue without waiting for confirmation. Set the goal's `phases:` block to `align_docs: false`, `pull_request: false`, `ladder: auto`, `qa: skip`. At every decision gate or escalation, take the recommended option and log it. Never push or open a pull request. Stop after Phase 5 is APPROVED and the quality checks have run.

## Result rows

`results.jsonl` holds one JSON object per line, with these keys in this order:

1. `task`: task id.
2. `arm`: `baseline` or `kit`.
3. `label`: the `--label` value.
4. `run`: 1-based run number.
5. `model`: the `--model` value.
6. `pass`: true or false (the grader exited 0).
7. `checks_passed`: number of `CHECK pass` lines.
8. `checks_total`: number of `CHECK` lines.
9. `cli_exit`: exit code of the CLI (or of `timeout`).
10. `timed_out`: true when the CLI was run under `timeout` (or `gtimeout`) and either exited 124, or exited 137 or 143 and its wall time reached the `--timeout` value (BusyBox `timeout` does not exit 124); otherwise false.
11. `duration_s`: wall time of the CLI call only (step 3), rounded down to whole seconds.
12. `cost_usd`: number from the CLI JSON `total_cost_usd`, or null.
13. `num_turns`: from the CLI JSON, or null.
14. `stop_reason`: the CLI JSON `subtype`, such as `success` or `error_max_budget_usd`, or null.
15. `changed_files`: the number of non-empty lines after the `--- paths ---` marker in `changes.txt`.
16. `spawns`: kit arm: number of lines matching `^### .* — SPAWN ` across `_memory/work/goals/*/orchestration-log.md` in scratch; baseline: null.
17. `kit_src`: kit arm path; baseline null.
18. `started_at`: UTC ISO 8601.

A CLI output that is not JSON gives null `cost_usd`, `num_turns` and `stop_reason`, not a runner failure.

## report.sh

```
bash tests/agent-kit/evals/report.sh DIR [DIR…]
```

It reads every `results.jsonl` under the given directories and prints markdown to stdout:

- A header line naming the directories.
- A table with one row per task and one column group per `label`: pass `k/n`, mean `cost_usd` with 2 decimals or `n/a`, mean `duration_s`. A totals row follows.
- With two or more labels, one line per further label, naming both labels, with per-task wins, losses and ties against the first label (the label of the first row of the first DIR given). The line format is exactly `vs <first label>: <label> wins <w>, losses <l>, ties <t>`, counting tasks present for both labels only. A win is a higher pass rate for the further label, a loss a lower one, a tie an equal one.
- For each `kit`-arm label, the line `warning: <n> kit run(s) with spawns 0 (the kit may not have run)` when any kit-arm row has `spawns` 0.
- Per label, the line `note: <n> run(s) of <label> stopped by budget or timeout` when any row has `timed_out` true or a `stop_reason` starting with `error_max`.
- The caveat line, printed as `caveat: ` followed by the quoted text: "at 10 tasks × 3 runs, differences below roughly 25 percentage points are within noise (K3: even a 24-task, three-run design hides differences under about 10 points); there are no pass/fail thresholds".

Exit 0; exit 2 when no `results.jsonl` is found.

## Stub CLI

`lib/stub-cli.sh` stands in for the real CLI in the self-test. It accepts the same arguments as the CLI in the per-run procedure and ignores them except `-p`. `EVAL_CLI` is split on spaces, so the command and its script path must not contain spaces; the self-test copies the stub to a scratch path without spaces. Other paths are passed through the environment.

Behaviour comes from `EVAL_STUB_MODE`:

- `solve`: copy the overlay from `EVAL_STUB_SOLUTION` (a path the self-test sets) into cwd, honouring `.delete`.
- `noop`: change nothing.
- `solve` and `noop` both write `{"type":"result","subtype":"success","total_cost_usd":0,"num_turns":1,"is_error":false,"result":"stub"}` to stdout.
- `garbage`: change nothing and write the non-JSON line `stub: not json` to stdout.
- `sleep`: sleep 5 seconds and change nothing.

When `EVAL_STUB_PROBE` (a file path) is set, the stub writes it with these lines:

- `grade_visible=yes|no`: whether any `grade.sh` or `solution/` exists under cwd.
- `prompt_has_feature=yes|no`: whether the `-p` prompt starts with `/feature`.
- `claude_env=yes|no`: whether any of the 18 Claude session variables removed in the per-run procedure is set.

## Self-test

`bash tests/agent-kit/evals/selftest.sh` checks:

- Grader true negative on the seed and true positive on the solution, for every task.
- Stub runs of both arms: `solve` gives `pass:true` and `noop` gives `pass:false`.
- The kit arm scratch holds `.claude/agents/evaluator.md` after emit.
- The probe shows `grade_visible=no`.
- The kit prompt starts with `/feature`.
- Rows carry every key of "Result rows", in order.
- `report.sh` prints the table, the win/loss/tie line, the spawns-0 warning, the budget or timeout note line and the caveat.
- The probe shows `claude_env=no` with `CLAUDECODE=1` exported to the runner.
- Caller-repository isolation holds under an exported `GIT_DIR`.
- Row values: for a baseline `solve` run, `checks_passed == checks_total`, `cli_exit` 0, `timed_out` false, `cost_usd` 0, `num_turns` 1, `stop_reason` `success` and `changed_files` at least 1; for `noop`, `changed_files` 0; for a kit `solve` run, `changed_files` at least 1 against the post-emit base.
- `garbage` gives null `cost_usd`, `num_turns` and `stop_reason`, and exit 0.
- `--arm kit --kit-src <empty dir>` exits 3 and adds no row.
- `sleep` with `--timeout 1` gives `timed_out` true (when `timeout` exists).
- A usage error exits 2.
- No `SKILL.md` file and no `.claude`, `.cursor`, `.agents` or `.github` folder exists in the tree.
- Candidate checks (added by the candidates goal; see "Candidates" and "compare.sh"):
  - `compare.sh --check` passes for every candidate: the marker is present in the patched emit and absent in the stock emit.
  - A candidate whose patch does not apply gives exit 3.
  - A candidate whose marker is also in the stock emit gives `check <name>: FAIL …`.
  - The `--plan` line and its arithmetic.
  - Usage errors exit 2: an unknown flag, an unknown `--cand` name, and `--plan` together with `--check`.
  - `--with-baseline` adds a `baseline` row.
  - A stub-CLI run of `compare.sh --cand <one> --runs 1 --tasks 01-trivial-fix` writes rows labelled `kit` and the candidate, and prints a `vs kit:` line.

The summary line is `PASS: <p> FAIL: <f> SKIP: <s>`, matching the format `tests/agent-kit/run-all.sh` recognizes. The self-test needs no network and no `claude` binary.

## Running real evals

A real run costs money and needs an authenticated `claude` on the path. Never run it in CI.

```
# baseline arm
bash tests/agent-kit/evals/run.sh --arm baseline

# kit arm (the kit in this checkout)
bash tests/agent-kit/evals/run.sh --arm kit

# candidate kit from another checkout, recorded under its own label
bash tests/agent-kit/evals/run.sh --arm kit --kit-src /path/to/skills/agent-kit --label kit-k1

# compare result directories (the first directory's label is the reference)
bash tests/agent-kit/evals/report.sh _memory/work/evals/baseline-<stamp> _memory/work/evals/kit-<stamp> _memory/work/evals/kit-k1-<stamp>
```

Limits and flags:

- The grader is hidden from the agent only by not being copied into scratch. The agent's Bash tool can still read the whole repository if it finds the path, so a determined agent could read a grader. Treat results as a measure of ordinary behaviour, not as tamper-proof.
- `--permission-mode acceptEdits` with an explicit `--allowedTools` list lets the agent edit and run commands inside scratch without a user. `--dangerously-skip-permissions` is not used because it would remove every permission check, including ones that keep the run from touching files outside scratch.
- `--setting-sources project` loads only the scratch project's settings, `--strict-mcp-config` loads no MCP servers, and `--no-session-persistence` leaves no session behind. The environment cleanup and git isolation in the per-run procedure keep the run away from the launching session and from this repository.
- At 10 tasks and 3 runs per task the results are noisy; read the caveat that `report.sh` prints.

## Candidates

A candidate is a proposed change to the kit that is measured before it is adopted. Each candidate is a directory `candidates/<name>/` (the name uses lowercase letters, digits and hyphens) that holds `patch.diff` and `README.md`. Nothing under `skills/` changes while a candidate is measured.

Patch format: a unified diff relative to the kit directory (paths like `a/templates/...`), applied with `git apply -p1` inside a copy of `skills/agent-kit/`. A patch may touch only files under `templates/`.

Candidate README sections, in this order: `## Hypothesis`, `## Change`, `## Expected effect`, `## Marker`, `## Files touched`. They are listed inline here, not shown as a fenced example, so this README has no extra `## ` heading lines.

Marker rule: `## Marker` holds exactly one line, and the whole content of that line is a backticked fixed string. The string is taken from the new instruction text the patch adds, not from a comment or a tag added only to be found. It must occur in the patched emitted `.claude/` tree and must not occur in the stock emitted `.claude/` tree.

Candidates are temporary. A later goal adopts each one (moves the change into `skills/agent-kit/` with a version bump) or deletes it. A patch that no longer applies fails the self-test and must be regenerated or deleted.

Budget rule: a patched kit keeps `templates/skills/feature/SKILL.template.md` at or below 11264 bytes (`tests/agent-kit/templates/skill-slimming.sh`, check (f)). Detail beyond that goes into a `templates/skills/feature/reference/*.md` file with a one-line pointer. `compare.sh --check` enforces it.

The four candidates:

- `k1-fold`: the test task goes to `implementer`, with no `test-writer` spawn.
- `k1-spec`: `test-writer` writes black-box tests from the task spec and the public signatures, not from module bodies.
- `k2-rightsize`: a deterministic, logged size rubric before Phase 1 routes small requests to a lite path.
- `k4-criteria`: evaluator task verdicts carry one row per acceptance criterion (met, unmet or unverified, with evidence), and PASS only when every row is met.

K4's "no new findings for N cycles" stop rule is not a candidate. The nearest existing rule is the section "Early ladder entry" in `skills/agent-kit/templates/skills/feature/reference/fix-cycles.md` (line 135): under `ladder: auto` a repeated `[structural]` key ends fix cycles early and starts the continuation ladder, which is more work, not a stop. The stop rule is left for a later candidate.

## compare.sh

```
bash tests/agent-kit/evals/compare.sh [--plan|--check] [--cand NAME]... [--with-baseline] [--tasks …] [--runs N] [--model ID] [--budget-usd X] [--timeout S] [--out DIR] [--keep]
```

Defaults:

- `--cand`: every directory under `candidates/` that holds a `patch.diff`, sorted.
- `--with-baseline`: off.
- `--out`: `_memory/work/evals/compare-<UTC YYYYmmddTHHMMSSZ>/` under the repo root.
- `--tasks`, `--runs`, `--model`, `--budget-usd`, `--timeout`: passed to `run.sh` unchanged, so `run.sh`'s own defaults apply.

An unknown `--cand` name, an unknown flag, or `--plan` together with `--check` prints usage on stderr and exits 2. `--plan` validates `--runs` (an integer of at least 1) and `--budget-usd` (a positive number) itself and exits 2 otherwise. Under `--check` the `run.sh` options are accepted and ignored.

Locations:

- Candidates are read from `EVAL_CANDIDATES_DIR`. Default: `<evals dir>/candidates`, where the evals dir is the script's own directory.
- The stock kit (`<repo>/skills/agent-kit`) and `<repo>/tests/agent-kit/lib/fixture-root.sh` resolve from the repository root, three levels above the script. A copy of `compare.sh` therefore works only inside a repo-shaped tree: `<S>/skills/agent-kit`, `<S>/tests/agent-kit/lib/` and `<S>/tests/agent-kit/evals/`.
- `EVAL_CLI` and `EVAL_TASKS_DIR` pass through to `run.sh`.

`--plan` uses `run.sh`'s defaults when an option is absent: 3 runs, budget 5, and every task directory under `EVAL_TASKS_DIR` (default `<evals dir>/tasks`). The `arms:` line lists labels in run order: `kit`, then the selected candidates in name order, then `baseline` when `--with-baseline` is given.

`--keep` is passed to every `run.sh` call and also keeps compare.sh's own `FIXTURE_TMPDIR` (the kit copies). `--out` and `--keep` are accepted and ignored under `--check` and `--plan`, except that `--check` with `--keep` keeps its scratch.

An unknown `--cand` name is a name with no directory under `EVAL_CANDIDATES_DIR`, or a directory without `patch.diff`; both exit 2. The names `kit` and `baseline` are reserved: a candidate directory with either name exits 2 with a message.

The answers file for every emit is `<evals dir>/answers.json`.

Exit codes:

- 0: `--plan` printed, every `--check` passed, or every `run.sh` call exited 0.
- 1: `--check` found at least one failing candidate (or the stock kit failed to emit), or, in a full run, `run.sh`'s own exit 1 passed through. After argument parsing, sourcing `fixture-root.sh` (or creating the run-level temp directory) can also fail with exit 1.
- 2: usage error.
- 3: a patch did not apply. The message names the candidate and nothing is run.
- Otherwise (a full run): the first non-zero `run.sh` exit code, after the remaining arms still ran.

### compare.sh procedure

0. Source `fixture-root.sh` with a run-level `FIXTURE_TMPDIR` under `mktemp -d`. All scratch lives inside it. It is removed at exit unless `--keep` is given.
1. For each selected candidate, copy `skills/agent-kit/` to `<FIXTURE_TMPDIR>/kits/<name>/` and apply the patch there with `git apply -p1`. A failure prints a message naming the candidate, exits 3, and runs nothing.
2. `--check`: emit the stock kit and each patched kit into scratch git repos with `answers.json`, calling `assert_fixture_repo` after each `git init`. Each candidate needs emit exit 0, the marker rule and the budget rule from "Candidates". Print `check <name>: ok` or `check <name>: FAIL <reason>` per candidate. Exit 0 when all are ok, otherwise 1. `run.sh` is never called.
3. `--plan`: print one line, `plan: <arms> arms × <tasks> tasks × <runs> runs = <n> runs; upper cost bound $<n × budget, two decimals>` (for example `plan: 2 arms × 1 tasks × 2 runs = 4 runs; upper cost bound $20.00`), then one line `arms: <labels, space-separated>`. Exit 0. `run.sh` is never called.
4. Otherwise, a full run:
   - `run.sh --arm kit --label kit --out <out>/kit` with the stock kit (the default `--kit-src`).
   - `run.sh --arm kit --kit-src <copy> --label <name> --out <out>/<name>` for each candidate.
   - With `--with-baseline`, `run.sh --arm baseline --label baseline --out <out>/baseline`.
   - The `run.sh` options are passed through.
   - Then print the `report.sh` output over the arm directories that hold a `results.jsonl`, stock kit first, so the `vs kit:` win, loss and tie lines compare each candidate with the stock kit. An arm whose `run.sh` exited before writing a row is named on stderr and left out.

Under `--check`, if the stock kit fails to emit, print `check stock: FAIL <reason>` and exit 1 without checking candidates.

When no arm wrote a row, compare.sh prints `compare.sh: no results to report` on stderr and exits with the first non-zero `run.sh` exit code (or 1 when every `run.sh` exited 0). When the stock `kit` arm wrote no row but candidates did, compare.sh still runs `report.sh` and prints one stderr line saying the comparisons are not against the stock kit.

Output layout: `<out>/kit/`, `<out>/<name>/` for each candidate and, with `--with-baseline`, `<out>/baseline/`, each holding what `run.sh --out` writes.
