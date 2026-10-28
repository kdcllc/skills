# emit.sh

Deterministic emitter for the AI Orchestration Kit (`/agent-kit` Steps 4–6). Resolves
IF / BOOTSTRAP / tokens, translates per harness, writes seeds, pointers, and the
manifest, then verifies.

Runs on **Bash 3.2+** with POSIX `awk` (no `jq`). On Windows outside Git Bash, use
`emit.cmd` beside this script — same flags, output, and exit codes ([windows-launcher](../reference/windows-launcher.md)).

## Flags

`--answers F` `--upgrade` `--dry-run` `--force` `--check-answers` `--check`
(legacy `_goals/` / `_research/` → `_memory/` migration runs whenever those dirs exist — fresh install or upgrade)
`--root DIR` (default: cwd; an empty value exits **2**) `--kit DIR` (default: this script's `..`)

`--check` runs `<kit>/templates/tools/kit-guard.sh check --root <root>` (default cwd).
It needs no `--answers` (any `--answers` is ignored). Mutually exclusive with
`--upgrade`, `--dry-run`, `--force`, and `--check-answers`. Exit **0** when every
manifest-listed kit file matches its recorded hash · **2** usage / no manifest (a
missing `--root` is not created) · **4** when any kit-owned file is missing or its
bytes differ (stdout lists each path and ends with the restore hint from `kit-guard.sh check`).

## Exit codes

`0` ok · `2` usage / answers unreadable · `3` answers invalid or
unanswered `--check-answers` ids · `4` emit blocked: user-modified kit files (disk
bytes differ from the last manifest hash), pre-existing files at kit paths that no
previous emit recorded (stderr distinguishes the two; `--dry-run` prints `blocked
<path>` for both), or a legacy migration target that already exists (`--force`
overrides file blocks and skips conflicting moves with a warning) · `5` verify failed ·
`6` template syntax. Pre-existing `.codex/config.toml` appends (user bytes plus kit
agent tables) are exempt from the no-manifest-entry block. `--help` → stderr, exit 2.

## Answers

JSON `schema: 1` per `SKILL.md` Step 4. `--check-answers` prints
`<id>\t<template-path>` for missing class-a bootstrap keys. Optional
`flags.loop_worktree` (boolean): absent ⇒ false; a present non-boolean ⇒ exit **3**
(`flags.loop_worktree must be a boolean`). Optional `flags.opt_in` (boolean): absent
⇒ false; a present non-boolean ⇒ exit **3** (`flags.opt_in must be a boolean`); drives
IF flag `opt_in` and the four derived `OPT_IN_*` tokens. When Codex is targeted with
`opt_in` true, emit warns:
`warning: flags.opt_in is partial on codex: no kit skills tree to gate, and an existing .codex/config.toml agent table is never rewritten`.
Optional `flags.kit_guard` (boolean): absent ⇒ false; a present non-boolean ⇒ exit **3**
(`flags.kit_guard must be a boolean`); drives IF flag `kit_guard` and emits
`_kit/kit-guard.sh`, `_kit/kit-guard.cmd`, `.claude/settings.json` (Claude Code
`PreToolUse` hook) when absent, and `.cursor/hooks.json` (`preToolUse`) when absent.
When those config files already exist without the hook, emit leaves them untouched and
warns (merge the snippet from stderr):
`warning: .claude/settings.json exists without the kit-guard hook — left untouched; merge into it: {"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/_kit/kit-guard.sh\" hook claude"}]}]}}`
`warning: .cursor/hooks.json exists without the kit-guard hook — left untouched; add to its "hooks" object: "preToolUse":[{"command":"bash _kit/kit-guard.sh hook cursor","matcher":"Write|Delete"}]`
With `kit_guard` off but a stale hook reference left in user config, emit warns:
`warning: .claude/settings.json still references _kit/kit-guard.sh but flags.kit_guard is off — remove that hook entry`
`warning: .cursor/hooks.json still references _kit/kit-guard.sh but flags.kit_guard is off — remove that hook entry`
Copilot and Codex partial warnings when `kit_guard` is on:
`warning: flags.kit_guard is partial on copilot: no edit-blocking hook; run emit.sh --check in CI (_kit/ is gitignored)`
`warning: flags.kit_guard is partial on codex: no edit-blocking hook; run emit.sh --check in CI (_kit/ is gitignored)`

Emit warnings (stderr, counted in `warnings W`, exit unchanged) include unanswered bootstrap
ids, same-family / reused arbiter model lines from the model map, and
`warning: models.<h>.alt_family equals light; fix cycle 2 would not rotate models`
when `alt_family` equals that harness's `light` tier.

## Manifest

Top-level key order: `kit`, `kitVersion`, `installedAt`, `harnesses`, `primary`,
`options`, `seedFiles`, `files`, `answers`. `options` is flat: `forge` (string),
optional `forgeHost`, booleans `greenfield`, `lint`, `typecheck`,
`models_pinned`, `research`, `loop`, and optional `loop_worktree`, `opt_in`, and
`kit_guard` (each copied from answers only when the matching `flags.*` key is
present). `files` maps emit-set paths → sha256
(compiler copies and seeds excluded; foreign entries carried). `seedFiles`
lists seeds written only if absent. Nested object keys are ordinal-sorted.
Rewriting the manifest never counts toward `written`.

## Determinism

Same inputs ⇒ byte-identical tree and manifest. `EMIT_DATE=YYYY-MM-DD` pins
`installedAt` on a fresh install. Directory walks use `LC_ALL=C`. Manifest
top-level key order is pinned (see Manifest); nested objects are ordinal-sorted.

## emit.cmd

Windows launcher copied from `templates/tools/bash-launcher.cmd`. Invokes this
script through Git for Windows Bash: `bin\emit.cmd --answers F --root DIR` (use
forward slashes in path arguments). The emitter also writes the same launcher
bytes to `_kit/memory.cmd`, `_kit/log-spawn.cmd`, `_kit/kit-guard.cmd` (when
`flags.kit_guard` is true), and — for loop-enabled installs — `_loop/loop.cmd`.

## `_kit/kit-guard.sh`

Emitted single-copy to `_kit/kit-guard.sh` (Windows: `_kit/kit-guard.cmd`) when
`flags.kit_guard` is true.

- **`check [--root DIR]`** — compare every kit-owned manifest `files` path to its
  sha256 (user-owned exclusions: `.claude/settings.json`, `.codex/config.toml`,
  `.cursor/hooks.json`). Exit **0** clean · **2** usage / no manifest / no hasher ·
  **4** missing or modified (prints `kit-guard: restore tracked files from git; delete a modified _kit/ file and re-run emit.sh --upgrade; never edit kit-owned files`).
  `_kit/` is gitignored: on a fresh clone or CI checkout the guard script and hooks are
  inactive until emit runs, and `check` skips `_kit/*` manifest entries (printing a note).
- **`hook <claude|cursor> [--root DIR]`** — read hook JSON from stdin; deny agent
  edits to kit-owned paths. Claude Code `PreToolUse` uses exit **2** with a stderr
  message; Cursor `preToolUse` returns JSON `permission: deny` on exit **2** (empty or
  non-JSON input fails open: prints `{"permission":"allow"}`, exit **0**). Matcher: Claude
  `Edit|Write|MultiEdit|NotebookEdit`;
  Cursor `Write|Delete`. Path fields checked include `file_path`, `notebook_path`,
  `path`, and `target_file`. Set `AGENT_KIT_GUARD=0` to fail open in hook mode.
  `hook claude` detects a Cursor caller (`CURSOR_PROJECT_DIR`, or JSON containing
  `cursor_version` / Cursor `preToolUse` shape) and answers with Cursor-format JSON.

Hooks cover agent edit tools only — shell and human edits are caught by `check`. The
guard does not protect its own configuration (manifest, hook config files); CI
`check` is the backstop. On Windows, a hook whose `bash` cannot start — or resolves
to WSL's `System32\bash.exe`, whose Windows-style paths never match the root — fails
open.

**CI recipe:** install the kit (e.g.
`npx skills add kdcllc/skills#agent-kit/v2.2.0 --skill agent-kit`) and run
`bash <kit>/bin/emit.sh --check --root .`.
