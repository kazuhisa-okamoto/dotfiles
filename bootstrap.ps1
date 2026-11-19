<#
.SYNOPSIS
    Installs the command-line tools the dotfiles rely on.

.DESCRIPTION
    Run this before install.ps1, as a normal user (not as administrator):
    scoop refuses to install itself from an elevated shell.

    - Installs scoop if it is missing.
    - Adds the buckets in packages\scoop-buckets.txt.
    - Installs the apps in packages\scoop-apps.txt that are not installed.
    - Installs the packages in packages\pipx.txt and packages\npm.txt
      that are not installed.
    - Adds the te64 shim for Tablacus Explorer and installs the add-ons in
      packages\tablacus-addons.txt that are missing (scoop drops them on
      every update of the app, so run this again after updating it).
    - Points Claude Code at scoop's Git Bash.

    Nothing already installed is updated or removed.
    It runs on Windows PowerShell 5.1, since pwsh itself comes from scoop.

.USAGE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -DryRun
    powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
#>

param(
    [switch]$dryrun
)

$reporoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "dotfiles bootstrap script"
if ($dryrun) {
    Write-Host "dryrun mode enabled (no changes will be made)" -ForegroundColor Yellow
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run this script as a normal user, not as administrator." -ForegroundColor Red
    exit 1
}

#================================
# Functions
#================================
function Read-ListFile {
    param([string]$listFile)

    $path = Join-Path $reporoot $listFile
    if (-not (Test-Path $path)) {
        Write-Host "list not found: $path" -ForegroundColor Red
        return @()
    }
    return @(Get-Content $path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Update-SessionPath {
    # Pick up PATH entries added by installers during this run.
    $env:PATH = [Environment]::GetEnvironmentVariable("Path", "User") + ';' +
                [Environment]::GetEnvironmentVariable("Path", "Machine")
}

function Install-Scoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-Host "install scoop"
    if ($dryrun) {
        return $false
    }

    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -eq 'Undefined' -or $policy -eq 'Restricted') {
        Write-Host "set execution policy for CurrentUser: RemoteSigned"
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    }

    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    Update-SessionPath
    return [bool](Get-Command scoop -ErrorAction SilentlyContinue)
}

function Get-ScoopInstalledApps {
    # An app whose install failed is listed with Info "Install failed";
    # treat it as not installed so it is retried.
    return @(scoop list 6>$null |
        Where-Object { $_.Info -notmatch 'failed' } |
        ForEach-Object { $_.Name.ToLower() })
}

function Install-ScoopApp {
    param(
        [string]$entry,
        [string[]]$installed
    )

    $name = ($entry -split '/')[-1]
    if ($installed -contains $name.ToLower()) {
        return
    }

    Write-Host "install scoop app: $entry"
    if (-not $dryrun) {
        scoop install $entry
    }
}

function Add-ScoopBuckets {
    param([string[]]$entries)

    $added = @(scoop bucket list 6>$null | ForEach-Object { $_.Name })

    foreach ($entry in $entries) {
        $parts = $entry -split '\s+', 2
        $name = $parts[0]
        if ($added -contains $name) {
            continue
        }

        Write-Host "add scoop bucket: $entry"
        if (-not $dryrun) {
            if ($parts.Count -gt 1) {
                scoop bucket add $name $parts[1]
            }
            else {
                scoop bucket add $name
            }
        }
    }
}

function Add-Te64Shim {
    # The tablacus-explorer manifest only creates a shim named "te64.exe"
    # (te64.exe.exe), so a bare "te64" does not resolve. The profile's te
    # function and yazi's opener call te64 / TE64.exe.
    $scoopdir = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE "scoop" }
    $te = Join-Path $scoopdir "apps\tablacus-explorer\current\TE64.exe"
    $shim = Join-Path $scoopdir "shims\te64.shim"

    if ((Test-Path $shim) -or -not (Test-Path $te)) {
        return
    }

    Write-Host "add scoop shim: te64 -> $te"
    if (-not $dryrun) {
        scoop shim add te64 $te
    }
}

function Install-TablacusAddons {
    param([string[]]$addons)

    # Same steps as the app's own add-on installer (script\options.js, Install):
    # read the version from index.xml, download <id>/<id>_<version without
    # its first dot>.zip, and move the extracted <id> folder into addons.
    $scoopdir = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE "scoop" }
    $addonsdir = Join-Path $scoopdir "apps\tablacus-explorer\current\addons"
    $baseurl = "https://tablacus.github.io/TablacusExplorerAddons/"

    if (-not $dryrun -and -not (Test-Path $addonsdir)) {
        Write-Warning "Tablacus Explorer not found; skipping its add-ons"
        return
    }

    $missing = @($addons | Where-Object { -not (Test-Path (Join-Path $addonsdir "$_\config.xml")) })
    if ($missing.Count -eq 0) {
        return
    }

    if ($dryrun) {
        foreach ($id in $missing) {
            Write-Host "install tablacus add-on: $id"
        }
        return
    }

    # Windows PowerShell 5.1 may not offer TLS 1.2 by default.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $temp = Join-Path $env:TEMP ("tablacus-addons-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
        $indexfile = Join-Path $temp "index.xml"
        Invoke-WebRequest -Uri ($baseurl + "index.xml") -OutFile $indexfile -UseBasicParsing
        $index = New-Object Xml.XmlDocument
        $index.Load($indexfile)

        foreach ($id in $missing) {
            $item = $index.SelectSingleNode("//Item[@Id='$id']")
            if (-not $item) {
                Write-Warning "Tablacus add-on not in index.xml: $id"
                continue
            }

            $version = $item.SelectSingleNode("General/Version").InnerText
            $zipname = "{0}_{1}.zip" -f $id, ([regex]'\.').Replace($version, '', 1)
            Write-Host "install tablacus add-on: $id $version"

            try {
                $zipfile = Join-Path $temp $zipname
                Invoke-WebRequest -Uri ($baseurl + "$id/$zipname") -OutFile $zipfile -UseBasicParsing
                $extractdir = Join-Path $temp $id
                Expand-Archive -Path $zipfile -DestinationPath $temp -Force
                if (-not (Test-Path (Join-Path $extractdir "config.xml"))) {
                    throw "config.xml not found in $zipname"
                }
                Move-Item $extractdir (Join-Path $addonsdir $id)
            }
            catch {
                Write-Warning "Tablacus add-on install failed: $id ($_)"
            }
        }
    }
    finally {
        Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
    }
}

function Set-ClaudeGitBashPath {
    # Claude Code otherwise looks for C:\Program Files\Git\bin\bash.exe.
    $scoopdir = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE "scoop" }
    $bash = Join-Path $scoopdir "apps\git\current\bin\bash.exe"

    if ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User')) {
        return
    }
    if (-not $dryrun -and -not (Test-Path $bash)) {
        return
    }

    Write-Host "set user environment variable: CLAUDE_CODE_GIT_BASH_PATH=$bash"
    if (-not $dryrun) {
        [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $bash, 'User')
    }
}

function Install-PipxPackages {
    param([string[]]$packages)

    if (-not (Get-Command pipx -ErrorAction SilentlyContinue)) {
        Write-Warning "pipx not found; skipping pipx packages"
        return
    }

    $installed = @(pipx list --short | ForEach-Object { ($_ -split '\s+')[0].ToLower() })

    foreach ($package in $packages) {
        if ($installed -contains $package.ToLower()) {
            continue
        }

        Write-Host "install pipx package: $package"
        if (-not $dryrun) {
            pipx install $package
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "pipx install failed: $package"
            }
        }
    }

    if (-not $dryrun) {
        # Adds the folder pipx puts commands in (~\.local\bin) to the user PATH.
        # It prints a warning when the folder is already there; nothing to act on.
        pipx ensurepath *> $null
    }
}

function Install-NpmPackages {
    param([string[]]$packages)

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found; skipping npm packages"
        return
    }

    $installed = @()
    $tree = npm ls -g --depth=0 --json 2>$null | Out-String | ConvertFrom-Json
    if ($tree.dependencies) {
        $installed = @($tree.dependencies.PSObject.Properties.Name)
    }

    foreach ($package in $packages) {
        if ($installed -contains $package) {
            continue
        }

        Write-Host "install npm package: $package"
        if (-not $dryrun) {
            npm install -g $package
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "npm install failed: $package"
            }
        }
    }
}

# ================================
# Execution
# ================================

if (-not (Install-Scoop)) {
    if ($dryrun) {
        Write-Host "scoop is not installed; the remaining steps need scoop" -ForegroundColor Yellow
    }
    else {
        Write-Host "scoop installation failed" -ForegroundColor Red
    }
    exit 1
}

$apps = Read-ListFile "packages\scoop-apps.txt"

# Buckets other than main are git repositories, so git comes first.
Install-ScoopApp "main/git" (Get-ScoopInstalledApps)
Add-ScoopBuckets (Read-ListFile "packages\scoop-buckets.txt")

$installed = Get-ScoopInstalledApps
foreach ($app in $apps) {
    Install-ScoopApp $app $installed
}

Add-Te64Shim
Install-TablacusAddons (Read-ListFile "packages\tablacus-addons.txt")
Set-ClaudeGitBashPath

Update-SessionPath
Install-PipxPackages (Read-ListFile "packages\pipx.txt")
Install-NpmPackages (Read-ListFile "packages\npm.txt")

Write-Host "Done"
