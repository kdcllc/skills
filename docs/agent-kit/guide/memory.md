**Who this is for / What you'll learn:** Kit **users** who want durable, searchable knowledge across sessions and machines, and **contributors** documenting how memory interacts with `/feature`, `/research`, and the autonomous loop. You will learn what belongs in `_memory/` versus goal and loop artifacts, when the orchestrator recalls and archives records, how to search and add records with `_kit/memory.sh` / `_kit/memory.ps1`, back-fill legacy work, the prior-knowledge DATA fence, pointer rules in always-loaded files, and common failure modes. Workflow phase detail stays in [feature-workflow.md](feature-workflow.md) and [research-workflow.md](research-workflow.md); harness-native stores are contrasted in [agent-memory-store research brief](../../../_memory/research/agent-memory-store.md).

# Memory store (`_memory/`)

Every emitted install gets a git-tracked `_memory/` tree (immutable markdown records), single-copy `_kit/memory.sh` and `_kit/memory.ps1`, and orchestration rules in [`skills/agent-kit/templates/skills/feature/reference/memory-protocol.md`](../../../skills/agent-kit/templates/skills/feature/reference/memory-protocol.md). Normative CLI and schema detail also live in [`skills/agent-kit/templates/memory/README.md`](../../../skills/agent-kit/templates/memory/README.md).

## Three kinds of “memory” in a kit project

The kit uses several persistence layers; each has a different lifecycle:

| Layer | Location | Holds | When to use it |
|-------|----------|-------|----------------|
| **Goal artifacts** | `_memory/work/goals/<goal>/` — `goal.md`, task files, append-only `orchestration-log.md`, `spawns/`, `evidence/`, `qa/` (behavioral QA index and artifacts when the optional QA gate runs), `memory-drafts/` (gitignored scratch) | In-flight and recently closed feature work: plans, verdicts, spawn audit trail | Trace how a goal was executed; not a cross-goal search index |
| **Loop ledgers** | `_memory/loop/` — `backlog.md`, `LEARNINGS.md`, `ESCALATIONS.md`, `archive/ESCALATIONS-<YYYY-MM>.md` (tracked); `breaker-state.json` (gitignored runtime) | Loop backlog, learnings, escalations; size gates defer compaction/archival to manual iterations | Autonomous loop operation; ledgers are **not** auto-imported into `records/` |
| **Memory store** | `_memory/records/`, `_memory/quarantine/` (immutable, tracked); plus gitignored `work/` and derived `.index/` / `raw/` | Distilled records (decisions, goal summaries, research ingests, pitfalls, etc.) | Cross-session recall before planning; team-shareable via git |

Scratch research lives under `_memory/work/research/<topic>/` (`prompt.md`, `report.md`, `recalled-memory.md`, `review.md`, `ingested` marker) until promoted or ingested; it is working space, not the immutable record store. **Curated research briefs** live in tracked **`_memory/research/<topic>.md`** with index **`_memory/research/README.md`** — orchestrator-owned, mutable status fields, not memory records. A **`research-ingest`** record in `_memory/records/` distills a closed research topic; the brief summarizes findings for humans and links to the ingest record id in frontmatter.

## Harness-native memory is not this store

Claude Code auto memory, Copilot Memory, Codex memories, and Cursor’s undocumented agent stores are **harness-local or hosted**. They are not cross-harness, not git-mergeable as one team store, and must not hold kit-chosen prior knowledge. The kit owns **`_memory/`** as the portable store; always-loaded project files carry **pointers** (search commands and `_memory/README.md`), never record bodies. Rationale and vendor facts are in [agent-memory-store research brief](../../../_memory/research/agent-memory-store.md).

## When the kit reads and writes memory

Only the **orchestrator** searches and selects records (at most **five**). Only the orchestrator (interactive archive) or the loop **integrator** (dispatched proposals) **creates** records via `_kit/memory.*`. Workers receive recalled content only inside the prior-knowledge fence (see below).

```mermaid
flowchart TD
    Store["_memory/ records"]
    FeatureRecall["Feature: recall once\nbefore Phase 2"]
    ResearchRecall["Research: recall once\nPhase 1 --kind research-ingest,decision"]
    FeatureArchive["Feature: archive after\nPhase 5 APPROVED + green QC"]
    ResearchArchive["Research: one research-ingest\nafter ingestion review"]
    LoopManual["Loop manual: add in story commit"]
    LoopProp["Loop dispatched: outbox/memory/*.md"]
    Integrator["Integrator step 3b at reap end"]
    Fence["Prior-knowledge fence\nimplementer / test-writer / diagnostician"]

    Store --> FeatureRecall
    Store --> ResearchRecall
    FeatureRecall --> Fence
    ResearchRecall -->|"Phase 4 copies to goal"| Fence
    FeatureArchive --> Store
    ResearchArchive --> Store
    LoopManual --> Store
    LoopProp --> Integrator
    Integrator --> Store
```

Recall and archive on interactive `/feature` goals follow this sequence (loop dispatch uses proposals + integrator step 3b instead of direct `add`).

```mermaid
sequenceDiagram
    participant O as Orchestrator
    participant M as _kit/memory.sh
    participant G as goal.md
    participant R as records/

    O->>M: search + show (≤5 picks)
    O->>G: ## Recalled memory ids
    O->>O: prior-knowledge fence in worker context
    Note over O,R: after Phase 5 APPROVED + green QC
    O->>M: add goal-summary (+ optional decision/pitfall)
    O->>M: check each new path
    O->>O: log-spawn note ARCHIVED: ids
    M->>R: immutable record files
```

### Feature workflow (`/feature`)

- **Recall:** Once **before Phase 2** (goal creation). Run `_kit/memory.sh search <term>… --limit 10`, read candidates with `show <id>`, pick **≤ 5** (drop anything contradicted by the codebase). Write ids or `none` into `goal.md` **`## Recalled memory`**. After `_memory/work/goals/<goal>/` exists, log picks or failure with `_kit/log-spawn.sh note`. Any non-zero exit, missing tool, or stderr `memory: 0 results` ⇒ treat as **no prior knowledge** — the phase never blocks.
- **Archive:** After Phase 5 **APPROVED** and green **Quality Checks**, before optional Phases 6/7: one **`goal-summary`** plus zero to three **`decision`** / **`pitfall`** records via `_kit/memory.sh add` (drafts under `_memory/work/goals/<goal>/memory-drafts/`). After each added or quarantined path, run `_kit/memory.sh check <path>`; exit **3** ⇒ report the failing stdout line to the user and do not commit until fixed. After every path passes `check`, the orchestrator logs one closed marker `_kit/log-spawn.sh note --goal <g> --text "ARCHIVED: <id> [<id>…]"` listing **all** ids `add` wrote (including quarantined). Driver-dispatched slots write no ARCHIVED note; their **`goal-summary`** proposals set `source: goal <g> (goal.md)`. Untracked bad record ⇒ `_kit/memory.sh rm <id>`; committed correction ⇒ new record with **`--supersedes`**. Records stay **uncommitted** with the goal for human review. Exit **5** (quarantined) ⇒ report to the user, run `check` on the quarantined path too; do not retry automatically.

See [feature-workflow.md](feature-workflow.md) for phase mechanics.

### Research workflow (`/research`)

- **Recall:** Once at **Phase 1**, with `--kind research-ingest,decision` so settled research is not re-litigated. Picks go to `_memory/work/research/<topic>/recalled-memory.md` until Phase 4.
- **Archive:** After the Phase 2 ingestion review, one **`research-ingest`** record summarizing the report (same `add`, **`check`**, exit **3**, and **`rm` / `--supersedes`** correction rules as feature archive). After `check`, the archive step writes `_memory/work/research/<topic>/ingested` (line 1 UTC `YYYY-MM-DDTHH:MM:SSZ`, line 2 the record id(s) separated by spaces).
- **Research-born goals:** Phase 4 copies Phase 1 picks into the new goal’s `## Recalled memory`; feature recall does **not** run again.

See [research-workflow.md](research-workflow.md).

### Autonomous loop

- **Recall (read):** **Manual** loop iterations and driver-dispatched slots at **`LOOP_WORKTREE=0`** run the feature **Recall** once before Phase 2 (same search/pick rules as interactive `/feature`). At **`LOOP_WORKTREE=1`**, slot worktrees have no `_kit/` — recall is **empty** there.
- **Manual mode:** Archive uses `_kit/memory.sh add` directly; include new record paths in the story commit like any other tracked `_memory/` file.
- **Driver-dispatched mode:** The feature archive step writes **proposals** under `<outbox>/memory/<name>.md` (header/body format in memory-protocol.md) instead of calling `add`.
- **Integrator step 3b:** At the **end** of the slot reap, **after** CB0 and disposal, only when there is no ITERATION-mismatch, no subset violation, and at `LOOP_WORKTREE=1` the branch was integrated (any verdict, including `failed`): proposals are applied via `_kit/memory.* add`, then a path-limited `chore(memory): <story-id> records` commit runs when something was added or quarantined. Step 3b **never** changes exit code, backlog, or breakers; failures print `!!!` lines only.
- **Degraded path:** If the integrator's path-limited `chore(memory): …` commit fails, stderr prints `!!! memory records left uncommitted: git add failed (exit N)` or `!!! memory records left uncommitted: git commit failed (exit N)`; records stay **uncommitted** (they may be staged). A later slot `git add -A` can trip CB0 — fix git identity and hooks.
- **Protected paths:** `_memory/records/` and `_memory/quarantine/` are integrator-only in driver-dispatched mode; no story may declare `_memory/records/` or `_memory/quarantine/` in `writes:` (manual iterations may update `_memory/loop/backlog.md`).

See [autonomous-loop.md](autonomous-loop.md).

## How to search

Run from the repo root or pass **`--root <dir>`** (store path is `<root>/_memory/`). Primary: `_kit/memory.sh`; Windows outside Git Bash: `_kit\memory.cmd` (Git for Windows). `_kit/memory.ps1` (PowerShell 7.2+) implements `add` (with redaction), `index`, `search`, `show`, and `redact`; **`check`**, **`rm`**, **`capture`**, and **`backfill`** are bash-only — the PowerShell twin prints `memory: '<sub>' is bash-only; run bash _kit/memory.sh <sub> (Windows: _kit\memory.cmd <sub>)` and exits **2**.

**Terms:** At least one required. Each term is an ASCII **case-folded substring** match; every term contributes to the score.

**Ranking (default `--engine grep`):** For each term: **+3** when the folded term appears in the **title** or any **tag**; **+1** for each **body line** that contains the folded term (per term, counted separately). Implementation: `score_file` / `meta_hit` in `memory.sh`, `Grep-Score` in `memory.ps1`. **Ties:** equal scores sort by **id descending** (newest id first). With **`--engine fts`**, the same grep candidates are re-ranked by **bm25**; rows without an FTS match sort last; equal bm25 breaks by id descending. FTS requires `sqlite3` with FTS5 and an index built by `index`; otherwise `--engine fts` exits **4**.

**Filters:** `--kind <comma-list>` · **`--limit`** default **10**, range **1–100** · **`--include-superseded`** (default search hides superseded ids).

**Output:** Tab-separated columns: **id**, **kind**, **date**, **score**, **title**, **path** (repo-relative under `_memory/`). **No hits:** `memory: 0 results` on stderr, exit **0**.

**Index staleness:** `search` rebuilds `.index/` when the manifest is missing, stale, or record count differs; run `_kit/memory.sh index` to rebuild explicitly.

**Exit codes:** **0** ok · **2** usage/format · **3** gate failed (`check` only) · **4** missing root, file, id, or optional dependency · **5** quarantined (on `add`, not search).

### Copy-paste examples

Use a temporary store while experimenting (copy `_kit/memory.sh` into the temp tree or point `--root` at a seeded directory):

```bash
ROOT=$(mktemp -d)
mkdir -p "$ROOT/_kit"
cp _kit/memory.sh "$ROOT/_kit/memory.sh"
chmod +x "$ROOT/_kit/memory.sh"
printf 'deploy pipeline notes\n' >"$ROOT/b1.md"
MEMORY_NOW=20261008T110000Z "$ROOT/_kit/memory.sh" add --kind decision --title 'alpha deploy' \
  --body "$ROOT/b1.md" --tags deploy --root "$ROOT"
printf 'legacy body only\n' >"$ROOT/b0.md"
MEMORY_NOW=20261008T100000Z "$ROOT/_kit/memory.sh" add --kind fact --title 'legacy alpha' \
  --body "$ROOT/b0.md" --root "$ROOT"
printf 'pitfall notes\n' >"$ROOT/b3.md"
MEMORY_NOW=20261008T105000Z "$ROOT/_kit/memory.sh" add --kind pitfall --title 'alpha tie' \
  --body "$ROOT/b3.md" --root "$ROOT"
printf 'alpha in body\nalpha again\n' >"$ROOT/b2.md"
MEMORY_NOW=20261008T110001Z "$ROOT/_kit/memory.sh" add --kind learning --title 'other' \
  --body "$ROOT/b2.md" --root "$ROOT"
printf 'replacement body\n' >"$ROOT/b4.md"
MEMORY_NOW=20261008T120000Z "$ROOT/_kit/memory.sh" add --kind fact --title 'replacement' \
  --body "$ROOT/b4.md" --supersedes 20261008T100000Z-8cc3bbf8 --root "$ROOT"

export ROOT
"$ROOT/_kit/memory.sh" search alpha --root "$ROOT"
"$ROOT/_kit/memory.sh" search alpha --kind learning --root "$ROOT"
"$ROOT/_kit/memory.sh" search alpha --include-superseded --root "$ROOT"
"$ROOT/_kit/memory.sh" search zzzz --root "$ROOT"
"$ROOT/_kit/memory.sh" show 20261008T110000Z-b1df2be6 --root "$ROOT"
```

PowerShell (run the bash block first — it runs `export ROOT` mid-block so the path is visible to pwsh; or set `$env:ROOT = '<same path>'` manually):

```powershell
pwsh _kit/memory.ps1 search alpha --root $env:ROOT
```

Optional when SQLite FTS5 is available:

```bash
"$ROOT/_kit/memory.sh" index --root "$ROOT"
"$ROOT/_kit/memory.sh" search alpha --engine fts --root "$ROOT"
```

## Adding, superseding, and quarantine

**By hand:** Only `_kit/memory.sh add` / `_kit/memory.ps1 add` creates files under `records/` or `quarantine/`. Never edit an existing tracked record; committed correction ⇒ `add` with **`--supersedes <id>`**. Untracked mistake ⇒ `_kit/memory.sh rm <full-id>` (bash-only; tracked records exit **2** `memory: record is tracked; add a superseding record instead`).

**Quarantine:** Admission patterns in the title or any single body line send the record to `_memory/quarantine/` with exit **5**. A human may delete the quarantined file directly, or an explicitly tasked agent runs `_kit/memory.sh rm <id>`, then re-`add` cleaned content (unchanged body reports **duplicate**).

**Kinds:** `goal-summary`, `spawn-digest`, `session-summary`, `research-ingest`, `decision`, `learning`, `fact`, `pitfall` — see `_memory/README.md`.

## Redaction

`add` redacts the title and normalized body **before** size check, hashing, dedupe, and the admission screen. `redact` applies the same function to stdin (both bash and PowerShell twins). Redaction is idempotent. When replacements occur, stderr prints `memory: redacted <n> secret(s): <classes>` (`<classes>` in frozen class order, comma-separated).

Classes (ERE, applied in this order): **`private-key`** (multi-line PEM block, body only) · **`secret`** (assignment keys such as `password`, `token`, `api_key`) · **`aws-key`** · **`github-token`** · **`api-key`** (`sk-…`) · **`slack-token`** · **`jwt`** · **`azure-key`**. Full patterns: [`skills/agent-kit/templates/memory/README.md`](../../../skills/agent-kit/templates/memory/README.md) **Redaction**.

## Commit gate (`check`)

```
_kit/memory.sh check [--staged] [--root <dir>] [<path>…]
```

Bash-only. **Scope:** no paths and no `--staged` ⇒ every `*.md` under `records/` and `quarantine/`; explicit paths ⇒ those files only; `--staged` ⇒ staged paths under those trees (requires a git work tree). **`--staged` with paths** ⇒ exit **2**.

**Per-file failures** (stdout `memory: check failed <reason> <repo-relative path>`, then exit **3**): `malformed` · `id-mismatch` · `sha256-mismatch` · `secret` (redaction would change content) · `admission` (`records/` only) · **`--staged` only:** `immutable` for modifications/deletions under tracked memory paths (deletions under `quarantine/` are allowed for human cleanup). All pass ⇒ stdout `memory: check ok <n> file(s)`, exit **0**.

Opt-in pre-commit hook (never installed by the kit):

```bash
printf '#!/bin/sh\nexec bash _kit/memory.sh check --staged\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

## Corrections (`rm`)

```
_kit/memory.sh rm <id> [--root <dir>]
```

Bash-only. Removes an **untracked** file under `records/` or `quarantine/` only. Invalid id ⇒ exit **2** `memory: invalid id`; not a git work tree ⇒ exit **4** `memory: rm needs a git work tree`; missing ⇒ exit **4** `memory: record not found: <id>`; tracked ⇒ exit **2** `memory: record is tracked; add a superseding record instead`. Success ⇒ stdout `memory: removed <id> <path>`, exit **0**.

## Transcript capture and distillation

**Capture (bash-only):**

```
_kit/memory.sh capture [--harness cursor|claude|codex|all] [--from <dir>] [--idle-hours <n>] [--since <YYYY-MM-DD>] [--root <dir>]
```

Defaults: harness `all`, idle-hours `6`, no `--since`. When `--idle-hours` is given, the value must be **1–6 ASCII digits** (`0`–`9` only; leading zeros allowed, e.g. `08` → 8 h); anything else (empty, non-digit characters, or 7 or more digits) → exit **2** `memory: invalid --idle-hours`. **`capture` requires `jq`** (exit **4** `memory: capture needs jq` without it); no other subcommand needs it. Discovers Cursor, Claude Code, and Codex transcript paths under `$HOME` (or `--from` with a single `--harness`); a missing transcript directory yields zero sessions (exit **0**, not an error). Skips live sessions (mtime within `--idle-hours`), out-of-range (`--since`), unchanged ledger rows, unreadable JSONL, and subagent sessions (context-package / subagent heuristics). Writes redacted compact files under gitignored `_memory/raw/<harness>/<session>.md` and appends rows to ledger `raw/.captured`; drafts live in `raw/drafts/`.

Capture hooks are not shipped.

**Distillation:** The emitted **`memory-capture`** skill orchestrates one session per increment: scope gate (human) → implementer draft (body-only under `raw/drafts/`) → evaluator (admission screen, privacy grep for remote owner, `$HOME`, emails) → `add` → **`check` on the record path** → one TAB-separated row in `raw/.distilled` (written by the distillation workflow, not by `capture`). Rows are TAB-separated `harness session record-id|skipped date sha256`; the **5th column** is the raw session file's frontmatter `sha256` when the row was written (legacy **4-column** rows remain valid and **never** trigger a re-offer). A raw session is **offered again** when it has no `.distilled` row, or when its **latest** row has a non-empty 5th column that **differs** from the raw file's current frontmatter `sha256`; a newly distilled `session-summary` passes **`--supersedes <previous record id>`** when that latest row holds a record id (not `skipped`). **Fallback:** Copilot always uses the orchestrator-written fallback (no scanner). Cursor and Claude Code use it only when `capture` cannot run — exit **4** `capture needs jq`, or exit **0** with no transcript directory for the active harness; if the only skip is **`live`** for the current session, offer no fallback — rerun after the idle window (default 6 h). **Quoted turns:** every claim that the user chose, approved, or decided something must quote a `## user` turn from the raw file (≤ 160 characters, ellipsis allowed), or attribute the choice to the assistant or orchestrator — never to the user without a quote. Normative rules: [`memory-capture.md`](../../../skills/agent-kit/templates/skills/feature/reference/memory-capture.md). Codex-only installs emit no skill tree — operators use `capture` / `check` from `_memory/README.md` and distill from another harness session in the same repo.

## Back-fill (`backfill`)

```
_kit/memory.sh backfill [--plan|--apply] [--goals] [--research] [--escalations] [--only <name>] [--root <dir>]
```

Bash-only, deterministic, LLM-free. Candidates go through the existing `add` path (redaction, admission, dedupe). Identical inputs at the same git HEAD yield byte-identical records; record ids are derived from source timestamps.

**Flags:** `--plan` (default) writes nothing; `--apply` adds records; both together ⇒ exit **2**. Kind flags `--goals`, `--research`, and `--escalations` select sources; when none are given, all three run. `--only <name>` (repeatable) names goal folders and research topics (exact names). When any `--only` is given, escalations run only if `--escalations` is also given.

**`--only` and skip reasons:** Any `--only` limits candidates to the named goals and topics. A goal with no `orchestration-log.md` is `skip:no-log` (checked first). Without `--only`, every research topic without an `ingested` marker or matching record prints `skip:not-selected`; with `--only`, unnamed goals and topics are not listed at all. An `--only` name matching no goal and no topic prints `memory: backfill only <name> skip:not-found`; one that matches only a kind excluded by the kind flags prints `memory: backfill only <name> skip:excluded-kind`. **Escalations** (per entry, first match wins): `skip:open` when no `- resolved: YYYY-MM-DD …` line exists; **`skip:bad-date`** when the date on the entry's **last** matching `- resolved:` line is not a real Gregorian calendar date; **`skip:archived`** when the candidate body hash already appears as a `sha256:` under `records/` or `quarantine/` (in both `--plan` and `--apply`); otherwise `would-add`.

| Source | Closed when | Skipped as archived when | Record |
|--------|-------------|--------------------------|--------|
| Goals (`_memory/work/goals/<g>/goal.md` + log) | last Phase 5 evaluator SPAWN has an OUTCOME starting `APPROVED`; or a `### <ts> — Phase 5 APPROVED` note; or named by `--only` | an `ARCHIVED:` note listing an existing id, or a record with source `goal <g> (goal.md)` or `_memory/work/goals/<g>/goal.md` | `goal-summary` |
| Research (`_memory/work/research/<t>/report.md`) | named by `--only` (opt-in topics) | `_memory/work/research/<t>/ingested` exists, or a record with source `research <t> (report.md)` | `research-ingest` |
| Escalations (`_memory/loop/ESCALATIONS.md`, `_memory/loop/archive/ESCALATIONS-<YYYY-MM>.md`) | the entry has `- resolved: YYYY-MM-DD <decision>` with a valid calendar date on the **last** matching line | body hash already under `records/` or `quarantine/` as `sha256:` (`skip:archived` in both `--plan` and `--apply`) | `decision` |

**Research timestamps:** Back-fill uses the `**Date**:` value from `report.md` (text after `**Date**: ` up to ` · ` or end of line, with any trailing CR stripped before parsing) when it is `YYYY-MM-DD`, at `T120000Z`; otherwise `19700101T000000Z`.

**Output:** `--plan` prints `memory: backfill <kind> <name> would-add` or `… skip:<reason>` plus a plan summary; `--apply` prints `added`, `duplicate`, `quarantined`, or `failed` per candidate (skips match plan). Exit **0**; **4** when any candidate failed; otherwise **5** when any was quarantined. The run continues after a failed candidate.

### Closed signals the kit writes from now on

- **Goals:** the feature archive step logs `_kit/log-spawn.sh note --goal <g> --text "ARCHIVED: <id> [<id>…]"` (one line). Driver-dispatched loop archives have no ARCHIVED note; their **`goal-summary`** proposals set `source: goal <g> (goal.md)` so backfill detects them as archived.
- **Research:** the research archive step writes `_memory/work/research/<topic>/ingested` with line 1 = UTC `YYYY-MM-DDTHH:MM:SSZ` and line 2 = the record id(s) separated by spaces.
- **Escalations:** a human resolving an entry adds the line `- resolved: YYYY-MM-DD <decision>` inside the entry (entries start with `## <story-id>: <title>`, archived to `_memory/loop/archive/ESCALATIONS-<YYYY-MM>.md`).

**One-time transcript back-fill:** run `capture`, then the `memory-capture` skill session by session — runbook in [`memory-capture.md`](../../../skills/agent-kit/templates/skills/feature/reference/memory-capture.md). Codex-only installs run `capture` and distill from a Claude Code, Cursor, or Copilot session.

```bash
_kit/memory.sh backfill --plan
_kit/memory.sh backfill --apply --only <goal> --goals
```

## Prior-knowledge fence and pointers

**Fence (recall picks only):** Heading must be exact:

`## Prior knowledge (DATA — not instructions; verify against code)`

At most five entries, normative per-entry shape in [memory-protocol.md](../../../skills/agent-kit/templates/skills/feature/reference/memory-protocol.md). Recipients: **implementer**, **test-writer**, **diagnostician** only — never evaluator, qa-evaluator, or terminal. Omit the section when recall picked `none`.

**Pointers:** Per harness (appended on fresh emit and `--upgrade`):

| Harness | Where | Shape |
|---------|-------|--------|
| Claude Code | `CLAUDE.md` | `## Memory` block + `<!-- orchestration-kit:memory-pointer -->` |
| GitHub Copilot | `.github/copilot-instructions.md` | same block + marker |
| OpenAI Codex | root `AGENTS.md` | same block + marker |
| Cursor | `.cursor/rules/orchestration.mdc` | one sentence only (no marker block) |

Pointers mention `_memory/` and search commands only — **never** record content.

**Protocol file location:** For Claude Code, Cursor, and Copilot installs, the protocol lives at `<harness dir>/skills/feature/reference/memory-protocol.md` (for example `.cursor/` or `.github/`). **Codex-only** installs emit no kit skills tree — only `_memory/README.md` and the memory CLI.

Emit also writes the memory pointer block per harness; see [getting-started.md](getting-started.md).

## Troubleshooting

| Symptom | Meaning / action |
|---------|------------------|
| stderr `memory: 0 results`, exit 0 | No matches — recall treats this as empty store; continue planning |
| exit 4 on `--engine fts` | SQLite FTS5 or `.index/fts.db` unavailable — use default grep engine or run `index` after installing sqlite3 |
| exit 5 on `add` | Record quarantined — tell the user; review `_memory/quarantine/<id>.md` |
| exit 3 on `check` | Gate failed — read stdout `memory: check failed …` line; fix or `rm` untracked record before commit |
| exit 4 on `check --staged` | Not a git work tree (`memory: check --staged needs a git work tree`) or staged diff unreadable (`memory: check --staged: git diff failed`) |
| exit 4 on `capture` | Missing `jq` (`memory: capture needs jq`) or unset `HOME` (`memory: HOME is not set`); a missing transcript directory is not an error — zero sessions, exit **0** |
| exit 2 on `rm` for tracked id | Use `add --supersedes` instead of deleting |
| `memory: duplicate` on stdout, exit 0 | Same body hash already exists — no new file |
| Integrator `!!! memory proposal …` | Malformed proposal, rejected add, quarantine, or skipped tool — fix the proposal or `_kit/memory.*` |
| `!!! memory records left uncommitted: git add failed (exit N)` or `… git commit failed (exit N)` | Step 3b added/quarantined paths but could not commit; records stay **uncommitted** (may be staged) — fix git identity/hooks |
| Later slot CB0 after failed memory commit | Uncommitted records swept by `git add -A` — fix identity/hooks so step 3b commits succeed |
| exit **4** on `backfill --apply` | One or more candidates failed — read the `memory: backfill <kind> <name> failed <rc> …` line; the run continued for other candidates |
| exit **5** on `backfill --apply` | A candidate was quarantined — review `_memory/quarantine/` |
| `backfill goal <g> skip:open` | No Phase 5 APPROVED signal in the log — name it with `--only <g>` if it is really done |
| `backfill escalation <name> skip:bad-date` | The entry's last `- resolved:` date is not a real calendar date — fix the line and re-run |

## Layout and upgrade

Every emit writes `_memory/README.md` and gitignore/gitattributes lines for `_kit/`, `_memory/.index/`, `_memory/raw/`, and `_memory/work/` (loop installs also gitignore `_memory/loop/breaker-state.json`). Tracked by default: `_memory/README.md`, `records/`, `quarantine/`, `_memory/research/` (briefs + index), and (when loop is enabled) `_memory/loop/` except `breaker-state.json`. See [getting-started.md](getting-started.md) for emit details.

**Upgrading from the private setup kit:** see [getting-started.md](getting-started.md) § Upgrading from the private setup kit for layout migration. On installs upgraded from the private **setup** kit, `backfill` also treats a goal as already archived when an existing record's `source` line cites the pre-`_memory/` goal path (same paths `memory.sh backfill` checks alongside `goal <g> (goal.md)` — see [`skills/agent-kit/templates/tools/memory.sh`](../../../skills/agent-kit/templates/tools/memory.sh) `backfill_goal_archived_p`).

## Instance note (this repository)

In **kdcllc/skills**, `_memory/records/`, `_memory/quarantine/`, `_memory/research/` (briefs + index), and `_memory/README.md` are **tracked**; `_memory/work/` and `_memory/loop/` are **gitignored** here (along with `_memory/.index/` and `_memory/raw/`), which differs from a canonical loop install where `_memory/loop/` is tracked. Feature archive **source** labels use `goal <name> (goal.md)` rather than repo-relative paths to gitignored scratch; research archives cite the tracked brief path `_memory/research/<topic>.md` (back-filled research records use `research <topic> (report.md)`). Canonical behavior is what `skills/agent-kit/templates/` emits.

## Sources

- [`skills/agent-kit/templates/memory/README.md`](../../../skills/agent-kit/templates/memory/README.md) — layout, record schema, search scoring, CLI exit codes
- [`skills/agent-kit/templates/skills/feature/reference/memory-protocol.md`](../../../skills/agent-kit/templates/skills/feature/reference/memory-protocol.md) — recall, fence, archive, loop proposals, integrator step 3b
- [`skills/agent-kit/templates/tools/memory.sh`](../../../skills/agent-kit/templates/tools/memory.sh) — reference implementation for search scoring, redaction, `check`, `rm`, `capture`, and `backfill`
- [`skills/agent-kit/templates/skills/memory-capture/SKILL.template.md`](../../../skills/agent-kit/templates/skills/memory-capture/SKILL.template.md) — orchestrator capture/distillation workflow
- [`skills/agent-kit/templates/skills/feature/reference/memory-capture.md`](../../../skills/agent-kit/templates/skills/feature/reference/memory-capture.md) — session-summary distillation contract
- [`skills/agent-kit/templates/skills/feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md) — feature recall and archive hooks
- [`skills/agent-kit/templates/skills/research/SKILL.template.md`](../../../skills/agent-kit/templates/skills/research/SKILL.template.md) — research recall and archive hooks
- [`skills/agent-kit/templates/ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md) — memory guard table and loop step 3b summary
- [`skills/agent-kit/bin/emit.sh`](../../../skills/agent-kit/bin/emit.sh) — `pointer_memory` and harness pointer emission
- [`../../../_memory/research/agent-memory-store.md`](../../../_memory/research/agent-memory-store.md) — harness-native vs kit store brief
