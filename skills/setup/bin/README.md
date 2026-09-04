# emit.sh

Deterministic emitter for the AI Orchestration Kit (`/setup` Steps 4–6). Resolves
IF / BOOTSTRAP / tokens, translates per harness, writes seeds, pointers, and the
manifest, then verifies.

**Requires `jq`.** If jq is missing, use the PowerShell twin:
`pwsh <kit>/bin/emit.ps1` (same flags, output, and exit codes).

## Flags

`--answers F` `--upgrade` `--dry-run` `--force` `--check-answers`
`--root DIR` (default: cwd) `--kit DIR` (default: this script's `..`)

## Exit codes

`0` ok · `2` usage / jq missing / answers unreadable · `3` answers invalid or
unanswered `--check-answers` ids · `4` upgrade blocked (user-modified; `--force`
overrides) · `5` verify failed · `6` template syntax. `--help` → stderr, exit 2.

## Answers

JSON `schema: 1` per `SKILL.md` Step 4. `--check-answers` prints
`<id>\t<template-path>` for missing class-a bootstrap keys.

## Manifest

Top-level key order: `kit`, `kitVersion`, `installedAt`, `harnesses`, `primary`,
`options`, `seedFiles`, `files`, `answers`. `options` is flat: `forge` (string),
optional `forgeHost`, and booleans `greenfield`, `lint`, `typecheck`,
`models_pinned`, `research`, `loop`. `files` maps emit-set paths → sha256
(compiler copies and seeds excluded; foreign entries carried). `seedFiles`
lists seeds written only if absent. Nested objects are `jq -S` sorted.
Rewriting the manifest never counts toward `written`.

## Determinism

Same inputs ⇒ byte-identical tree and manifest. `EMIT_DATE=YYYY-MM-DD` pins
`installedAt` on a fresh install. Directory walks use `LC_ALL=C`. Manifest
top-level key order is pinned (see Manifest); nested objects are ordinal-sorted.

## emit.ps1

PowerShell 7 twin: same flags (`--answers` / `-Answers`, `--root` / `-Root`, …),
same stdout/stderr/exit codes, byte-identical tree and manifest. No jq.
`pwsh <kit>/bin/emit.ps1 --answers F --root DIR`.
