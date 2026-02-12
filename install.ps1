<#
.SYNOPSIS
    Dotfiles install script for Windows.

.DESCRIPTION
    This script creates symbolic links from files in this repository
    to application-specific configuration locations.

    - Existing files are backed up before replacement.
    - Existing symbolic links are removed without backup.
    - Symbolic links are always recreated.
    - DryRun mode shows intended actions without making changes.

.USAGE
    .\install.ps1 -DryRun
    .\install.ps1
#>

param(
    [switch]$dryrun
)

$reporoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$homedir  = $env:USERPROFILE

Write-Host "dotfiles install script"
Write-Host "reporoot: $reporoot"

if ($dryrun) {
    Write-Host "dryrun mode enabled (no changes will be made)" -ForegroundColor Yellow
}

#================================
# Link definitions
#================================
$links = @(
    @{
        source = "nvim\init.lua"
        target = "$homedir\AppData\Local\nvim\init.lua"
    },
    @{
        source = "vscode\settings.json"
        target = "$homedir\AppData\Roaming\Code\User\settings.json"
    },
    @{
        source = "vscode\keybindings.json"
        target = "$homedir\AppData\Roaming\Code\User\keybindings.json"
    },
    @{
        source = "wezterm\wezterm.lua"
        target = "$homedir\.config\wezterm\wezterm.lua"
    },
    @{
        source = "wezterm\keybinds.lua"
        target = "$homedir\.config\wezterm\keybinds.lua"
    },
    @{
        source = "powershell\Microsoft.PowerShell_profile.ps1"
        target = "$profile"
    }
)

#================================
# Functions
#================================
function New-DirectoryIfMissing {
    param([string]$path)

    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        Write-Host "create directory: $dir"
        if (-not $dryrun) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

function Backup-ExistingPath {
    param([string]$path)

    if (-not (Test-Path $path)) {
        return
    }

    $item = Get-Item $path -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'SymbolicLink') {
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = "$path.bak.$timestamp"

    Write-Host "backup existing: $path -> $backup" -ForegroundColor Yellow
    if (-not $dryrun) {
        Move-Item $path $backup
    }
}

function New-SymbolicLinkSafe {
    param(
        [string]$source,
        [string]$target
    )

    $src = Join-Path $reporoot $source

    if (-not (Test-Path $src)) {
        Write-Host "source not found: $src" -ForegroundColor Red
        return
    }

    New-DirectoryIfMissing $target
    Backup-ExistingPath   $target

    if (Test-Path $target) {
        $item = Get-Item $target -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'SymbolicLink') {
            if (-not $dryrun) {
                Remove-Item $target -Force
            }
        }
    }

    Write-Host "link:"
    Write-Host "  $target"
    Write-Host "  -> $src"

    if ($dryrun) {
        return
    }

    try {
        New-Item -ItemType SymbolicLink -Path $target -Target $src -ErrorAction Stop | Out-Null

        if (-not (Test-Path $target)) {
            throw "link creation failed"
        }
    }
    catch {
        Write-Warning "Link creation failed: $target"
    }
}

# ================================
# Execution
# ================================

foreach ($link in $links) {
    New-SymbolicLinkSafe $link.source $link.target
}

Write-Host "Done"