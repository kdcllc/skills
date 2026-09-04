#!/usr/bin/env pwsh
#Requires -Version 7
# log-spawn — append-only orchestration-log writer for the AI Orchestration Kit.
# Emitted single-copy to `_kit/log-spawn.ps1` (twin: `_kit/log-spawn.sh`, bash,
# behaviorally identical — same flags, same entry text byte-for-byte, same exit codes;
# any divergence is a bug). The orchestrator runs it INLINE after writing a context
# package / report file; it prints exactly one line on success.
#
# CLI CONTRACT (frozen — the feature skill and ORCHESTRATION.md describe this):
#
#   log-spawn.ps1 spawn   --goal <name> --agent <agent> --phase <text>
#                         --model-requested <id> --context <path>
#                         [--writes <text>] [--why <text>] [--expect <text>]
#     Appends (preceded by one blank line):
#       ### <ts> — SPAWN <agent> (<phase>) [#NN]
#       - agent: <agent> · model requested: <id>
#       - why: <why | —>
#       - writes claim: <writes | none>
#       - expected output: <expect | —>
#       - context: <path as given> · context_chars: <N>
#     NN = two digits parsed from the context file basename `NN-context.md`;
#     N  = byte length of the context file.
#
#   log-spawn.ps1 outcome --goal <name> --spawn <NN> --report <path> --verdict <text>
#                         --model-reported <text> [--note <text>] [--work-chars <C>]
#     Appends:
#       - OUTCOME [#NN]: <verdict> · model reported: <text> · report: <path> · report_chars: <R> · io_est_tokens: <T> · work_read_chars: <C|n/a> · work_est_tokens: <W|n/a> · running io: <X> · running work: <Y>
#         <note>                (only with --note; indented two spaces)
#     R = byte length of the report file; T = floor((context_chars of SPAWN #NN + R) / 4);
#     C/W parsed from report line `files_read: <N> (~<C> chars)` (digit-only C) or
#     overridden by --work-chars (digits only, else exit 2); W = floor(C/4) or n/a;
#     X = last `running io: <n>` (fallback: last `running total: <n>` for pre-v0.26 logs;
#     0 if none) + T; Y = last `running work: <n>` (0 if none) + W (W treated as 0 when n/a).
#
#   log-spawn.ps1 note    --goal <name> --text <text>
#     Appends a blank line + `### <ts> — <text>`.
#
#   Common: [--root <path>] (repo root; default $PWD). Log path:
#   <root>/_goals/<goal>/orchestration-log.md — created when missing with the header
#   `# Orchestration Log — <goal>` / blank / `Append-only spawn ledger. Running io_est_tokens
#   (orchestrator I/O proxy, chars/4) and work_est_tokens (subagent self-reported footprint /4):
#   see latest entry.` / blank / `---`.
#
#   Exit codes: 0 ok · 2 usage (unknown subcommand/flag, missing required flag, context
#   basename not `NN-context.md`, --help/no args) · 3 ledger integrity (spawn with an NN
#   already present; outcome whose SPAWN #NN is missing or already has an OUTCOME) ·
#   4 missing goal directory or context/report file.
#   Check order is fixed: flags/basename (2) → paths (4) → integrity (3).
#   Errors: one line on stderr prefixed `log-spawn:`. Success: exactly one stdout line
#   (the appended heading or outcome line).
#
#   Portability freeze (both twins): timestamp = local time, minutes precision, colon in
#   the offset (`2026-09-03T16:59-04:00`); byte counts are FILE BYTES
#   (ReadAllBytes().Length, never string length); io_est_tokens is floor((c + r) / 4);
#   every append is UTF-8 without BOM with LF line endings via
#   [System.IO.File]::AppendAllText — Add-Content / Out-File are forbidden here; running
#   totals are the LAST `running io: <n>` / `running work: <n>` matches (io falls back to
#   `running total: <n>` when no `running io` exists).
#
# Zero runtime deps beyond PowerShell 7 built-ins. Append-only: this script never
# rewrites an existing line. No setup placeholders — harness-agnostic.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$FootprintRe = '^files_read: [0-9]+ \(~([0-9]+) chars\)$'

function Show-Usage {
  $u = @(
    'usage: log-spawn.ps1 <spawn|outcome|note> [--root <path>] <flags>',
    '  spawn   --goal G --agent A --phase P --model-requested M --context _goals/G/spawns/NN-context.md [--writes T] [--why T] [--expect T]',
    '  outcome --goal G --spawn NN --report _goals/G/spawns/NN-report.md --verdict V --model-reported M [--note T] [--work-chars C]',
    '  note    --goal G --text T',
    'exit: 0 ok · 2 usage · 3 ledger integrity · 4 missing goal dir / file'
  )
  [Console]::Out.Write(($u -join "`n") + "`n")
}

function Fail([int]$Code, [string]$Message) {
  [Console]::Error.Write("log-spawn: $Message`n")
  exit $Code
}

function Get-Timestamp { return (Get-Date -Format 'yyyy-MM-ddTHH:mmzzz') }

function Get-FileBytes([string]$Path) { return [System.IO.File]::ReadAllBytes($Path).Length }

function Append-Text([string]$Log, [string]$Text) {
  [System.IO.File]::AppendAllText($Log, $Text, $Utf8NoBom)
}

function Ensure-Log([string]$Log, [string]$Goal) {
  if (-not (Test-Path -LiteralPath $Log -PathType Leaf)) {
    $hdr = "# Orchestration Log — $Goal`n`nAppend-only spawn ledger. Running io_est_tokens (orchestrator I/O proxy, chars/4) and work_est_tokens (subagent self-reported footprint /4): see latest entry.`n`n---`n"
    [System.IO.File]::WriteAllText($Log, $hdr, $Utf8NoBom)
  }
}

function Resolve-Rel([string]$Root, [string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return (Join-Path $Root $Path)
}

function Emit([string]$Line) { [Console]::Out.Write($Line + "`n") }

function Get-PrevRunningIo([string[]]$Lines) {
  $prev = $null
  foreach ($l in $Lines) {
    $m = [regex]::Match($l, 'running io: ([0-9]+)')
    if ($m.Success) { $prev = [int64]$m.Groups[1].Value }
  }
  if ($null -ne $prev) { return $prev }
  foreach ($l in $Lines) {
    $m = [regex]::Match($l, 'running total: ([0-9]+)')
    if ($m.Success) { $prev = [int64]$m.Groups[1].Value }
  }
  if ($null -eq $prev) { return [int64]0 }
  return $prev
}

function Get-PrevRunningWork([string[]]$Lines) {
  $prev = [int64]0
  foreach ($l in $Lines) {
    $m = [regex]::Match($l, 'running work: ([0-9]+)')
    if ($m.Success) { $prev = [int64]$m.Groups[1].Value }
  }
  return $prev
}

function Get-ParsedWorkChars([string]$ReportPath) {
  $text = [System.IO.File]::ReadAllText($ReportPath, $Utf8NoBom)
  foreach ($line in ($text -split "`n")) {
    if ($line -match $FootprintRe) { return [int64]$Matches[1] }
  }
  return $null
}

if ($args.Count -eq 0) { Show-Usage; exit 2 }
$sub = [string]$args[0]
switch ($sub) {
  { $_ -in '-h', '--help', 'help' } { Show-Usage; exit 2 }
  { $_ -in 'spawn', 'outcome', 'note' } { }
  default { Show-Usage; Fail 2 "unknown subcommand '$sub'" }
}

$opt = @{
  root = $PWD.Path; goal = ''; agent = ''; phase = ''; 'model-requested' = ''; context = '';
  writes = ''; why = ''; expect = ''; spawn = ''; report = ''; verdict = '';
  'model-reported' = ''; note = ''; text = ''; 'work-chars' = ''
}
$i = 1
while ($i -lt $args.Count) {
  $flag = [string]$args[$i]
  if (-not $flag.StartsWith('--')) { Fail 2 "unknown flag '$flag' for '$sub'" }
  $name = $flag.Substring(2)
  if (-not $opt.ContainsKey($name)) { Fail 2 "unknown flag '$flag' for '$sub'" }
  if ($i + 1 -ge $args.Count) { Fail 2 "flag '$flag' needs a value" }
  $opt[$name] = [string]$args[$i + 1]
  $i += 2
}

function Require([string]$Flag) {
  if ([string]::IsNullOrEmpty($opt[$Flag.Substring(2)])) { Fail 2 "'$sub' requires $Flag" }
}
Require '--goal'

$root = $opt.root
$goal = $opt.goal
$goalDir = Join-Path $root (Join-Path '_goals' $goal)
$log = Join-Path $goalDir 'orchestration-log.md'

function Get-LogLines([string]$Log) {
  if (-not (Test-Path -LiteralPath $Log -PathType Leaf)) { return @() }
  return [System.IO.File]::ReadAllText($Log, $Utf8NoBom) -split "`n"
}

switch ($sub) {
  'spawn' {
    Require '--agent'; Require '--phase'; Require '--model-requested'; Require '--context'
    $context = $opt.context
    $base = [System.IO.Path]::GetFileName($context)
    if ($base -notmatch '^([0-9]{2})-context\.md$') {
      Fail 2 "context basename must match NN-context.md (got '$base')"
    }
    $nn = $Matches[1]
    $ctxPath = Resolve-Rel $root $context
    if (-not (Test-Path -LiteralPath $goalDir -PathType Container)) { Fail 4 "goal directory not found: $goalDir" }
    if (-not (Test-Path -LiteralPath $ctxPath -PathType Leaf)) { Fail 4 "context file not found: $context" }
    $lines = Get-LogLines $log
    $spawnRe = '^### .* — SPAWN .* \[#' + $nn + '\]$'
    if (@($lines | Where-Object { $_ -match $spawnRe }).Count -gt 0) {
      Fail 3 "SPAWN [#$nn] already present in $log"
    }
    $chars = Get-FileBytes $ctxPath
    Ensure-Log $log $goal
    $heading = "### $(Get-Timestamp) — SPAWN $($opt.agent) ($($opt.phase)) [#$nn]"
    $why = if ($opt.why) { $opt.why } else { '—' }
    $writes = if ($opt.writes) { $opt.writes } else { 'none' }
    $expect = if ($opt.expect) { $opt.expect } else { '—' }
    $entry = "`n$heading`n- agent: $($opt.agent) · model requested: $($opt.'model-requested')`n- why: $why`n- writes claim: $writes`n- expected output: $expect`n- context: $context · context_chars: $chars`n"
    Append-Text $log $entry
    Emit $heading
  }
  'outcome' {
    Require '--spawn'; Require '--report'; Require '--verdict'; Require '--model-reported'
    $nn = $opt.spawn
    if ($nn -notmatch '^[0-9]{2}$') { Fail 2 "--spawn must be two digits (got '$nn')" }
    if ($opt.'work-chars') {
      if ($opt.'work-chars' -notmatch '^[0-9]+$') { Fail 2 "invalid --work-chars value '$($opt.'work-chars')'" }
    }
    $report = $opt.report
    $repPath = Resolve-Rel $root $report
    if (-not (Test-Path -LiteralPath $goalDir -PathType Container)) { Fail 4 "goal directory not found: $goalDir" }
    if (-not (Test-Path -LiteralPath $repPath -PathType Leaf)) { Fail 4 "report file not found: $report" }
    if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { Fail 3 "no orchestration log at $log (no SPAWN [#$nn])" }
    $lines = Get-LogLines $log
    $spawnRe = '^### .* — SPAWN .* \[#' + $nn + '\]$'
    $spawnIdx = -1
    for ($k = 0; $k -lt $lines.Count; $k++) { if ($lines[$k] -match $spawnRe) { $spawnIdx = $k; break } }
    if ($spawnIdx -lt 0) { Fail 3 "SPAWN [#$nn] not found in $log" }
    $outRe = '^- OUTCOME \[#' + $nn + '\]:'
    if (@($lines | Where-Object { $_ -match $outRe }).Count -gt 0) { Fail 3 "OUTCOME [#$nn] already present in $log" }
    $ctxChars = $null
    $end = [Math]::Min($spawnIdx + 5, $lines.Count - 1)
    for ($k = $spawnIdx; $k -le $end; $k++) {
      if ($lines[$k] -match 'context_chars: ([0-9]+)') { $ctxChars = [int64]$Matches[1]; break }
    }
    if ($null -eq $ctxChars) { Fail 3 "SPAWN [#$nn] has no context_chars line" }
    $repChars = [int64](Get-FileBytes $repPath)
    $ioEst = [int64][math]::Floor(($ctxChars + $repChars) / 4)
    $prevIo = Get-PrevRunningIo $lines
    $prevWork = Get-PrevRunningWork $lines
    $runningIo = $prevIo + $ioEst
    if ($opt.'work-chars') {
      $workC = [int64]$opt.'work-chars'
      $workReadDisp = [string]$workC
      $workEst = [int64][math]::Floor($workC / 4)
      $workEstDisp = [string]$workEst
      $runningWork = $prevWork + $workEst
    } else {
      $parsed = Get-ParsedWorkChars $repPath
      if ($null -ne $parsed) {
        $workReadDisp = [string]$parsed
        $workEst = [int64][math]::Floor($parsed / 4)
        $workEstDisp = [string]$workEst
        $runningWork = $prevWork + $workEst
      } else {
        $workReadDisp = 'n/a'
        $workEstDisp = 'n/a'
        $runningWork = $prevWork
      }
    }
    $line = "- OUTCOME [#$nn]: $($opt.verdict) · model reported: $($opt.'model-reported') · report: $report · report_chars: $repChars · io_est_tokens: $ioEst · work_read_chars: $workReadDisp · work_est_tokens: $workEstDisp · running io: $runningIo · running work: $runningWork"
    if ($opt.note) { Append-Text $log "$line`n  $($opt.note)`n" } else { Append-Text $log "$line`n" }
    Emit $line
  }
  'note' {
    Require '--text'
    if (-not (Test-Path -LiteralPath $goalDir -PathType Container)) { Fail 4 "goal directory not found: $goalDir" }
    Ensure-Log $log $goal
    $heading = "### $(Get-Timestamp) — $($opt.text)"
    Append-Text $log "`n$heading`n"
    Emit $heading
  }
}
exit 0
