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
    - Run it as administrator, or as a normal user with pwsh once Windows
      Developer Mode is on (Developer Mode lets normal users create
      symbolic links).
    - Without either, it stops. With -NoSymlink it uses links a normal user
      can create instead: directory junctions for whole folders, hard links
      for the VS Code settings, a loader file for the PowerShell profile, and
      the user PATH for bin\.

.USAGE
    .\install.ps1 -DryRun
    .\install.ps1
    .\install.ps1 -NoSymlink
#>

param(
    [switch]$dryrun,
    # Use junctions, hard links, a profile loader and the user PATH instead of
    # symbolic links. Only used when given.
    [switch]$NoSymlink
)

$reporoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$homedir  = $env:USERPROFILE

Write-Host "dotfiles install script"
Write-Host "reporoot: $reporoot"

if ($dryrun) {
    Write-Host "dryrun mode enabled (no changes will be made)" -ForegroundColor Yellow
}

#================================
# Permission check
#================================
# Creating symbolic links needs administrator rights, unless Windows Developer
# Mode is on. With Developer Mode, PowerShell 7 asks Windows for an unprivileged
# symbolic link; Windows PowerShell 5.1 does not, so it still needs elevation.
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$devMode = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
    -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1

# The links a normal user can create are used only with -NoSymlink.
$useFallback = [bool]$NoSymlink

$permissionError = $null
if (-not $useFallback -and -not $isAdmin) {
    if (-not $devMode) {
        $permissionError = @"
Symbolic links need administrator rights or Windows Developer Mode.
Either run this script as administrator, or turn on Developer Mode once
(Settings > System > For developers > Developer Mode; it needs an administrator
to approve) and run this script again as a normal user with pwsh.
Without either, run it with -NoSymlink to use directory junctions and hard links.
"@
    }
    elseif ($PSVersionTable.PSVersion.Major -lt 6) {
        $permissionError = @"
Developer Mode is on, but Windows PowerShell $($PSVersionTable.PSVersion) cannot create
symbolic links without administrator rights. Run this script with pwsh (PowerShell 7),
or with -NoSymlink to use directory junctions and hard links.
"@
    }
}

if ($permissionError) {
    if ($dryrun) {
        Write-Warning $permissionError
    }
    else {
        Write-Host $permissionError -ForegroundColor Red
        exit 1
    }
}
elseif ($useFallback) {
    Write-Host @"
-NoSymlink: using directory junctions, hard links, a profile loader and the user
PATH instead of symbolic links. The VS Code settings are hard links: git replaces
a file when it changes it, which cuts the link, so run this script again after a
git pull that changes vscode\.
"@ -ForegroundColor Yellow
}
elseif (-not $isAdmin) {
    Write-Host "not elevated; creating symbolic links through Developer Mode"
}

#================================
# Link definitions
#================================
# Symbolic links, used with administrator rights or Developer Mode.
$links = @(
    @{
        source = "nvim\init.lua"
        target = "$homedir\AppData\Local\nvim\init.lua"
    },
    @{
        source = "nvim\lua"
        target = "$homedir\AppData\Local\nvim\lua"
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
        source = "wezterm\workspace_session.lua"
        target = "$homedir\.config\wezterm\workspace_session.lua"
    },
    @{
        source = "wezterm\claude_status.lua"
        target = "$homedir\.config\wezterm\claude_status.lua"
    },
    @{
        source = "wezterm\claude_session_hook.ps1"
        target = "$homedir\.config\wezterm\claude_session_hook.ps1"
    },
    @{
        source = "powershell\Microsoft.PowerShell_profile.ps1"
        target = "$profile"
    }
    @{
        source = "oh_my_posh\mytheme.omp.json"
        target = "$env:POSH_THEMES_PATH\mytheme.omp.json"
    }
    @{
        source = "yazi\init.lua"
        target = "$homedir\AppData\Roaming\yazi\config"
    }
    @{
        source = "yazi\keymap.toml"
        target = "$homedir\AppData\Roaming\yazi\config"
    }
    @{
        source = "yazi\package.toml"
        target = "$homedir\AppData\Roaming\yazi\config"
    }
    @{
        source = "yazi\yazi.toml"
        target = "$homedir\AppData\Roaming\yazi\config"
    }
    @{
        source = "bin\code-root.ps1"
        target = "$homedir\.local\bin\code-root.ps1"
    }
    @{
        source = "bin\code-root.cmd"
        target = "$homedir\.local\bin\code-root.cmd"
    }
    @{
        source = "bin\vs.ps1"
        target = "$homedir\.local\bin\vs.ps1"
    }
    @{
        source = "bin\vs.cmd"
        target = "$homedir\.local\bin\vs.cmd"
    }
)

# Without symbolic links: each whole configuration folder becomes a directory
# junction to the repository folder. Files the app writes there therefore land
# in the repository (see .gitignore). "keep" lists such files to carry over from
# a folder that was there before.
$fallbackJunctions = @(
    @{
        source = "nvim"
        target = "$homedir\AppData\Local\nvim"
        keep   = @("lazy-lock.json")
    },
    @{
        source = "wezterm"
        target = "$homedir\.config\wezterm"
        keep   = @()
    },
    @{
        source = "yazi"
        target = "$homedir\AppData\Roaming\yazi\config"
        keep   = @("bookmark")
    }
)

# VS Code keeps other data next to these files, so its folder cannot be a
# junction; hard links are used instead (they need the same drive).
$fallbackHardLinks = @(
    @{
        source = "vscode\settings.json"
        target = "$homedir\AppData\Roaming\Code\User\settings.json"
    },
    @{
        source = "vscode\keybindings.json"
        target = "$homedir\AppData\Roaming\Code\User\keybindings.json"
    }
)

# The profile is a loader that dot-sources the repository's profile, which reads
# the Oh My Posh theme from the repository. bin\ is added to the user PATH.
$fallbackProfileSource = "powershell\Microsoft.PowerShell_profile.ps1"
$fallbackPathSource = "bin"

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
    return $backup
}

function Remove-LinkOnly {
    # Removes a symbolic link or junction without touching what it points to.
    param($item)

    Write-Host "remove link: $($item.FullName)"
    if (-not $dryrun) {
        # Delete() removes only the link itself, even for a directory link
        $item.Delete()
    }
}

function Test-SamePath {
    param([string]$a, [string]$b)

    if (-not $a -or -not $b) {
        return $false
    }
    return $a.TrimEnd('\') -ieq $b.TrimEnd('\')
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

    # Determine whether the given target should be treated as a directory.
    $srcIsDirectory = Test-Path $src -PathType Container

    $targetIsDirectory = $false
    $targetItem = Get-Item $target -ErrorAction SilentlyContinue
    if ($srcIsDirectory) {
        # A folder source (e.g. nvim\lua) names the folder itself as its target.
        # An existing folder there is backed up and replaced, not used as a
        # place to put the source into.
        $targetIsDirectory = $false
    }
    elseif ($targetItem -and $targetItem.LinkType -eq 'SymbolicLink') {
        # An existing link from a previous run is the link to recreate, not a
        # directory to place a new link into.
        $targetIsDirectory = $false
    }
    elseif (Test-Path $target -PathType Container) {
        $targetIsDirectory = $true
    }
    elseif ($target.EndsWith('\') -or $target.EndsWith('/')) {
        $targetIsDirectory = $true
    }
    elseif (-not (Test-Path $target) -and -not $srcIsDirectory) {
        $ext = [System.IO.Path]::GetExtension($target)
        if ([string]::IsNullOrEmpty($ext)) {
            $targetIsDirectory = $true
        }
    }

    if ($targetIsDirectory) {
        if (-not (Test-Path $target)) {
            Write-Host "create directory: $target"
            if (-not $dryrun) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }
        }

        $leaf = Split-Path $source -Leaf
        $finalTarget = Join-Path $target $leaf
    }
    else {
        $finalTarget = $target
    }

    New-DirectoryIfMissing $finalTarget
    Backup-ExistingPath $finalTarget | Out-Null

    if (Test-Path $finalTarget) {
        $item = Get-Item $finalTarget -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'SymbolicLink') {
            if (-not $dryrun) {
                # Delete() removes only the link itself, even for a directory link
                $item.Delete()
            }
        }
    }

    Write-Host "link:"
    Write-Host "  $finalTarget"
    Write-Host "  -> $src"

    if ($dryrun) {
        return
    }

    try {
        New-Item -ItemType SymbolicLink -Path $finalTarget -Target $src -ErrorAction Stop | Out-Null

        if (-not (Test-Path $finalTarget)) {
            throw "link creation failed"
        }
    }
    catch {
        Write-Warning "Link creation failed: $finalTarget"
    }
}

function Remove-FallbackJunctions {
    # Symbolic link mode after an earlier run without symbolic links: remove the
    # folder junctions first. Otherwise the links below would be made inside the
    # repository folders, and the repository files would be backed up away.
    foreach ($junction in $fallbackJunctions) {
        $item = Get-Item -LiteralPath $junction.target -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'Junction') {
            Remove-LinkOnly $item
        }
    }
}

function New-JunctionSafe {
    param(
        [string]$source,
        [string]$target,
        [string[]]$keep
    )

    $src = Join-Path $reporoot $source
    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        Write-Host "source folder not found: $src" -ForegroundColor Red
        return
    }

    $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction' -and (Test-SamePath @($item.Target)[0] $src)) {
        Write-Host "up to date: $target -> $src"
        return
    }

    $backup = $null
    if ($item) {
        if ($item.LinkType) {
            Remove-LinkOnly $item
        }
        else {
            $backup = Backup-ExistingPath $target
        }
    }

    New-DirectoryIfMissing $target

    Write-Host "junction:"
    Write-Host "  $target"
    Write-Host "  -> $src"

    # Carry over files the app wrote into the old folder (e.g. lazy-lock.json).
    # With -DryRun nothing was moved, so look in the folder as it is.
    $oldDir = $backup
    if ($dryrun) {
        $oldDir = $target
    }
    if ($backup) {
        foreach ($name in $keep) {
            $from = Join-Path $oldDir $name
            $to = Join-Path $src $name
            if ((Test-Path -LiteralPath $from) -and -not (Test-Path -LiteralPath $to)) {
                Write-Host "  keep $name from the old folder"
                if (-not $dryrun) {
                    Copy-Item -LiteralPath $from -Destination $to -Recurse
                }
            }
        }
    }

    if ($dryrun) {
        return
    }

    try {
        New-Item -ItemType Junction -Path $target -Target $src -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "Junction creation failed: $target ($($_.Exception.Message))"
    }
}

function New-HardLinkSafe {
    param(
        [string]$source,
        [string]$target
    )

    $src = Join-Path $reporoot $source
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Host "source not found: $src" -ForegroundColor Red
        return
    }

    New-DirectoryIfMissing $target

    $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction') {
            Remove-LinkOnly $item
        }
        elseif ((Get-FileHash -LiteralPath $src).Hash -eq (Get-FileHash -LiteralPath $target).Hash) {
            # Same contents: a hard link from an earlier run, or one that a git
            # checkout cut by replacing the repository file. Recreate it without
            # a backup.
            if (-not $dryrun) {
                Remove-Item -LiteralPath $target -Force
            }
        }
        else {
            Backup-ExistingPath $target | Out-Null
        }
    }

    Write-Host "hard link:"
    Write-Host "  $target"
    Write-Host "  -> $src"

    if ($dryrun) {
        return
    }

    try {
        New-Item -ItemType HardLink -Path $target -Value $src -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "Hard link creation failed: $target ($($_.Exception.Message)). Hard links need the repository and the target on the same drive."
    }
}

function Set-ProfileLoader {
    param(
        [string]$source,
        [string]$target
    )

    $src = Join-Path $reporoot $source
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Host "source not found: $src" -ForegroundColor Red
        return
    }

    $loader = @(
        "# Written by dotfiles install.ps1: loads the profile from the repository."
        ". '$($src.Replace("'", "''"))'"
    ) -join "`r`n"

    New-DirectoryIfMissing $target

    $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType) {
            Remove-LinkOnly $item
        }
        elseif ((Get-Content -LiteralPath $target -Raw).Trim() -eq $loader) {
            Write-Host "up to date: $target"
            return
        }
        else {
            Backup-ExistingPath $target | Out-Null
        }
    }

    Write-Host "profile loader:"
    Write-Host "  $target"
    Write-Host "  -> . $src"

    if (-not $dryrun) {
        # UTF-8 with BOM, so Windows PowerShell 5.1 also reads a non-ASCII path
        [IO.File]::WriteAllText($target, $loader + "`r`n", [Text.UTF8Encoding]::new($true))
    }
}

function Add-UserPath {
    param([string]$source)

    $dir = Join-Path $reporoot $source

    # Read and write the registry value directly to keep it REG_EXPAND_SZ and
    # its %VAR% entries unexpanded ([Environment]::SetEnvironmentVariable does not).
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $current = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $entries = @($current -split ';' | Where-Object { $_ })
        foreach ($entry in $entries) {
            if (Test-SamePath ([Environment]::ExpandEnvironmentVariables($entry)) $dir) {
                Write-Host "up to date: user PATH has $dir"
                return
            }
        }

        Write-Host "add to user PATH: $dir"
        if ($dryrun) {
            return
        }
        $key.SetValue('Path', (($entries + $dir) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    }
    finally {
        $key.Close()
    }

    # Tell running programs (Explorer, ...) that the environment changed, so
    # terminals started from them get the new PATH.
    if (-not ('Dotfiles.NativeMethods' -as [type])) {
        Add-Type -Namespace Dotfiles -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam,
    string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    # HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG, 5 seconds
    [Dotfiles.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero,
        'Environment', 2, 5000, [ref]$result) | Out-Null

    $env:PATH = "$env:PATH;$dir"
}

function Install-VSCodeExtensions {
    param([string]$listFile)

    $listPath = Join-Path $reporoot $listFile
    if (-not (Test-Path $listPath)) {
        Write-Host "extension list not found: $listPath" -ForegroundColor Red
        return
    }

    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-Warning "VS Code CLI 'code' not found in PATH; skipping extension install"
        return
    }

    $wanted = Get-Content $listPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }

    # Extension IDs are case-insensitive; -contains compares case-insensitively.
    $installed = @(code --list-extensions)

    foreach ($id in $wanted) {
        if ($installed -contains $id) {
            continue
        }

        Write-Host "install vscode extension: $id"
        if (-not $dryrun) {
            code --install-extension $id
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Extension install failed: $id"
            }
        }
    }
}

function Install-YaziPackages {
    # Installs the plugins listed in yazi\package.toml (linked above).
    if (-not (Get-Command ya -ErrorAction SilentlyContinue)) {
        Write-Warning "yazi CLI 'ya' not found in PATH; skipping yazi packages"
        return
    }

    # ya stops when an installed plugin differs from package.toml: after the
    # patch below, and also when package.toml moves to another revision.
    # --discard replaces it instead; older versions of ya do not have it.
    $installArgs = @("pkg", "install")
    if ((ya pkg install --help | Out-String) -match '--discard') {
        $installArgs += "--discard"
    }

    Write-Host "install yazi packages: ya $installArgs"
    if (-not $dryrun) {
        ya @installArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "ya pkg install failed"
        }
    }

    Repair-YaziPlugins "$homedir\AppData\Roaming\yazi\config\plugins"
}

function Repair-YaziPlugins {
    # yazi 26.9.1 no longer has ya.mgr_emit, which bookmarks and relative-motions
    # still call (their fixes, bookmarks.yazi #66 and relative-motions.yazi #32,
    # are not merged). ya.emit takes the same arguments. It cannot be done in
    # init.lua: a plugin's entry does not see what init.lua adds to ya.
    param([string]$pluginsDir)

    foreach ($file in @(Get-ChildItem "$pluginsDir\*.yazi\main.lua" -ErrorAction SilentlyContinue)) {
        $text = [IO.File]::ReadAllText($file.FullName)
        $fixed = $text -creplace '\bya\.mgr_emit\b', 'ya.emit'
        if ($fixed -ceq $text) {
            continue
        }

        Write-Host "patch yazi plugin: $($file.Directory.Name) (ya.mgr_emit -> ya.emit)"
        if (-not $dryrun) {
            # ya makes the files it installs read-only.
            $file.IsReadOnly = $false
            [IO.File]::WriteAllText($file.FullName, $fixed, [Text.UTF8Encoding]::new($false))
        }
    }
}

# ================================
# Execution
# ================================

if ($useFallback) {
    foreach ($junction in $fallbackJunctions) {
        New-JunctionSafe $junction.source $junction.target $junction.keep
    }
    foreach ($hardLink in $fallbackHardLinks) {
        New-HardLinkSafe $hardLink.source $hardLink.target
    }
    Set-ProfileLoader $fallbackProfileSource $profile
    Add-UserPath $fallbackPathSource
}
else {
    Remove-FallbackJunctions
    foreach ($link in $links) {
        New-SymbolicLinkSafe $link.source $link.target
    }
}

Install-VSCodeExtensions "vscode\extensions.txt"
Install-YaziPackages

Write-Host "Done"
