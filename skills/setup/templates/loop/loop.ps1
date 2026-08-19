#!/usr/bin/env pwsh
#Requires -Version 7.0
# Autonomous feature loop for {{PROJECT_NAME}} — drives one `auto-loop` iteration per
# fresh-context CLI run. State lives in _goals/backlog.md + git, never in memory.
#
# Twin: skills/setup/templates/loop/loop.sh (bash) — behaviorally identical — same
# defaults, guards, and exit codes; any divergence is a bug.
#
# Usage:   pwsh _loop/loop.ps1 [MaxIterations]   (default 10)
# CLI:     override with $env:LOOP_CLI, e.g. $env:LOOP_CLI = "codex exec" or "claude -p"
#
# SAFETY: run inside a sandbox (worktree/container) with minimal credentials.
# This script never pushes and never bypasses permission prompts by itself.
#
# Breaker: dot-sources breaker.ps1 (functions: Breaker-Load, Breaker-ShouldSkip,
# Breaker-Record, Breaker-CurrentModel); state file: _goals/breaker-state.json.
#
# Exit codes: 0 = backlog complete (sentinel found); 1 = max iterations reached without
# completion; 2 = circuit breaker — no commit for 3 consecutive iterations; 3 = circuit
# breaker — same failure signature 5 times consecutively; 4 = protected-path
# modification detected (iteration reverted).

param(
    [Parameter(Position = 0)]
    [int]$MaxIterations = 10
)

# Explicit, deliberate preference choices (PowerShell has no `set -e`):
#   - $ErrorActionPreference = 'Continue' so a non-zero exit from a native command
#     (git, the CLI under test) never throws a terminating error out from under us —
#     every exit code we care about is read from $LASTEXITCODE explicitly, immediately
#     after the call that produced it, exactly like loop.sh reads `$?`/status manually
#     around the commands it does not want `set -e` to kill the script on.
#   - $PSNativeCommandUseErrorActionPreference = $false (PowerShell 7.3+ default flips
#     this to $true) for the same reason: native non-zero exit must stay data we branch
#     on, not an exception. Harmless on 7.0-7.2 where the variable does not yet exist as
#     a builtin (it is simply created as an ordinary variable).
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

$LoopCli = $env:LOOP_CLI
if ([string]::IsNullOrEmpty($LoopCli)) {
    $LoopCli = 'claude -p'
}

$PromptFile = Join-Path $PSScriptRoot 'PROMPT.md'
$Sentinel = '<promise>COMPLETE</promise>'
$StateFile = '_goals/breaker-state.json'

$LoopModelFlag = $env:LOOP_MODEL_FLAG
if ($null -eq $LoopModelFlag) { $LoopModelFlag = '' }

# Dot-source the breaker helper twin (never invoked as a separate process — same
# process/scope as loop.sh's `source`).
. (Join-Path $PSScriptRoot 'breaker.ps1')
Breaker-Load -Path $StateFile -Chain '{{LOOP_MODEL_CHAIN}}'

# Test-RateLimited <output> -> $true iff any SINGLE line of <output> matches the pinned
# rate-limit pattern (case-insensitive), $false otherwise. Deliberately line-oriented
# (the foreach below tests one line's text at a time) — never a whole-capture match,
# whose `.`/regex engine could otherwise join unrelated lines (e.g. a bare token count
# on one line and the word "error" on another) into a false positive.
function Test-RateLimited {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Output)
    $outputLines = ($Output -replace "`r`n", "`n") -split "`n"
    foreach ($ln in $outputLines) {
        if ($ln -imatch 'rate.?limit|too many requests|quota (exceeded|reached|hit)') {
            return $true
        }
        if (($ln -imatch '429') -and ($ln -imatch 'error|status|http|rate|too many')) {
            return $true
        }
    }
    return $false
}

$noProgress = 0
$sameError = 0
$lastErrorSig = ''

# LOOP_CLI is token-split into command + args before invocation — naive whitespace
# splitting, matching bash's unquoted-expansion word splitting of $LOOP_CLI (no shell
# quoting support inside the value on either side).
$cliParts = $LoopCli.Trim() -split '\s+'
$cliCmd = $cliParts[0]
$cliArgs = @()
if ($cliParts.Length -gt 1) {
    $cliArgs = $cliParts[1..($cliParts.Length - 1)]
}

# Bash `set -e` aborts the whole script if a git command fails; PowerShell has no such
# mechanism, so this helper reads $LASTEXITCODE explicitly (plus a null/empty guard) and
# exits with git's own non-zero status on failure, matching that abort semantics at both
# call sites below.
function Get-GitHead {
    $head = (& git rev-parse HEAD)
    $rc = $LASTEXITCODE
    if ($rc -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        [Console]::Error.WriteLine('!!! git rev-parse HEAD failed — aborting')
        if ($rc -eq 0) { $rc = 1 }
        exit $rc
    }
    return $head.Trim()
}

for ($i = 1; $i -le $MaxIterations; $i++) {
    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    Write-Output "=== iteration $i/$MaxIterations $timestamp ==="

    # Mechanism B: single machine, no loop restructure. If OPEN and cooldown has not
    # elapsed, log + sleep, then ask again — the second call performs OPEN->HALF-OPEN
    # and returns 0 — and proceed with this SAME iteration.
    $skip = Breaker-ShouldSkip -Path $StateFile -Now ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    if ($skip -gt 0) {
        Write-Output ("breaker OPEN — sleeping {0}s before HALF-OPEN trial" -f $skip)
        Start-Sleep -Seconds $skip
        $skip = Breaker-ShouldSkip -Path $StateFile -Now ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    }

    $headBefore = Get-GitHead

    # Model arg only when BOTH LOOP_MODEL_FLAG and the current model are non-empty.
    $model = Breaker-CurrentModel -Path $StateFile
    $modelArgs = @()
    if (-not [string]::IsNullOrEmpty($LoopModelFlag) -and -not [string]::IsNullOrEmpty($model)) {
        $modelArgs = @($LoopModelFlag, $model)
    }

    # Get-Content -Raw does not strip trailing newlines the way bash's $(cat ...) command
    # substitution does; TrimEnd restores that parity so the prompt argument matches.
    # Read inside the loop (not hoisted before it) so a mid-run edit to PROMPT.md is
    # picked up on the next iteration, matching bash's per-iteration $(cat "$PROMPT_FILE").
    $promptContent = (Get-Content -Raw -LiteralPath $PromptFile).TrimEnd("`r", "`n")

    # Combined stdout+stderr capture (2>&1), exit code read from $LASTEXITCODE
    # immediately after the call — no other native command runs in between. ForEach
    # ToString + -join is used instead of Out-String because Out-String renders through
    # the formatter — host-width truncation could silently wrap/truncate long lines
    # (risking the sentinel) and ErrorRecord objects get decorated across multiple
    # lines; ToString per object preserves each line's raw text width-independently.
    $output = (& $cliCmd @cliArgs @modelArgs $promptContent 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    $status = $LASTEXITCODE
    # Trailing-newline trim keeps sentinel/last-N-lines logic keyed off the same
    # (unpadded) content as bash's command substitution, which strips trailing newlines.
    # The trailing-CR strip here and the CRLF->LF normalization below are an intentional,
    # behavior-neutral deviation from bash (which strips only newlines): they keep output
    # CR-free on Windows-native tool output without changing observable behavior.
    $output = $output.TrimEnd("`r", "`n")

    $lines = ($output -replace "`r`n", "`n") -split "`n"
    $lines | Select-Object -Last 25 | ForEach-Object { Write-Output $_ }

    $detected = if (Test-RateLimited -Output $output) { 1 } else { 0 }
    Breaker-Record -Path $StateFile -RateLimited $detected -Now ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

    if ($output.Contains($Sentinel)) {
        Write-Output "=== backlog complete after $i iteration(s) ==="
        exit 0
    }

    # Circuit breaker 0: protected paths — the loop must never modify its own machinery.
    # Parity rule (matches bash `if ! git diff --quiet`): ANY non-zero exit code from
    # this diff (1 = differences found, >=2 = git error) takes the revert+exit branch.
    & git diff --quiet $headBefore HEAD -- '_loop/' '{{IDE_DIR}}/agents/' '{{IDE_DIR}}/skills/' 'orchestration-kit.manifest.json' '.gitattributes' 2>$null
    $diffStatus = $LASTEXITCODE
    if ($diffStatus -ne 0) {
        [Console]::Error.WriteLine('!!! protected-path modification detected — reverting iteration and stopping')
        & git reset --hard $headBefore
        exit 4
    }

    # Circuit breaker 1: no new commit for 3 consecutive iterations.
    # CB1 carve-out (amended scope): a rate-limited pass never counts against this
    # counter — the breaker owns recovery for it instead. Non-rate-limited no-commit
    # passes increment noProgress exactly as before.
    $headAfter = Get-GitHead
    if ($headAfter -eq $headBefore) {
        if ($detected -eq 1) {
            Write-Output "rate-limited pass — CB1 exempt (breaker owns it)"
        } else {
            $noProgress++
            Write-Output "--- no progress ($noProgress/3)"
            if ($noProgress -ge 3) {
                [Console]::Error.WriteLine('!!! circuit breaker: 3 iterations without a commit — stopping')
                exit 2
            }
        }
    } else {
        $noProgress = 0
    }

    # Circuit breaker 2: same failure signature 5 times in a row. Semantics pinned to
    # loop.sh: the counter initializes to 1 when a new signature is seen, so the
    # breaker trips on the 5th consecutive occurrence (not the 6th).
    if ($status -ne 0) {
        # No trailing-newline padding here: bash's `tail -n 5` on a string with no
        # trailing newline (see the TrimEnd above) copies bytes exactly, so the last
        # line carries no newline either; -join reproduces that byte-for-byte so the
        # SHA-256 digest matches `printf '%s' "$output" | tail -n 5 | sha256sum`.
        $last5 = ($lines | Select-Object -Last 5) -join "`n"
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($last5))
        } finally {
            $sha256.Dispose()
        }
        $errorSig = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
        if ($errorSig -eq $lastErrorSig) {
            $sameError++
            if ($sameError -ge 5) {
                [Console]::Error.WriteLine('!!! circuit breaker: same error 5 times — stopping')
                exit 3
            }
        } else {
            $sameError = 1
            $lastErrorSig = $errorSig
        }
    } else {
        $sameError = 0
        $lastErrorSig = ''
    }
}

Write-Output "=== max iterations ($MaxIterations) reached; backlog not complete ==="
exit 1
