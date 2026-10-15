# emit.sh

Deterministic emitter for the AI Orchestration Kit (`/agent-kit` Steps 4–6). Resolves
IF / BOOTSTRAP / tokens, translates per harness, writes seeds, pointers, and the
manifest, then verifies.

Runs on **Bash 3.2+** with POSIX `awk` (no `jq`). On Windows outside Git Bash, use
`emit.cmd` beside this script — same flags, output, and exit codes ([windows-launcher](../reference/windows-launcher.md)).

## Flags

`--answers F` `--upgrade` `--dry-run` `--force` `--check-answers`
(legacy `_goals/` / `_research/` → `_memory/` migration runs whenever those dirs exist — fresh install or upgrade)
`--root DIR` (default: cwd; an empty value exits **2**) `--kit DIR` (default: this script's `..`)

## Exit codes

`0` ok · `2` usage / answers unreadable · `3` answers invalid or
unanswered `--check-answers` ids · `4` upgrade blocked (user-modified kit files or
legacy migration target exists; `--force` overrides file blocks and skips conflicting
moves with a warning) · `5` verify failed · `6` template syntax. `--help` → stderr, exit 2.

## Answers

JSON `schema: 1` per `SKILL.md` Step 4. `--check-answers` prints
`<id>\t<template-path>` for missing class-a bootstrap keys.

## Manifest

Top-level key order: `kit`, `kitVersion`, `installedAt`, `harnesses`, `primary`,
`options`, `seedFiles`, `files`, `answers`. `options` is flat: `forge` (string),
optional `forgeHost`, and booleans `greenfield`, `lint`, `typecheck`,
`models_pinned`, `research`, `loop`. `files` maps emit-set paths → sha256
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
forward slashes in path arguments).
