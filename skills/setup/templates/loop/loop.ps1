#!/usr/bin/env pwsh
#Requires -Version 7.0
# Autonomous feature loop for {{PROJECT_NAME}} — drives one `auto-loop` iteration per
# fresh-context CLI run. State lives in _goals/backlog.md + git, never in memory.
#
# Twin: loop.sh (bash) — behaviorally identical — same
# defaults, guards, and exit codes; any divergence is a bug.
#
# Usage:   pwsh _loop/loop.ps1 [MaxIterations]   (default 10)
# CLI:     override with $env:LOOP_CLI, e.g. $env:LOOP_CLI = "codex exec" or "claude -p"
# SLOTS:   override with $env:LOOP_SLOTS (default 2, clamped [1,3]) -- a
#          dark-launch guard (STORY-010) holds effective concurrency at 1
#          regardless of this value until STORY-011.
# WORKTREE: override with $env:LOOP_WORKTREE = 1 to run each iteration in
#          its own git worktree under .loop-worktrees/ (default 0 = main
#          tree, today's behavior).
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
# 126/127 (shell-propagated edge cases, not loop-owned codes): command-not-found
# propagates as exit 127 and found-but-not-executable as exit 126 (bash) —
# standard shell convention, distinct from the four codes above. The
# PowerShell twin's Get-Command guard does not attempt to distinguish the two
# and exits 127 for both — a stated, knowingly-accepted platform difference
# (the 126 case is Unix-host-only).
# Exit 5 = setup or integration failure: the LOOP_WORKTREE=1 tracked-instance
# preflight failing after `git worktree add`, or the interim ff-only
# integration step hitting a non-fast-forward -- both are loud, driver-level
# stops that never silently fall back to the main tree (the preflight path
# removes its worktree; the non-ff path retains worktree and branch for
# inspection).

param(
    # total iterations dispatched ACROSS slots (today: the one slot the
    # dark-launch guard below permits)
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
# Absolute, resolved BEFORE any `cd` happens anywhere below (the per-slot job
# dispatched per-iteration sets its OWN cwd to the slot's tree at
# LOOP_WORKTREE=1) -- $PromptFile above was already absolute via
# $PSScriptRoot; $StateFile was relative and depended on the invocation cwd.
$StateFile = Join-Path (Get-Location).Path '_goals/breaker-state.json'

$LoopModelFlag = $env:LOOP_MODEL_FLAG
if ($null -eq $LoopModelFlag) { $LoopModelFlag = '' }

# Dot-source the breaker helper twin (never invoked as a separate process — same
# process/scope as loop.sh's `source`).
. (Join-Path $PSScriptRoot 'breaker.ps1')
Breaker-Load -Path $StateFile -Chain '{{LOOP_MODEL_CHAIN}}'

# --- LOOP_SLOTS: read, clamp, dark-launch guard -----------------------------
# LoopSlotsExplicit captures the RAW value (pre-clamp) so the guard below can
# tell "explicitly requested >1" apart from the unset default -- the stderr
# warning fires only in the former case (no warning fatigue on every default
# run).
$LoopSlotsExplicit = $env:LOOP_SLOTS
$SlotsRaw = $env:LOOP_SLOTS
if ([string]::IsNullOrEmpty($SlotsRaw)) { $SlotsRaw = '2' }
$Slots = [int]$SlotsRaw
if ($Slots -lt 1) {
    $Slots = 1
}
if ($Slots -gt 3) {
    $Slots = 3
}

# Capacity-contention rationale (why the design default is 2, not 3+): (1) one
# iteration fans out many subagents (implementer/test-writer execute, judge
# verifies every task, fixes are always re-judged), and that per-iteration
# fan-out multiplies by N against a shared ~20-concurrent subagent-spawn
# ceiling; (2) all N slots would authenticate through the same LOOP_CLI as one
# provider account, so they would share ONE rate-limit budget -- more slots
# raise request rate against an unchanged quota rather than adding real
# throughput; (3) the circuit breaker is provider-global (one state file, one
# 600s cooldown) -- a single OPEN trip stalls ALL N slots at once, so more
# slots raise the odds of a full-run stall without shortening it. N=3 crowds
# fact (1) hardest, which is why 2 (not 3) is the design default.
#
# LOOP_SLOTS dark launch (STORY-010): this story ships the slot-supervision
# STRUCTURE only (slot table, available_slots accounting, poll supervision,
# per-slot breakers) -- driver-owned dispatch, admission, and the real
# integrator arrive in STORY-011. Until then EffectiveSlots is held at 1
# regardless of the clamped Slots value above, so the machinery below always
# drives exactly one concurrent child -- the same structure STORY-011
# activates for N>1 without restructuring it.
if ($Slots -gt 1) {
    $EffectiveSlots = 1
} else {
    $EffectiveSlots = $Slots
}

# Nested (not `-and`-combined) so the int cast below never runs when
# LoopSlotsExplicit is unset/empty -- avoids depending on -and short-circuit
# evaluation, which this box cannot verify (pwsh absent).
if (-not [string]::IsNullOrEmpty($LoopSlotsExplicit)) {
    if ([int]$LoopSlotsExplicit -gt 1) {
        [Console]::Error.WriteLine('LOOP_SLOTS>1 requires driver-owned dispatch (STORY-011); running with 1')
    }
}
Write-Output "slots: $EffectiveSlots — dark launch; design default 2 activates in STORY-011"

# LOOP_WORKTREE: 0 (default) runs every iteration in the main tree -- today's
# behavior, unchanged. 1 activates the worktree lifecycle below (loud
# tracked-instance preflight, per-slot HEAD/CB0-2, pinned ff-only
# integration, quarantine-lite on abnormal exit).
$WorktreeRaw = $env:LOOP_WORKTREE
if ([string]::IsNullOrEmpty($WorktreeRaw)) { $WorktreeRaw = '0' }
$Worktree = [int]$WorktreeRaw

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

# --- Slot table --------------------------------------------------------------
# Array of hashtables (ps1 analog of loop.sh's bash-3.2-safe parallel indexed
# arrays; precedent breaker.ps1's Read-BreakerState hashtable shape) -- one
# row per slot, indexed 0..EffectiveSlots-1; STORY-011 raises EffectiveSlots
# past 1 by adding more rows here, not by changing this shape.
$slots = @(
    @{
        Job          = $null
        Tree         = ''
        Branch       = ''
        NoProgress   = 0
        LastErrorSig = ''
        SameError    = 0
        State        = 'idle'   # 'idle' | 'running'
    }
)

$Slot = 0   # the dark-launch guard means every iteration dispatches into
            # (and reaps) this one row; STORY-011 turns this into a loop
            # 0..EffectiveSlots-1.

# Integrate-Slot <tree> <branch> -- interim integration (flag=1 only).
# ORDERING PINNED: merge --ff-only (from the MAIN tree, i.e. this process's
# own cwd, never the worktree) -> worktree remove -> branch -d. That order is
# load-bearing: `git branch -d` fails while the branch is still checked out
# in a worktree, so the worktree must be removed first. Non-ff -> loud
# stderr + exit 5, never merge.
# STORY-011 replaces this interim, slot-called integrator with the real one
# (single integrator, never a slot, per the design's integrator-not-slots
# rule).
function Integrate-Slot {
    param(
        [Parameter(Mandatory)] [string]$Tree,
        [Parameter(Mandatory)] [string]$Branch
    )
    & git merge --ff-only $Branch
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("!!! integration failed: '$Branch' is not a fast-forward of the current tree — stopping (worktree and branch retained for inspection: $Tree)")
        exit 5
    }
    & git worktree remove $Tree
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        # Mirrors bash's `set -e`: a failed post-merge removal aborts with
        # git's own status (branch and worktree left in place for
        # inspection).
        [Console]::Error.WriteLine("!!! git worktree remove failed for '$Tree' — aborting (branch '$Branch' retained)")
        exit $rc
    }
    & git branch -d $Branch
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        [Console]::Error.WriteLine("!!! git branch -d failed for '$Branch' — aborting")
        exit $rc
    }
}

$activeSlots = 0
$retainedBranches = @()   # quarantine-lite: branches from abnormally-exited
                          # slots, retained (not integrated) for inspection --
                          # named again in the driver's closing output below.

# Write-RetainedSummary -- prints the retained-branches list (if any) exactly
# once, in the driver's closing output, on EVERY run-ending path (0/1/2/3/4/5),
# not just the max-iterations path. A try/finally around the main loop below
# is the ps1-idiomatic analog of loop.sh's EXIT trap: `finally` runs even when
# `exit` executes inside `try` (PowerShell unwinds the pending exit through
# enclosing finally blocks before the process actually terminates), it fires
# once regardless of exit reason, and — because it never calls `exit` itself
# — cannot alter the pending exit code, so it does not touch (and cannot
# hide) any of the literal `exit N` statements below (check G's greps still
# see them; this block runs strictly after them).
function Write-RetainedSummary {
    if ($retainedBranches.Count -gt 0) {
        Write-Output "=== retained branches from quarantined slots (NOT integrated): $($retainedBranches -join ' ') ==="
    }
}

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
# call sites below. -Tree unifies both flags via `git -C`: at LOOP_WORKTREE=0, Tree is
# the main-tree cwd, so this is identical to a plain `git rev-parse HEAD`.
function Get-GitHead {
    param([Parameter(Mandatory)] [string]$Tree)
    # T1a parity: bash's command-not-found exits 127; without this guard PowerShell
    # would instead surface whatever $LASTEXITCODE happens to hold (or none at all)
    # when the `git` binary itself cannot be found, diverging from the bash twin.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        [Console]::Error.WriteLine('!!! git rev-parse HEAD failed — aborting')
        exit 127
    }
    $head = (& git -C $Tree rev-parse HEAD)
    $rc = $LASTEXITCODE
    if ($rc -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        [Console]::Error.WriteLine('!!! git rev-parse HEAD failed — aborting')
        if ($rc -eq 0) { $rc = 1 }
        exit $rc
    }
    return $head.Trim()
}

try {
    for ($i = 1; $i -le $MaxIterations; $i++) {
        $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
        Write-Output "=== iteration $i/$MaxIterations $timestamp ==="

        # available_slots accounting (design pin, trivially exercised at N=1):
        # the structure STORY-011 activates for real concurrency.
        $availableSlots = $EffectiveSlots - $activeSlots
        if ($availableSlots -lt 0) {
            $availableSlots = 0
        }

        # Mechanism B: single machine, no loop restructure. If OPEN and
        # cooldown has not elapsed, log + sleep, then ask again — the
        # second call performs OPEN->HALF-OPEN and returns 0 — and
        # proceed with this SAME iteration.
        $skip = Breaker-ShouldSkip -Path $StateFile -Now ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        if ($skip -gt 0) {
            Write-Output ("breaker OPEN — sleeping {0}s before HALF-OPEN trial" -f $skip)
            Start-Sleep -Seconds $skip
            $skip = Breaker-ShouldSkip -Path $StateFile -Now ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        }

        # --- worktree lifecycle (LOOP_WORKTREE=1 only) ------------------------
        # Interim `loop/iter-<i>` branch naming: the real story id is unknown
        # at spawn time until STORY-011's claim table exists.
        $branch = "loop/iter-$i"
        if ($Worktree -eq 1) {
            $wt = Join-Path (Get-Location).Path ".loop-worktrees/slot-1"
            & git worktree add -b $branch $wt HEAD | Out-Null
            $rc = $LASTEXITCODE
            if ($rc -ne 0) {
                # Mirrors bash's `set -e` at this line: a failed `git worktree
                # add` aborts the run with git's own status (e.g. 128 "branch
                # already exists") BEFORE the preflight -- never a
                # misdiagnosed preflight exit 5, and never a `branch -D` of a
                # branch this run did not create (a rerun after quarantine
                # must not destroy the retained branch).
                [Console]::Error.WriteLine("!!! git worktree add failed for '$wt' (branch '$branch') — aborting")
                exit $rc
            }

            # Loud preflight (cycle-3 correction): BOTH probes are built from
            # the SAME resolved worktree-path variable ($wt) just passed to
            # `git worktree add` above — never a second hardcoded literal.
            # The second probe is a DIRECTORY test on {{IDE_DIR}}, deliberately
            # NOT a skill-FILE path: that file exists only on Claude-Code
            # installs (this template's own loop skill) -- codex emits no
            # loop skill file at all, copilot may inline its instructions
            # instead of a file, and a Cursor+Claude install keeps the file
            # under .claude/ while {{IDE_DIR}} resolves to .cursor. A
            # directory probe on {{IDE_DIR}} is true on all four harnesses
            # whenever the instance is tracked, and false in exactly the
            # gitignored-instance case -- the iteration needs that whole
            # directory (it is sent to ORCHESTRATION.md and
            # _goals/ESCALATIONS.md), not just one file in it.
            $backlogOk = Test-Path -LiteralPath (Join-Path $wt '_goals/backlog.md') -PathType Leaf
            $ideDirOk = Test-Path -LiteralPath (Join-Path $wt '{{IDE_DIR}}') -PathType Container
            if (-not $backlogOk -or -not $ideDirOk) {
                [Console]::Error.WriteLine("!!! worktree preflight failed: '$wt' is missing a tracked _goals/backlog.md and/or a tracked {{IDE_DIR}} directory — a worktree checks out TRACKED files only, so this repo's loop instance must be committed (not gitignored) for LOOP_WORKTREE=1 — stopping, no fallback to the main tree")
                & git worktree remove --force $wt 2>$null
                & git worktree prune
                # The `-b $branch` on `git worktree add` above already
                # created this branch (the add itself SUCCEEDED -- see the
                # gate above -- only this preflight failed), so it is always
                # THIS run's own branch, safe to force-delete: a branch left
                # over from a prior quarantined run would have made the add
                # itself fail and exit above, before ever reaching here.
                & git branch -D $branch 2>$null
                exit 5
            }
            $tree = $wt
        } else {
            $tree = (Get-Location).Path
        }
        $slots[$Slot].Tree = $tree
        $slots[$Slot].Branch = $branch

        # DRIVER-owned HEAD capture, before dispatch (after reap: see
        # $headAfter below).
        $headBefore = Get-GitHead -Tree $tree

        # Model arg only when BOTH LOOP_MODEL_FLAG and the current model are non-empty.
        $model = Breaker-CurrentModel -Path $StateFile
        $modelArgs = @()
        if (-not [string]::IsNullOrEmpty($LoopModelFlag) -and -not [string]::IsNullOrEmpty($model)) {
            $modelArgs = @($LoopModelFlag, $model)
        }

        # Get-Content -Raw does not strip trailing newlines the way
        # bash's $(cat ...) command substitution does —
        # both twins strip trailing CR/LF from the prompt tail —
        # TrimEnd here, an iterative both-character strip loop in
        # loop.sh — interior content untouched. Read inside the loop
        # (not hoisted before it) so a mid-run edit to PROMPT.md is
        # picked up on the next iteration, matching bash's
        # per-iteration $(cat "$PROMPT_FILE"). T1b: a 0-byte PROMPT.md
        # makes -Raw return $null (not ''), which would throw a
        # null-method error on .TrimEnd; coalesce ONLY that
        # literal-null case to '' — do NOT coalesce whitespace-only
        # content, which must pass through unchanged exactly as
        # bash's $(cat …) does (coalescing it would create a twin
        # divergence).
        $raw = Get-Content -Raw -LiteralPath $PromptFile
        if ($null -eq $raw) { $raw = '' }
        $promptContent = $raw.TrimEnd("`r", "`n")

        # --- driver/child boundary (the pin) -----------------------------------
        # The child is a Start-Job background job that runs ONLY the CLI
        # invocation, cwd = the slot's tree (worktree at LOOP_WORKTREE=1, main
        # tree otherwise), stdout+stderr redirected to a driver-created
        # per-slot output file (New-TemporaryFile, outside the repo — no
        # gitignore concern; removed after evaluation below). The ONLY things
        # that cross child->driver are the CLI exit status (returned as the
        # job's own output, read via Receive-Job after the poll loop below)
        # and that output file. Every exit 2/3/4/5 statement in this script
        # lives OUTSIDE the job's scriptblock, at driver level: an `exit`
        # inside a background job only ends the job's own runspace, so
        # keeping every exit statement out here is a discipline this comment
        # is the only guard for.
        $outFile = New-TemporaryFile
        $job = Start-Job -ScriptBlock {
            param($Tree, $CliCmd, $CliArgs, $ModelArgs, $Prompt, $OutFile)
            Set-Location -LiteralPath $Tree
            & $CliCmd @CliArgs @ModelArgs $Prompt > $OutFile 2>&1
            $LASTEXITCODE
        } -ArgumentList $tree, $cliCmd, $cliArgs, $modelArgs, $promptContent, $outFile.FullName

        $slots[$Slot].Job = $job
        $slots[$Slot].State = 'running'
        $activeSlots++

        # Supervision: a poll loop on $job.State, then Receive-Job for the
        # real exit status -- the ps1 analog of loop.sh's `kill -0` poll +
        # `wait "$pid"` (the poll-loop structure STORY-011 activates for N>1
        # by iterating more jobs here, not by restructuring this shape).
        while ($job.State -eq 'Running') {
            Start-Sleep -Milliseconds 200
        }

        # Windows removal ordering (design pin -- an implementation
        # requirement): the job must be FULLY reaped -- Wait-Job below blocks
        # until its process has genuinely exited -- BEFORE any `git worktree
        # remove` runs later in this iteration. Removing a worktree while its
        # slot process still holds open file handles under it fails on
        # Windows (POSIX allows unlinking an open file; Windows does not), so
        # reap-before-remove is load-bearing here, not merely tidy. On
        # failure, fall back to `git worktree remove --force` then `git
        # worktree prune` (both cleanup call sites below already do this).
        Wait-Job -Job $job | Out-Null
        $status = (Receive-Job -Job $job)[-1]
        Remove-Job -Job $job -Force

        $slots[$Slot].State = 'idle'
        $activeSlots--   # refill trigger: slot exit, not merge

        # Identifier preservation (cycle-3 twin mirror): $output is
        # populated, verbatim, from the per-slot output file the job wrote
        # to -- never a reimplementation.
        $output = Get-Content -Raw -LiteralPath $outFile.FullName
        if ($null -eq $output) { $output = '' }
        Remove-Item -LiteralPath $outFile.FullName -Force -ErrorAction SilentlyContinue

        # Trailing-newline trim keeps sentinel/last-N-lines logic keyed
        # off the same (unpadded) content as bash's command
        # substitution, which strips trailing newlines. The
        # trailing-CR strip here and the CRLF->LF normalization below
        # are an intentional, behavior-neutral deviation from bash
        # (which strips only newlines): they keep output CR-free on
        # Windows-native tool output without changing observable
        # behavior.
        $output = $output.TrimEnd("`r", "`n")

        $lines = ($output -replace "`r`n", "`n") -split "`n"
        $lines | Select-Object -Last 25 | ForEach-Object { Write-Output $_ }

        $detected = if (Test-RateLimited -Output $output) { 1 } else { 0 }
        Breaker-Record -Path $StateFile -RateLimited $detected -Now ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

        if ($output.Contains($Sentinel)) {
            Write-Output "=== backlog complete after $i iteration(s) ==="
            if ($Worktree -eq 1) {
                Integrate-Slot -Tree $tree -Branch $branch
            }
            exit 0
        }

        # Circuit breaker 0: protected paths — the loop must never modify
        # its own machinery. Evaluated over the slot's own
        # $headBefore..HEAD (its worktree at LOOP_WORKTREE=1, the main tree
        # at 0 — today's behavior); run-fatal, meaning preserved. Parity
        # rule (matches bash `if ! git diff --quiet`): ANY non-zero exit
        # code from this diff (1 = differences found, >=2 = git error)
        # takes the revert+exit branch.
        & git -C $tree diff --quiet $headBefore HEAD -- '_loop/' '{{IDE_DIR}}/agents/' '{{IDE_DIR}}/skills/' 'orchestration-kit.manifest.json' '.gitattributes' 2>$null
        $diffStatus = $LASTEXITCODE
        if ($diffStatus -ne 0) {
            [Console]::Error.WriteLine('!!! protected-path modification detected — reverting iteration and stopping')
            & git -C $tree reset --hard $headBefore
            if ($Worktree -eq 1) {
                & git worktree remove --force $tree 2>$null
                & git worktree prune
            }
            exit 4
        }

        # DRIVER-owned HEAD capture, after reap.
        $headAfter = Get-GitHead -Tree $tree

        # $cbDisposition/$cbExit defer CB1/CB2's exit so the worktree
        # lifecycle (integrate-or-quarantine, below) runs first even on a
        # terminal iteration — the underlying evaluation order (record ->
        # sentinel -> CB0 -> CB1 -> CB2) is unchanged; only WHERE the exit
        # statement executes moves.
        $cbDisposition = 0
        $cbExit = 0

        # Circuit breaker 1: no new commit for 3 consecutive iterations
        # (per-slot counter, unchanged threshold).
        # CB1 carve-out (amended scope): a rate-limited pass never counts against this
        # counter — the breaker owns recovery for it instead. Non-rate-limited no-commit
        # passes increment NoProgress exactly as before.
        if ($headAfter -eq $headBefore) {
            if ($detected -eq 1) {
                Write-Output "rate-limited pass — CB1 exempt (breaker owns it)"
            } else {
                $slots[$Slot].NoProgress = $slots[$Slot].NoProgress + 1
                Write-Output ("--- no progress ({0}/3)" -f $slots[$Slot].NoProgress)
                if ($slots[$Slot].NoProgress -ge 3) {
                    [Console]::Error.WriteLine('!!! circuit breaker: 3 iterations without a commit — stopping')
                    $cbDisposition = 1
                    $cbExit = 2
                }
            }
        } else {
            $slots[$Slot].NoProgress = 0
        }

        # Circuit breaker 2: same failure signature 5 times in a row
        # (per-slot counter, thresholds unchanged; CB2's signature reads the
        # same $output the driver already captured above). Semantics pinned
        # to loop.sh: the counter initializes to 1 when a new signature is
        # seen, so the breaker trips on the 5th consecutive occurrence (not
        # the 6th). Skipped entirely once CB1 has already assigned a
        # disposition this iteration — matches the original ordering, where
        # CB1's exit would have prevented this code from ever running.
        if ($cbDisposition -eq 0 -and $status -ne 0) {
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
            if ($errorSig -eq $slots[$Slot].LastErrorSig) {
                $slots[$Slot].SameError = $slots[$Slot].SameError + 1
                if ($slots[$Slot].SameError -ge 5) {
                    [Console]::Error.WriteLine('!!! circuit breaker: same error 5 times — stopping')
                    $cbDisposition = 1
                    $cbExit = 3
                }
            } else {
                $slots[$Slot].SameError = 1
                $slots[$Slot].LastErrorSig = $errorSig
            }
        } elseif ($cbDisposition -eq 0) {
            $slots[$Slot].SameError = 0
            $slots[$Slot].LastErrorSig = ''
        }

        # --- slot disposal: quarantine-lite (abnormal) vs normal integration ---
        if ($Worktree -eq 1) {
            $dirty = 0
            $statusOutput = & git -C $tree status --porcelain 2>$null
            if (-not [string]::IsNullOrEmpty($statusOutput)) {
                $dirty = 1
            }
            $abnormal = 0
            # Abnormal slot exit (quarantine-lite, pinned): a nonzero CLI
            # status that did NOT earn a recognized CB1/CB2 disposition this
            # iteration, OR a dirty worktree left behind either way. Full
            # quarantine (markers, retirement bookkeeping) is STORY-012's;
            # this is an explicit deferral.
            if ($status -ne 0 -and $cbDisposition -eq 0) {
                $abnormal = 1
            }
            if ($dirty -eq 1) {
                $abnormal = 1
            }

            if ($abnormal -eq 1) {
                [Console]::Error.WriteLine("!!! slot exited abnormally (status=$status dirty=$dirty) — quarantine-lite: NOT integrating; retaining branch '$branch' for inspection ($tree)")
                & git worktree remove --force $tree 2>$null
                & git worktree prune
                $retainedBranches += $branch
            } else {
                Integrate-Slot -Tree $tree -Branch $branch
            }
        }

        # Literal `exit 2`/`exit 3` statements (not a variable exit, per check
        # G's greps at .claude/checks.sh:295-297, which require the literal
        # digit on a driver-level exit line): $cbExit only SELECTS between
        # them, it never substitutes for them.
        if ($cbDisposition -eq 1) {
            if ($cbExit -eq 2) {
                exit 2
            }
            exit 3
        }
    }

    Write-Output "=== max iterations ($MaxIterations) reached; backlog not complete ==="
    exit 1
} finally {
    Write-RetainedSummary
}
