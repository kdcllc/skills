#!/usr/bin/env pwsh
# Structural verification suite for the AI Orchestration Kit repo
# (test-ladder rung 3 — cycle end only). No runtime, no network:
# regex scans, parser checks, and frontmatter validation over the working tree.
#
# Twin: checks.sh (bash) — behaviorally identical: same checks (A–O), same
# report lines, same exit semantics (exit 1 on any FAIL, else 0). Any
# divergence is a bug. Interpreter-native swaps only: check C (bash -n) is
# skip-aware here (bash may be absent under pwsh), mirroring how check F
# (pwsh parse) is skip-aware in the bash twin; check J's hash join uses
# Get-FileHash/ConvertFrom-Json natively instead of python3.
#
# See checks.sh's header for the full A–O check descriptions. Both twins
# exclude BOTH checks scripts (checks.sh, checks.ps1) from checks B and J —
# the pair is one logical unit and neither can guard its own in-progress edit.
# Checks B and D cover both .claude/ and .cursor/ (excluding the self-install
# compiler copies at .claude/skills/agent-kit/ and .cursor/skills/agent-kit/). Check M
# asserts no `.claude/` path reference exists under `.cursor/` (excluding
# `.cursor/skills/agent-kit/`). No carve-outs: any `.claude/` hit under `.cursor/`
# is real cross-contamination and FAILs.
# Check N asserts every `.cursor/skills/*/SKILL.md` (excluding `agent-kit/`) is
# byte-identical to its `.claude/skills/` twin after normalizing
# `.cursor/` -> `.claude/` path references.
# Check A builds `used` after stripping class-d `kit-*` BOOTSTRAP comment
# bodies (grammar examples such as `{{TOKEN}}` in kit-meta are not
# placeholders). Check B's pattern is `{{[A-Z_]+}}|<!-- (BOOTSTRAP|IF|ENDIF)`
# with label "instance fully resolved (tokens, bootstrap, IF)".
# Check O: `bash -n skills/agent-kit/bin/emit.sh` (PASS/FAIL; SKIP if bash is
# absent) and skip-aware pwsh parse of `skills/agent-kit/bin/emit.ps1`.
#
# Check L (ps1 unbraced-colon interpolation) is a line-based tripwire, not proof
# -- here-strings and multi-line constructs are out of its reach; check F owns
# parser-level truth where pwsh exists. It flags "$Var:"-style unbraced colon
# interpolation inside double-quoted strings, using the same derived target
# set in both twins: every *.ps1 under skills/agent-kit/templates/, _loop/, and
# scripts/, excluding any file named checks.ps1.

$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent (Split-Path -Parent $ScriptDir)
Set-Location -LiteralPath $Root

$script:FailCount = 0
$script:Summary = @()

function Report {
    param([string]$Status, [string]$Name, [string]$Detail = '')
    if ($Status -eq 'FAIL') {
        $script:FailCount++
        $msg = "FAIL: $Name"
        if ($Detail) { $msg = "$msg — $Detail" }
        [Console]::Error.WriteLine($msg)
    }
    $script:Summary += ("{0}  {1}" -f $Status, $Name)
}

function Get-RelPath {
    param([string]$FullName)
    $rel = [System.IO.Path]::GetRelativePath((Get-Location).Path, $FullName)
    return $rel -replace '\\', '/'
}

# Frontmatter name: same semantics as the bash twin's awk — scan from line 2,
# stop at the first closing '---', return the first 'name:' value found.
function Get-FrontmatterName {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($i -gt 0 -and $line -eq '---') { return '' }
        if ($line -match '^name:\s*(.*)$') { return $Matches[1].Trim() }
    }
    return ''
}

# ---------------------------------------------------------------------------
# Check A: every {{TOKEN}} used in templates is documented in SKILL.md's table
# ---------------------------------------------------------------------------
function Invoke-CheckA {
    $tokenRe = '\{\{[A-Z_]+\}\}'
    $docRe = '\{\{[A-Z_*]+\}\}'
    # Class-d kit-* BOOTSTRAP bodies are instruction-only and may contain
    # grammar examples (e.g. {{TOKEN}} in kit-meta) that are not placeholders.
    $kitBsRe = [regex]::new('(?s)<!--\s*BOOTSTRAP\[kit-[a-z0-9]+(?:-[a-z0-9]+)*\]:.*?-->')
    $used = @(Get-ChildItem -Recurse -File -LiteralPath 'skills/agent-kit/templates' |
        ForEach-Object {
            $raw = Get-Content -Raw -LiteralPath $_.FullName
            if ($null -eq $raw) { $raw = '' }
            $stripped = $kitBsRe.Replace($raw, '')
            [regex]::Matches($stripped, $tokenRe) |
                ForEach-Object { $_.Value }
        } | Sort-Object -Unique)
    $documented = @([regex]::Matches((Get-Content -Raw -LiteralPath 'skills/agent-kit/SKILL.md'), $docRe) |
        ForEach-Object { $_.Value } | Sort-Object -Unique)
    if ($documented.Count -eq 0) {
        Report FAIL 'A: placeholder-table coverage' 'no tokens found in skills/agent-kit/SKILL.md'
        return
    }
    $undocumented = @()
    foreach ($tok in $used) {
        $tokName = $tok.Substring(2, $tok.Length - 4)
        $ok = $false
        foreach ($pat in $documented) {
            $patName = $pat.Substring(2, $pat.Length - 4)
            if ($tokName -like $patName) { $ok = $true; break }   # -like: glob, honors wildcards
        }
        if (-not $ok) { $undocumented += $tok }
    }
    if ($undocumented.Count -gt 0) {
        Report FAIL 'A: placeholder-table coverage' ("undocumented tokens: {0}" -f ($undocumented -join ' '))
        foreach ($tok in $undocumented) {
            Get-ChildItem -Recurse -File -LiteralPath 'skills/agent-kit/templates' | ForEach-Object {
                $rel = Get-RelPath $_.FullName
                $n = 0
                foreach ($line in (Get-Content -LiteralPath $_.FullName)) {
                    $n++
                    if ($line.Contains($tok)) { [Console]::Error.WriteLine("${rel}:${n}:$line") }
                }
            } | Select-Object -First 5 | Out-Null
        }
    } else {
        Report PASS 'A: placeholder-table coverage'
    }
}

# ---------------------------------------------------------------------------
# Check B: instance is fully resolved (no tokens, no bootstrap comments)
# ---------------------------------------------------------------------------
function Invoke-CheckB {
    # Pattern matches the bash twin: leftover tokens, bootstrap, IF, ENDIF.
    $pattern = '\{\{[A-Z_]+\}\}|<!-- (BOOTSTRAP|IF|ENDIF)'
    $hits = @()
    foreach ($dir in @('.claude', '.cursor', '_loop')) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        Get-ChildItem -Recurse -File -LiteralPath $dir | Where-Object {
            $_.Name -ne 'checks.sh' -and $_.Name -ne 'checks.ps1' -and
            ($_.FullName -replace '\\', '/') -notmatch '/agent-kit(/|$)'
        } | ForEach-Object {
            $rel = Get-RelPath $_.FullName
            $n = 0
            foreach ($line in (Get-Content -LiteralPath $_.FullName)) {
                $n++
                if ($line -match $pattern) { $hits += "${rel}:${n}:$line" }
            }
        }
    }
    if ($hits.Count -gt 0) {
        Report FAIL 'B: instance fully resolved (tokens, bootstrap, IF)' 'leftover tokens/bootstrap/IF comments'
        $hits | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'B: instance fully resolved (tokens, bootstrap, IF)'
    }
}

# ---------------------------------------------------------------------------
# Check C: canonical loop.sh AND breaker.sh templates are valid bash.
# Skip-aware here (mirrors check F's idiom in the bash twin): bash may be
# absent on a pwsh-only host; parse errors FAIL, bash absent SKIPs.
# ---------------------------------------------------------------------------
function Invoke-CheckC {
    if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
        Report SKIP 'C: bash not available'
        return
    }
    $bad = @()
    foreach ($f in @('skills/agent-kit/templates/loop/loop.sh', 'skills/agent-kit/templates/loop/breaker.sh')) {
        $out = & bash -n $f 2>&1
        if ($LASTEXITCODE -ne 0) {
            $bad += ("{0}: {1}" -f (Split-Path -Leaf $f), ($out -join ' '))
        }
    }
    if ($bad.Count -gt 0) {
        Report FAIL 'C: loop.sh + breaker.sh template bash -n' ($bad -join ' ')
    } else {
        Report PASS 'C: loop.sh + breaker.sh template bash -n'
    }
}

# ---------------------------------------------------------------------------
# Check D: frontmatter name matches folder/file — canonical AND instance
# ---------------------------------------------------------------------------
function Invoke-CheckD {
    $bad = @()

    $skillFiles = @()
    $skillFiles += Get-ChildItem -Recurse -File -LiteralPath 'skills/agent-kit/templates' -Filter 'SKILL.template.md'
    if (Test-Path -LiteralPath 'skills/agent-kit') {
        Get-ChildItem -Recurse -File -LiteralPath 'skills/agent-kit' -Filter 'SKILL.md' |
            Where-Object { ($_.FullName -replace '\\', '/') -notmatch '/skills/agent-kit/templates/' } |
            ForEach-Object { $skillFiles += $_ }
    }
    if (Test-Path -LiteralPath '.claude/skills') {
        $skillFiles += Get-ChildItem -Recurse -File -LiteralPath '.claude/skills' -Filter 'SKILL.md' |
            Where-Object { ($_.FullName -replace '\\', '/') -notmatch '/\.claude/skills/agent-kit(/|$)' }
    }
    if (Test-Path -LiteralPath '.cursor/skills') {
        $skillFiles += Get-ChildItem -Recurse -File -LiteralPath '.cursor/skills' -Filter 'SKILL.md' |
            Where-Object { ($_.FullName -replace '\\', '/') -notmatch '/\.cursor/skills/agent-kit(/|$)' }
    }

    foreach ($f in ($skillFiles | Sort-Object FullName)) {
        $rel = Get-RelPath $f.FullName
        $name = Get-FrontmatterName $f.FullName
        if ($rel -eq 'skills/agent-kit/templates/loop/SKILL.template.md') {
            $expected = 'auto-loop'   # emitter maps templates/loop/ -> .claude/skills/auto-loop/
        } else {
            $expected = Split-Path -Leaf (Split-Path -Parent $f.FullName)
        }
        if (-not $name) {
            $bad += "${rel}: missing frontmatter name"
        } elseif ($name -ne $expected) {
            $bad += "${rel}: name '$name' != expected '$expected'"
        }
    }

    $agentFiles = @()
    foreach ($dir in @('skills/agent-kit/templates/agents', '.claude/agents', '.cursor/agents')) {
        if (Test-Path -LiteralPath $dir) {
            $agentFiles += Get-ChildItem -File -LiteralPath $dir -Filter '*.md'
        }
    }
    foreach ($f in ($agentFiles | Sort-Object FullName)) {
        $rel = Get-RelPath $f.FullName
        $name = Get-FrontmatterName $f.FullName
        $expected = $f.BaseName
        if (-not $name) {
            $bad += "${rel}: missing frontmatter name"
        } elseif ($name -ne $expected) {
            $bad += "${rel}: name '$name' != expected '$expected'"
        }
    }

    if ($bad.Count -gt 0) {
        Report FAIL 'D: frontmatter name==folder/file' ("{0} mismatch(es)" -f $bad.Count)
        $bad | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'D: frontmatter name==folder/file'
    }
}

# ---------------------------------------------------------------------------
# Check E: no hardcoded model IDs in canonical templates outside models.map.md
# ---------------------------------------------------------------------------
function Invoke-CheckE {
    $hits = @()
    Get-ChildItem -Recurse -File -LiteralPath 'skills/agent-kit/templates' |
        Where-Object { $_.Name -ne 'models.map.md' } | ForEach-Object {
            $rel = Get-RelPath $_.FullName
            $n = 0
            foreach ($line in (Get-Content -LiteralPath $_.FullName)) {
                $n++
                if ($line -cmatch '(claude|gpt|gemini)-[0-9a-z]') { $hits += "${rel}:${n}:$line" }
            }
        }
    if ($hits.Count -gt 0) {
        Report FAIL 'E: no hardcoded model IDs in templates' 'model IDs belong in models.map.md'
        $hits | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'E: no hardcoded model IDs in templates'
    }
}

# ---------------------------------------------------------------------------
# Check F: pwsh parse of loop.ps1 + breaker.ps1 (canonical + instance).
# We ARE pwsh here, so the parse runs in-process — no skip path needed.
# ---------------------------------------------------------------------------
function Invoke-CheckF {
    $targets = @(
        'skills/agent-kit/templates/loop/loop.ps1',
        '_loop/loop.ps1',
        'skills/agent-kit/templates/loop/breaker.ps1',
        '_loop/breaker.ps1'
    )
    $parseErrors = $false
    $invocationErrors = $false
    $detail = @()

    foreach ($f in $targets) {
        if (-not (Test-Path -LiteralPath $f)) {
            $invocationErrors = $true
            $detail += "${f}: file not found"
            continue
        }
        try {
            $tokens = $null
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Path -LiteralPath $f).Path, [ref]$tokens, [ref]$errs) | Out-Null
            if ($errs.Count -gt 0) {
                $parseErrors = $true
                $detail += "${f}: parse errors:"
                $errs | ForEach-Object { $detail += $_.ToString() }
            }
        } catch {
            $invocationErrors = $true
            $detail += "${f}: parser invocation error: $($_.Exception.Message)"
        }
    }

    if ($parseErrors) {
        Report FAIL 'F: pwsh parse (skip-aware)' 'parse errors found'
        $detail | ForEach-Object { [Console]::Error.WriteLine($_) }
    } elseif ($invocationErrors) {
        Report WARN 'F: pwsh parse (skip-aware)' 'invocation error, not a parse failure'
        $detail | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'F: pwsh parse (skip-aware)'
    }
}

# ---------------------------------------------------------------------------
# Check G: parity heuristic — sentinel, all six exit codes, matching default
# iteration count between the two canonical drivers (drift tripwire, not proof)
# ---------------------------------------------------------------------------
function Invoke-CheckG {
    $sh = 'skills/agent-kit/templates/loop/loop.sh'
    $ps1 = 'skills/agent-kit/templates/loop/loop.ps1'
    $sentinel = '<promise>COMPLETE</promise>'
    $bad = @()

    foreach ($f in @($sh, $ps1)) {
        if (-not (Test-Path -LiteralPath $f)) {
            $bad += "${f}: file not found"
            continue
        }
        $raw = Get-Content -Raw -LiteralPath $f
        if (-not $raw.Contains($sentinel)) { $bad += "${f}: missing sentinel string" }
        foreach ($n in 0..5) {
            if ($raw -notmatch "exit $n([^0-9]|`$)") { $bad += "${f}: missing exit $n" }
        }
    }

    # Anchor the default digits on the closing brace — a naive [0-9]+ over the
    # whole ${1:-10} match would also pick up the positional-parameter "1".
    $shDefault = ''
    $ps1Default = ''
    if (Test-Path -LiteralPath $sh) {
        $m = [regex]::Match((Get-Content -Raw -LiteralPath $sh), '\{1:-([0-9]+)\}')
        if ($m.Success) { $shDefault = $m.Groups[1].Value }
    }
    if (Test-Path -LiteralPath $ps1) {
        $m = [regex]::Match((Get-Content -Raw -LiteralPath $ps1), '\$MaxIterations = ([0-9]+)')
        if ($m.Success) { $ps1Default = $m.Groups[1].Value }
    }
    if (-not $shDefault) {
        $bad += "${sh}: no default iteration count found"
    } elseif ($shDefault -ne '10') {
        $bad += "${sh}: default iteration count is $shDefault, expected 10"
    }
    if (-not $ps1Default) {
        $bad += "${ps1}: no default iteration count found"
    } elseif ($ps1Default -ne '10') {
        $bad += "${ps1}: default iteration count is $ps1Default, expected 10"
    }
    if ($shDefault -and $ps1Default -and $shDefault -ne $ps1Default) {
        $bad += "default iteration counts differ: loop.sh=$shDefault loop.ps1=$ps1Default"
    }

    # Breaker twins: state names, cooldown literal, successes threshold keyed
    # on the ACTUAL transition line in each twin's own identifier spelling.
    foreach ($f in @('skills/agent-kit/templates/loop/breaker.sh', 'skills/agent-kit/templates/loop/breaker.ps1')) {
        if (-not (Test-Path -LiteralPath $f)) {
            $bad += "${f}: file not found"
            continue
        }
        $raw = Get-Content -Raw -LiteralPath $f
        if (-not $raw.Contains('CLOSED')) { $bad += "${f}: missing state name CLOSED" }
        if (-not $raw.Contains('OPEN')) { $bad += "${f}: missing state name OPEN" }
        if (-not $raw.Contains('HALF-OPEN')) { $bad += "${f}: missing state name HALF-OPEN" }
        if (-not $raw.Contains('600')) { $bad += "${f}: missing cooldown literal 600" }
        if ($raw -notmatch '(?i)(halfOpenSuccesses|_BRK_HALF)[^0-9]*(-eq|==)[^0-9]*2') {
            $bad += "${f}: successes threshold ACTUAL transition line (halfOpenSuccesses/_BRK_HALF compared -eq/== 2) not found"
        }
    }

    if ($bad.Count -gt 0) {
        Report FAIL 'G: loop driver parity heuristic' ("{0} issue(s)" -f $bad.Count)
        $bad | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'G: loop driver parity heuristic'
    }
}

# ---------------------------------------------------------------------------
# Check H: loop.ps1 reference coverage across setup docs
# ---------------------------------------------------------------------------
function Invoke-CheckH {
    $files = @(
        'skills/agent-kit/emitters/claude-code.md',
        'skills/agent-kit/emitters/codex.md',
        'skills/agent-kit/emitters/copilot.md',
        'skills/agent-kit/emitters/cursor.md',
        'skills/agent-kit/templates/loop/SKILL.template.md',
        'skills/agent-kit/templates/ORCHESTRATION.md'
    )
    $missing = @()
    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f)) {
            $missing += "${f}: file not found"
        } elseif (-not (Get-Content -Raw -LiteralPath $f).Contains('loop.ps1')) {
            $missing += "${f}: no mention of loop.ps1"
        }
    }
    if ($missing.Count -gt 0) {
        Report FAIL 'H: loop.ps1 reference coverage' ("{0} file(s) missing mention" -f $missing.Count)
        $missing | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'H: loop.ps1 reference coverage'
    }
}

# ---------------------------------------------------------------------------
# Check I: H-analog for the breaker helper -- breaker.ps1 mentioned in all
# four skills/agent-kit/emitters/*.md
# ---------------------------------------------------------------------------
function Invoke-CheckI {
    $files = @(
        'skills/agent-kit/emitters/claude-code.md',
        'skills/agent-kit/emitters/codex.md',
        'skills/agent-kit/emitters/copilot.md',
        'skills/agent-kit/emitters/cursor.md'
    )
    $missing = @()
    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f)) {
            $missing += "${f}: file not found"
        } elseif (-not (Get-Content -Raw -LiteralPath $f).Contains('breaker.ps1')) {
            $missing += "${f}: no mention of breaker.ps1"
        }
    }
    if ($missing.Count -gt 0) {
        Report FAIL 'I: breaker.ps1 reference coverage' ("{0} file(s) missing mention" -f $missing.Count)
        $missing | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'I: breaker.ps1 reference coverage'
    }
}

# ---------------------------------------------------------------------------
# Check J: manifest + seed-class hash integrity (self-excluding), the
# manifest-independent A4 regression grep over the four _loop driver/breaker
# twins, and the kitVersion==VERSION tripwire. Three independently gated
# sub-checks, each with its own Report line.
# ---------------------------------------------------------------------------
function Invoke-CheckJ {
    $manifest = if ($env:CHECKS_MANIFEST) { $env:CHECKS_MANIFEST } else { 'orchestration-kit.manifest.json' }
    $selfPaths = @('tests/agent-kit/checks.sh', 'tests/agent-kit/checks.ps1')

    if (-not (Test-Path -LiteralPath $manifest)) {
        Report SKIP 'J: manifest hash join' "$manifest not found"
    } else {
        $verifierFailed = $false
        $data = $null
        try {
            $data = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json
        } catch {
            $verifierFailed = $true
            Report FAIL 'J: manifest hash join' "verifier failed ($($_.Exception.Message))"
        }
        if (-not $verifierFailed) {
            $filesMap = @{}
            if ($null -ne $data.files) {
                foreach ($prop in $data.files.PSObject.Properties) { $filesMap[$prop.Name] = $prop.Value }
            }
            $seed = @()
            if ($null -ne $data.seedFiles) { $seed = @($data.seedFiles) }
            $bad = @()
            if ($filesMap.Count -eq 0) {
                Report FAIL 'J: manifest hash join' "manifest 'files' map has zero entries -- empty join is not proof of integrity"
            } else {
                foreach ($path in $filesMap.Keys) {
                    if ($selfPaths -contains $path) {
                        Write-Output "J: self, excluded -- $path"
                        continue
                    }
                    if ($seed -contains $path) {
                        Write-Output "J: seed, exempt -- $path"
                        continue
                    }
                    if (-not (Test-Path -LiteralPath $path)) {
                        $bad += "${path}: file missing"
                        continue
                    }
                    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
                    if ($actual -ne $filesMap[$path]) { $bad += "${path}: sha256 mismatch" }
                }
                if ($bad.Count -gt 0) {
                    Report FAIL 'J: manifest hash join' ("{0} path(s) mismatched/missing" -f $bad.Count)
                    $bad | ForEach-Object { [Console]::Error.WriteLine($_) }
                } else {
                    Report PASS 'J: manifest hash join'
                }
            }
        }
    }

    if (-not (Test-Path -LiteralPath '_loop')) {
        Report SKIP 'J: A4 regression grep' '_loop/ not found'
    } else {
        $a4Targets = @('_loop/loop.sh', '_loop/loop.ps1', '_loop/breaker.sh', '_loop/breaker.ps1')
        $a4Bad = @()
        foreach ($f in $a4Targets) {
            if (-not (Test-Path -LiteralPath $f)) {
                $a4Bad += "${f}: file not found"
            } else {
                $head = Get-Content -LiteralPath $f -TotalCount 20
                if (($head | Where-Object { $_.Contains('skills/agent-kit/templates') }).Count -gt 0) {
                    $a4Bad += "${f}: header (first 20 lines) contains 'skills/agent-kit/templates' — Twin: line must use sibling form (A4 regression)"
                }
            }
        }
        if ($a4Bad.Count -gt 0) {
            Report FAIL 'J: A4 regression grep' ("{0} issue(s)" -f $a4Bad.Count)
            $a4Bad | ForEach-Object { [Console]::Error.WriteLine($_) }
        } else {
            Report PASS 'J: A4 regression grep'
        }
    }

    # kitVersion==VERSION tripwire: plain-text join, mirroring the bash twin.
    $versionFile = if ($env:CHECKS_VERSION_FILE) { $env:CHECKS_VERSION_FILE } else { 'skills/agent-kit/SKILL.md' }
    if (-not (Test-Path -LiteralPath $versionFile)) {
        Report SKIP 'J: kitVersion==VERSION join' "$versionFile not found"
    } elseif (-not (Test-Path -LiteralPath $manifest)) {
        Report SKIP 'J: kitVersion==VERSION join' "$manifest not found"
    } else {
        # A SKILL.md yields metadata.version; a bare version file (mutation
        # fixtures) yields its whitespace-stripped content.
        $versionLines = @(Get-Content -LiteralPath $versionFile)
        if ($versionLines.Count -gt 0 -and $versionLines[0] -eq '---') {
            $versionVal = ''
            $inMeta = $false
            for ($i = 1; $i -lt $versionLines.Count; $i++) {
                $ln = $versionLines[$i]
                if ($ln -eq '---') { break }
                if ($ln -match '^metadata:') { $inMeta = $true; continue }
                if ($inMeta -and $ln -match '^[^ \t]') { break }
                if ($inMeta -and $ln -match '^[ \t]+version:[ \t]+(\S+)') { $versionVal = $Matches[1] -replace '["'']', ''; break }
            }
        } else {
            $versionVal = ((Get-Content -Raw -LiteralPath $versionFile) -replace '\s', '')
        }
        $manifestVal = ''
        $line = Get-Content -LiteralPath $manifest | Where-Object { $_ -match '"kitVersion"' } | Select-Object -First 1
        if ($line -and $line -match '"kitVersion"\s*:\s*"([^"]*)"') { $manifestVal = $Matches[1] }
        if (-not $manifestVal) {
            Report FAIL 'J: kitVersion==VERSION join' "could not extract kitVersion from $manifest"
        } elseif ($versionVal -ne $manifestVal) {
            Report FAIL 'J: kitVersion==VERSION join' "VERSION=$versionVal kitVersion=$manifestVal"
        } else {
            Report PASS 'J: kitVersion==VERSION join'
        }
    }
}

# ---------------------------------------------------------------------------
# Check K: ownership-contract shape on the CANONICAL templates only
# ---------------------------------------------------------------------------
function Invoke-CheckK {
    $bad = @()
    $taskTpl = 'skills/agent-kit/templates/skills/feature/templates/task.md'
    $implTpl = 'skills/agent-kit/templates/agents/implementer.md'
    $twTpl = 'skills/agent-kit/templates/agents/test-writer.md'
    $criteriaTpl = 'skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md'

    if (-not (Test-Path -LiteralPath $taskTpl)) {
        $bad += "${taskTpl}: file not found"
    } else {
        $taskLines = Get-Content -LiteralPath $taskTpl
        foreach ($field in @('^writes:', '^reads:', '^depends_on:', '^owner:', '^rewrite_semantics:')) {
            $n = ($taskLines | Where-Object { $_ -match $field }).Count
            if ($n -ne 1) { $bad += "${taskTpl}: $field count is $n, expected 1" }
        }
    }

    foreach ($f in @($implTpl, $twTpl)) {
        if (-not (Test-Path -LiteralPath $f)) {
            $bad += "${f}: file not found"
        } elseif (-not (Get-Content -Raw -LiteralPath $f).Contains('Write fence')) {
            $bad += "${f}: missing 'Write fence'"
        }
    }

    if (-not (Test-Path -LiteralPath $criteriaTpl)) {
        $bad += "${criteriaTpl}: file not found"
    } else {
        $raw = Get-Content -Raw -LiteralPath $criteriaTpl
        if (-not $raw.Contains('### Ownership contract')) { $bad += "${criteriaTpl}: missing '### Ownership contract'" }
        if (-not $raw.Contains('Missing ownership block')) { $bad += "${criteriaTpl}: missing 'Missing ownership block'" }
        if (-not $raw.Contains('bracket-literal placeholder values')) { $bad += "${criteriaTpl}: missing 'bracket-literal placeholder values'" }
    }

    if ($bad.Count -gt 0) {
        Report FAIL 'K: ownership-contract shape' ("{0} issue(s)" -f $bad.Count)
        $bad | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'K: ownership-contract shape'
    }
}

# ---------------------------------------------------------------------------
# Check L: ps1 unbraced-colon interpolation (accepted-limitation line-based
# scan, not a parser -- here-strings/multi-line constructs are out of scope;
# check F owns parser-level truth where pwsh exists). Derived target set
# computed at run time: every *.ps1 under skills/agent-kit/templates/, _loop/,
# and scripts/, excluding any file named checks.ps1. A missing root is
# skipped and noted without failing by itself; the empty-set FAIL fires only
# when the TOTAL derived set across all present roots is empty.
# ---------------------------------------------------------------------------
function Invoke-CheckL {
    # Bug-pattern literal assembled by concatenation, matching Invoke-CheckB's
    # house style: keeps the "$Var:" trigger sequence out of this file as an
    # unbroken literal (grep-tool hygiene).
    $dollarSign = '\$'
    $namePart = '[A-Za-z_][A-Za-z0-9_]*'
    $colon = ':'
    $boundary = '([^A-Za-z0-9_]|$)'
    $pattern = $dollarSign + $namePart + $colon + $boundary

    $roots = @('skills/agent-kit/templates', '_loop', 'scripts')
    $targets = @()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            Write-Output "L: root not found, skipped -- $root"
            continue
        }
        $targets += Get-ChildItem -Recurse -File -LiteralPath $root -Filter '*.ps1' |
            Where-Object { $_.Name -ne 'checks.ps1' }
    }

    if ($targets.Count -eq 0) {
        Report FAIL 'L: ps1 unbraced-colon interpolation' 'empty target set is not proof'
        return
    }

    $hits = @()
    foreach ($f in $targets) {
        $rel = Get-RelPath $f.FullName
        $n = 0
        foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
            $n++
            if ($line -match '^\s*#') { continue }
            if ($line -notmatch '"') { continue }
            if ($line -match $pattern) { $hits += "${rel}:${n}:$line" }
        }
    }

    if ($hits.Count -gt 0) {
        Report FAIL 'L: ps1 unbraced-colon interpolation' 'unbraced colon interpolation found'
        $hits | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'L: ps1 unbraced-colon interpolation'
    }
}

# ---------------------------------------------------------------------------
# Check M: no .claude/ path reference exists under .cursor/ (excluding the
# self-install compiler copy at .cursor/skills/agent-kit/). No carve-outs: any
# .claude/ reference under .cursor/ is real cross-contamination and FAILs.
# Exclusion is anchored to the .cursor/skills/agent-kit/ subtree specifically
# (not "any directory named setup" anywhere), mirroring the bash twin's
# `grep -v '^\.cursor/skills/agent-kit/'`.
# ---------------------------------------------------------------------------
function Invoke-CheckM {
    $hits = @()
    if (Test-Path -LiteralPath '.cursor') {
        Get-ChildItem -Recurse -File -LiteralPath '.cursor' | Where-Object {
            ($_.FullName -replace '\\', '/') -notmatch '/\.cursor/skills/agent-kit(/|$)'
        } | ForEach-Object {
            $rel = Get-RelPath $_.FullName
            $n = 0
            foreach ($line in (Get-Content -LiteralPath $_.FullName)) {
                $n++
                if ($line -match '\.claude/') {
                    $hits += "${rel}:${n}:$line"
                }
            }
        }
    }
    if ($hits.Count -gt 0) {
        Report FAIL 'M: no .claude/ references under .cursor/' 'stray .claude/ path reference(s) found'
        $hits | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'M: no .claude/ references under .cursor/'
    }
}

# ---------------------------------------------------------------------------
# Check N: .cursor/ <-> .claude/ skill-tree drift. Every
# .cursor/skills/*/SKILL.md (excluding agent-kit/) must be byte-identical to its
# .claude/skills/ twin after normalizing .cursor/ -> .claude/ path
# references.
# ---------------------------------------------------------------------------
function Invoke-CheckN {
    if (-not (Test-Path -LiteralPath '.cursor/skills')) {
        Report SKIP 'N: .cursor/↔.claude/ skill-tree drift' '.cursor/skills/ not found'
        return
    }
    $cursorSkills = Get-ChildItem -Recurse -File -LiteralPath '.cursor/skills' -Filter 'SKILL.md' |
        Where-Object { ($_.FullName -replace '\\', '/') -notmatch '/\.cursor/skills/agent-kit(/|$)' }
    $bad = @()
    foreach ($f in $cursorSkills) {
        $name = Split-Path -Leaf (Split-Path -Parent $f.FullName)
        $twin = ".claude/skills/$name/SKILL.md"
        if (-not (Test-Path -LiteralPath $twin)) {
            $bad += "$($f.FullName): no twin at $twin"
            continue
        }
        $normalized = (Get-Content -Raw -LiteralPath $f.FullName) -replace '\.cursor/', '.claude/'
        $twinContent = Get-Content -Raw -LiteralPath $twin
        if ($normalized -ne $twinContent) {
            $bad += "$($f.FullName): differs from $twin after .cursor/ -> .claude/ normalization"
        }
    }
    if ($bad.Count -gt 0) {
        Report FAIL 'N: .cursor/↔.claude/ skill-tree drift' ("{0} mismatch(es)" -f $bad.Count)
        $bad | ForEach-Object { [Console]::Error.WriteLine($_) }
    } else {
        Report PASS 'N: .cursor/↔.claude/ skill-tree drift'
    }
}

# ---------------------------------------------------------------------------
# Check O: emitter twins parse — bash -n of skills/agent-kit/bin/emit.sh
# (skip-aware: bash may be absent) and pwsh parse of emit.ps1.
# ---------------------------------------------------------------------------
function Invoke-CheckO {
    if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
        Report SKIP 'O: emit.sh bash -n' 'bash not available'
    } elseif (-not (Test-Path -LiteralPath 'skills/agent-kit/bin/emit.sh')) {
        Report FAIL 'O: emit.sh bash -n' 'skills/agent-kit/bin/emit.sh not found'
    } else {
        $out = & bash -n 'skills/agent-kit/bin/emit.sh' 2>&1
        if ($LASTEXITCODE -ne 0) {
            Report FAIL 'O: emit.sh bash -n' ($out -join ' ')
        } else {
            Report PASS 'O: emit.sh bash -n'
        }
    }

    $f = 'skills/agent-kit/bin/emit.ps1'
    if (-not (Test-Path -LiteralPath $f)) {
        Report FAIL 'O: emit.ps1 pwsh parse' 'skills/agent-kit/bin/emit.ps1 not found'
        return
    }
    try {
        $tokens = $null
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path -LiteralPath $f).Path, [ref]$tokens, [ref]$errs) | Out-Null
        if ($errs.Count -gt 0) {
            Report FAIL 'O: emit.ps1 pwsh parse' 'parse errors found'
            $errs | ForEach-Object { [Console]::Error.WriteLine($_.ToString()) }
        } else {
            Report PASS 'O: emit.ps1 pwsh parse'
        }
    } catch {
        Report FAIL 'O: emit.ps1 pwsh parse' ("parser invocation error: {0}" -f $_.Exception.Message)
    }
}

Invoke-CheckA
Invoke-CheckB
Invoke-CheckC
Invoke-CheckD
Invoke-CheckE
Invoke-CheckF
Invoke-CheckG
Invoke-CheckH
Invoke-CheckI
Invoke-CheckJ
Invoke-CheckK
Invoke-CheckL
Invoke-CheckM
Invoke-CheckN
Invoke-CheckO

Write-Output ''
Write-Output '=== checks.ps1 summary ==='
$script:Summary | ForEach-Object { Write-Output $_ }
if ($script:FailCount -gt 0) {
    Write-Output "RESULT: $($script:FailCount) check(s) FAILED"
    exit 1
}
Write-Output 'RESULT: all checks passed'
exit 0
