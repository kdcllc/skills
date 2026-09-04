#!/usr/bin/env pwsh
#Requires -Version 7.0
# Kit-repo-only dogfood installer — copies (or symlinks) every top-level skill
# from this working tree into the harness destination directories.
# Never emitted to consumers; internal to the kit only.
#
# Twin: self-install.sh (bash) — behaviorally identical —
# same defaults, guards, and exit codes; any divergence is a bug.
#
# After copying skills, runs skills/setup/bin/emit.ps1 from
# skills/setup/fixtures/self-answers.json unless --no-emit. Dest paths are the
# definition; this script does not invoke npx or any network tool.
#
# Usage:  scripts/self-install.ps1 [--dry-run] [--symlink] [--force] [--no-emit] [--force-emit]
#   --dry-run  Print planned dest paths to stdout; write nothing; exit 0.
#              Combined with --symlink, prints the symlink plan. When emit runs,
#              passes --dry-run to emit.ps1 (action lines only; no writes).
#   --symlink  Canonical real tree at .agents/skills/<name>/;
#              .claude/skills/<name> and .cursor/skills/<name> become symlinks.
#              Fails loudly on symlink failure; never falls back to copy.
#   --force    Accepted and ignored (overwrite is already the default).
#   --no-emit  Copy skills only; skip emit (legacy behaviour).
#   --force-emit  Pass --force to emit.ps1 (overwrite user-modified instance files).
#
# Exit codes: 0 = success (including dry-run); non-zero = any error.

# Explicit, deliberate preference choices (PowerShell has no `set -e`):
#   - $ErrorActionPreference = 'Continue' so a non-zero exit from a native command
#     never throws a terminating error out from under us.
#   - $PSNativeCommandUseErrorActionPreference = $false (PowerShell 7.3+ default flips
#     this to $true) for the same reason. Harmless on 7.0-7.2 where it does not exist.
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

$ScriptDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent $ScriptDir
$script:ScriptName = Split-Path -Leaf $PSCommandPath

# _Usage is printed only on the unknown-flag path; never on missing-skills or
# install-failure paths. Binding decision — sh twin must match.
function _Usage {
    [Console]::Error.WriteLine("Usage: $script:ScriptName [--dry-run] [--symlink] [--force] [--no-emit] [--force-emit]")
    [Console]::Error.WriteLine("  --dry-run  Print planned dest paths; write nothing; exit 0.")
    [Console]::Error.WriteLine("  --symlink  Symlink mode: canonical tree at .agents/skills/<name>/;")
    [Console]::Error.WriteLine("             .claude/skills/<name> and .cursor/skills/<name> become symlinks.")
    [Console]::Error.WriteLine("  --force    Accepted and ignored (overwrite is already the default).")
    [Console]::Error.WriteLine("  --no-emit  Copy skills only; skip emit.")
    [Console]::Error.WriteLine("  --force-emit  Pass --force to emit.ps1.")
}

$DryRun = $false
$Symlink = $false
$NoEmit = $false
$ForceEmit = $false

# Parse GNU-style --flags from $args so `pwsh -File self-install.ps1 --dry-run` works.
foreach ($arg in $args) {
    switch -CaseSensitive ($arg) {
        '--dry-run' { $DryRun = $true }
        '--symlink' { $Symlink = $true }
        '--force'   { }
        '--no-emit' { $NoEmit = $true }
        '--force-emit' { $ForceEmit = $true }
        default {
            [Console]::Error.WriteLine("error: unknown argument: $arg")
            _Usage
            exit 1
        }
    }
}

# Discover skills: immediate children of skills/ that contain a SKILL.md file.
# Nested files such as skills/setup/templates/skills/feature/SKILL.md are NOT
# skills — Get-ChildItem without -Recurse is intentionally non-recursive (maxdepth 1).
$SkillsDir = Join-Path $RepoRoot 'skills'
if (-not (Test-Path -LiteralPath $SkillsDir -PathType Container)) {
    [Console]::Error.WriteLine("error: skills/ directory not found: $SkillsDir")
    exit 1
}

$SkillNames = @()
foreach ($item in Get-ChildItem -LiteralPath $SkillsDir -Directory -ErrorAction SilentlyContinue) {
    $name = $item.Name
    if (Test-Path -LiteralPath (Join-Path $SkillsDir $name 'SKILL.md') -PathType Leaf) {
        $SkillNames += $name
    }
}

if ($SkillNames.Count -eq 0) {
    [Console]::Error.WriteLine("error: no skills found under $SkillsDir (each must be a directory containing SKILL.md)")
    exit 1
}

function Invoke-RunEmit {
    $emitArgs = @(
        '--root', $RepoRoot,
        '--kit', (Join-Path $RepoRoot 'skills/setup'),
        '--answers', (Join-Path $RepoRoot 'skills/setup/fixtures/self-answers.json'),
        '--upgrade'
    )
    if ($ForceEmit) { $emitArgs += '--force' }
    if ($DryRun) { $emitArgs += '--dry-run' }
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'skills/setup/bin/emit.ps1') @emitArgs
    $script:EmitExitCode = $LASTEXITCODE
    if ($script:EmitExitCode -eq 4) {
        [Console]::Error.WriteLine('re-run with --force-emit to overwrite user-modified instance files')
    }
}

# Dry-run: print the plan; optionally print emit dry-run lines; write nothing.
if ($DryRun) {
    foreach ($name in $SkillNames) {
        if ($Symlink) {
            Write-Output "[dry-run] real tree:  $RepoRoot/.agents/skills/$name/"
            Write-Output "[dry-run] symlink:    $RepoRoot/.claude/skills/$name -> $RepoRoot/.agents/skills/$name"
            Write-Output "[dry-run] symlink:    $RepoRoot/.cursor/skills/$name -> $RepoRoot/.agents/skills/$name"
        } else {
            Write-Output "[dry-run] copy: $RepoRoot/.claude/skills/$name/"
            Write-Output "[dry-run] copy: $RepoRoot/.cursor/skills/$name/"
        }
    }
    if (-not $NoEmit) {
        Invoke-RunEmit
        if ($script:EmitExitCode -ne 0) { exit $script:EmitExitCode }
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Snapshot / rollback infrastructure.
#
# Take a snapshot of every dest this run will touch BEFORE any mutation.
# The finally block restores all snapshotted paths on non-zero exit, after
# the first dest has been written ($script:WroteSomething = $true). Because
# .claude is always written before .cursor (copy mode) / before symlinks
# (symlink mode), a failure mid-run correctly restores .claude too.
# ---------------------------------------------------------------------------
$script:SnapshotDir = ''
$script:SnapCount = 0
$script:SnapPath = @()
$script:WroteSomething = $false
$script:RestoreFailPaths = @()
$script:InstallSucceeded = $false
$script:FinalExitCode = 0

function Invoke-Snapshot {
    param([Parameter(Mandatory)] [string]$Dest)
    $idx = $script:SnapCount
    $script:SnapPath += $Dest
    $script:SnapCount += 1
    $slotDir = Join-Path $script:SnapshotDir ([string]$idx)
    New-Item -ItemType Directory -Path $slotDir -Force -ErrorAction Stop | Out-Null

    # Probe with Get-Item -Force, not Test-Path: Test-Path follows a symlink to its
    # target and reports a dangling link as absent. The link branch must be decided
    # from this probe alone so a dangling symlink is snapshotted, matching bash `[[ -L ]]`.
    $item = Get-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType -eq 'SymbolicLink') {
            # Snapshot a symlink: record the target path.
            # .Target is a string collection on PS 7.0 and a plain string from 7.1 on;
            # Select-Object -First 1 yields one string on every 7.x.
            $linkTarget = $item.Target | Select-Object -First 1
            $linkTarget | Set-Content -LiteralPath (Join-Path $slotDir 'link_target') -NoNewline -ErrorAction Stop
        } elseif (-not $item.PSIsContainer) {
            # Regular file: copy it.
            Copy-Item -LiteralPath $Dest -Destination (Join-Path $slotDir 'file_backup') -Force -ErrorAction Stop
        } else {
            # Directory: copy recursively.
            # NOTE: Copy-Item -Recurse does not reproduce cp -a attribute/symlink
            # preservation; accepted while skill trees have no exec bits or nested symlinks.
            Copy-Item -LiteralPath $Dest -Destination (Join-Path $slotDir 'dir_backup') -Recurse -Force -ErrorAction Stop
        }
    }
    # absent path: no backup written — restore will only rm, not re-create
}

function Invoke-DoRestore {
    for ($i = $script:SnapCount - 1; $i -ge 0; $i--) {
        $dest = $script:SnapPath[$i]
        if ([string]::IsNullOrEmpty($dest)) { continue }
        $fail = $false

        # Remove current content, mirroring bash's `rm -rf "$_dest" 2>/dev/null`.
        # Get-Item -Force so a dangling symlink is still seen and removed.
        $removeOk = $true
        $current = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        if ($current) {
            try {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction Stop
            } catch {
                $removeOk = $false
            }
        }
        if (-not $removeOk) {
            [Console]::Error.WriteLine("error: rollback: could not remove: $dest")
            $script:RestoreFailPaths += $dest
            continue
        }

        $slotDir = Join-Path $script:SnapshotDir ([string]$i)
        $linkTargetFile = Join-Path $slotDir 'link_target'
        $fileBackup     = Join-Path $slotDir 'file_backup'
        $dirBackup      = Join-Path $slotDir 'dir_backup'

        if (Test-Path -LiteralPath $linkTargetFile -PathType Leaf) {
            $raw = Get-Content -LiteralPath $linkTargetFile -Raw
            if ($null -eq $raw) { $raw = '' }
            $tgt = $raw.TrimEnd("`r", "`n")
            try {
                New-Item -ItemType SymbolicLink -Path $dest -Value $tgt -ErrorAction Stop | Out-Null
            } catch {
                [Console]::Error.WriteLine("error: rollback: could not restore symlink: $dest")
                $fail = $true
            }
        } elseif (Test-Path -LiteralPath $fileBackup -PathType Leaf) {
            try {
                Copy-Item -LiteralPath $fileBackup -Destination $dest -Force -ErrorAction Stop
            } catch {
                [Console]::Error.WriteLine("error: rollback: could not restore file: $dest")
                $fail = $true
            }
        } elseif (Test-Path -LiteralPath $dirBackup -PathType Container) {
            try {
                Copy-Item -LiteralPath $dirBackup -Destination $dest -Recurse -Force -ErrorAction Stop
            } catch {
                [Console]::Error.WriteLine("error: rollback: could not restore directory: $dest")
                $fail = $true
            }
        }
        # absent-before dest: rm-only is the correct restore; no re-create needed
        if ($fail) {
            $script:RestoreFailPaths += $dest
        }
    }
}

# Parent dirs (.claude/skills/, .cursor/skills/, .agents/skills/) created during
# a rolled-back run may remain — no parent-dir cleanup is performed. Twin must match.

$script:SnapshotDir = Join-Path ([System.IO.Path]::GetTempPath()) ("self-install-snap-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:SnapshotDir -Force -ErrorAction Stop | Out-Null

try {
    # Snapshot all dest paths before any mutation.
    if ($Symlink) {
        foreach ($name in $SkillNames) {
            Invoke-Snapshot -Dest (Join-Path $RepoRoot ".agents/skills/$name")
            Invoke-Snapshot -Dest (Join-Path $RepoRoot ".claude/skills/$name")
            Invoke-Snapshot -Dest (Join-Path $RepoRoot ".cursor/skills/$name")
        }
    } else {
        foreach ($name in $SkillNames) {
            Invoke-Snapshot -Dest (Join-Path $RepoRoot ".claude/skills/$name")
            Invoke-Snapshot -Dest (Join-Path $RepoRoot ".cursor/skills/$name")
        }
    }

    # Install each skill.
    foreach ($name in $SkillNames) {
        $src = Join-Path $SkillsDir $name

        if ($Symlink) {
            $agentsDest = Join-Path $RepoRoot ".agents/skills/$name"
            $claudeDest = Join-Path $RepoRoot ".claude/skills/$name"
            $cursorDest = Join-Path $RepoRoot ".cursor/skills/$name"

            # Real tree at .agents/skills/<name>/
            New-Item -ItemType Directory -Path (Join-Path $RepoRoot '.agents/skills') -Force -ErrorAction Stop | Out-Null
            $script:WroteSomething = $true
            $existing = Get-Item -LiteralPath $agentsDest -Force -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-Item -LiteralPath $agentsDest -Recurse -Force -ErrorAction Stop
            }
            # NOTE: Copy-Item -Recurse does not reproduce cp -a attribute/symlink
            # preservation; accepted while skill trees have no exec bits or nested symlinks.
            Copy-Item -LiteralPath $src -Destination $agentsDest -Recurse -Force -ErrorAction Stop

            # .claude/skills/<name> symlink (fail-loud, never fall back to copy)
            New-Item -ItemType Directory -Path (Join-Path $RepoRoot '.claude/skills') -Force -ErrorAction Stop | Out-Null
            $existing = Get-Item -LiteralPath $claudeDest -Force -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-Item -LiteralPath $claudeDest -Recurse -Force -ErrorAction Stop
            }
            try {
                New-Item -ItemType SymbolicLink -Path $claudeDest -Value $agentsDest -ErrorAction Stop | Out-Null
            } catch {
                [Console]::Error.WriteLine("error: failed to create symlink: $claudeDest -> $agentsDest")
                $script:FinalExitCode = 1
                exit 1
            }

            # .cursor/skills/<name> symlink
            New-Item -ItemType Directory -Path (Join-Path $RepoRoot '.cursor/skills') -Force -ErrorAction Stop | Out-Null
            $existing = Get-Item -LiteralPath $cursorDest -Force -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-Item -LiteralPath $cursorDest -Recurse -Force -ErrorAction Stop
            }
            try {
                New-Item -ItemType SymbolicLink -Path $cursorDest -Value $agentsDest -ErrorAction Stop | Out-Null
            } catch {
                [Console]::Error.WriteLine("error: failed to create symlink: $cursorDest -> $agentsDest")
                $script:FinalExitCode = 1
                exit 1
            }

        } else {
            $claudeDest = Join-Path $RepoRoot ".claude/skills/$name"
            $cursorDest = Join-Path $RepoRoot ".cursor/skills/$name"

            # .claude/skills/<name>/ first — copy mode must never write through a
            # leftover symlink; Remove-Item removes the symlink itself, not its target.
            New-Item -ItemType Directory -Path (Join-Path $RepoRoot '.claude/skills') -Force -ErrorAction Stop | Out-Null
            $script:WroteSomething = $true
            $existing = Get-Item -LiteralPath $claudeDest -Force -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-Item -LiteralPath $claudeDest -Recurse -Force -ErrorAction Stop
            }
            # NOTE: Copy-Item -Recurse does not reproduce cp -a attribute/symlink
            # preservation; accepted while skill trees have no exec bits or nested symlinks.
            Copy-Item -LiteralPath $src -Destination $claudeDest -Recurse -Force -ErrorAction Stop

            # .cursor/skills/<name>/ second
            New-Item -ItemType Directory -Path (Join-Path $RepoRoot '.cursor/skills') -Force -ErrorAction Stop | Out-Null
            $existing = Get-Item -LiteralPath $cursorDest -Force -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-Item -LiteralPath $cursorDest -Recurse -Force -ErrorAction Stop
            }
            # NOTE: Copy-Item -Recurse does not reproduce cp -a attribute/symlink
            # preservation; accepted while skill trees have no exec bits or nested symlinks.
            Copy-Item -LiteralPath $src -Destination $cursorDest -Recurse -Force -ErrorAction Stop
        }

        Write-Output "installed: $name"
    }

    Write-Output "done: $($SkillNames.Count) skill(s) installed"
    if (-not $NoEmit) {
        Invoke-RunEmit
        if ($script:EmitExitCode -ne 0) {
            $script:FinalExitCode = $script:EmitExitCode
            exit $script:EmitExitCode
        }
    }
    $script:InstallSucceeded = $true
    exit 0

} catch {
    [Console]::Error.WriteLine("error: $($_.Exception.Message)")
    if ($script:FinalExitCode -eq 0) { $script:FinalExitCode = 1 }

} finally {
    if (-not $script:InstallSucceeded -and $script:WroteSomething) {
        [Console]::Error.WriteLine("error: install failed (exit $($script:FinalExitCode)); rolling back changes...")
        Invoke-DoRestore
        if ($script:RestoreFailPaths.Count -eq 0) {
            [Console]::Error.WriteLine("rollback complete")
        } else {
            [Console]::Error.WriteLine("error: PARTIAL ROLLBACK — the following paths could not be restored:")
            foreach ($p in $script:RestoreFailPaths) {
                [Console]::Error.WriteLine("  $p")
            }
        }
    }
    if ($script:SnapshotDir -and (Test-Path -LiteralPath $script:SnapshotDir -PathType Container)) {
        Remove-Item -LiteralPath $script:SnapshotDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Reached only when an exception propagated through catch (not from an explicit exit).
exit $script:FinalExitCode
