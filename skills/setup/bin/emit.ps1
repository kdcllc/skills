#!/usr/bin/env pwsh
#Requires -Version 7
# emit.ps1 — deterministic emitter for the AI Orchestration Kit.
# Twin: emit.sh (bash 4+ / jq, behaviorally identical — same flags, same
# stdout/stderr, same exit codes, same tree + manifest bytes; any divergence is
# a bug). Replaces the LLM compile of /setup Steps 4–6: resolve IF / BOOTSTRAP /
# tokens, translate per harness, write seeds/pointers/manifest, prune, verify.
#
# CLI CONTRACT (frozen — SKILL.md Steps 4–6 describe the flow):
#
#   emit.ps1 [--answers F] [--upgrade] [--dry-run] [--force] [--check-answers]
#            [--root DIR] [--kit DIR]
#   (PowerShell spellings -Answers -Upgrade -DryRun -Force -CheckAnswers
#    -Root -Kit are also accepted.)
#
#   --root  repo root (default: cwd). --kit  setup skill dir (default: dirname $0/..).
#           Templates are read from <kit>/templates.
#   --answers F   answers JSON (schema 1). Without --answers, answers are read from
#                 an existing manifest (upgrade). A pre-v0.27.0 manifest without
#                 answers and no --answers ⇒ exit 3.
#   --upgrade     explicit upgrade path (optional when a manifest exists).
#   --dry-run     print one action line per planned write|skip|prune|keep|seed|warn|blocked
#                 path; touch nothing. Any blocked line ⇒ exit 4, else 0.
#   --force       overwrite user-modified kit files.
#   --check-answers  print <id>\t<template path relative to <kit>/templates> for every
#                 class-a BOOTSTRAP id missing from answers.bootstrap (empty string
#                 counts as answered; kit-* never listed). Exit 3 if any line, else 0.
#
#   Optional answers fields (schema 1): models.<h>.fast (string, fast-tier ID;
#   defaults to light), models.<h>.arbiter_same_family (boolean, acknowledges a
#   same-family rung-5 arbiter when frontier_alt_family equals frontier). Arbiter
#   reuse warnings (stderr `emit: warning: …`, counted in warnings W, exit unchanged)
#   when frontier_alt_family equals frontier without the flag, or equals alt_family
#   (≠ frontier) regardless of the flag.
#
#   Exit codes: 0 ok · 2 usage / answers file unreadable · 3 answers
#   invalid, unanswered ids under --check-answers, loop_chain usage-credit denylist
#   entry, or models.<h>.fast / arbiter_same_family wrong JSON type · 4 upgrade blocked by
#   user-modified files (listed on stderr; --force overrides) · 5 verify failed ·
#   6 template syntax error. Errors: one stderr line each, prefixed `emit: `.
#   --help prints usage to stderr and exits 2.
#
#   Success stdout is exactly one line:
#     emit: written N · unchanged M · pruned P · seeds-kept S · warnings W · manifest orchestration-kit.manifest.json · kit <VERSION>
#   N/M count emit-set files only (written = bytes differ or file absent; unchanged
#   = identical). The manifest is always rewritten and never counted in N.
#
#   Determinism: no timestamps except installedAt (kept from an existing manifest,
#   else EMIT_DATE, else today YYYY-MM-DD). Sorted walks ([StringComparer]::Ordinal).
#   Manifest top-level keys in fixed order; nested objects ordinal-sorted (jq -S).
#
# Requires PowerShell 7+. Zero other runtime deps (jq not used). Every written file
# is UTF-8 without BOM, LF only, via [IO.File]::WriteAllText + UTF8Encoding(false).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:Ord = [StringComparer]::Ordinal
$script:Sha256 = [System.Security.Cryptography.SHA256]::Create()
[Console]::OutputEncoding = $script:Utf8
$OutputEncoding = $script:Utf8

$script:PointerMarker = '<!-- orchestration-kit:pointer -->'
$script:CodexAgentsMarker = '# orchestration-kit:agents'

function Show-Usage {
  $u = @(
    'usage: emit.ps1 [--answers F] [--upgrade] [--dry-run] [--force] [--check-answers]'
    '               [--root DIR] [--kit DIR]'
    '  --root DIR   repo root (default: cwd)'
    '  --kit DIR    setup skill dir (default: dirname $0/..)'
    '  --answers F  answers JSON (schema 1). omitted ⇒ read from manifest'
    '  --upgrade    upgrade using answers embedded in the manifest'
    '  --dry-run    print planned actions; touch nothing'
    '  --force      overwrite user-modified kit files'
    '  --check-answers  list unanswered class-a bootstrap ids; exit 3 if any'
    'exit: 0 ok · 2 usage/unreadable · 3 answers invalid · 4 blocked · 5 verify · 6 template syntax'
  )
  [Console]::Error.Write(($u -join "`n") + "`n")
}

function Fail([int]$Code, [string]$Message) {
  [Console]::Error.Write("emit: $Message`n")
  exit $Code
}

function Write-ErrLine([string]$Message) {
  [Console]::Error.Write("emit: $Message`n")
}

function Get-AbsPath([string]$Path) {
  if (-not [System.IO.Path]::IsPathRooted($Path)) {
    $Path = [System.IO.Path]::Combine([Environment]::CurrentDirectory, $Path)
  }
  return [System.IO.Path]::GetFullPath($Path).Replace('\', '/').TrimEnd('/')
}

function Strip-AllNl([string]$s) {
  if ($null -eq $s) { return '' }
  return $s.TrimEnd([char]10)
}

function Strip-OneNl([string]$s) {
  if ($null -eq $s) { return '' }
  if ($s.EndsWith("`n")) { return $s.Substring(0, $s.Length - 1) }
  return $s
}

function Ensure-Nl([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return $s }
  if ($s.EndsWith("`n")) { return $s }
  return $s + "`n"
}

function Get-BashLines([string]$text) {
  $lines = [System.Collections.Generic.List[string]]::new()
  if ([string]::IsNullOrEmpty($text)) { return ,$lines }
  $start = 0
  for ($i = 0; $i -lt $text.Length; $i++) {
    if ($text[$i] -eq [char]10) {
      $lines.Add($text.Substring($start, $i - $start))
      $start = $i + 1
    }
  }
  if ($start -lt $text.Length) {
    $lines.Add($text.Substring($start))
  }
  return ,$lines
}

function Get-AwkNR([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return 0 }
  $n = 0
  foreach ($ch in $text.ToCharArray()) {
    if ($ch -eq [char]10) { $n++ }
  }
  if (-not $text.EndsWith("`n")) { $n++ }
  return $n
}

function Test-CSpace([int]$c) {
  return ($c -eq 32 -or ($c -ge 9 -and $c -le 13))
}

function Trim-CEnd([string]$s) {
  $i = $s.Length
  while ($i -gt 0 -and (Test-CSpace ([int][char]$s[$i - 1]))) { $i-- }
  return $s.Substring(0, $i)
}

function Trim-CStart([string]$s) {
  $i = 0
  while ($i -lt $s.Length -and (Test-CSpace ([int][char]$s[$i]))) { $i++ }
  return $s.Substring($i)
}

function Read-FileRaw([string]$Path) {
  $text = [System.IO.File]::ReadAllText($Path, $script:Utf8)
  return $text.Replace("`r", '')
}

function Get-Sha256String([string]$s) {
  $bytes = $script:Utf8.GetBytes($s)
  $hash = $script:Sha256.ComputeHash($bytes)
  return [BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
}

function Get-Sha256File([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $hash = $script:Sha256.ComputeHash($bytes)
  return [BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
}

function Write-Utf8File([string]$Path, [string]$Content) {
  $parent = [System.IO.Path]::GetDirectoryName($Path)
  if (-not [string]::IsNullOrEmpty($parent)) {
    [void][System.IO.Directory]::CreateDirectory($parent)
  }
  [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8)
}

function Invoke-ChmodX([string]$Path) {
  $chmod = Get-Command chmod -CommandType Application -ErrorAction SilentlyContinue
  if ($null -eq $chmod) { return }
  & chmod +x -- $Path
}

function ConvertTo-UnixRel([string]$full, [string]$root) {
  $rootN = $root.TrimEnd('/') + '/'
  $fullN = $full.Replace('\', '/')
  if ($fullN.StartsWith($rootN, [StringComparison]::Ordinal)) {
    return $fullN.Substring($rootN.Length)
  }
  return $fullN
}

function Get-FilesSorted([string]$dir, [string]$filter, [bool]$recurse) {
  if (-not [System.IO.Directory]::Exists($dir)) { return [string[]]@() }
  $opt = if ($recurse) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
  $arr = [System.IO.Directory]::GetFiles($dir, $filter, $opt)
  if ($arr.Length -gt 1) { [Array]::Sort($arr, $script:Ord) }
  return $arr
}

function Get-DirsSorted([string]$dir) {
  if (-not [System.IO.Directory]::Exists($dir)) { return [string[]]@() }
  $arr = [System.IO.Directory]::GetDirectories($dir)
  if ($arr.Length -gt 1) { [Array]::Sort($arr, $script:Ord) }
  return $arr
}

# --- jq-matching JSON (RFC 8259; control chars \u00XX; / unescaped; UTF-8 raw) ---
function ConvertTo-JqEscaped([string]$s) {
  $sb = [System.Text.StringBuilder]::new($s.Length + 8)
  [void]$sb.Append([char]0x22)
  foreach ($ch in $s.ToCharArray()) {
    $c = [int][char]$ch
    if ($c -eq 8) { [void]$sb.Append('\b') }
    elseif ($c -eq 9) { [void]$sb.Append('\t') }
    elseif ($c -eq 10) { [void]$sb.Append('\n') }
    elseif ($c -eq 12) { [void]$sb.Append('\f') }
    elseif ($c -eq 13) { [void]$sb.Append('\r') }
    elseif ($c -eq 34) { [void]$sb.Append('\"') }
    elseif ($c -eq 92) { [void]$sb.Append('\\') }
    elseif ($c -lt 32) {
      [void]$sb.Append('\u')
      [void]$sb.Append($c.ToString('x4'))
    }
    else { [void]$sb.Append($ch) }
  }
  [void]$sb.Append([char]0x22)
  return $sb.ToString()
}

function Test-IsJsonObject($v) {
  return ($null -ne $v -and $v -is [System.Collections.IDictionary])
}
function Test-IsJsonArray($v) {
  if ($null -eq $v) { return $false }
  if ($v -is [string]) { return $false }
  if ($v -is [System.Collections.IDictionary]) { return $false }
  if ($v -is [System.Array]) { return $true }
  if ($v -is [System.Collections.IList]) { return $true }
  return $false
}

function ConvertTo-JqJson($value, [int]$level, [string[]]$keyOrder) {
  if ($null -eq $value) { return 'null' }
  if ($value -is [bool]) {
    if ($value) { return 'true' } else { return 'false' }
  }
  if ($value -is [string]) { return (ConvertTo-JqEscaped $value) }
  if ($value -is [byte] -or $value -is [int16] -or $value -is [uint16] -or $value -is [int] -or $value -is [uint32] -or $value -is [int64] -or $value -is [uint64] -or $value -is [decimal]) {
    return ([IFormattable]$value).ToString($null, [Globalization.CultureInfo]::InvariantCulture)
  }
  if ($value -is [double] -or $value -is [float]) {
    $d = [double]$value
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return 'null' }
    if ($d -eq [math]::Floor($d) -and $d -ge [int64]::MinValue -and $d -le [int64]::MaxValue) {
      return ([int64]$d).ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    return $d.ToString('G17', [Globalization.CultureInfo]::InvariantCulture)
  }
  if (Test-IsJsonObject $value) {
    $keys = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $keyOrder) {
      foreach ($k in $keyOrder) { $keys.Add([string]$k) }
    } else {
      foreach ($k in @($value.Keys)) { $keys.Add([string]$k) }
      $keys.Sort($script:Ord)
    }
    if ($keys.Count -eq 0) { return '{}' }
    $pad = '  ' * $level
    $inner = '  ' * ($level + 1)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('{')
    [void]$sb.Append([char]10)
    for ($i = 0; $i -lt $keys.Count; $i++) {
      $k = $keys[$i]
      if ($i -gt 0) { [void]$sb.Append(','); [void]$sb.Append([char]10) }
      [void]$sb.Append($inner)
      [void]$sb.Append((ConvertTo-JqEscaped $k))
      [void]$sb.Append(': ')
      [void]$sb.Append((ConvertTo-JqJson $value[$k] ($level + 1) $null))
    }
    [void]$sb.Append([char]10)
    [void]$sb.Append($pad)
    [void]$sb.Append('}')
    return $sb.ToString()
  }
  if (Test-IsJsonArray $value) {
    $items = @($value)
    if ($items.Count -eq 0) { return '[]' }
    $pad = '  ' * $level
    $inner = '  ' * ($level + 1)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('[')
    [void]$sb.Append([char]10)
    for ($i = 0; $i -lt $items.Count; $i++) {
      if ($i -gt 0) { [void]$sb.Append(','); [void]$sb.Append([char]10) }
      [void]$sb.Append($inner)
      [void]$sb.Append((ConvertTo-JqJson $items[$i] ($level + 1) $null))
    }
    [void]$sb.Append([char]10)
    [void]$sb.Append($pad)
    [void]$sb.Append(']')
    return $sb.ToString()
  }
  return (ConvertTo-JqEscaped ([string]$value))
}

function ConvertTo-JqRaw($v) {
  if ($null -eq $v) { return '' }
  if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
  if ($v -is [string]) { return $v }
  if ($v -is [byte] -or $v -is [int16] -or $v -is [uint16] -or $v -is [int] -or $v -is [uint32] -or $v -is [int64] -or $v -is [uint64] -or $v -is [decimal] -or $v -is [double] -or $v -is [float]) {
    return ([IFormattable]$v).ToString($null, [Globalization.CultureInfo]::InvariantCulture)
  }
  return [string]$v
}

function Test-JqTruthy($v) {
  if ($null -eq $v) { return $false }
  if ($v -is [bool] -and -not $v) { return $false }
  if ($v -is [string] -and $v.Length -eq 0) { return $false }
  return $true
}

# --- CLI ---
$script:AnswersFile = ''
$script:DoUpgrade = $false
$script:DryRun = $false
$script:Force = $false
$script:CheckAnswers = $false
$script:Root = ''
$script:Kit = ''

if ($args.Count -eq 0) { Show-Usage; exit 2 }

$i = 0
while ($i -lt $args.Count) {
  $flag = [string]$args[$i]
  if ($flag -in @('-h', '--help', 'help')) { Show-Usage; exit 2 }
  elseif ($flag -in @('--answers', '-Answers')) {
    if ($i + 1 -ge $args.Count) { Fail 2 "flag '$flag' needs a value" }
    $script:AnswersFile = [string]$args[$i + 1]
    $i += 2
  }
  elseif ($flag -in @('--root', '-Root')) {
    if ($i + 1 -ge $args.Count) { Fail 2 "flag '$flag' needs a value" }
    $script:Root = [string]$args[$i + 1]
    $i += 2
  }
  elseif ($flag -in @('--kit', '-Kit')) {
    if ($i + 1 -ge $args.Count) { Fail 2 "flag '$flag' needs a value" }
    $script:Kit = [string]$args[$i + 1]
    $i += 2
  }
  elseif ($flag -in @('--upgrade', '-Upgrade')) { $script:DoUpgrade = $true; $i += 1 }
  elseif ($flag -in @('--dry-run', '-DryRun')) { $script:DryRun = $true; $i += 1 }
  elseif ($flag -in @('--force', '-Force')) { $script:Force = $true; $i += 1 }
  elseif ($flag -in @('--check-answers', '-CheckAnswers')) { $script:CheckAnswers = $true; $i += 1 }
  else { Fail 2 "unknown flag '$flag'" }
}

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptDir)) {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$scriptDir = (Get-AbsPath $scriptDir)

if ([string]::IsNullOrEmpty($script:Kit)) {
  $script:Kit = Get-AbsPath (Join-Path $scriptDir '..')
} else {
  if (-not [System.IO.Directory]::Exists($script:Kit)) { Fail 2 "kit directory not found: $($script:Kit)" }
  $script:Kit = Get-AbsPath $script:Kit
}

if ([string]::IsNullOrEmpty($script:Root)) {
  $script:Root = Get-AbsPath ([Environment]::CurrentDirectory)
} else {
  if (-not [System.IO.Directory]::Exists($script:Root)) {
    if ($script:DryRun) { Fail 2 "root directory not found: $($script:Root)" }
    [void][System.IO.Directory]::CreateDirectory($script:Root)
  }
  $script:Root = Get-AbsPath $script:Root
}

$script:Tpl = "$($script:Kit)/templates"
if (-not [System.IO.Directory]::Exists($script:Tpl)) { Fail 2 "templates directory not found: $($script:Tpl)" }
$verPath = "$($script:Kit)/VERSION"
if (-not [System.IO.File]::Exists($verPath)) { Fail 2 "kit VERSION file is empty" }
$script:Version = ([System.IO.File]::ReadAllText($verPath, $script:Utf8) -replace '[ \t\n\r\v\f]', '')
if ([string]::IsNullOrEmpty($script:Version)) { Fail 2 "kit VERSION file is empty" }

$script:Manifest = "$($script:Root)/orchestration-kit.manifest.json"

# --- IF / ENDIF ---
$script:KnownFlag = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
foreach ($f in @('research', 'loop', 'greenfield', 'lint', 'typecheck', 'models_pinned', 'is_claude', 'is_cursor', 'is_copilot', 'is_codex', 'want_claude', 'want_cursor', 'want_copilot', 'want_codex')) {
  $script:KnownFlag[$f] = $true
}
$script:Flags = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
foreach ($f in @($script:KnownFlag.Keys)) { $script:Flags[$f] = $false }

$script:IfRe = [regex]::new('^<!-- IF (!?[a-z][a-z0-9_]*) -->$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
$script:EndifRe = [regex]::new('^<!-- ENDIF (!?[a-z][a-z0-9_]*) -->$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
$script:TokenRe = [regex]::new('\{\{([A-Z_]+)\}\}', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
$script:BsOpenRe = [regex]::new('^<!-- BOOTSTRAP\[([a-z0-9]+(?:-[a-z0-9]+)*)\]:', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
$script:WsOnlyRe = [regex]::new('^[ \t\n\x0b\f\r]*$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
$script:BqPrefixRe = [regex]::new('^[ \t\n\x0b\f\r]*(>[ \t\n\x0b\f\r]*)+$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
$script:ListPrefixRe = [regex]::new('^[ \t\n\x0b\f\r]*([*+-]|[0-9]+\.)[ \t\n\x0b\f\r]*$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
$script:WsThenNlRe = [regex]::new('^[ \t\n\x0b\f\r]*\n', [Text.RegularExpressions.RegexOptions]::CultureInvariant)

function Parse-IfLine([string]$line) {
  $s = Trim-CStart (Trim-CEnd $line)
  if ($s.Length -gt 0 -and $s[0] -eq [char]'>') {
    $s = Trim-CStart $s.Substring(1)
  }
  $m = $script:IfRe.Match($s)
  if ($m.Success) { return @{ Kind = 'IF'; Spec = $m.Groups[1].Value } }
  $m = $script:EndifRe.Match($s)
  if ($m.Success) { return @{ Kind = 'ENDIF'; Spec = $m.Groups[1].Value } }
  return $null
}

$script:SyntaxErrs = [System.Collections.Generic.List[string]]::new()
$script:UnknownFlags = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
function Record-Syntax([string]$msg) { $script:SyntaxErrs.Add($msg) }

function Scan-IfSyntax([string]$file, [string]$rel) {
  $content = Read-FileRaw $file
  $stSpec = [System.Collections.Generic.List[string]]::new()
  $stLine = [System.Collections.Generic.List[int]]::new()
  $n = 0
  $lines = Get-BashLines $content
  foreach ($line in $lines) {
    $n++
    $mk = Parse-IfLine $line
    if ($null -eq $mk) { continue }
    $name = $mk.Spec.TrimStart('!')
    if (-not $script:KnownFlag.ContainsKey($name)) {
      $script:UnknownFlags[$name] = "${rel}:${n}"
    }
    if ($mk.Kind -eq 'IF') {
      $stSpec.Add($mk.Spec)
      $stLine.Add($n)
    } else {
      if ($stSpec.Count -eq 0) {
        Record-Syntax "${rel}:${n}: unmatched ENDIF '$($mk.Spec)'"
      } else {
        $top = $stSpec[$stSpec.Count - 1]
        if ($top -ne $mk.Spec) {
          Record-Syntax "${rel}:${n}: mismatched ENDIF '$($mk.Spec)' (open IF '$top' at line $($stLine[$stLine.Count - 1]))"
        }
        $stSpec.RemoveAt($stSpec.Count - 1)
        $stLine.RemoveAt($stLine.Count - 1)
      }
    }
  }
  for ($k = 0; $k -lt $stSpec.Count; $k++) {
    Record-Syntax "${rel}:$($stLine[$k]): unmatched IF '$($stSpec[$k])'"
  }
}

function Resolve-If([string]$content) {
  $stSpec = [System.Collections.Generic.List[string]]::new()
  $stKeep = [System.Collections.Generic.List[int]]::new()
  $out = [System.Collections.Generic.List[string]]::new()
  $keep = 1
  $lines = Get-BashLines $content
  foreach ($line in $lines) {
    $mk = Parse-IfLine $line
    if ($null -ne $mk) {
      $name = $mk.Spec.TrimStart('!')
      if ($mk.Kind -eq 'IF') {
        $cond = 0
        if ($script:Flags.ContainsKey($name) -and $script:Flags[$name] -eq $true) { $cond = 1 }
        if ($mk.Spec.StartsWith('!')) { $cond = 1 - $cond }
        $stSpec.Add($mk.Spec)
        $stKeep.Add($keep)
        if ($keep -eq 1 -and $cond -eq 1) { $keep = 1 } else { $keep = 0 }
      } else {
        $keep = $stKeep[$stKeep.Count - 1]
        $stSpec.RemoveAt($stSpec.Count - 1)
        $stKeep.RemoveAt($stKeep.Count - 1)
      }
      continue
    }
    if ($keep -eq 1) { $out.Add($line) }
  }
  if ($out.Count -eq 0) { return '' }
  return (Strip-AllNl (($out -join "`n") + "`n"))
}

# --- BOOTSTRAP ---
$script:BootstrapVal = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
$script:BootstrapHas = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
$script:BootstrapIdPath = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
$script:BsStart = [System.Collections.Generic.List[int]]::new()
$script:BsEnd = [System.Collections.Generic.List[int]]::new()
$script:BsId = [System.Collections.Generic.List[string]]::new()
$script:BsLine = [System.Collections.Generic.List[int]]::new()
$script:BsWhole = [System.Collections.Generic.List[int]]::new()

function Join-Collapse([string]$left, [string]$right) {
  $trail = 0
  $lead = 0
  while ($left.Length -gt 0 -and $left.EndsWith("`n")) {
    $left = $left.Substring(0, $left.Length - 1)
    $trail++
  }
  while ($right.Length -gt 0 -and $right.StartsWith("`n")) {
    $right = $right.Substring(1)
    $lead++
  }
  if ($left.Length -eq 0) { return $right }
  if ($right.Length -eq 0) { return ($left + "`n") }
  if (($trail + $lead) -ge 2) { return "${left}`n`n${right}" }
  return "${left}`n${right}"
}

function Find-Bootstrap([string]$text, [string]$rel) {
  $script:BsStart.Clear(); $script:BsEnd.Clear(); $script:BsId.Clear(); $script:BsLine.Clear(); $script:BsWhole.Clear()
  $pos = 0
  $needle = '<!-- BOOTSTRAP['
  while ($true) {
    if ($pos -gt $text.Length) { break }
    $idx = if ($pos -ge $text.Length) { -1 } else { $text.IndexOf($needle, $pos, [StringComparison]::Ordinal) }
    if ($idx -lt 0) { break }
    $abs = $idx
    $after = $text.Substring($abs)
    $om = $script:BsOpenRe.Match($after)
    if (-not $om.Success) {
      $pos = $abs + 16
      continue
    }
    $id = $om.Groups[1].Value
    $openLen = $om.Value.Length
    $rest = $text.Substring($abs + $openLen)
    $close = $rest.IndexOf('-->', [StringComparison]::Ordinal)
    if ($close -lt 0) {
      $pre = $text.Substring(0, $abs)
      $lineno = Get-AwkNR $pre
      $r = $rel
      if ([string]::IsNullOrEmpty($r)) { $r = '?' }
      Record-Syntax "${r}:${lineno}: unclosed BOOTSTRAP[$id]"
      break
    }
    $commentEnd = $abs + $openLen + $close + 3
    $pre = $text.Substring(0, $abs)
    $lineStart = 0
    if ($pre.Length -gt 0) {
      $nl = $pre.LastIndexOf("`n")
      if ($nl -ge 0) { $lineStart = $nl + 1 } else { $lineStart = 0 }
    }
    $linePrefix = $text.Substring($lineStart, $abs - $lineStart)
    $regionStart = $abs
    if ($script:WsOnlyRe.IsMatch($linePrefix) -or $script:BqPrefixRe.IsMatch($linePrefix) -or $script:ListPrefixRe.IsMatch($linePrefix)) {
      $regionStart = $lineStart
    }
    $regionEnd = $commentEnd
    $whole = 0
    $tail = $text.Substring($commentEnd)
    $atLineStart = ($regionStart -eq 0) -or ($text[$regionStart - 1] -eq [char]10)
    if ($atLineStart) {
      if ($tail.Length -eq 0) {
        $whole = 1
      } elseif ($script:WsThenNlRe.IsMatch($tail) -or $script:WsOnlyRe.IsMatch($tail)) {
        $nl = $tail.IndexOf("`n", [StringComparison]::Ordinal)
        if ($nl -ge 0) { $regionEnd = $commentEnd + $nl + 1 } else { $regionEnd = $text.Length }
        $whole = 1
      }
    }
    $lineno = Get-AwkNR ($text.Substring(0, $abs))
    if ($lineno -eq 0 -and $abs -eq 0) { $lineno = 0 }
    if ([string]::IsNullOrEmpty([string]$lineno)) { $lineno = 1 }
    $script:BsStart.Add($regionStart)
    $script:BsEnd.Add($regionEnd)
    $script:BsId.Add($id)
    $script:BsLine.Add($lineno)
    $script:BsWhole.Add($whole)
    $pos = $commentEnd
  }
}

function Scan-BootstrapIdsIn([string]$file, [string]$rel) {
  $content = Read-FileRaw $file
  Find-Bootstrap $content $rel
  for ($bi = 0; $bi -lt $script:BsId.Count; $bi++) {
    $id = $script:BsId[$bi]
    if ($id.StartsWith('kit-')) { continue }
    if (-not $script:BootstrapIdPath.ContainsKey($id)) {
      $script:BootstrapIdPath[$id] = $rel
    }
  }
}

function Invoke-Bootstrap([string]$text, [string]$rel, [string]$mode) {
  Find-Bootstrap $text $rel
  if ($script:BsId.Count -eq 0) { return $text }
  for ($bi = $script:BsId.Count - 1; $bi -ge 0; $bi--) {
    $id = $script:BsId[$bi]
    $start = $script:BsStart[$bi]
    $end = $script:BsEnd[$bi]
    $whole = $script:BsWhole[$bi]
    $left = $text.Substring(0, $start)
    $right = $text.Substring($end)
    $repl = ''
    $doDelete = 1
    if ($mode -eq 'apply') {
      if ($id.StartsWith('kit-')) {
        $doDelete = 1
      } elseif ($script:BootstrapHas.ContainsKey($id)) {
        $repl = [string]$script:BootstrapVal[$id]
        if ($repl.Length -gt 0) { $doDelete = 0 } else { $doDelete = 1 }
      } else {
        $doDelete = 1
      }
    }
    if ($doDelete -eq 1) {
      if ($whole -eq 1) {
        $text = Strip-AllNl (Join-Collapse $left $right)
      } else {
        $text = $left + $right
      }
    } else {
      if ($whole -eq 1 -and $end -gt 0 -and $text[$end - 1] -eq [char]10) {
        $text = $left + $repl + "`n" + $right
      } else {
        $text = $left + $repl + $right
      }
    }
  }
  return $text
}

# --- tokens / frontmatter ---
$script:Tokens = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
$script:Problems = [System.Collections.Generic.List[string]]::new()
$script:Resolved = ''
function Add-Problem([string]$m) { $script:Problems.Add($m) }

function Replace-Tokens([string]$text) {
  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($name in @($script:Tokens.Keys)) {
      $needle = '{{' + $name + '}}'
      if ($text.Contains($needle)) {
        $text = $text.Replace($needle, [string]$script:Tokens[$name])
        $changed = $true
      }
    }
  }
  return $text
}

function Scan-UnresolvedTokens([string]$text, [string]$rel) {
  $tmp = $text
  while ($true) {
    $m = $script:TokenRe.Match($tmp)
    if (-not $m.Success) { break }
    $tok = $m.Groups[1].Value
    if (-not $script:Tokens.ContainsKey($tok)) {
      Add-Problem "token '$tok' has no value in $rel"
    }
    $tmp = $tmp.Substring($m.Index + $m.Length)
  }
}

$script:FmInner = ''
$script:BodyAfter = ''

function Split-Fm([string]$content) {
  if ($content.Length -lt 4 -or $content.Substring(0, 4) -ne "---`n") { return $false }
  $rest = $content.Substring(4)
  $close = $rest.IndexOf("`n---", [StringComparison]::Ordinal)
  if ($close -lt 0) { return $false }
  $script:FmInner = $rest.Substring(0, $close)
  $script:BodyAfter = $rest.Substring($close + 4)
  return $true
}

function Filter-FmLines([string]$inner, [string]$role, [string]$mode) {
  $out = ''
  $seenUser = 0
  $lines = Get-BashLines $inner
  foreach ($line in $lines) {
    switch ($mode) {
      'cursor-agent' {
        if ($line.StartsWith('effort:') -or $line.StartsWith('tools:')) { continue }
        $out += $line + "`n"
        if ($line.StartsWith('model:')) {
          if ($role -in @('evaluator', 'qa-evaluator', 'diagnostician')) {
            $out += "readonly: true`n"
          }
        }
      }
      'cursor-skill' {
        if ($line.StartsWith('model:') -or $line.StartsWith('effort:')) { continue }
        $out += $line + "`n"
      }
      'copilot-agent' {
        if ($line.StartsWith('effort:')) { continue }
        elseif ($line.StartsWith('model:')) {
          $mv = $line.Substring(6)
          $mv = Trim-CStart $mv
          $out += "model: [`"$mv`"]`n"
        }
        elseif ($line.StartsWith('tools:')) {
          if ($role -eq 'terminal') { $out += "tools: ['read', 'execute']`n" }
          else { $out += $line + "`n" }
        }
        elseif ($line.StartsWith('user-invocable:')) { $seenUser = 1; $out += $line + "`n" }
        else { $out += $line + "`n" }
      }
      'copilot-feature' {
        if ($line.StartsWith('effort:')) { continue }
        elseif ($line.StartsWith('user-invocable:')) { $seenUser = 1; $out += $line + "`n" }
        else { $out += $line + "`n" }
      }
      default { $out += $line + "`n" }
    }
  }
  if ($mode -eq 'copilot-agent' -and $seenUser -eq 0) {
    $out += "user-invocable: false`n"
  }
  if ($mode -eq 'copilot-feature') {
    $out += "model: [`"$($script:Tokens['MODEL_FRONTIER'])`"]`n"
    if ($seenUser -eq 0) { $out += "user-invocable: true`n" }
    $out += "agents: [implementer, test-writer, evaluator, qa-evaluator, terminal, diagnostician]`n"
    $out += "tools: ['agent']`n"
  }
  return $out
}

function Wrap-Fm([string]$inner, [string]$body) {
  $inner = Strip-AllNl $inner
  return "---`n$inner`n---$body"
}

function Translate-CursorAgent([string]$role, [string]$content) {
  if (-not (Split-Fm $content)) { return $content }
  return (Wrap-Fm (Filter-FmLines $script:FmInner $role 'cursor-agent') $script:BodyAfter)
}
function Translate-CursorSkill([string]$content) {
  if (-not (Split-Fm $content)) { return $content }
  return (Wrap-Fm (Filter-FmLines $script:FmInner '' 'cursor-skill') $script:BodyAfter)
}
function Translate-CopilotAgent([string]$role, [string]$content) {
  if (-not (Split-Fm $content)) { return $content }
  return (Wrap-Fm (Filter-FmLines $script:FmInner $role 'copilot-agent') $script:BodyAfter)
}
function Translate-CopilotFeature([string]$content) {
  if (-not (Split-Fm $content)) { return $content }
  return (Wrap-Fm (Filter-FmLines $script:FmInner 'feature' 'copilot-feature') $script:BodyAfter)
}
function Strip-Frontmatter([string]$content) {
  if (-not (Split-Fm $content)) { return $content }
  $body = $script:BodyAfter
  while ($body.Length -gt 0 -and $body[0] -eq [char]10) { $body = $body.Substring(1) }
  return $body
}

function Get-IdeDir([string]$h) {
  switch ($h) {
    'claude-code' { return '.claude' }
    'cursor' { return '.cursor' }
    'copilot' { return '.github' }
    'codex' { return '.codex' }
    default { Fail 3 "unknown harness '$h'" }
  }
}
function Get-HarnessSuffix([string]$h) {
  switch ($h) {
    'claude-code' { return 'claude' }
    'cursor' { return 'cursor' }
    'copilot' { return 'copilot' }
    'codex' { return 'codex' }
    default { Fail 3 "unknown harness '$h'" }
  }
}
function Get-HarnessPrefix([string]$h) {
  switch ($h) {
    'claude-code' { return 'CLAUDE' }
    'cursor' { return 'CURSOR' }
    'copilot' { return 'COPILOT' }
    'codex' { return 'CODEX' }
    default { return '' }
  }
}

$script:KitSkills = [System.Collections.Generic.List[string]]::new()
function Load-KitSkills {
  $script:KitSkills.Clear()
  foreach ($d in (Get-DirsSorted "$($script:Tpl)/skills")) {
    $script:KitSkills.Add([System.IO.Path]::GetFileName($d.Replace('\', '/')))
  }
  $hasAl = $false
  foreach ($s in $script:KitSkills) { if ($s -eq 'auto-loop') { $hasAl = $true } }
  if (-not $hasAl) { $script:KitSkills.Add('auto-loop') }
}

function Test-SeedPath([string]$p) { return ($p -eq '_goals/backlog.md') }

function Test-KitOwned([string]$p) {
  if ($p -like '.claude/agents/*' -or $p -like '.cursor/agents/*' -or $p -like '.github/agents/*' -or $p -like '.codex/agents/*') { return $true }
  if ($p -eq '.cursor/rules/orchestration.mdc') { return $true }
  if ($p -like '_loop/*' -or $p -like '_kit/*') { return $true }
  if ($p -eq 'ORCHESTRATION.md') { return $true }
  if ($p -eq '.claude/ORCHESTRATION.md' -or $p -eq '.cursor/ORCHESTRATION.md') { return $true }
  if ($p -eq '.claude/skills/setup-models.map.md' -or $p -eq '.cursor/skills/setup-models.map.md') { return $true }
  foreach ($dir in @('.claude', '.cursor', '.github', '.codex')) {
    foreach ($skill in $script:KitSkills) {
      if ($p -eq "$dir/skills/$skill" -or $p.StartsWith("$dir/skills/$skill/", [StringComparison]::Ordinal)) { return $true }
    }
  }
  return $false
}

function Get-PointerClaude {
  return @"
## Orchestration
Feature work runs through the orchestrator/worker/evaluator system — see
.claude/ORCHESTRATION.md. Start features with /feature.
$($script:PointerMarker)
"@
}
function Get-PointerCopilot {
  return @"
## Orchestration
Feature work runs through the orchestrator/worker/evaluator system — see ORCHESTRATION.md. Start features with the ``feature`` agent.
$($script:PointerMarker)
"@
}
function Get-PointerAgentsMd {
  return @"
## Orchestration
Non-trivial features run through the orchestrator/worker/evaluator flow in
ORCHESTRATION.md: plan → evaluate the plan → implement per task (spawn ``implementer`` /
``test-writer``) → evaluate every task (spawn ``evaluator``) → final audit → quality checks.
Fixes are always re-evaluated. After three fix cycles, spawn ``diagnostician`` for rung 4
diagnosis. Quality checks spawn ``terminal`` for the full-suite run so its raw output stays
out of the session. Role instructions: .codex/agents/*.md (six roles).
$($script:PointerMarker)
"@
}
function Get-PointerCursorMdc {
  return @'
---
alwaysApply: true
---
Feature work runs through the orchestrator/worker/evaluator system described in
.cursor/ORCHESTRATION.md. Non-trivial features start with the `feature` skill;
implementation goes to the implementer/test-writer subagents; all verification goes to
the evaluator subagents. Never mark orchestrated work complete without an evaluator PASS.
'@
}
function Get-CodexConfigTables([string]$light) {
  return @"
$($script:CodexAgentsMarker)
[agents]
default_subagent_model = "$light"
default_subagent_reasoning_effort = "medium"

[agents.evaluator]
description = "Skeptical goal/task/code evaluator. Spawn to verify any completed work; returns PASS/NEEDS FIXES/REJECT. Read .codex/agents/evaluator.md first."
config_file = "agents/evaluator.toml"

[agents.qa-evaluator]
description = "User-perspective behavioral QA evaluator for captured evidence. Read .codex/agents/qa-evaluator.md first."
config_file = "agents/qa-evaluator.toml"

[agents.implementer]
description = "Checklist-driven implementer for one task per spawn. Read .codex/agents/implementer.md first."
config_file = "agents/implementer.toml"

[agents.test-writer]
description = "Coverage-obsessed test writer, external services mocked. Read .codex/agents/test-writer.md first."
config_file = "agents/test-writer.toml"

[agents.terminal]
description = "Command runner — any Bash or PowerShell command; returns only the result the caller asked for. Read .codex/agents/terminal.md first."
config_file = "agents/terminal.toml"

[agents.diagnostician]
description = "Root-cause diagnostician for task failures after fix-cycle exhaustion. Read .codex/agents/diagnostician.md first."
config_file = "agents/diagnostician.toml"
"@
}
function Get-CodexRoleToml([string]$mid) { return "model = `"$mid`"`n" }
function Get-SettingsJsonMin {
  return "{`n  `"env`": {`n    `"CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`": `"3`"`n  }`n}`n"
}

# --- emit set ---
$script:Emit = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
$script:Warnings = 0
$script:WarnLines = [System.Collections.Generic.List[string]]::new()
function Bump-Warn { $script:Warnings++ }
function Add-WarnLine([string]$msg) {
  $script:WarnLines.Add($msg)
  Bump-Warn
}
function Write-BufferedWarnLines {
  if ($script:WarnLines.Count -eq 0) { return }
  $arr = $script:WarnLines.ToArray()
  [Array]::Sort($arr, $script:Ord)
  foreach ($line in $arr) { [Console]::Error.Write("emit: $line`n") }
  $script:WarnLines.Clear()
}
$script:DryActions = [System.Collections.Generic.List[string]]::new()
function Add-DryAction([string]$a, [string]$p) { $script:DryActions.Add("$a $p") }

$script:Harnesses = [System.Collections.Generic.List[string]]::new()
$script:Primary = ''
$script:Answers = $null
$script:ForgeKind = ''
$script:ForgeHost = ''
$script:OrchRootWriter = ''
$script:ModelsMapBytes = ''
$script:SeedContent = ''
$script:MissingBootstrap = [System.Collections.Generic.List[string]]::new()

function Set-WantFlags {
  $script:Flags['want_claude'] = $false
  $script:Flags['want_cursor'] = $false
  $script:Flags['want_copilot'] = $false
  $script:Flags['want_codex'] = $false
  foreach ($h in $script:Harnesses) {
    $s = Get-HarnessSuffix $h
    $script:Flags["want_$s"] = $true
  }
}
function Set-IsFlags([string]$h) {
  $script:Flags['is_claude'] = $false
  $script:Flags['is_cursor'] = $false
  $script:Flags['is_copilot'] = $false
  $script:Flags['is_codex'] = $false
  if (-not [string]::IsNullOrEmpty($h)) {
    $s = Get-HarnessSuffix $h
    $script:Flags["is_$s"] = $true
  }
}

function Get-ModelField([string]$h, [string]$f) {
  if ($null -eq $script:Answers -or -not $script:Answers.ContainsKey('models')) { return '' }
  $m = $script:Answers['models']
  if (-not (Test-IsJsonObject $m) -or -not $m.ContainsKey($h)) { return '' }
  $mh = $m[$h]
  if (-not (Test-IsJsonObject $mh) -or -not $mh.ContainsKey($f)) { return '' }
  $v = $mh[$f]
  if ($null -eq $v) { return '' }
  return (Strip-AllNl (ConvertTo-JqRaw $v))
}

# Usage-credit loop-chain entries (exact + claude-fable prefix); sole pinned literal set.
$script:LoopChainUsageCreditDenylist = @('best', 'fable', 'claude-fable*')

function Test-LoopChainEntryBillsUsageCredits([string]$entry) {
  foreach ($pat in $script:LoopChainUsageCreditDenylist) {
    if ($entry -clike $pat) { return $true }
  }
  return $false
}

function Get-ModelFast([string]$h) {
  $v = Get-ModelField $h 'fast'
  if (-not [string]::IsNullOrEmpty($v)) { return $v }
  return (Get-ModelField $h 'light')
}

function Test-ModelsFieldPresent([string]$h, [string]$f) {
  if ($null -eq $script:Answers -or -not $script:Answers.ContainsKey('models')) { return $false }
  $m = $script:Answers['models']
  if (-not (Test-IsJsonObject $m) -or -not $m.ContainsKey($h)) { return $false }
  $mh = $m[$h]
  return ((Test-IsJsonObject $mh) -and $mh.ContainsKey($f))
}

function Validate-ModelsContract([string]$h) {
  if (Test-ModelsFieldPresent $h 'fast') {
    $mh = $script:Answers['models'][$h]
    if ($mh['fast'] -isnot [string]) { Add-Problem "models.$h.fast must be a string" }
  }
  if (Test-ModelsFieldPresent $h 'arbiter_same_family') {
    $mh = $script:Answers['models'][$h]
    if ($mh['arbiter_same_family'] -isnot [bool]) { Add-Problem "models.$h.arbiter_same_family must be a boolean" }
  }
  $lc = Get-ModelField $h 'loop_chain'
  if ([string]::IsNullOrEmpty($lc)) { return }
  foreach ($entry in $lc.Split(',')) {
    if (Test-LoopChainEntryBillsUsageCredits $entry) {
      Add-Problem "models.$h.loop_chain entry '$entry' can bill usage credits in headless runs"
    }
  }
}

function Warn-ModelsArbiter([string]$h) {
  $fam = Get-ModelField $h 'frontier_alt_family'
  if ([string]::IsNullOrEmpty($fam)) { return }
  $frontier = Get-ModelField $h 'frontier'
  $alt = Get-ModelField $h 'alt_family'
  if ($fam -ceq $frontier) {
    $flag = $false
    if (Test-ModelsFieldPresent $h 'arbiter_same_family') {
      $flag = ($script:Answers['models'][$h]['arbiter_same_family'] -eq $true)
    }
    if (-not $flag) {
      Add-WarnLine "warning: models.$h.frontier_alt_family equals frontier; set arbiter_same_family: true to accept a same-family arbiter"
    }
    return
  }
  if (($fam -cne $frontier) -and ($fam -ceq $alt)) {
    Add-WarnLine "warning: models.$h.frontier_alt_family equals alt_family; the rung-5 arbiter must not reuse the fix-cycle-2 model"
  }
}

function Load-GlobalTokens {
  $script:Tokens = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
  $pn = ''
  if ($script:Answers.ContainsKey('tokens') -and (Test-IsJsonObject $script:Answers['tokens']) -and $script:Answers['tokens'].ContainsKey('PROJECT_NAME')) {
    $pn = Strip-AllNl (ConvertTo-JqRaw $script:Answers['tokens']['PROJECT_NAME'])
  }
  if ([string]::IsNullOrEmpty($pn) -and $script:Answers.ContainsKey('projectName')) {
    $pn = Strip-AllNl (ConvertTo-JqRaw $script:Answers['projectName'])
  }
  if (-not [string]::IsNullOrEmpty($pn)) { $script:Tokens['PROJECT_NAME'] = $pn }
  if ($script:Answers.ContainsKey('tokens') -and (Test-IsJsonObject $script:Answers['tokens'])) {
    foreach ($k in @($script:Answers['tokens'].Keys)) {
      $ks = [string]$k
      $v = $script:Answers['tokens'][$k]
      if ($null -eq $v) { $script:Tokens[$ks] = '' }
      else { $script:Tokens[$ks] = Strip-AllNl (ConvertTo-JqRaw $v) }
    }
  }
  if (-not [string]::IsNullOrEmpty($pn)) { $script:Tokens['PROJECT_NAME'] = $pn }
  foreach ($h in $script:Harnesses) {
    $pre = Get-HarnessPrefix $h
    $v = Get-ModelField $h 'frontier'
    if (-not [string]::IsNullOrEmpty($v)) { $script:Tokens["${pre}_MODEL_FRONTIER"] = $v }
    $v = Get-ModelField $h 'light'
    if (-not [string]::IsNullOrEmpty($v)) { $script:Tokens["${pre}_MODEL_LIGHT"] = $v }
    $v = Get-ModelFast $h
    if (-not [string]::IsNullOrEmpty($v)) { $script:Tokens["${pre}_MODEL_FAST"] = $v }
  }
  $script:Tokens['LOOP_MODEL_CHAIN'] = (Get-ModelField $script:Primary 'loop_chain')
}

function Set-HarnessTokens([string]$h) {
  $script:Tokens['IDE_DIR'] = Get-IdeDir $h
  $v = Get-ModelField $h 'frontier'
  if (-not [string]::IsNullOrEmpty($v)) { $script:Tokens['MODEL_FRONTIER'] = $v } else { $script:Tokens.Remove('MODEL_FRONTIER') }
  $v = Get-ModelField $h 'light'
  if (-not [string]::IsNullOrEmpty($v)) { $script:Tokens['MODEL_LIGHT'] = $v } else { $script:Tokens.Remove('MODEL_LIGHT') }
  $v = Get-ModelField $h 'alt_family'
  if (-not [string]::IsNullOrEmpty($v)) { $script:Tokens['MODEL_ALT_FAMILY'] = $v } else { $script:Tokens.Remove('MODEL_ALT_FAMILY') }
  $v = Get-ModelField $h 'frontier_alt_family'
  if (-not [string]::IsNullOrEmpty($v)) { $script:Tokens['MODEL_FRONTIER_ALT_FAMILY'] = $v } else { $script:Tokens.Remove('MODEL_FRONTIER_ALT_FAMILY') }
  $v = Get-ModelFast $h
  if (-not [string]::IsNullOrEmpty($v)) { $script:Tokens['MODEL_FAST'] = $v } else { $script:Tokens.Remove('MODEL_FAST') }
}

function Resolve-Template([string]$src, [string]$rel) {
  $content = Strip-AllNl (Read-FileRaw $src)
  $content = Strip-AllNl (Resolve-If $content)
  $stripped = Strip-AllNl (Invoke-Bootstrap $content $rel 'strip')
  Scan-UnresolvedTokens $stripped $rel
  $content = Strip-AllNl (Invoke-Bootstrap $content $rel 'apply')
  $content = Strip-AllNl (Replace-Tokens $content)
  $script:Resolved = $content
}

function Put-Emit([string]$p, [string]$c) {
  if (-not [string]::IsNullOrEmpty($c) -and -not $c.EndsWith("`n")) { $c += "`n" }
  $script:Emit[$p] = $c
}

function Copy-SkillTree([string]$name, [string]$destPrefix, [string]$mode) {
  $srcRoot = "$($script:Tpl)/skills/$name"
  if (-not [System.IO.Directory]::Exists($srcRoot)) { return }
  $srcRootN = $srcRoot.Replace('\', '/')
  foreach ($f in (Get-FilesSorted $srcRoot '*' $true)) {
    $fn = $f.Replace('\', '/')
    $rel = ConvertTo-UnixRel $fn $srcRootN
    $dest = $rel
    $base = [System.IO.Path]::GetFileName($rel)
    if ($base -eq 'SKILL.template.md') {
      $d = [System.IO.Path]::GetDirectoryName($rel)
      if ([string]::IsNullOrEmpty($d) -or $d -eq '.') { $dest = 'SKILL.md' }
      else { $dest = ($d.Replace('\', '/') + '/SKILL.md') }
    }
    Resolve-Template $fn "skills/$name/$rel"
    $content = $script:Resolved
    if ([System.IO.Path]::GetFileName($dest) -eq 'SKILL.md' -and $mode -eq 'cursor') {
      $content = Strip-AllNl (Translate-CursorSkill $content)
    }
    Put-Emit "$destPrefix/$dest" $content
  }
}

function Emit-Agents([string]$h) {
  $destDir = "$(Get-IdeDir $h)/agents"
  $agentsDir = "$($script:Tpl)/agents"
  foreach ($f in (Get-FilesSorted $agentsDir '*.md' $false)) {
    $fn = $f.Replace('\', '/')
    $role = [System.IO.Path]::GetFileNameWithoutExtension($fn)
    Resolve-Template $fn "agents/$(Split-Path -Leaf $fn)"
    $content = $script:Resolved
    switch ($h) {
      'claude-code' { Put-Emit "$destDir/$role.md" $content }
      'cursor' { Put-Emit "$destDir/$role.md" (Strip-AllNl (Translate-CursorAgent $role $content)) }
      'copilot' { Put-Emit ".github/agents/${role}.agent.md" (Strip-AllNl (Translate-CopilotAgent $role $content)) }
      'codex' {
        Put-Emit ".codex/agents/${role}.md" (Strip-AllNl (Strip-Frontmatter $content))
        if ($role -in @('evaluator', 'qa-evaluator', 'diagnostician')) { $mid = [string]$script:Tokens['MODEL_FRONTIER'] }
        elseif ($role -eq 'terminal') {
          if ($script:Tokens.ContainsKey('MODEL_FAST')) { $mid = [string]$script:Tokens['MODEL_FAST'] }
          else { $mid = [string]$script:Tokens['MODEL_LIGHT'] }
        }
        else { $mid = [string]$script:Tokens['MODEL_LIGHT'] }
        Put-Emit ".codex/agents/${role}.toml" (Strip-AllNl (Get-CodexRoleToml $mid))
      }
    }
  }
}

function Emit-SkillsFor([string]$h) {
  $ide = Get-IdeDir $h
  $mode = ''
  switch ($h) {
    'claude-code' { $mode = 'claude' }
    'cursor' { $mode = 'cursor' }
    'copilot' { $mode = 'copilot' }
    'codex' { return }
  }
  foreach ($d in (Get-DirsSorted "$($script:Tpl)/skills")) {
    $name = [System.IO.Path]::GetFileName($d.Replace('\', '/'))
    if ($name -eq 'research' -and $script:Flags['research'] -ne $true) { continue }
    if ($h -eq 'copilot' -and $name -eq 'feature') {
      # Copilot gets the orchestrator as a native agent (subagent allowlist +
      # model array) AND as a first-class skill tree below — same as every
      # other kit skill — so .github/skills/feature/ always has its SKILL.md.
      $src = "$($script:Tpl)/skills/feature/SKILL.template.md"
      Resolve-Template $src 'skills/feature/SKILL.template.md'
      Put-Emit '.github/agents/feature.agent.md' (Strip-AllNl (Translate-CopilotFeature $script:Resolved))
    }
    Copy-SkillTree $name "$ide/skills/$name" $mode
  }
  if ($script:Flags['loop'] -eq $true) {
    $src = "$($script:Tpl)/loop/SKILL.template.md"
    if ([System.IO.File]::Exists($src)) {
      Resolve-Template $src 'loop/SKILL.template.md'
      $content = $script:Resolved
      if ($mode -eq 'cursor') { $content = Strip-AllNl (Translate-CursorSkill $content) }
      Put-Emit "$ide/skills/auto-loop/SKILL.md" $content
    }
  }
}

function Emit-ModelsMapOnce {
  Resolve-Template "$($script:Tpl)/models.map.md" 'models.map.md'
  $script:ModelsMapBytes = $script:Resolved
}

function Emit-Orchestration([string]$h) {
  Resolve-Template "$($script:Tpl)/ORCHESTRATION.md" 'ORCHESTRATION.md'
  $content = $script:Resolved
  switch ($h) {
    { $_ -in 'claude-code', 'cursor' } { Put-Emit "$(Get-IdeDir $h)/ORCHESTRATION.md" $content }
    { $_ -in 'copilot', 'codex' } {
      if ($h -eq $script:OrchRootWriter) { Put-Emit 'ORCHESTRATION.md' $content }
    }
  }
}

function Emit-SingleCopy {
  Set-IsFlags $script:Primary
  Set-HarnessTokens $script:Primary
  if ($script:Flags['loop'] -eq $true) {
    foreach ($f in @('loop.sh', 'loop.ps1', 'breaker.sh', 'breaker.ps1', 'PROMPT.md')) {
      $src = "$($script:Tpl)/loop/$f"
      if ([System.IO.File]::Exists($src)) {
        Resolve-Template $src "loop/$f"
        Put-Emit "_loop/$f" $script:Resolved
      }
    }
  }
  foreach ($f in @('log-spawn.sh', 'log-spawn.ps1')) {
    $src = "$($script:Tpl)/tools/$f"
    if ([System.IO.File]::Exists($src)) {
      Resolve-Template $src "tools/$f"
      Put-Emit "_kit/$f" $script:Resolved
    }
  }
}

function Prepare-Seed {
  $script:SeedContent = ''
  if ($script:Flags['loop'] -eq $true -and [System.IO.File]::Exists("$($script:Tpl)/loop/backlog.md")) {
    Set-IsFlags $script:Primary
    Set-HarnessTokens $script:Primary
    Resolve-Template "$($script:Tpl)/loop/backlog.md" 'loop/backlog.md'
    $script:SeedContent = $script:Resolved
  }
}

function Choose-OrchRootWriter {
  $script:OrchRootWriter = ''
  foreach ($h in $script:Harnesses) {
    if ($h -in @('copilot', 'codex')) {
      if ($script:Primary -in @('copilot', 'codex') -and $h -eq $script:Primary) {
        $script:OrchRootWriter = $h
        return
      }
    }
  }
  foreach ($h in $script:Harnesses) {
    if ($h -in @('copilot', 'codex')) { $script:OrchRootWriter = $h; return }
  }
}

function Collect-EmitSet {
  $script:Emit = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
  Set-WantFlags
  Choose-OrchRootWriter
  $wantMap = $false
  foreach ($h in $script:Harnesses) {
    if ($h -in @('claude-code', 'cursor')) { $wantMap = $true }
  }
  Set-IsFlags ''
  Load-GlobalTokens
  if ($wantMap) {
    Set-HarnessTokens $script:Primary
    Emit-ModelsMapOnce
  }
  foreach ($h in $script:Harnesses) {
    Set-IsFlags $h
    Set-HarnessTokens $h
    Emit-Agents $h
    Emit-SkillsFor $h
    Emit-Orchestration $h
    if ($h -in @('claude-code', 'cursor')) {
      Put-Emit "$(Get-IdeDir $h)/skills/setup-models.map.md" $script:ModelsMapBytes
    }
    if ($h -eq 'cursor') {
      Put-Emit '.cursor/rules/orchestration.mdc' (Strip-AllNl (Get-PointerCursorMdc))
    }
  }
  Emit-SingleCopy
  Prepare-Seed
}

# --- answers ---
function ConvertFrom-AnswersJson([string]$json) {
  try {
    $obj = $json | ConvertFrom-Json -AsHashtable -Depth 100
  } catch {
    Fail 2 'answers file unreadable'
  }
  if ($null -eq $obj) { Fail 2 'answers file unreadable' }
  return $obj
}

function Validate-AnswersSchema {
  $v = ''
  if ($script:Answers -is [System.Collections.IDictionary] -and $script:Answers.ContainsKey('schema')) {
    $v = ConvertTo-JqRaw $script:Answers['schema']
  }
  if ($v -ne '1') {
    $got = $v
    if ([string]::IsNullOrEmpty($got)) { $got = 'missing' }
    Add-Problem "schema must be 1 (got '$got')"
  }
  $hs = $null
  if ($script:Answers -is [System.Collections.IDictionary] -and $script:Answers.ContainsKey('harnesses')) {
    $hs = $script:Answers['harnesses']
  }
  if (-not (Test-IsJsonArray $hs) -or @($hs).Count -lt 1) {
    Add-Problem 'harnesses must be a non-empty array'
  } else {
    foreach ($h in @($hs)) {
      $hs2 = [string]$h
      if ($hs2 -in @('claude-code', 'cursor', 'copilot', 'codex')) { $script:Harnesses.Add($hs2) }
      else { Add-Problem "unknown harness '$hs2'" }
    }
  }
  $script:Primary = ''
  if ($script:Answers -is [System.Collections.IDictionary] -and $script:Answers.ContainsKey('primary')) {
    $script:Primary = Strip-AllNl (ConvertTo-JqRaw $script:Answers['primary'])
  }
  if ([string]::IsNullOrEmpty($script:Primary)) {
    Add-Problem 'primary is missing'
  } else {
    $found = $false
    foreach ($h in $script:Harnesses) { if ($h -eq $script:Primary) { $found = $true } }
    if (-not $found) { Add-Problem "primary '$($script:Primary)' is not in harnesses" }
  }
  foreach ($h in $script:Harnesses) {
    $ok = $false
    if ($script:Answers.ContainsKey('models') -and (Test-IsJsonObject $script:Answers['models']) -and $script:Answers['models'].ContainsKey($h) -and (Test-IsJsonObject $script:Answers['models'][$h])) {
      $ok = $true
    }
    if (-not $ok) { Add-Problem "models entry missing for harness '$h'" }
    else { Validate-ModelsContract $h }
  }
  foreach ($f in @('research', 'loop', 'greenfield', 'lint', 'typecheck', 'models_pinned')) {
    $has = $false
    $isTrue = $false
    if ($script:Answers.ContainsKey('flags') -and (Test-IsJsonObject $script:Answers['flags']) -and $script:Answers['flags'].ContainsKey($f)) {
      $has = $true
      $fv = $script:Answers['flags'][$f]
      if ($fv -is [bool] -and $fv) { $isTrue = $true }
    }
    if (-not $has) {
      Add-Problem "flags.$f missing"
      $script:Flags[$f] = $false
    } else {
      $script:Flags[$f] = $isTrue
    }
  }
  $script:ForgeKind = ''
  $script:ForgeHost = ''
  if ($script:Answers.ContainsKey('forge') -and (Test-IsJsonObject $script:Answers['forge'])) {
    $fg = $script:Answers['forge']
    if ($fg.ContainsKey('kind')) { $script:ForgeKind = Strip-AllNl (ConvertTo-JqRaw $fg['kind']) }
    if ($fg.ContainsKey('host')) { $script:ForgeHost = Strip-AllNl (ConvertTo-JqRaw $fg['host']) }
  }
  if ($script:ForgeKind -notin @('github', 'azuredevops', 'gitlab', 'none')) {
    $got = $script:ForgeKind
    if ([string]::IsNullOrEmpty($got)) { $got = 'missing' }
    Add-Problem "forge.kind must be github|azuredevops|gitlab|none (got '$got')"
  }
}

function Load-BootstrapMap {
  $script:BootstrapVal = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
  $script:BootstrapHas = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
  if ($script:Answers.ContainsKey('bootstrap') -and (Test-IsJsonObject $script:Answers['bootstrap'])) {
    foreach ($id in @($script:Answers['bootstrap'].Keys)) {
      $ids = [string]$id
      $script:BootstrapHas[$ids] = 1
      $v = $script:Answers['bootstrap'][$id]
      if ($null -eq $v) { $script:BootstrapVal[$ids] = '' }
      else { $script:BootstrapVal[$ids] = Strip-AllNl (ConvertTo-JqRaw $v) }
    }
  }
}

function Walk-AllTemplates {
  return (Get-FilesSorted $script:Tpl '*' $true)
}

function Scan-AllTemplates {
  foreach ($f in (Walk-AllTemplates)) {
    $fn = $f.Replace('\', '/')
    $rel = ConvertTo-UnixRel $fn $script:Tpl
    Scan-IfSyntax $fn $rel
    Scan-BootstrapIdsIn $fn $rel
  }
}

function Flush-Syntax {
  if ($script:SyntaxErrs.Count -gt 0) {
    $full = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $script:SyntaxErrs) { $full.Add("emit: $e") }
    $arr = $full.ToArray()
    [Array]::Sort($arr, $script:Ord)
    foreach ($line in $arr) { [Console]::Error.Write($line + "`n") }
    exit 6
  }
}
function Flush-Problems {
  if ($script:Problems.Count -gt 0) {
    $full = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $script:Problems) { $full.Add("emit: $p") }
    $arr = $full.ToArray()
    [Array]::Sort($arr, $script:Ord)
    foreach ($line in $arr) { [Console]::Error.Write($line + "`n") }
    exit 3
  }
}

function Compute-MissingBootstrap {
  $script:MissingBootstrap.Clear()
  $ids = [System.Collections.Generic.List[string]]::new()
  foreach ($id in @($script:BootstrapIdPath.Keys)) { $ids.Add([string]$id) }
  $ids.Sort($script:Ord)
  foreach ($id in $ids) {
    if (-not $script:BootstrapHas.ContainsKey($id)) { $script:MissingBootstrap.Add($id) }
  }
}

function Test-FileHasMarker([string]$path, [string]$marker) {
  if (-not [System.IO.File]::Exists($path)) { return $false }
  $t = Read-FileRaw $path
  return $t.Contains($marker)
}

function Append-LineOnce([string]$current, [string]$line) {
  $current = Strip-OneNl $current
  if (-not [string]::IsNullOrEmpty($current)) {
    $have = $false
    foreach ($ln in (Get-BashLines $current)) {
      if ($ln -ceq $line) { $have = $true; break }
    }
    if ($have) { return (Strip-AllNl ($current + "`n")) }
  }
  if ([string]::IsNullOrEmpty($current)) { return $line }
  return (Strip-AllNl ($current + "`n" + $line + "`n"))
}

function Set-PlannedGitLines {
  $script:GaLines = [System.Collections.Generic.List[string]]::new()
  $script:GiLines = [System.Collections.Generic.List[string]]::new()
  $script:GaLines.Add('_goals/*/orchestration-log.md merge=union')
  $script:GiLines.Add('_kit/')
  if ($script:Flags['loop'] -eq $true) {
    $script:GaLines.Add('_goals/LEARNINGS.md merge=union')
    $script:GaLines.Add('_goals/ESCALATIONS.md merge=union')
    $script:GaLines.Add('*.sh text eol=lf')
    $script:GaLines.Add('*.ps1 text eol=lf')
    $script:GiLines.Add('_goals/breaker-state.json')
  }
}

function Test-GitAppendWouldChange([string]$file, $lines) {
  if (-not [System.IO.File]::Exists($file)) { return $true }
  $cur = Strip-AllNl (Read-FileRaw $file)
  foreach ($line in $lines) {
    $have = $false
    if (-not [string]::IsNullOrEmpty($cur)) {
      foreach ($ln in (Get-BashLines $cur)) {
        if ($ln -ceq $line) { $have = $true; break }
      }
    }
    if (-not $have) { return $true }
  }
  return $false
}

# --- old manifest / write ---
$script:OldHash = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
$script:OldHasManifest = $false
$script:OldInstalledAt = ''
$script:HasOldAnswers = $false
$script:WrittenN = 0
$script:UnchangedM = 0
$script:PrunedP = 0
$script:SeedsKept = 0
$script:BlockedPaths = [System.Collections.Generic.List[string]]::new()
$script:NewFiles = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)

function Load-OldManifest {
  $script:OldHash = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
  $script:OldHasManifest = $false
  $script:OldInstalledAt = ''
  $script:HasOldAnswers = $false
  if ([System.IO.File]::Exists($script:Manifest)) {
    $script:OldHasManifest = $true
    $raw = Read-FileRaw $script:Manifest
    try {
      $obj = $raw | ConvertFrom-Json -AsHashtable -Depth 100
    } catch {
      Fail 2 'answers file unreadable'
    }
    if ($null -eq $obj) { Fail 2 'answers file unreadable' }
    if ($obj -is [System.Collections.IDictionary] -and $obj.ContainsKey('installedAt') -and $null -ne $obj['installedAt']) {
      $script:OldInstalledAt = Strip-AllNl (ConvertTo-JqRaw $obj['installedAt'])
    }
    if ($obj -is [System.Collections.IDictionary] -and $obj.ContainsKey('answers') -and (Test-JqTruthy $obj['answers'])) {
      $script:HasOldAnswers = $true
    }
    if ($obj -is [System.Collections.IDictionary] -and $obj.ContainsKey('files') -and (Test-IsJsonObject $obj['files'])) {
      foreach ($k in @($obj['files'].Keys)) {
        $script:OldHash[[string]$k] = ConvertTo-JqRaw $obj['files'][$k]
      }
    }
    $script:OldManifestObj = $obj
  } else {
    $script:OldManifestObj = $null
  }
}

function Get-SortedEmitKeys {
  $keys = [System.Collections.Generic.List[string]]::new()
  foreach ($k in @($script:Emit.Keys)) { $keys.Add([string]$k) }
  $keys.Sort($script:Ord)
  return ,$keys
}

function Plan-AndMaybeWrite {
  $script:BlockedPaths.Clear()
  $script:WrittenN = 0
  $script:UnchangedM = 0
  $sorted = Get-SortedEmitKeys
  foreach ($p in $sorted) {
    $newHash = Get-Sha256String ([string]$script:Emit[$p])
    $script:NewFiles[$p] = $newHash
    $diskPath = "$($script:Root)/$p"
    $diskHash = ''
    if ([System.IO.File]::Exists($diskPath)) { $diskHash = Get-Sha256File $diskPath }
    if ($diskHash.Length -gt 0 -and $diskHash -eq $newHash) {
      $script:UnchangedM++
      Add-DryAction 'skip' $p
      continue
    }
    if ($script:OldHasManifest -and $diskHash.Length -gt 0) {
      $old = ''
      if ($script:OldHash.ContainsKey($p)) { $old = [string]$script:OldHash[$p] }
      if ($old.Length -gt 0 -and $diskHash -ne $old -and -not $script:Force) {
        $script:BlockedPaths.Add($p)
        Add-DryAction 'blocked' $p
        continue
      }
    }
    $script:WrittenN++
    Add-DryAction 'write' $p
  }
}

function Write-EmitFiles {
  $sorted = Get-SortedEmitKeys
  foreach ($p in $sorted) {
    $dest = "$($script:Root)/$p"
    $newHash = Get-Sha256String ([string]$script:Emit[$p])
    if ([System.IO.File]::Exists($dest) -and (Get-Sha256File $dest) -eq $newHash) { continue }
    Write-Utf8File $dest ([string]$script:Emit[$p])
    if ($p.EndsWith('.sh')) { Invoke-ChmodX $dest }
  }
}

function Plan-Seeds {
  if ([string]::IsNullOrEmpty($script:SeedContent)) { return }
  $p = '_goals/backlog.md'
  if ([System.IO.File]::Exists("$($script:Root)/$p")) { $script:SeedsKept++ }
  Add-DryAction 'seed' $p
}

function Write-Seed {
  if ([string]::IsNullOrEmpty($script:SeedContent)) { return }
  $dest = "$($script:Root)/_goals/backlog.md"
  if (-not [System.IO.File]::Exists($dest)) {
    $c = $script:SeedContent
    if (-not [string]::IsNullOrEmpty($c) -and -not $c.EndsWith("`n")) { $c += "`n" }
    Write-Utf8File $dest $c
  } else {
    $script:SeedsKept++
  }
}

function Plan-PruneAndForeign {
  $script:PrunedP = 0
  foreach ($p in @($script:OldHash.Keys)) {
    $ps = [string]$p
    if (Test-SeedPath $ps) { continue }
    if ($script:Emit.ContainsKey($ps)) { continue }
    $old = [string]$script:OldHash[$ps]
    if (Test-KitOwned $ps) {
      $fp = "$($script:Root)/$ps"
      if ([System.IO.File]::Exists($fp)) {
        $disk = Get-Sha256File $fp
        if ($disk -eq $old) {
          $script:PrunedP++
          Add-DryAction 'prune' $ps
        } else {
          Bump-Warn
          Add-DryAction 'warn' $ps
        }
      }
    } else {
      $fp = "$($script:Root)/$ps"
      if ([System.IO.File]::Exists($fp)) {
        $script:NewFiles[$ps] = Get-Sha256File $fp
        Add-DryAction 'keep' $ps
      } else {
        Bump-Warn
        Add-DryAction 'warn' $ps
      }
    }
  }
}

function Remove-EmptyParents([string]$filePath) {
  $dir = [System.IO.Path]::GetDirectoryName($filePath)
  $rootFull = $script:Root.Replace('\', '/')
  while (-not [string]::IsNullOrEmpty($dir)) {
    $dn = $dir.Replace('\', '/')
    if ($dn.Length -lt $rootFull.Length) { break }
    if ($dn -eq $rootFull) { break }
    if (-not [System.IO.Directory]::Exists($dir)) { break }
    $entries = [System.IO.Directory]::GetFileSystemEntries($dir)
    if ($entries.Length -gt 0) { break }
    [System.IO.Directory]::Delete($dir)
    $dir = [System.IO.Path]::GetDirectoryName($dir)
  }
}

function Invoke-DoPrune {
  foreach ($p in @($script:OldHash.Keys)) {
    $ps = [string]$p
    if (Test-SeedPath $ps) { continue }
    if ($script:Emit.ContainsKey($ps)) { continue }
    if (-not (Test-KitOwned $ps)) {
      $fp = "$($script:Root)/$ps"
      if ([System.IO.File]::Exists($fp)) { $script:NewFiles[$ps] = Get-Sha256File $fp }
      continue
    }
    $old = [string]$script:OldHash[$ps]
    $fp = "$($script:Root)/$ps"
    if ([System.IO.File]::Exists($fp)) {
      $disk = Get-Sha256File $fp
      if ($disk -eq $old) {
        [System.IO.File]::Delete($fp)
        $script:PrunedP++
        Remove-EmptyParents $fp
      }
    }
  }
}

function Test-HarnessWanted([string]$want) {
  foreach ($h in $script:Harnesses) { if ($h -eq $want) { return $true } }
  return $false
}

function Put-OptionalKitFiles {
  if (Test-HarnessWanted 'claude-code') {
    $sf = "$($script:Root)/.claude/settings.json"
    if (-not [System.IO.File]::Exists($sf)) {
      Put-Emit '.claude/settings.json' (Strip-AllNl (Get-SettingsJsonMin))
    } else {
      $ok = $false
      try {
        $sj = (Read-FileRaw $sf) | ConvertFrom-Json -AsHashtable -Depth 100
        if ((Test-IsJsonObject $sj) -and $sj.ContainsKey('env') -and (Test-IsJsonObject $sj['env']) -and $sj['env'].ContainsKey('CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH') -and (Test-JqTruthy $sj['env']['CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH'])) {
          $ok = $true
        }
      } catch { $ok = $false }
      if (-not $ok) {
        Bump-Warn
        Add-DryAction 'warn' '.claude/settings.json'
        Write-ErrLine '.claude/settings.json present without CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH — left untouched'
      }
    }
  }
  if (Test-HarnessWanted 'codex') {
    $cf = "$($script:Root)/.codex/config.toml"
    $light = Get-ModelField 'codex' 'light'
    $tables = Get-CodexConfigTables $light
    if (-not [System.IO.File]::Exists($cf)) {
      Put-Emit '.codex/config.toml' (Strip-AllNl (Ensure-Nl $tables))
    } elseif (-not (Test-FileHasMarker $cf $script:CodexAgentsMarker)) {
      $existing = Strip-AllNl (Read-FileRaw $cf)
      $existing = Strip-OneNl $existing
      $tb = Strip-AllNl (Ensure-Nl $tables)
      Put-Emit '.codex/config.toml' ($existing + "`n" + $tb)
    }
  }
}

function Append-PointerFile([string]$dest, [string]$section) {
  if (Test-FileHasMarker $dest $script:PointerMarker) { return }
  $section = Strip-OneNl $section
  if ([System.IO.File]::Exists($dest)) {
    $existing = Strip-AllNl (Read-FileRaw $dest)
    $existing = Strip-OneNl $existing
    Write-Utf8File $dest ($existing + "`n" + $section + "`n")
  } else {
    Write-Utf8File $dest ($section + "`n")
  }
}

function Plan-PointersAndGit {
  if (Test-HarnessWanted 'claude-code') {
    if ([System.IO.File]::Exists("$($script:Root)/CLAUDE.md") -and (Test-FileHasMarker "$($script:Root)/CLAUDE.md" $script:PointerMarker)) {
      Add-DryAction 'keep' 'CLAUDE.md'
    } else { Add-DryAction 'write' 'CLAUDE.md' }
  }
  if (Test-HarnessWanted 'copilot') {
    $p = '.github/copilot-instructions.md'
    if ([System.IO.File]::Exists("$($script:Root)/$p") -and (Test-FileHasMarker "$($script:Root)/$p" $script:PointerMarker)) {
      Add-DryAction 'skip' $p
    } else { Add-DryAction 'write' $p }
  }
  if (Test-HarnessWanted 'codex') {
    if ([System.IO.File]::Exists("$($script:Root)/AGENTS.md") -and (Test-FileHasMarker "$($script:Root)/AGENTS.md" $script:PointerMarker)) {
      Add-DryAction 'skip' 'AGENTS.md'
    } else { Add-DryAction 'write' 'AGENTS.md' }
  }
  Set-PlannedGitLines
  if (Test-GitAppendWouldChange "$($script:Root)/.gitattributes" $script:GaLines) {
    Add-DryAction 'write' '.gitattributes'
  } else {
    Add-DryAction 'keep' '.gitattributes'
  }
  if (Test-GitAppendWouldChange "$($script:Root)/.gitignore" $script:GiLines) {
    Add-DryAction 'write' '.gitignore'
  } else {
    Add-DryAction 'keep' '.gitignore'
  }
}

function Write-PointersAndGit {
  if (Test-HarnessWanted 'claude-code') { Append-PointerFile "$($script:Root)/CLAUDE.md" (Get-PointerClaude) }
  if (Test-HarnessWanted 'copilot') { Append-PointerFile "$($script:Root)/.github/copilot-instructions.md" (Get-PointerCopilot) }
  if (Test-HarnessWanted 'codex') {
    Append-PointerFile "$($script:Root)/AGENTS.md" (Get-PointerAgentsMd)
    if ([System.IO.File]::Exists("$($script:Root)/AGENTS.md")) {
      $sz = [System.IO.File]::ReadAllBytes("$($script:Root)/AGENTS.md").Length
      if ($sz -gt 32768) {
        Bump-Warn
        Write-ErrLine 'AGENTS.md exceeds 32 KiB after pointer append'
      }
    }
  }
  Set-PlannedGitLines
  $cur = ''
  if ([System.IO.File]::Exists("$($script:Root)/.gitattributes")) { $cur = Strip-AllNl (Read-FileRaw "$($script:Root)/.gitattributes") }
  foreach ($line in $script:GaLines) { $cur = Append-LineOnce $cur $line }
  Write-Utf8File "$($script:Root)/.gitattributes" ($cur + "`n")
  $cur = ''
  if ([System.IO.File]::Exists("$($script:Root)/.gitignore")) { $cur = Strip-AllNl (Read-FileRaw "$($script:Root)/.gitignore") }
  foreach ($line in $script:GiLines) { $cur = Append-LineOnce $cur $line }
  Write-Utf8File "$($script:Root)/.gitignore" ($cur + "`n")
}

function Write-KitManifest {
  $installed = ''
  if (-not [string]::IsNullOrEmpty($script:OldInstalledAt)) { $installed = $script:OldInstalledAt }
  elseif (-not [string]::IsNullOrEmpty($env:EMIT_DATE)) { $installed = $env:EMIT_DATE }
  else { $installed = Get-Date -Format 'yyyy-MM-dd' }

  $opt = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
  $fl = $script:Answers['flags']
  $opt['research'] = $fl['research']
  $opt['loop'] = $fl['loop']
  $opt['greenfield'] = $fl['greenfield']
  $opt['lint'] = $fl['lint']
  $opt['typecheck'] = $fl['typecheck']
  $opt['models_pinned'] = $fl['models_pinned']
  $opt['forge'] = $script:ForgeKind
  if (-not [string]::IsNullOrEmpty($script:ForgeHost)) { $opt['forgeHost'] = $script:ForgeHost }

  $files = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
  $fk = [System.Collections.Generic.List[string]]::new()
  foreach ($k in @($script:NewFiles.Keys)) { $fk.Add([string]$k) }
  $fk.Sort($script:Ord)
  foreach ($k in $fk) { $files[$k] = [string]$script:NewFiles[$k] }

  $seed = [System.Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrEmpty($script:SeedContent)) { $seed.Add('_goals/backlog.md') }

  $harnessArr = @($script:Answers['harnesses'])

  $top = New-Object 'System.Collections.Specialized.OrderedDictionary'
  [void]$top.Add('kit', 'agent-kit')
  [void]$top.Add('kitVersion', $script:Version)
  [void]$top.Add('installedAt', $installed)
  [void]$top.Add('harnesses', $harnessArr)
  [void]$top.Add('primary', $script:Primary)
  [void]$top.Add('options', $opt)
  [void]$top.Add('seedFiles', $seed)
  [void]$top.Add('files', $files)
  [void]$top.Add('answers', $script:Answers)

  $order = @('kit', 'kitVersion', 'installedAt', 'harnesses', 'primary', 'options', 'seedFiles', 'files', 'answers')
  $json = (ConvertTo-JqJson $top 0 $order) + "`n"
  Write-Utf8File $script:Manifest $json
}

function Test-VerifyContent([string]$p, [string]$content) {
  $ok = $true
  if ($script:TokenRe.IsMatch($content)) {
    $script:VerifyErrs.Add("verify: ${p}: leftover token")
    $ok = $false
  }
  if ($content.Contains('<!-- BOOTSTRAP')) {
    $script:VerifyErrs.Add("verify: ${p}: leftover BOOTSTRAP")
    $ok = $false
  }
  if ($content.Contains('<!-- IF')) {
    $script:VerifyErrs.Add("verify: ${p}: leftover IF")
    $ok = $false
  }
  if ($content.Contains('<!-- ENDIF')) {
    $script:VerifyErrs.Add("verify: ${p}: leftover ENDIF")
    $ok = $false
  }
  return $ok
}

function Get-FmName([string]$content) {
  if (-not (Split-Fm $content)) { return '' }
  foreach ($line in (Get-BashLines $script:FmInner)) {
    if ($line.StartsWith('name:')) {
      $n = Trim-CStart $line.Substring(5)
      if ($n.StartsWith('"') -and $n.EndsWith('"') -and $n.Length -ge 2) {
        $n = $n.Substring(1, $n.Length - 2)
      }
      return $n
    }
  }
  return ''
}

function Invoke-VerifyAll {
  $rc = 0
  $script:VerifyErrs = [System.Collections.Generic.List[string]]::new()
  $paths = [System.Collections.Generic.List[string]]::new()
  foreach ($k in @($script:Emit.Keys)) { $paths.Add([string]$k) }
  $paths.Sort($script:Ord)
  foreach ($p in $paths) {
    $content = [string]$script:Emit[$p]
    if (-not (Test-VerifyContent $p $content)) { $rc = 1 }
    $isAgent = ($p -like '*/agents/*.md' -or $p -like '*/agents/*.agent.md' -or $p -like '.github/agents/*.agent.md')
    if ($isAgent) {
      $name = Get-FmName $content
      if (-not [string]::IsNullOrEmpty($name)) {
        $expected = [System.IO.Path]::GetFileName($p)
        if ($expected.EndsWith('.agent.md')) { $expected = $expected.Substring(0, $expected.Length - 9) }
        elseif ($expected.EndsWith('.md')) { $expected = $expected.Substring(0, $expected.Length - 3) }
        if ($name -ne $expected) {
          $script:VerifyErrs.Add("verify: ${p}: name: $name != $expected")
          $rc = 1
        }
      }
    } elseif ($p -match '/skills/[^/]+/SKILL\.md$') {
      $name = Get-FmName $content
      $expected = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($p))
      if (-not [string]::IsNullOrEmpty($name) -and $name -ne $expected) {
        $script:VerifyErrs.Add("verify: ${p}: name: $name != $expected")
        $rc = 1
      }
    }
  }
  $cursorDir = "$($script:Root)/.cursor"
  if ([System.IO.Directory]::Exists($cursorDir)) {
    $hit = $false
    foreach ($f in (Get-FilesSorted $cursorDir '*' $true)) {
      $fn = $f.Replace('\', '/')
      $skip = $false
      foreach ($seg in $fn.Split('/')) { if ($seg -eq 'setup') { $skip = $true; break } }
      if ($skip) { continue }
      $t = Read-FileRaw $fn
      if ($t.Contains('.claude/')) { $hit = $true; break }
    }
    if ($hit) {
      $script:VerifyErrs.Add('verify: .cursor/: contains .claude/ reference')
      $rc = 1
    }
  }
  $ps1Files = [System.Collections.Generic.List[string]]::new()
  foreach ($p in @($script:Emit.Keys)) {
    if ([string]$p -like '*.ps1') { $ps1Files.Add([string]$p) }
  }
  if ($ps1Files.Count -gt 0) {
    $pwshCmd = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $pwshCmd) {
      foreach ($p in $ps1Files) {
        $fp = "$($script:Root)/$p"
        if ([System.IO.File]::Exists($fp)) {
          $tok = $null
          $err = $null
          [void][System.Management.Automation.Language.Parser]::ParseFile($fp, [ref]$tok, [ref]$err)
          if ($null -ne $err -and @($err).Count -gt 0) {
            $script:VerifyErrs.Add("verify: ${p}: pwsh parse failed")
            $rc = 1
          }
        }
      }
    } else {
      Bump-Warn
      Write-ErrLine 'pwsh not on PATH — skipped .ps1 parse'
    }
  }
  if ($script:VerifyErrs.Count -gt 0) {
    $full = [System.Collections.Generic.List[string]]::new()
    foreach ($w in $script:WarnLines) { $full.Add("emit: $w") }
    foreach ($m in $script:VerifyErrs) { $full.Add("emit: $m") }
    $arr = $full.ToArray()
    [Array]::Sort($arr, $script:Ord)
    foreach ($line in $arr) { [Console]::Error.Write($line + "`n") }
    $script:WarnLines.Clear()
    return 1
  }
  return $rc
}

function Write-DryActions {
  if ($script:DryActions.Count -eq 0) {
    [Console]::Out.Write("`n")
    return
  }
  $arr = $script:DryActions.ToArray()
  [Array]::Sort($arr, $script:Ord)
  [Console]::Out.Write(($arr -join "`n") + "`n")
}

function Write-Summary {
  Write-BufferedWarnLines
  $line = "emit: written $($script:WrittenN) · unchanged $($script:UnchangedM) · pruned $($script:PrunedP) · seeds-kept $($script:SeedsKept) · warnings $($script:Warnings) · manifest orchestration-kit.manifest.json · kit $($script:Version)"
  [Console]::Out.Write($line + "`n")
}

function Invoke-RunEmit {
  Load-OldManifest

  if (-not [string]::IsNullOrEmpty($script:AnswersFile)) {
    if (-not [System.IO.File]::Exists($script:AnswersFile)) { Fail 2 'answers file unreadable' }
    $script:Answers = ConvertFrom-AnswersJson (Read-FileRaw $script:AnswersFile)
    if (-not (Test-IsJsonObject $script:Answers)) {
      $script:Answers = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
    }
  } elseif ($script:OldHasManifest) {
    if (-not $script:HasOldAnswers) {
      Fail 3 'answers missing from manifest — pass --answers (pre-v0.27.0 install)'
    }
    $script:Answers = $script:OldManifestObj['answers']
    if (-not (Test-IsJsonObject $script:Answers)) {
      $script:Answers = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
    }
  } else {
    Fail 2 'answers file unreadable'
  }

  Validate-AnswersSchema
  Load-KitSkills
  Scan-AllTemplates
  Flush-Syntax

  if ($script:UnknownFlags.Count -gt 0) {
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($n in @($script:UnknownFlags.Keys)) { $names.Add([string]$n) }
    $names.Sort($script:Ord)
    foreach ($n in $names) {
      Add-Problem "unknown IF flag '$n' at $($script:UnknownFlags[$n])"
    }
  }
  Flush-Problems
  foreach ($h in $script:Harnesses) { Warn-ModelsArbiter $h }
  Load-BootstrapMap
  Compute-MissingBootstrap

  if ($script:CheckAnswers) {
    Write-BufferedWarnLines
    $rc = 0
    foreach ($id in $script:MissingBootstrap) {
      [Console]::Out.Write("$id`t$($script:BootstrapIdPath[$id])`n")
      $rc = 3
    }
    exit $rc
  }

  foreach ($mid in $script:MissingBootstrap) {
    if ([string]::IsNullOrEmpty($mid)) { continue }
    Bump-Warn
  }

  Collect-EmitSet
  Put-OptionalKitFiles
  Flush-Syntax
  Flush-Problems

  $script:NewFiles = New-Object 'System.Collections.Hashtable' ([StringComparer]::Ordinal)
  $script:DryActions = [System.Collections.Generic.List[string]]::new()
  Plan-AndMaybeWrite
  Plan-Seeds
  Plan-PruneAndForeign
  Plan-PointersAndGit

  if ($script:BlockedPaths.Count -gt 0) {
    if ($script:DryRun) { Write-BufferedWarnLines; Write-DryActions; exit 4 }
    $full = [System.Collections.Generic.List[string]]::new()
    foreach ($w in $script:WarnLines) { $full.Add("emit: $w") }
    foreach ($bp in $script:BlockedPaths) { $full.Add("emit: blocked $bp") }
    $arr = $full.ToArray()
    [Array]::Sort($arr, $script:Ord)
    foreach ($line in $arr) { [Console]::Error.Write($line + "`n") }
    $script:WarnLines.Clear()
    exit 4
  }

  if ($script:DryRun) { Write-BufferedWarnLines; Write-DryActions; exit 0 }

  Write-EmitFiles
  $script:SeedsKept = 0
  Write-Seed
  $script:PrunedP = 0
  Invoke-DoPrune
  Write-PointersAndGit
  Write-KitManifest

  $vrc = Invoke-VerifyAll
  if ($vrc -ne 0) { exit 5 }
  Write-Summary
  exit 0
}

Invoke-RunEmit
