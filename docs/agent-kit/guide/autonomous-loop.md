**Who this is for / What you'll learn:** Kit **users** who want to run the optional autonomous loop responsibly — and kit **contributors** who need to understand what the canonical drivers enforce. You will learn what one loop **run** is, how a single iteration moves from driver dispatch through evaluation-gated commit and breaker checks, which structural guards the drivers apply (not honor-system prose), how `LOOP_SLOTS` and `LOOP_WORKTREE` interact, what exit codes 0–5 mean, and how quarantine markers protect the repo when a slot goes wrong. When to choose the loop over `/feature` or direct edit is covered in [decision-guide.md](decision-guide.md).

# Autonomous Loop

The autonomous loop is **optional**. It drives unattended runs: the loop driver (`_loop/loop.sh` or `_loop/loop.ps1`) repeatedly dispatches the `auto-loop` skill with fresh context until the run budget is exhausted or a structural guard stops the run. **SAFETY: run inside a sandbox** (worktree/container) with minimal credentials. A worktree only separates the git tree — it gives no filesystem, network, or credential isolation — so any CLI flag that skips permission prompts or disables the CLI's own sandbox (for example Cursor `--force` or Codex `--sandbox danger-full-access`) needs a container or VM. The drivers never push and never bypass permission prompts by themselves — the same sandbox warning appears in the skill [README](../../../skills/agent-kit/README.md) and the loop driver header.

This guide describes **canonical shipped behavior** — what `/agent-kit` emits from `skills/agent-kit/templates/loop/` into your project's `_loop/` tree. In **this kit repo**, the emitted instance is gitignored and `_memory/loop/` is not tracked, so live runs here stay serial on the main tree; `LOOP_WORKTREE=1` requires a **tracked** `_memory/loop/backlog.md` (and harness directory) in the install, which is labeled explicitly wherever it matters below.

## What a run is

One **run** is:

1. **N iterations** — the driver's `max-iterations` argument (default **10** when omitted), counting total dispatches across all active slots.
2. **One backlog story per fresh-context iteration** — each dispatch gets a clean CLI session; state lives in `_memory/loop/backlog.md`, git, and outbox files, never in driver memory.
3. **One human-approved PR at run end (when enabled)** — Phase 7 (`ship-pr`) ships the branch as a single pull request with your approval when loop-level `pull_request` is enabled. The loop never auto-pushes.

If you have not installed the loop yet, see [getting-started.md](getting-started.md) for `/agent-kit` and the emitted `_loop/` layout.

## One iteration's lifecycle

Each iteration follows the same contract whether it runs in the main tree or a driver-managed worktree. The driver owns story selection, write-set admission, backlog transitions, and integration; the `auto-loop` skill executes exactly one story per dispatch.

```mermaid
flowchart TD
    Select["Story selection\n(driver-owned dispatch)"]
    Admit["Write-set admission\n(protected paths refused)"]
    Exec["Iteration execution\n(main tree or worktree)"]
    Eval["Evaluation-gated commit\n(evaluator PASS + ladder rungs 1-2)"]
    Breaker["Breaker checks\n(CB0-CB2, model breaker)"]
    Next["Next iteration"]
    Retire["Slot retirement\n(CB1 or CB2)"]
    Exit["Run exit\n(aggregated code)"]

    Select --> Admit
    Admit -->|"admitted"| Exec
    Admit -->|"protected path refused"| Select
    Exec --> Eval
    Eval --> Breaker
    Breaker -->|"slot healthy"| Next
    Breaker -->|"CB1 or CB2 trip"| Retire
    Retire --> Next
    Next --> Select
    Breaker -->|"CB0 protected-path violation"| Exit
    Next -->|"no eligible stories or max iter"| Exit
```

**Story selection (driver-owned dispatch).** The driver reads `_memory/loop/backlog.md`, picks the highest-priority eligible story (`passes: false`, not blocked, within attempt limits), increments `attempts` at claim time, and dispatches a prompt naming the story id and outbox directory. Slots never re-select or print `<promise>COMPLETE</promise>` in dispatched mode — that sentinel is for manual `auto-loop` runs only.

**Write-set admission.** Before dispatch, the driver checks the story's declared `writes:` globs against other in-flight claims and refuses stories that would touch **protected paths** (see below). Refused stories are skipped for this run, not silently widened.

**Iteration in main tree or worktree.** The emitted default follows the install's `flags.loop_worktree` (`0` unless worktree was chosen at install); an explicit `LOOP_WORKTREE` env value, including `0`, wins. At `LOOP_WORKTREE=0`, every slot runs in the main checkout. At `LOOP_WORKTREE=1`, each slot gets its own git worktree under `.loop-worktrees/` after a tracked-instance preflight.

**Evaluation-gated commit.** The iteration follows `/feature` Phases 2–6 with the story's acceptance criteria replacing Phase 1 alignment. Phase 7 (`pull_request`) is deferred to the end of the whole run — the loop never pushes during per-story iterations. A commit lands only on evaluator PASS (or APPROVED for audits) plus green test-ladder rungs 1–2; rung 3 runs per story after that story's Phase 5 audit. Details of verdicts and the ladder live in [evaluation-system.md](evaluation-system.md). Iterations inherit Phase 4's continuation ladder (rungs 5→4→6 on fix-cycle exhaustion, before terminal escalation) because each iteration runs the phased flow; the drivers' per-story attempt cap and circuit breakers stay the unchanged outer backstop. Ladder mechanics are documented in [feature-workflow.md](feature-workflow.md).

**Phase 6/7 and ladder controls** — the loop cannot ask questions, so flags are read from story backlog frontmatter and run configuration only (same naming as `goal.md`'s `phases:` block):

- **`align_docs`** (per story, default `true`): Phase 6 (`align-docs`) runs **per story** when enabled, so doc updates land in the story's commit and documentation never drifts from shipped code. A story may set `align_docs: false` in its backlog frontmatter to skip the per-story Phase 6 run; the skip is logged, never silent — write "Phase 6 skipped per story frontmatter" to the orchestration log.
- **`ladder`** (per story, fixed `auto`): loop-created goals always set `ladder: auto` in `goal.md`'s `phases:` block so cycle-3 exhaustion runs the continuation ladder unattended; the drivers' attempt cap and circuit breakers remain the outer backstop.
- **`pull_request`** (loop-level, opt-in): the end-of-run ship step stays explicitly enabled — a human or an opt-in final step runs `ship-pr` once to draft and create the PR/MR on the project's forge, or hand over. Control this with loop-level `pull_request` in run configuration (`pull_request: false` skips the ship step with a logged skip, never silent); default remains opt-in as today.

**Breaker checks.** After each reap, the driver evaluates per-slot circuit breakers (CB1 no-progress, CB2 repeated signatures), the model rate-limit breaker, and protected-path diffs (CB0). Trips **retire** the slot rather than stopping the whole run on first failure — unless CB0 fires (exit 4).

**Next iteration / retirement / exit.** Healthy slots refill; retired slots are not refilled. When every slot is retired, or the backlog is drained, or `max-iterations` is reached, the driver aggregates an exit code (see below).

## Structural safety guards

These guards are **structural** — enforced by `loop.sh` / `loop.ps1` and the `auto-loop` skill, not optional prose. They mirror the canonical guard table in [`skills/agent-kit/templates/ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md).

| Guard | Driver behavior |
|-------|----------------------------------|
| **Protected paths** | The loop may not modify `_loop/`, kit agents/skills, `orchestration-kit.manifest.json`, or `.gitattributes`. **`_memory/records/`** and **`_memory/quarantine/`** are integrator-only in driver-dispatched mode (no story may declare `_memory/records/` or `_memory/quarantine/` in `writes:`; manual iterations may update `_memory/loop/backlog.md`). A protected-path violation reverts the iteration and **stops the run immediately** (exit **4**); other running slots are killed. |
| **Circuit breaker (CB1 / CB2)** | **Per slot:** retire after **3 consecutive no-commit reaps** (CB1) or **5 identical failure signatures** (CB2). The run **continues** while other slots remain active. When **every slot is retired**, the run stops — exit **3** if any retirement was signature-based (CB2), else exit **2**. |
| **Model breaker** | CLOSED/OPEN/HALF-OPEN on anchored rate-limit detection; 600s cooldown, 2 successes to close; falls down the loop model chain. OPEN sleeps instead of hammering; rate-limited passes are CB1-exempt. **bash driver only:** after a rate-limit fallback, an **upward probe** of the preferred model — first delay **1800 s**, doubling on each failed probe with an **1800 s** floor and **14400 s (4 h)** cap; a **successful probe stays on the preferred model**, a **failed probe restores the pre-probe model** (no state-file deletion required — deleting `_memory/loop/breaker-state.json` still resets everything). The frozen PowerShell twin (`breaker.ps1`) has no upward path. State: `_memory/loop/breaker-state.json` (gitignored). |
| **Memory size gates** | After integrate, the driver **detects** breaches and prints a deferral — it never compacts or archives. Thresholds match the guard table: `_memory/loop/LEARNINGS.md` ≥ **15 KB** (compact) and `_memory/loop/ESCALATIONS.md` ≥ **20 KB** (archive resolved entries) — an entry is resolved when it carries a `- resolved: YYYY-MM-DD <decision>` line; archived entries go to `_memory/loop/archive/ESCALATIONS-<YYYY-MM>.md`, where `memory.sh backfill --escalations` can turn them into `decision` records. Compaction and archival happen in a **manual** `auto-loop` iteration only; driver-dispatched slots never run these gates. |
| **Merge gate** | Evaluator PASS + green ladder rungs **1–2** before any commit; rung **3** per story after that story's Phase 5 audit, before that story's commit. |
| **PR gate / shipping** | The loop **never pushes**. At run end, when loop-level `pull_request` is enabled, **`ship-pr` (Phase 7)** ships the branch as **one PR**, with the user approving the draft. |
| **Per-story attempt cap** | **3** attempts, then `blocked: true` plus an escalation entry. |
| **Iteration timeout / budgets** | Opt-in (`LOOP_ITER_TIMEOUT`, `LOOP_RUN_BUDGET_TOKENS`, `LOOP_STORY_BUDGET_TOKENS`, `LOOP_RUN_BUDGET_USD`, `LOOP_STORY_BUDGET_USD`, `LOOP_ITER_BUDGET_USD`); **bash driver only** (`loop.sh`); run-budget stop exits **1** when eligible work remains; missing usage/cost data fails open. |
| **Tamper check** | `LOOP_TAMPER_CHECK` = `warn` (default) \| `fail` (worktree only — requires `LOOP_WORKTREE=1`) \| `off`; optional `LOOP_TEST_PATTERNS`; **bash driver only**; `fail` quarantines with reason `tamper`. |
| **Sandbox** | Run in a worktree/container with minimal credentials; never skip permission prompts outside a container or VM (a worktree is not isolation). |

Known failure mode: loops can burn large budgets without converging — prefer more, smaller backlog stories (each sized to one context window) and let the circuit breakers stop a drifting run early.

## Driver knobs

`loop.sh` and `loop.ps1` share the 1.1.2 knob set (`LOOP_WORKTREE`, `LOOP_SLOTS`, `LOOP_USAGE_FORMAT`, and the subsections below through **`ladder`**). **`loop.ps1` is frozen at agent-kit 1.1.2 behavior** — timeout, budget, tamper, ledger, lint, attempt-dossier, `claude-stream`, and breaker-probe knobs are **bash-only**; on Windows run `_loop/loop.sh` under Git Bash for them.

### CLI recipes

**Claude Code:** The default `LOOP_CLI` is `claude -p`. Unattended iterations need a **permission mode** — configure project settings such as `permissions.defaultMode` and allow rules, or pass `--permission-mode` in `LOOP_CLI`. Newer CLI releases may start `-p` in a manual mode when nothing sets one; iterations may then stall or refuse edits until a mode is configured.

**Opt-in `--bare`:** For a headless session without project hooks, use for example `LOOP_CLI="claude --bare -p --append-system-prompt-file <file>"`. `--bare` skips project hooks, plugin sync, and `CLAUDE.md` auto-discovery, so context must be passed explicitly. It authenticates only via `ANTHROPIC_API_KEY` or `apiKeyHelper`, never **OAuth** or subscription login. It is opt-in — never the default.

**Codex:** Use `LOOP_CLI="codex exec --sandbox danger-full-access"` only inside an **external** container or VM sandbox. The general SAFETY note at the top of this guide (worktree or container) still applies to every loop run; for `danger-full-access` specifically, a plain git worktree (`LOOP_WORKTREE=1`) is not enough on its own, because it gives no filesystem, network, or credential isolation. The `--sandbox workspace-write` mode reportedly keeps `.git` read-only, so slot commits fail and slots are retired. The exec default may be read-only.

**Cursor:** Use `agent -p` or `cursor-agent -p`. Unattended runs need commands allowed — for example `--force` — and only inside a sandbox.

### `LOOP_WORKTREE`

Default follows install `flags.loop_worktree`; an explicit env var overrides it (including `0`).

| Value | Meaning |
|-------|---------|
| **0** | Every iteration runs in the **main tree** — install default unless worktree sandboxing was chosen at install. |
| **1** | Each iteration runs in its own git worktree under `.loop-worktrees/` — install default when worktree sandboxing was chosen. |

When `LOOP_WORKTREE=1`, the driver runs a **tracked-instance preflight** immediately after `git worktree add`: the worktree must contain a tracked `_memory/loop/backlog.md` and a tracked harness directory (`{{IDE_DIR}}` at install time). If either is missing — typical when the loop instance is gitignored in this repo — the driver removes the worktree, deletes the branch, prints a loud error, and exits **5**. There is **no fallback to the main tree**.

### `LOOP_SLOTS`

| Fact | Value |
|------|-------|
| Default | **2** |
| Clamped range | **[1, 3]** |
| Honored when | **`LOOP_WORKTREE=1` only** (worktree isolation makes concurrent slots sound) |
| At `LOOP_WORKTREE=0` | **Effective concurrency clamps to 1** regardless of requested slots |

**N>1-iff-worktree rule:** `LOOP_SLOTS>1` is honored **if and only if** `LOOP_WORKTREE=1`. Without per-slot worktree isolation, concurrent slots would share one working tree and stomp each other's checkout state.

**Stderr note (explicit request only):** when `LOOP_SLOTS>1` was **explicitly requested** (`LOOP_SLOTS` set in the environment) but `LOOP_WORKTREE≠1`, the driver prints to stderr:

```text
LOOP_SLOTS>1 requires LOOP_WORKTREE=1 (worktree isolation); running with 1
```

This note fires **only** when `LOOP_SLOTS>1` was explicitly set — not on every default run (avoids warning fatigue when the default is 2 but worktree mode is off).

### `LOOP_USAGE_FORMAT` and `LOOP_USAGE_LOG`

Both drivers capture real per-iteration token usage from the headless CLI when the format is active. Resolved once at startup from `LOOP_USAGE_FORMAT`:

| Value | Meaning |
|-------|---------|
| **`auto`** (default when unset) | Basename of the first word of `LOOP_CLI`: `claude` → claude; `codex` → codex; `agent` or `cursor-agent` → cursor; anything else → none |
| **`claude`** | Splices `--output-format json` before the prompt; parses the last `{` line with `"type":"result"` for `usage` + `total_cost_usd` |
| **`claude-stream`** | **Opt-in, bash driver only** — splices **`--output-format stream-json --verbose`** before the prompt; rate limits are detected from typed **`system`** / **`api_retry`** events whose **`error`** is **`rate_limit`** or **`overloaded`**, with a **text fallback** over stderr plus the **final result envelope only**; **never chosen by `auto`**. Same usage/cost parsing as **`claude`**. |
| **`codex`** | Splices `--json` before the prompt; parses JSONL `turn.completed.usage` (summed) and the last `agent_message` for decoded text |
| **`cursor`** | Splices `--output-format json` before the prompt (requires `-p`/print mode); parses camelCase `usage` + `result` |
| **`none`** | No flag splice; no usage extraction |

**Silent-none rule:** when `LOOP_USAGE_FORMAT` is **unset** and `auto` resolves to `none`, the driver prints nothing new — no banner, no `usage:` line (existing behaviour byte-for-byte). Only an **explicit** `LOOP_USAGE_FORMAT=none` prints the `usage format: none` banner and `usage: unavailable (format none)` per slot.

When a format is active, the driver prints a normalized line immediately after each slot's existing `tail -n 25` output block:

```text
usage: input=<n> output=<n> cache_read=<n|n/a> cache_write=<n|n/a> cost_usd=<x|n/a> format=<f>
```

Unparseable output yields `usage: unavailable (no envelope)`. Set **`LOOP_USAGE_LOG`** to a file path to append the `usage:` line prefixed with an ISO timestamp, slot id, and story id (`<ISO> slot=<s> story=<story> usage: …`) after each reap; default unset — no new tracked file.

**`jq` (bash only):** decoding the CLI's `result` string requires `jq` on PATH. When `jq` is missing, the bash driver prints `usage: unavailable (jq not on PATH)` once at startup and forces `none` for that run — the loop never breaks. PowerShell uses built-in `ConvertFrom-Json`. Per-harness flag details and verification dates are in [`harness-matrix.md`](../../../skills/agent-kit/reference/harness-matrix.md) § Token usage exposure.

These proxy fields in the orchestration log (`io_est_tokens`, `work_est_tokens`) are **not** billed usage — only this `usage:` line and the bash driver's run ledger (`_memory/loop/ledger.jsonl`, § Run ledger and summary below), which stores the same decoded counts, are real.

### `ladder` (goal `phases:` block)

Loop-created goals always set **`ladder: auto`** in `goal.md`'s `phases:` block (alongside `align_docs` and `pull_request`) so cycle-3 exhaustion runs the continuation ladder unattended. Interactive `/feature` goals default to `ladder: escalate` instead.

Driver-owned dispatch, slot worktrees, write-set admission, and integrator merge semantics are covered in this guide and [architecture.md](architecture.md).

The following sequence shows one driver-dispatched iteration from dispatch through integrator step 3b (memory proposals).

```mermaid
sequenceDiagram
    participant D as loop driver (integrator)
    participant W as slot worktree
    participant A as auto-loop agent

    D->>D: select story + write-set admission
    D->>W: dispatch prompt + outbox path
    W->>A: fresh CLI session
    A->>D: iteration result + outbox files
    D->>D: reap + ITERATION verdict check
    D->>D: step 2 backlog passes/blocked fields
    D->>D: step 3 append LEARNINGS/ESCALATIONS
    D->>D: CB0 protected-path check
    alt clean integration
        D->>D: merge branch (step disposal)
        D->>D: step 3b memory add + chore(memory) commit
    else quarantine-lite
        D->>D: retain branch + marker
        Note over D: step 3b skipped (slot not integrated)
    end
    Note over D: step 3b never changes backlog, exit code, or breakers
```

**Memory in the loop:** Manual iterations call `_kit/memory.sh add` in the story commit. Driver-dispatched slots write `<outbox>/memory/*.md` proposals instead; the integrator **step 3b** at reap end materializes them (after CB0, with path-limited `chore(memory): …` commits when records land). Failures are `!!!` lines only and never change exit codes. Full rules: [memory.md](memory.md).

### `LOOP_ITER_TIMEOUT` and budgets

**bash driver only** — all six knobs default **off** (unset). Budget enforcement **fails open** when the headless CLI reports no usage or cost.

| Knob | Meaning |
|------|---------|
| **`LOOP_ITER_TIMEOUT`** | Positive integer **seconds**; wraps each CLI dispatch with `timeout`/`gtimeout` **`-s INT -k 60`** (60 s SIGKILL grace after SIGINT). Requires `timeout` or `gtimeout` on PATH supporting `-s`/`-k` (GNU coreutils, or BusyBox ≥ 1.35) — otherwise exit **5**. |
| **`LOOP_RUN_BUDGET_TOKENS`** | Positive integer token ceiling for the **whole run** (claude/claude-stream/cursor: input+output+cache\_read+cache\_write; codex: input+output). When reached, the driver stops claiming new stories — exit **1** if eligible work remains; a **drained backlog still exits 0**. |
| **`LOOP_STORY_BUDGET_TOKENS`** | Positive integer token ceiling **per story** (same token math). When reached on a non-passing reap, the driver sets `blocked: true` and appends an escalation entry to `_memory/loop/ESCALATIONS.md`. |
| **`LOOP_RUN_BUDGET_USD`** | Positive decimal **USD** ceiling from parsed CLI cost for the run (same stop semantics as run token budget). |
| **`LOOP_STORY_BUDGET_USD`** | Positive decimal **USD** ceiling per story (same block + escalation semantics as story token budget). |
| **`LOOP_ITER_BUDGET_USD`** | Positive decimal **USD** passed to Claude Code as **`--max-budget-usd`** on each dispatch (**`claude`** / **`claude-stream`** formats only). |

At startup (not in `--lint` mode), the bash driver may print budget notices on **stderr**: `note: LOOP_ITER_BUDGET_USD ignored for usage format <f> (Claude Code only)`; `note: LOOP_RUN_BUDGET_USD has no effect …` and `note: LOOP_STORY_BUDGET_USD has no effect for usage format <f> (no cost reported)` when the resolved usage format cannot supply cost.

### `LOOP_TAMPER_CHECK`

**bash driver only** — at reap, scans the slot's own commits (`head_before..HEAD`) for test gaming:

| Signal | Meaning |
|--------|---------|
| **`deleted:<path>`** | Test file removed or renamed to a non-test path |
| **`skip-marker:<path>`** | Added skip/only/disabled markers |
| **`assertions-removed:<path>:<n>`** | Net removed assertion lines in a modified test file |

| Mode | Behavior |
|------|----------|
| **`warn`** (default) | Prints `!!! tamper (warn) slot …`; integration unchanged |
| **`fail`** | Quarantine-lite with reason **`tamper`** and **no backlog transition** — **worktree only** (`LOOP_WORKTREE=1`); without worktree isolation the driver exits **5** at startup |
| **`off`** | Disables the scan |

Optional **`LOOP_TEST_PATTERNS`** — comma-separated bash `case` patterns against the full repo-relative path. When set, **replaces all default rules**. When unset, paths match when any segment is `test`/`tests`/`__tests__`/`spec` or the basename matches `test_*`, `*_test.*`, `*.test.*`, `*.spec.*`, `*Test.*`, or `*Tests.*` — **excluding** paths with a **`fixtures/`** segment and basenames **`*.golden`** / **`*.snap`** (not classified as tests unless **`LOOP_TEST_PATTERNS`** explicitly matches them). The scan is **one awk pass per file**.

### Run ledger and summary

**bash driver only** — **`LOOP_LEDGER`** defaults **on** → **`$PWD/_memory/loop/ledger.jsonl`** (absolute path); set **`LOOP_LEDGER=off`** to disable, or set it to another path (relative paths resolve against `$PWD`). The file is **gitignored** runtime state (like `_memory/loop/breaker-state.json`).

Each reaped or killed slot appends one JSON line with: `schema`, `run_id`, `ts_start`, `ts_end`, `slot`, `story`, `attempt`, `format`, `model`, `exit_status`, `outcome`, `rate_limited`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, `cache_read_tokens`, `cache_write_tokens`, `cost_usd`, `cost_source`, `diff_files`, `diff_lines`, `tamper`, `tamper_reasons`.

**Outcomes** recorded in the ledger and run summary: `passed`, `failed`, `blocked`, `mismatch`, `abnormal`, `subset`, `tamper`, `timeout`, `protected`, `nonff`, `killed`.

After **≥ 1** reap or kill, the bash driver prints a **stderr run summary** on exit (outcome counts plus run token/cost totals when seen) — **never** in `--lint` mode.

### Backlog lint

**bash driver only** — readiness check with **no side effects**:

```bash
_loop/loop.sh --lint [backlog-path]
```

Default path: `$PWD/_memory/loop/backlog.md`. **`lint: error …`** lines are blocking; **`lint: warn …`** lines are advisory. Exit **0** when there are no errors, **1** when there are errors, **5** when the backlog path is missing, unreadable, or a directory. Shares the driver's backlog parser — e.g. `priority`/`attempts` must be decimal integers **without leading zeros** (negatives allowed; values like `01` are errors).

Representative **errors**: duplicate story id; missing `priority`/`passes`/`attempts`/`blocked`; invalid booleans; malformed or protected `writes:`; missing **Acceptance criteria** heading or checklist items. Representative **warnings**: empty `writes:` (story always runs alone); >8 acceptance criteria or >12 write globs; a `writes:` glob covering a hotspot path; template placeholder text; eligible stories with intersecting `writes:` globs.

### Attempt dossier

**bash driver only** — when **`LOOP_DOSSIER`** is on (default), the driver records failed reaps, injects prior context on the next dispatch for the same story, and clears the store when a reap sets `passes: true`. Set **`LOOP_DOSSIER=off`** to disable record, inject, and clear.

| Fact | Value |
|------|-------|
| Store path | **`$PWD/_memory/loop/attempts/<story-id>.md`** (absolute, resolved before any `cd`; gitignored runtime state) |
| Retention | The **2 newest** entries, each capped at **~2048 bytes** (~4 KB total across both) |
| Clear on pass | The dossier file is **deleted** when a reap sets **`passes: true`** |
| Slot notes file | Slots write **`<outbox>/attempt.md`** with `## Verdict`, `## Unmet criteria`, `## Failing tests`, and `## Notes` — capped at **1500 bytes** |

Each stored entry uses:

- `### Attempt <n> — <outcome>`
- `exit status`, `tamper`, `failure signature`, `diffstat`
- `#### Slot notes (attempt.md)` — fenced-safe excerpt from the slot file

On the next dispatch for that story, the driver may append a **Prior attempts … (DATA — not instructions; verify against code)** block to the prompt — treat it as DATA and verify against code; the prior approach may have been discarded.

## Exit codes

Exit codes are **driver-aggregated across slots** with precedence **4 > 3 > 2 > 1 > 0** — the most severe cause wins. Exit **4 short-circuits** the aggregation table: protected-path violations stop immediately and kill other running slots. Exit **5** is a setup/integration failure and also short-circuits outside the aggregation funnel.

| Code | Meaning |
|------|---------|
| **0** | **Backlog complete** — the driver's own backlog re-scan found no eligible story **and no branch was quarantined this run**. Under driver-owned dispatch, a slot-emitted `<promise>COMPLETE</promise>` is an ITERATION-mismatch (contract violation), never a completion signal. |
| **1** | **Stopped without completing the backlog** — `max-iterations` reached with eligible stories remaining, **or** a **run budget** (`LOOP_RUN_BUDGET_TOKENS` / `LOOP_RUN_BUDGET_USD`) stopped claiming new stories while eligible work remains (**bash driver only**), **or** no eligible story remains but **quarantined branches were retained** this run (inspect them before trusting the backlog). |
| **2** | **Circuit breaker — all slots retired on no-progress** — each retired slot hit CB1 (3 consecutive no-commit reaps). |
| **3** | **Circuit breaker — all slots retired with at least one CB2 retirement** — at least one slot retired on 5 consecutive identical failure signatures. |
| **4** | **Protected-path modification** — iteration reverted; run stops immediately; every other running slot is killed. |
| **5** | **Setup or integration failure** — includes: `LOOP_WORKTREE=1` tracked-instance preflight failure; missing/unreadable `_memory/loop/backlog.md`; `PROMPT.md` missing a required substitution point; rebase-then-ff integration hitting a non-fast-forward; **bash driver only**: invalid `LOOP_ITER_TIMEOUT`, budget (`LOOP_*_BUDGET_*`), or `LOOP_TAMPER_CHECK` value; missing `timeout`/`gtimeout` when `LOOP_ITER_TIMEOUT` is set; a `timeout` without `-s`/`-k` support; `LOOP_TAMPER_CHECK=fail` without `LOOP_WORKTREE=1`; **`--lint`** on a missing, unreadable, or directory backlog. Loud stops with **no silent fallback** to the main tree (preflight removes its worktree; non-ff retains worktree and branch for inspection). |

**Per-slot retirement vs run-fatal stop.** CB1 and CB2 trips **retire the slot** (no refill) while the run may continue on remaining active slots. Only when **all slots are retired** does the run exit **2** or **3** — not on the first no-progress or signature match.

**Drained completion.** Exit **0** requires both an empty eligible backlog **and** zero quarantined branches retained this run. If quarantined branches remain, exit **1** even when no eligible stories are left.

Shell-propagated **126/127** (command-not-found / not-executable) are standard shell edge cases, not loop-owned codes; the PowerShell twin exits **127** for both cases — a stated platform difference.

## Quarantine markers

When `LOOP_WORKTREE=1`, a slot whose branch cannot be integrated — ITERATION-mismatch, abnormal exit, write-subset violation, tamper fail (`LOOP_TAMPER_CHECK=fail`), or killed when another slot hit a protected path — leaves a quarantine marker instead of silently dropping work.

| Fact | Value |
|------|-------|
| Path | `.loop-worktrees/QUARANTINE-<branch>.md` |
| Branch naming | Slashes in the branch name become **dashes** |
| Content order | `QUARANTINE`, `story:`, `slot:`, `branch:`, `status:`, `reason:` (`mismatch` \| `abnormal` \| `subset` \| `tamper` \| `killed`), `dirty_paths:`, blank line, `--- dispatched prompt ---`, then the dispatched prompt verbatim |

Quarantined branches block a "clean" exit **0** — inspect markers and branches before trusting the backlog.

## Backlog stories

Stories live in **`_memory/loop/backlog.md`**. Each entry requires `priority` (lower number picked first), `passes`, `attempts`, `blocked`, `writes` (comma-separated path globs — disjoint globs allow concurrent slots; absent/empty `writes` serializes the story), a description that replaces Phase 1 alignment, and concrete acceptance criteria. Loop-suitable stories are **small, well-specified, and independently verifiable** — sized to one context window with observable outcomes a skeptical evaluator can check without asking you mid-run. Whether your work belongs in the loop at all — versus `/feature`, `/research`, or a direct edit — is a mode choice; see [decision-guide.md](decision-guide.md).

## Starting a run

After `/agent-kit` emits `_loop/` and seeds `_memory/loop/backlog.md` (create-if-missing), start an unattended run from the repository root:

```bash
_loop/loop.sh 10
```

```powershell
pwsh _loop/loop.ps1 10
```

(PowerShell **7+** required.) The numeric argument is `max-iterations` (default **10** when omitted). Override the CLI with `LOOP_CLI` (for example `LOOP_CLI="claude -p"` or `LOOP_CLI="codex exec --sandbox danger-full-access"` (only inside an external sandbox; see [CLI recipes](#cli-recipes))). Example with worktree isolation and two slots:

```bash
LOOP_WORKTREE=1 LOOP_SLOTS=2 _loop/loop.sh 10
```

At run end, review commits on the branch and run **`ship-pr`** (Phase 7) once to open a single approval-gated pull request — the loop never pushes for you.

## Related guides

| Topic | Guide |
|-------|-------|
| When to choose the loop | [decision-guide.md](decision-guide.md) |
| Evaluator PASS, acceptance criteria, test ladder | [evaluation-system.md](evaluation-system.md) |
| Install and first `/agent-kit` | [getting-started.md](getting-started.md) |
| Architecture map (dispatch + integrator) | [architecture.md](architecture.md) |

## Sources

- [`skills/agent-kit/templates/loop/loop.sh`](../../../skills/agent-kit/templates/loop/loop.sh) — driver truth: knobs, exit codes, aggregation, quarantine, worktree preflight
- [`skills/agent-kit/templates/loop/loop.ps1`](../../../skills/agent-kit/templates/loop/loop.ps1) — PowerShell twin (frozen at 1.1.2; new knobs are bash-only)
- [`skills/agent-kit/templates/loop/breaker.sh`](../../../skills/agent-kit/templates/loop/breaker.sh) — model circuit breaker state machine
- [`skills/agent-kit/templates/loop/SKILL.template.md`](../../../skills/agent-kit/templates/loop/SKILL.template.md) — one-iteration contract, dispatch modes, protected paths
- [`skills/agent-kit/templates/loop/PROMPT.md`](../../../skills/agent-kit/templates/loop/PROMPT.md) — dispatched prompt shape
- [`skills/agent-kit/templates/loop/backlog.md`](../../../skills/agent-kit/templates/loop/backlog.md) — canonical backlog story format
- [`skills/agent-kit/templates/ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md) — autonomous loop guard table
- [`README.md`](../../../skills/agent-kit/README.md) — loop feature summary, sandbox warning, knob overview
- [`docs/agent-kit/guide/architecture.md`](architecture.md) — loop dispatch, worktrees, integrator step 3b
