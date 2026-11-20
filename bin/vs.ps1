<#
.SYNOPSIS
    Find a solution file (.sln / .slnx) and open it in Visual Studio.

.DESCRIPTION
    The search starts from the given folder (the current folder by default):

    1. Solution files directly in that folder.
    2. If there are none and the folder is inside a git repository (a ".git"
       entry is found upward), every folder under the repository root.
    3. If there are none and there is no repository, every folder under the
       start folder.

    When more than one solution file is found, the user picks one (with fzf
    if it is installed, otherwise by number).

    The recursive searches use fd when it is installed, which skips hidden
    folders and what .gitignore excludes (node_modules, bin, obj, ...).
    Without fd, Get-ChildItem searches every folder.

    Visual Studio is located with vswhere, which the Visual Studio Installer
    puts in "Program Files (x86)\Microsoft Visual Studio\Installer".

.USAGE
    vs              search from the current folder
    vs <folder>     search from that folder
    vs <file>       search from the folder of the file; a solution file is
                    opened as it is
#>

param(
    [string]$Path = '.'
)

$ErrorActionPreference = 'Stop'

$solutionExtensions = @('.sln', '.slnx')

function Find-GitRoot([string]$dir) {
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
            return $dir
        }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) {
            break
        }
        $dir = $parent
    }
    return $null
}

function Test-SolutionFile([string]$file) {
    return $solutionExtensions -contains [System.IO.Path]::GetExtension($file).ToLower()
}

function Find-SolutionsHere([string]$dir) {
    return @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { Test-SolutionFile $_.Name } |
        ForEach-Object FullName |
        Sort-Object)
}

function Find-SolutionsBelow([string]$dir) {
    if (Get-Command fd -CommandType Application -ErrorAction SilentlyContinue) {
        $extArgs = foreach ($ext in $solutionExtensions) { '--extension'; $ext.TrimStart('.') }
        # fd keeps the separators of the folder it was given; use backslashes.
        return @(fd --type file @extArgs --absolute-path . $dir |
            ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
            Sort-Object)
    }
    return @(Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { Test-SolutionFile $_.Name } |
        ForEach-Object FullName |
        Sort-Object)
}

function Select-Solution([string[]]$files, [string]$baseDir) {
    if ($files.Count -eq 1) {
        return $files[0]
    }

    # Show paths relative to the folder that was searched.
    $relative = @($files | ForEach-Object { [System.IO.Path]::GetRelativePath($baseDir, $_) })

    if (Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue) {
        $picked = $relative | fzf --header "Open in Visual Studio ($baseDir)" --no-sort
        if (-not $picked) {
            return $null
        }
        return $files[[array]::IndexOf($relative, $picked)]
    }

    Write-Host "Solution files under ${baseDir}:"
    for ($i = 0; $i -lt $relative.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $relative[$i])
    }
    $answer = Read-Host "Number to open (empty to cancel)"
    $number = 0
    if (-not [int]::TryParse($answer, [ref]$number) -or $number -lt 1 -or $number -gt $files.Count) {
        return $null
    }
    return $files[$number - 1]
}

function Get-DevenvPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        return $null
    }
    $devenv = & $vswhere -latest -prerelease -property productPath | Select-Object -First 1
    if ($devenv -and (Test-Path -LiteralPath $devenv)) {
        return $devenv
    }

    # -latest leaves out an installation the Visual Studio Installer does not
    # consider complete (an interrupted install or update). Use one anyway if
    # its devenv.exe is there.
    $devenv = & $vswhere -all -prerelease -sort -property productPath |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1
    if ($devenv) {
        Write-Warning "The Visual Studio Installer reports this installation as incomplete: $devenv. If it fails to start, repair or update it in the Visual Studio Installer."
        return $devenv
    }
    return $null
}

# ---- Decide the start folder ----
$full = [System.IO.Path]::GetFullPath($Path, (Get-Location).ProviderPath)
if (-not (Test-Path -LiteralPath $full)) {
    Write-Host "not found: $full" -ForegroundColor Red
    exit 1
}

$solution = $null
if (Test-Path -LiteralPath $full -PathType Leaf) {
    if (Test-SolutionFile $full) {
        $solution = $full
    }
    $startDir = Split-Path -Parent $full
}
else {
    $startDir = $full
}

# ---- Search ----
if (-not $solution) {
    $baseDir = $startDir
    $found = Find-SolutionsHere $startDir

    if ($found.Count -eq 0) {
        $root = Find-GitRoot $startDir
        if ($root) {
            $baseDir = $root
        }
        $found = Find-SolutionsBelow $baseDir
    }

    if ($found.Count -eq 0) {
        Write-Host "no solution file (.sln / .slnx) found under $baseDir" -ForegroundColor Red
        exit 1
    }

    $solution = Select-Solution $found $baseDir
    if (-not $solution) {
        # Cancelled by the user: not an error (the yazi opener pauses on errors).
        Write-Host "cancelled"
        exit 0
    }
}

# ---- Open ----
$devenv = Get-DevenvPath
if (-not $devenv) {
    Write-Host "Visual Studio (devenv.exe) not found with vswhere" -ForegroundColor Red
    exit 1
}

Write-Host "open: $solution"
Start-Process -FilePath $devenv -ArgumentList "`"$solution`""
