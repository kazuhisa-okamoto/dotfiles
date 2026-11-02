<#
.SYNOPSIS
    Open files in VS Code with their enclosing git repository as the workspace.

.DESCRIPTION
    For each file, search upward for a ".git" entry (a directory, or a file in
    worktrees and submodules) and run `code <repo root> <file>`. If a window
    already has that repository open, VS Code reuses it.
    Directories and files outside any repository are passed to `code` as-is.
    If any option other than -g / --goto is given (e.g. --wait, --diff, -n),
    all arguments are passed to `code` unchanged.

    The PowerShell profile defines a `code` function that calls this script,
    so this script always calls the real code.cmd by its full path.

.USAGE
    code-root <path> ...
    code-root -g <path>[:line[:column]] ...
#>

# Arguments are parsed by hand (no param block) so that unknown options such
# as --wait reach this script instead of failing in the parameter binder.

$realCode = Get-Command code -CommandType Application -ErrorAction Stop |
    Select-Object -First 1 -ExpandProperty Source

$g = $false
$Paths = [System.Collections.Generic.List[string]]::new()
foreach ($arg in $args) {
    $arg = [string]$arg
    if ($arg -eq '-g' -or $arg -eq '--goto') {
        $g = $true
    }
    elseif ($arg.StartsWith('-')) {
        & $realCode @args
        exit $LASTEXITCODE
    }
    else {
        $Paths.Add($arg)
    }
}

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

$gotoArgs = @()
if ($g) {
    $gotoArgs = @('-g')
}

if ($Paths.Count -eq 0) {
    & $realCode @gotoArgs
    exit $LASTEXITCODE
}

$groups = [ordered]@{}  # repository root -> files under it
$plain = [System.Collections.Generic.List[string]]::new()

foreach ($arg in $Paths) {
    $path = $arg
    $suffix = ''
    if ($g -and $arg -match '^(.+?)(:\d+(?::\d+)?)$') {
        $path = $Matches[1]
        $suffix = $Matches[2]
    }
    $full = [System.IO.Path]::GetFullPath($path, (Get-Location).ProviderPath)

    $root = $null
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        $root = Find-GitRoot (Split-Path -Parent $full)
    }

    if ($root) {
        if (-not $groups.Contains($root)) {
            $groups[$root] = [System.Collections.Generic.List[string]]::new()
        }
        $groups[$root].Add($full + $suffix)
    }
    else {
        $plain.Add($full + $suffix)
    }
}

foreach ($root in $groups.Keys) {
    $files = $groups[$root].ToArray()
    & $realCode $root @gotoArgs @files
}
if ($plain.Count -gt 0) {
    $files = $plain.ToArray()
    & $realCode @gotoArgs @files
}
