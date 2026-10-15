---
title: "Research: Runtime Language for Kit Scripts (Bash + PowerShell Twins vs. Node, Python, Binary)"
topic: runtime-language
date: 2026-10-12
status: shipped
shipped_in: ["1.0.0"]
recheck_by: 2027-04-12
goals: [runtime-bash-single-source]
supersedes: []
memory: [20261012T112437Z-81273d7a]
---

# Research: Runtime Language for Kit Scripts (Bash + PowerShell Twins vs. Node, Python, Binary)

**Method**: external deep-research report
(`_memory/work/research/runtime-language/report.md`) plus an orchestrator ingest review against
`skills/agent-kit/`.

**Legend**: ✅ documented (official vendor source) · 🔬 verified in this repo on
2026-10-12 · 💬 community/secondary · 🤔 inferred.

**Question**: The kit's runtime scripts (emitter, loop driver, circuit breaker, memory
CLI, spawn ledger) exist as Bash and PowerShell twins, about 11,700 lines with every
behavior written twice. Would a single Node/TypeScript or Python implementation be
better?

## 1. Answer

No port. Bash becomes the single source of truth; the PowerShell twins are retired one
script group at a time behind a thin Windows launcher that finds Git Bash. This revisits,
and does not overturn, decision `20260818T120014Z-4bbe83aa`: Node is still rejected as a
new dependency in the critical path, and the launcher it kept as the strongest
alternative is now the recommended path.

| Script group | Target |
|---|---|
| Loop driver + circuit breaker | Bash only; Windows reaches it through the launcher |
| Memory CLI | Bash only |
| Spawn ledger (`log-spawn`) | Bash only |
| Emitter | Keep both twins until `emit.sh` runs on Bash 3.2 without `jq` (or `jq` is declared required), proven by golden-file tests on Linux, macOS and Windows; then retire `emit.ps1` |

## 2. Why not Node, Python, or a compiled binary

- **No harness puts `node` or `python3` on PATH.** ✅ Claude Code's native installer,
  Homebrew, WinGet, apt, dnf and apk installs don't involve Node; even its npm package
  installs a native binary that "does not itself invoke Node". Codex CLI is a Rust binary
  (npm is only a delivery wrapper). Cursor's CLI installs from a shell or PowerShell
  script. VS Code tells users to install Node themselves.
- **Stock OS Python is unreliable.** ✅ Windows `python.exe`/`python3.exe` are App
  Execution Alias stubs that exit 9009; even a Store install leaves `python3` a stub 💬.
  macOS `/usr/bin/python3` is an `xcode-select` shim yielding 3.9.6.
- **Node works where present but buys little.** ✅ Node 22.18+ strips TypeScript types
  without flags (stable in 24.12/25.2); `node:sqlite` is still "Stability 1.2 – Release
  candidate". 🤔 Its Windows process-tree story is no better than Bash: Windows "does not
  support signals" and grandchildren survive `subprocess.kill()`.
- **Compiled binaries don't fit copy-the-folder distribution.** 💬 Bun-compiled
  hello-worlds are 57 MB (darwin-arm64) to about 114 MB (windows-x64); `npx skills add`
  caps direct downloads at 10 MiB ✅. Go/Rust would be small but add a release pipeline and
  code signing.
- **Precedent.** ✅ Husky moved from Node-generated hooks to plain POSIX shell. 💬 Claude
  Code plugin authors fixed Windows hook breakage by forcing `"shell": "bash"` or exec form.

## 3. Why the PowerShell twins should go

- **They target a PowerShell that isn't installed.** 🔬 `loop.ps1`, `memory.ps1` and
  `emit.ps1` all `#Requires -Version 7`. ✅ Fresh Windows 11 ships only Windows PowerShell
  5.1; Claude Code's documented fallback is `powershell.exe` 5.1, and VS Code Copilot has
  been reported running agent commands in 5.1 💬.
- **Bash comes with the git the kit already needs.** ✅ Claude Code uses Git Bash for its
  own Bash tool on Windows and recommends Git for Windows. macOS and most Linux images ship
  Bash; Alpine needs `apk add bash` (Claude Code requires it there too).
- **Drift is the dominant maintenance cost.** 🔬 45 of 137 memory records mention twin
  parity. Both serious incidents (the `"$Slot:"` parse failure and the ungated
  `git worktree add`) were PowerShell-specific.

## 4. Repo facts that shape the migration

- 🔬 **`emit.sh` needs Bash 4+ and `jq`** (`declare -A` at 8 sites; header line 49). Stock
  macOS has Bash 3.2 and no `pwsh`, so neither emitter twin runs on an unmodified Mac
  today. Making `emit.sh` 3.2-safe is a prerequisite for retiring `emit.ps1`.
- 🔬 **The other four scripts are already Bash-3.2-safe** (explicit comments in `loop.sh`)
  and need no `jq`: `loop.sh` degrades to `usage: unavailable` without it, and
  `breaker.sh` declares zero dependencies.
- 🔬 **CI runs only on `ubuntu-latest`**, and PowerShell cases skip when `pwsh` is absent.
  No test has run on Windows or macOS.
- ✅ **`windows-latest` is not a fresh machine**: it ships Bash 5.3.15, pwsh 7, Node
  22.23.2, Python 3.12.10 and jq 1.8.1. Matrix legs must also run with `jq` and `pwsh`
  hidden from PATH.

## 5. Unverified risks to test before retiring `loop.ps1`

- 🤔 Under Git Bash, `loop.sh` stops a slot with `kill` on a backgrounded subshell. Whether
  native Windows children (`claude.exe`, `codex.exe`) die with it is unknown.
- 🤔 Whether Git Bash resolves `LOOP_CLI=cursor-agent` to a `cursor-agent.cmd` shim.
- 💬 Windows pitfalls for the test suites: CRLF (pin `eol=lf` for golden files), MSYS path
  conversion (`MSYS_NO_PATHCONV=1`), `core.longpaths`, and worktree deletion blocked by
  open file handles.
- The launcher must itself run on Windows PowerShell 5.1 (or be a `.cmd`), find
  `bash.exe` via `CLAUDE_CODE_GIT_BASH_PATH`, then relative to `git --exec-path`, then
  `C:\Program Files\Git\bin\bash.exe`, never the `WindowsApps\bash.exe` WSL stub, and fail
  with an actionable message when no Git Bash exists.

## 6. Migration shape

1. Add `macos-latest` and `windows-latest` legs to `.github/workflows/agent-kit.yml`
   driving the existing Bash suites; add a leg with `jq`/`pwsh` removed from PATH.
2. Pin behavior first: golden files for every emitter output, table-driven tests for loop
   exit-code precedence.
3. Ship the launcher behind a selector (for example `AGENT_KIT_IMPL=pwsh|bash`) for one
   release so both paths run in CI, then delete each `.ps1` twin group by group: ledger,
   memory, loop + breaker, emitter last.
4. Record a decision superseding `20260818T120014Z-4bbe83aa`.

## 7. Open questions

- Which PowerShell does VS Code Copilot's agent use on a fresh Windows 11 machine?
  Documented only as "PowerShell".
- How do Claude Code's PowerShell-tool permission rules match a launcher invocation when
  Git Bash is absent?
- What share of Windows users lack Git for Windows? A doctor/preflight message is the
  proposed answer instead of keeping a twin.
- Does `gh skill` impose size or binary limits? None documented as of v2.90.0.
