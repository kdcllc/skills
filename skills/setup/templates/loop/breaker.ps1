#!/usr/bin/env pwsh
#Requires -Version 7.0
# Model circuit breaker for the {{PROJECT_NAME}} autonomous loop — CLOSED/OPEN/
# HALF-OPEN state machine that degrades to cheaper models on rate limits and
# self-heals. Dot-sourced by the loop driver (`loop.ps1`); never executed directly.
#
# Twin: skills/setup/templates/loop/breaker.sh (bash) — behaviorally identical —
# same states, thresholds, transitions, and schema; any divergence is a bug.
# Function-name mapping (PowerShell -> bash):
#   Breaker-Load          -> breaker_load
#   Breaker-ShouldSkip     -> breaker_should_skip
#   Breaker-Record         -> breaker_record
#   Breaker-CurrentModel   -> breaker_current_model
#
# Cooldown threshold: 600s (OPEN -> HALF-OPEN eligible after 600s elapsed).
# Recovery threshold: HALF-OPEN closes at exactly 2 consecutive successes.
#
# State schema (flat JSON, one key per line — never nested, never minified/reflowed;
# both twins hand-write this exact layout so the file stays a byte-for-byte parity
# contract, not merely a JSON-equivalence one):
#   {
#   "state": "CLOSED"|"OPEN"|"HALF-OPEN",
#   "chain": "<comma-separated model chain, first = preferred>",
#   "fallbackIndex": <int, 0-based index of currentModel within chain — at chain
#     end the index stays put (pointing at the last entry) while currentModel
#     empties (omit-the-pin), so the two fields diverge by design>,
#   "currentModel": "<model id, or \"\" = omit the model flag/pin>",
#   "cooldownSeconds": 600,
#   "openedAt": <epoch seconds when OPEN was (re)entered, or 0>,
#   "halfOpenSuccesses": <int, consecutive successes while HALF-OPEN>,
#   "totalFallbacks": <int, lifetime>,
#   "totalRecoveries": <int, lifetime>
#   }
# NOTE: there is no `consecutiveFailures` key — it was a dead key in the original
# design note and is intentionally dropped from this schema.
#
# `chain` is normally seeded by the driver from the chain configured at install
# time (the LOOP_MODEL_CHAIN placeholder; see models.map.md's "Loop fallback
# chain" row) — this file never reads that token itself; the chain always
# arrives as a plain argument.
#
# Zero runtime deps: state is written by hand-built strings — NEVER ConvertTo-Json
# (which would reorder/re-escape/nest and break the byte-for-byte parity with the
# bash twin) — and parsed back with plain string ops, never Invoke-Expression, so
# the state file is read strictly as inert data: a corrupted or adversarially-edited
# file can only fail validation, never execute anything.
#
# Testability: all timestamps are passed in as [long] `-Now` epoch-seconds
# parameters — no wall-clock reads inside any transition logic. Wall-clock anomaly
# guard: the remaining-cooldown value is CLAMPED to [0, cooldownSeconds] so a system
# clock that jumps backward or forward can never produce a negative or absurdly
# long skip.
#
# Dot-sourcing this file has zero side effects: it only defines functions.

# --- internal helpers (private-by-convention; not part of the pinned API) --------

# Read the raw value for a flat-JSON key from a state file, or $null if absent.
function Get-BreakerField {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Key
    )
    $needle = '"' + $Key + '":'
    $line = (Get-Content -LiteralPath $Path) | Where-Object { $_.Contains($needle) } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    $value = $line.Substring($line.IndexOf(':') + 1).Trim()
    if ($value.EndsWith(',')) { $value = $value.Substring(0, $value.Length - 1) }
    if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return $value
}

# Return $true iff every required key is present and every typed field parses
# (state is one of the three enum values; numeric fields are numeric). This is the
# "parseable" gate Breaker-Load uses to decide reset-vs-keep.
function Test-BreakerStateValid {
    param([Parameter(Mandatory)] [string]$Path)
    $requiredKeys = @('state', 'chain', 'fallbackIndex', 'currentModel', 'cooldownSeconds',
                       'openedAt', 'halfOpenSuccesses', 'totalFallbacks', 'totalRecoveries')
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($key in $requiredKeys) {
        if (-not $content.Contains('"' + $key + '":')) { return $false }
    }
    $state = Get-BreakerField -Path $Path -Key 'state'
    if ($state -notin @('CLOSED', 'OPEN', 'HALF-OPEN')) { return $false }
    foreach ($key in @('fallbackIndex', 'cooldownSeconds', 'halfOpenSuccesses', 'totalFallbacks', 'totalRecoveries')) {
        $v = Get-BreakerField -Path $Path -Key $key
        if ($v -notmatch '^[0-9]+$') { return $false }
    }
    $opened = Get-BreakerField -Path $Path -Key 'openedAt'
    if ($opened -notmatch '^-?[0-9]+$') { return $false }
    return $true
}

# The ONE place that serializes the schema — every transition below funnels
# through this so the on-disk layout never drifts. LF-only, no BOM, to stay a
# byte-for-byte match with the bash twin's `printf`-written file.
function Write-BreakerState {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$State,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Chain,
        [Parameter(Mandatory)] [int]$FallbackIndex,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$CurrentModel,
        [Parameter(Mandatory)] [int]$CooldownSeconds,
        [Parameter(Mandatory)] [long]$OpenedAt,
        [Parameter(Mandatory)] [int]$HalfOpenSuccesses,
        [Parameter(Mandatory)] [int]$TotalFallbacks,
        [Parameter(Mandatory)] [int]$TotalRecoveries
    )
    $lines = @(
        '{'
        ('"state": "{0}",' -f $State)
        ('"chain": "{0}",' -f $Chain)
        ('"fallbackIndex": {0},' -f $FallbackIndex)
        ('"currentModel": "{0}",' -f $CurrentModel)
        ('"cooldownSeconds": {0},' -f $CooldownSeconds)
        ('"openedAt": {0},' -f $OpenedAt)
        ('"halfOpenSuccesses": {0},' -f $HalfOpenSuccesses)
        ('"totalFallbacks": {0},' -f $TotalFallbacks)
        ('"totalRecoveries": {0}' -f $TotalRecoveries)
        '}'
    )
    $text = ($lines -join "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
}

# Writes a fresh CLOSED state seeded from -Chain. currentModel = first chain
# entry, or "" when the chain is empty.
function New-BreakerSeed {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Chain
    )
    $first = ''
    if ($Chain -ne '') { $first = ($Chain -split ',')[0] }
    Write-BreakerState -Path $Path -State 'CLOSED' -Chain $Chain -FallbackIndex 0 `
        -CurrentModel $first -CooldownSeconds 600 -OpenedAt 0 -HalfOpenSuccesses 0 `
        -TotalFallbacks 0 -TotalRecoveries 0
}

# Reads every field into a single hashtable — the PowerShell analog of bash's
# _BRK_* scratch-variable read, used by Breaker-ShouldSkip/Breaker-Record.
function Read-BreakerState {
    param([Parameter(Mandatory)] [string]$Path)
    return @{
        State             = Get-BreakerField -Path $Path -Key 'state'
        Chain             = Get-BreakerField -Path $Path -Key 'chain'
        FallbackIndex     = [int](Get-BreakerField -Path $Path -Key 'fallbackIndex')
        CurrentModel      = Get-BreakerField -Path $Path -Key 'currentModel'
        CooldownSeconds   = [int](Get-BreakerField -Path $Path -Key 'cooldownSeconds')
        OpenedAt          = [long](Get-BreakerField -Path $Path -Key 'openedAt')
        HalfOpenSuccesses = [int](Get-BreakerField -Path $Path -Key 'halfOpenSuccesses')
        TotalFallbacks    = [int](Get-BreakerField -Path $Path -Key 'totalFallbacks')
        TotalRecoveries   = [int](Get-BreakerField -Path $Path -Key 'totalRecoveries')
    }
}

# Mutates $s.FallbackIndex/$s.CurrentModel per the pinned rule: index++ (and
# currentModel = that entry) if a next entry exists, ELSE currentModel=""
# (chain-end reconciles with models.map's omit-the-pin rule). A further advance
# while already at chain-end recomputes the same false condition, so
# currentModel simply stays "" — no special "exhausted" sentinel needed.
function Step-BreakerChain {
    param([Parameter(Mandatory)] [hashtable]$State)
    $entries = @()
    if ($State.Chain -ne '') { $entries = $State.Chain -split ',' }
    $n = $entries.Length
    if (($State.FallbackIndex + 1) -lt $n) {
        $State.FallbackIndex = $State.FallbackIndex + 1
        $State.CurrentModel = $entries[$State.FallbackIndex]
    } else {
        $State.CurrentModel = ''
    }
}

# --- pinned API --------------------------------------------------------------

# Breaker-Load -Path <state-file> -Chain <chain>
# Missing file -> create fresh CLOSED seeded from -Chain, silently.
# Unparseable file -> rewrite fresh CLOSED (same seeding) + one stderr warning.
# Parseable file -> left untouched (-Chain is ignored in this case; only a fresh
# file is ever seeded from it).
function Breaker-Load {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Chain
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-BreakerSeed -Path $Path -Chain $Chain
        return
    }
    if (Test-BreakerStateValid -Path $Path) {
        return
    }
    [Console]::Error.WriteLine("breaker: $Path is unparseable — resetting to fresh CLOSED state")
    New-BreakerSeed -Path $Path -Chain $Chain
}

# Breaker-CurrentModel -Path <state-file> -> echoes currentModel (may be empty).
function Breaker-CurrentModel {
    param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Output ''
        return
    }
    $model = Get-BreakerField -Path $Path -Key 'currentModel'
    Write-Output $model
}

# Breaker-ShouldSkip -Path <state-file> -Now <now-epoch>
# OPEN & cooldown not elapsed -> echo remaining seconds (clamped to
#   [0, cooldownSeconds]).
# OPEN & cooldown elapsed -> transition to HALF-OPEN (halfOpenSuccesses=0),
#   persist, echo 0.
# Any other state -> echo 0, no state change.
function Breaker-ShouldSkip {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [long]$Now
    )
    $s = Read-BreakerState -Path $Path

    if ($s.State -ne 'OPEN') {
        Write-Output 0
        return
    }

    $elapsed = $Now - $s.OpenedAt
    $remaining = $s.CooldownSeconds - $elapsed
    # Wall-clock anomaly guard: clamp to [0, cooldownSeconds].
    if ($remaining -lt 0) { $remaining = 0 }
    if ($remaining -gt $s.CooldownSeconds) { $remaining = $s.CooldownSeconds }

    if ($remaining -gt 0) {
        Write-Output $remaining
        return
    }

    $s.State = 'HALF-OPEN'
    $s.HalfOpenSuccesses = 0
    Write-BreakerState -Path $Path -State $s.State -Chain $s.Chain -FallbackIndex $s.FallbackIndex `
        -CurrentModel $s.CurrentModel -CooldownSeconds $s.CooldownSeconds -OpenedAt $s.OpenedAt `
        -HalfOpenSuccesses $s.HalfOpenSuccesses -TotalFallbacks $s.TotalFallbacks -TotalRecoveries $s.TotalRecoveries
    Write-Output 0
}

# Breaker-Record -Path <state-file> -RateLimited <0|1> -Now <now-epoch>
# Transitions exactly per goal.md's exhaustive table:
#   CLOSED   + 0 -> no-op.
#   CLOSED   + 1 -> OPEN; advance chain; openedAt=now; totalFallbacks++.
#   HALF-OPEN+ 0 -> halfOpenSuccesses++; at exactly 2 -> CLOSED (reset
#                   halfOpenSuccesses/openedAt; totalRecoveries++).
#   HALF-OPEN+ 1 -> OPEN; advance chain; openedAt=now (reset).
#   OPEN     +any -> defensive path (normally unreachable under mechanism B):
#                   log a warning, then treat exactly as the HALF-OPEN input above.
function Breaker-Record {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [int]$RateLimited,
        [Parameter(Mandatory)] [long]$Now
    )
    $s = Read-BreakerState -Path $Path

    if ($s.State -eq 'OPEN') {
        [Console]::Error.WriteLine('breaker: Breaker-Record called while OPEN (defensive path — mechanism B should make this unreachable); treating as HALF-OPEN input')
        $s.State = 'HALF-OPEN'
    }

    switch ($s.State) {
        'CLOSED' {
            if ($RateLimited -eq 1) {
                Step-BreakerChain -State $s
                $s.State = 'OPEN'
                $s.OpenedAt = $Now
                $s.TotalFallbacks = $s.TotalFallbacks + 1
                Write-BreakerState -Path $Path -State $s.State -Chain $s.Chain -FallbackIndex $s.FallbackIndex `
                    -CurrentModel $s.CurrentModel -CooldownSeconds $s.CooldownSeconds -OpenedAt $s.OpenedAt `
                    -HalfOpenSuccesses $s.HalfOpenSuccesses -TotalFallbacks $s.TotalFallbacks -TotalRecoveries $s.TotalRecoveries
            }
            # CLOSED + success -> no-op: nothing written.
        }
        'HALF-OPEN' {
            if ($RateLimited -eq 1) {
                Step-BreakerChain -State $s
                $s.State = 'OPEN'
                $s.OpenedAt = $Now
                Write-BreakerState -Path $Path -State $s.State -Chain $s.Chain -FallbackIndex $s.FallbackIndex `
                    -CurrentModel $s.CurrentModel -CooldownSeconds $s.CooldownSeconds -OpenedAt $s.OpenedAt `
                    -HalfOpenSuccesses $s.HalfOpenSuccesses -TotalFallbacks $s.TotalFallbacks -TotalRecoveries $s.TotalRecoveries
            } else {
                $s.HalfOpenSuccesses = $s.HalfOpenSuccesses + 1
                if ($s.HalfOpenSuccesses -eq 2) {
                    $s.State = 'CLOSED'
                    $s.HalfOpenSuccesses = 0
                    $s.OpenedAt = 0
                    $s.TotalRecoveries = $s.TotalRecoveries + 1
                }
                Write-BreakerState -Path $Path -State $s.State -Chain $s.Chain -FallbackIndex $s.FallbackIndex `
                    -CurrentModel $s.CurrentModel -CooldownSeconds $s.CooldownSeconds -OpenedAt $s.OpenedAt `
                    -HalfOpenSuccesses $s.HalfOpenSuccesses -TotalFallbacks $s.TotalFallbacks -TotalRecoveries $s.TotalRecoveries
            }
        }
    }
}
