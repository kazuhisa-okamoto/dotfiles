
# Path
# user_path.ps1に$notedir, $mydirsを定義
$profile_dir = Split-Path -Parent (Get-Item $PROFILE).Target
$user_path_file = Join-Path $profile_dir "user_path.ps1"
$mydirs = @(".")
if (Test-Path $user_path_file) {
    . $user_path_file
}

function Get-TopLevelPaths($paths) {
    # フルパスに正規化 + 重複除去
    $normalized = $paths |
        ForEach-Object {
            try {
                (Resolve-Path $_).Path.TrimEnd('\')
            } catch {
                $null
            }
        } |
        Where-Object { $_ } |
        Sort-Object -Unique

    $result = @()

    foreach ($path in $normalized) {

        $isChild = $false

        foreach ($parent in $result) {
            if ($path.StartsWith($parent + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $isChild = $true
                break
            }
        }

        if (-not $isChild) {
            $result += $path
        }
    }

    return $result
}
$mydirs = Get-TopLevelPaths $mydirs

# Use emacs keybinding in commandline
Import-Module PSReadLine
Set-PSReadLineOption -EditMode Emacs
function emacskey {
    Write-Host "C-n, C-p: Next line/Previous line(next command/previous command)"
    Write-Host "C-f, C-b: Forward/Backward one character."
    Write-Host "C-a, C-e: Beginning/End of line."
    Write-Host "M-f, M-b: Forward/Backward one word."
    Write-Host "C-d, C-h: Delete one character before/after the cursor."
    Write-Host "C-w, M-d: Delete one word before/after the cursor."
}

$env:PATH = [Environment]::GetEnvironmentVariable("Path", "User") + ';' + [Environment]::GetEnvironmentVariable("Path", "Machine")

# UTF-8
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
# コードページ
chcp 65001 | Out-Null

# 補完適用
if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Chord "Ctrl+s" -Function AcceptNextSuggestionWord
}

# Oh My Posh
$ErrorActionPreference = 'SilentlyContinue' # デフォルトpowershellのエラー無視
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\mytheme.omp.json" | Invoke-Expression
$ErrorActionPreference = 'Continue'

# 既存の Set-Location をラップ
function Set-Location {
    param(
        [Parameter(Position=0)]
        [string]$Path
    )

    Microsoft.PowerShell.Management\Set-Location @PSBoundParameters
    Send-TerminalCwd
    ls
}

# lsコマンド
function Get-DisplayWidth($s) {
    $w = 0
    $s = [string]$s
    foreach ($ch in $s.ToCharArray()) {
        $w += if ([int][char]$ch -gt 255) { 2 } else { 1 }
    }
    return $w
}
function Format-DisplayRight($s, $width) {
    $current = Get-DisplayWidth $s
    $pad = $width - $current
    if ($pad -gt 0) {
        return $s + (' ' * $pad)
    }
    return $s
}
Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
function ls {
    param(
        [Parameter(Position=0)]
        [string]$Path = ".",
        [switch]$a,
        [switch]$l
    )

    $show_all = $a.IsPresent
    $detail   = $l.IsPresent

    $items = if ($show_all) {
        Get-ChildItem -Path $Path -Force
    } else {
        Get-ChildItem -Path $Path
    }

    # 詳細表示
    if ($detail) {
    	$items | Format-Table Mode, LastWriteTime, Length,
       	    @{Label="Name"; Expression={
                if ($_.PSIsContainer) {
                    "$($PSStyle.Foreground.Blue)$($_.Name)$($PSStyle.Reset)"
                } else {
                    $_.Name
                }
        }}
        return
    }

    # 通常表示
    if ($items.Count -eq 0) { return }
    
    $names = $items.Name
    $termWidth = [Console]::WindowWidth - 1
    $count = $names.Count
    
    for ($cols = $count; $cols -ge 1; $cols--) {
    
        $rows = [Math]::Ceiling($count / $cols)
    
        # 列ごとの最大幅を計算
        $colWidths = @()
    
        for ($c = 0; $c -lt $cols; $c++) {
            $max = 0
            for ($r = 0; $r -lt $rows; $r++) {
                $i = $c * $rows + $r
                if ($i -ge $count) { continue }
    
                $len = Get-DisplayWidth($names[$i])
                if ($len -gt $max) { $max = $len }
            }
            $colWidths += $max + 2
        }
    
        $totalWidth = ($colWidths | Measure-Object -Sum).Sum
    
        if ($totalWidth -le $termWidth) {
            break
        }
    }
    
    # 表示
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $i = $c * $rows + $r
            if ($i -ge $count) { continue }

            $item = $items[$i]
            $width = $colWidths[$c]
            $text = Format-DisplayRight $item.Name $width
    
            if ($item.PSIsContainer) {
                Write-Host $text -NoNewline -ForegroundColor Blue
            } else {
                Write-Host $text -NoNewline
            }
        }
        Write-Host ""
    }
}

# tablacus
function te {
    param([string]$path = ".")
    & "te64" (Resolve-Path $path)
}

# Fork
# If the arugument is not specified, open current directory.
function fork($dirpath) {
    if ($null -eq $dirpath -or $dirpath -eq "") {
        $dirpath = Resolve-Path .
    } else {
        $dirpath = Resolve-Path $dirpath
    }
    
    $fork = Join-Path $env:LOCALAPPDATA "Fork\current\Fork.exe"
    & $fork $dirpath
}

# SourceTree
# If the argument is not specified: Open current directory
# If the argument is a directory  : Open the directory
# If the argument is a file       : Open file change history
function stree($filedirpath) {
    if ($null -eq $filedirpath -or $filedirpath -eq "") {
        $filedirpath = Resolve-Path .
    }

    # Get absolute path. Repository path for the SourceTree argument must be absolute path.
    $filedirpath = Resolve-Path $filedirpath
    
    if (Test-Path $filedirpath -PathType Container) {
        $filepath = ""
        $dirpath = $filedirpath
    } else {
        $filepath = $filedirpath
        $dirpath = Split-Path $filedirpath -Parent
    }

    # Get the root path of the repository
    $gitfound = $false
    for ($i = 0; $i -lt 1000; $i++) {
        if ($null -eq $dirpath -or $dirpath -eq "") {
            break    
        }
        $gitdir = Join-Path $dirpath ".git"
        if (Test-Path $gitdir) { 
            $gitfound = $true
            break
        }
        $dirpath = Split-Path $dirpath -Parent
    }
    
    $sourcetree = Join-Path $env:LOCALAPPDATA "SourceTree\SourceTree.exe"
    if (!$gitfound) {
        & $sourcetree
    } else {
        if ($filepath -eq "") {
            & $sourcetree -f $dirpath
        } else {
            & $sourcetree -f $dirpath filelog $filepath
        }
    }
}

Set-Alias -Name lg -Value lazygit

Set-Alias vim nvim
Set-Alias vi nvim

# yazi
function y {
	$tmp = (New-TemporaryFile).FullName
	yazi.exe $args --cwd-file="$tmp"

    if (Test-Path $tmp) {
        $cwd = Get-Content -Path $tmp -Raw

        if ($cwd -and $cwd -ne $PWD.Path -and
            (Test-Path -LiteralPath $cwd -PathType Container)) {

            Set-Location -Path $cwd
        }
    }

	Remove-Item $tmp
}

# ターミナルタブタイトル設定
function Set-PsTabName {
    $dir = Split-Path -Leaf (Get-Location)
    $host.UI.RawUI.WindowTitle = $dir
}

function Send-TerminalCwd {
    $cwd = (Get-Location).ProviderPath
    $esc = [char]27
    $Host.UI.Write("$esc]7;file://localhost/$cwd$esc\")
    Set-PsTabName
}

function python2() {
    $python2path = "C:\Python27\python.exe"
    if (Test-Path $python2path) {
    	& $python2path $args
    } else {
	    Write-Host "$python2path is not found"
    }
}

# zoxide
# z "key1" "key2"
Invoke-Expression (& {zoxide init powershell | Out-String})

# fd
# fzf のデフォルトコマンドを fd に変更 (ファイル検索用)
$fdExclude = @(".git/", ".hg/") # fd検索で除外するフォルダ
# 配列と文字列の両方を用意する。
# - $fdExcludeArgs: コマンド実行時に配列展開して渡す用途
# - $fdExcludeOption: 環境変数のコマンド文字列用
$fdExcludeArgs = $fdExclude | ForEach-Object { "--exclude=$_" }
$fdExcludeOption = $fdExcludeArgs -join " "
$env:FZF_DEFAULT_COMMAND = "fd --type f --strip-cwd-prefix --hidden $fdExcludeOption"
# CTRL-T (ファイル検索) 用の設定
$env:FZF_CTRL_T_COMMAND = $env:FZF_DEFAULT_COMMAND
$env:FZF_DEFAULT_OPTS = "--exact"

# 関数引数で渡されるパスの解釈
function Resolve-PathArg($default, $path) {
    if ($path) {
        $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
        if (-not $resolved) {
            Write-Host "Path not found: $path"
            return
        }
        $ret = @($resolved.Path)
    } else {
        $ret = $default
    }
    return $ret
}

# fzfコマンド
# ヒストリー実行
function fhis {
    $selected = Get-History | Select-Object -Unique CommandLine | Out-String -Stream | fzf --query=(Get-Content -Raw -ErrorAction SilentlyContinue .fzf_query) --header="Select a command to execute"
    
    if ($selected) {
        Write-Host "Executing: $selected" -ForegroundColor Cyan
        Invoke-Expression $selected
    }
}

# 選択ディレクトリへ移動
function fcd {
    param(
        [Alias('p')][string]$Path,
        [Parameter(Position=0)][string]$Query
    )

    $roots = Resolve-PathArg $mydirs $Path

    # fd の出力をパイプで直接 fzf に渡す(fdが走っている途中からfzfを動かせる)
    $selected = & {
        $roots
        fd . $roots --type d --hidden --absolute-path $fdExcludeArgs
    } | fzf --query="$Query" --header "Move to Directory" --no-sort

    if ($selected) { Set-Location $selected }
}

# .gitがあるディレクトリへ移動
function fcdg {
    param(
        [Alias('p')][string]$Path,
        [Parameter(Position=0)][string]$Query
    )
    $roots = Resolve-PathArg $mydirs $Path

    $repos = fd "^\.git$" $roots --hidden --type d --max-depth 5 |
         ForEach-Object { Split-Path $_ -Parent } |
         Sort-Object
    $selected = $repos |
        fzf --query="$Query" --header "Move to Git Repository" --no-sort
    if ($selected) { Set-Location $selected }
}

# VS Codeで開く. 引数でファイル(-f)/ディレクトリ(-d)を指定.
function fcode {
    param(
        [Alias('p')][string]$Path,
        [switch]$f,
        [switch]$d, # -d はデフォルト（ディレクトリ）
        [Parameter(Position=0)][string]$Query
    )

    $type = if ($f) { "f" } else { "d" }
    $roots = Resolve-PathArg $mydirs $Path

    $selected = & {
        #if ($type -eq "d") { $mydirs }
        
        fd . $roots --type $type --hidden --absolute-path $fdExcludeArgs
    } | fzf --query="$Query" --header "Open with VS Code ($type)" --no-sort --no-select-1

    if ($selected) { code $selected }
}

# Neovimで開く
function fvi {
    param(
        [Alias('p')][string]$Path,
        [switch]$f,
        [switch]$d, # -d はデフォルト（ディレクトリ）
        [Parameter(Position=0)][string]$Query
    )
    $type = if ($f) { "f" } else { "d" }
    $roots = Resolve-PathArg $mydirs $Path

    $selected = & {
        fd . $roots --type $type --hidden --absolute-path $fdExcludeArgs
    } | fzf --query="$Query" --header "Open with Neovim" --no-sort --multi

    if ($selected) { nvim $selected }
}

# メモをvscodeで開く
function fcodememo {
    param(
        [Alias('p')][string]$Path,
        [Parameter(Position=0)][string]$Query
    )
    $roots = Resolve-PathArg $notedir $Path
    
    $selected = & {
        fd . $roots --type f $fdExcludeArgs
    } | fzf --query="$Query" --header "Open Memo (VS Code)" --no-sort --multi

    if ($selected) { code $selected }
}

# メモをNeovimで開く
function fvimemo {
    param(
        [Alias('p')][string]$Path,
        [Parameter(Position=0)][string]$Query
    )
    $roots = Resolve-PathArg $notedir $Path
    
    $selected = & {
        fd . $roots --type f $fdExcludeArgs
    } | fzf --query="$Query" --header "Open Memo (Neovim)" --no-sort --multi

    if ($selected) { nvim $selected }
}

# リポジトリをVS Codeで開く
function fcodeg {
    param(
        [Alias('p')][string]$Path,
        [Parameter(Position=0)][string]$Query
    )
    $roots = Resolve-PathArg $mydirs $Path
    $repos = fd "^\.git$" $roots --hidden --type d --max-depth 5 |
        ForEach-Object { Split-Path $_ -Parent }
    $repos |
        fzf --query="$Query" --header "Open Repository (VS Code)" --no-sort |
        ForEach-Object { code $_ }
}

# リポジトリをNeovimで開く
function fvig {
    param(
        [Alias('p')][string]$Path,
        [Parameter(Position=0)][string]$Query
    )
    $roots = Resolve-PathArg $mydirs $Path
    $repos = fd "^\.git$" $roots --hidden --type d --max-depth 5 |
        ForEach-Object { Split-Path $_ -Parent }
    $repos |
        fzf --query="$Query" --header "Open Repository (Neovim)" --no-sort |
        ForEach-Object { nvim $_ }
}

# ripgrep
# ファイルを検索し, 選択したファイル, 行番号を@(ファイル, 行番号)として返す
function rgf {
    param(
        [Alias('p')]
        [string]$Path = ".",

        [Parameter(Position = 0)]
        [string]$Query
    )

    $selected = rg --line-number --column --color=always --smart-case . $Path | 
        fzf --ansi `
            --query "$Query" `
            --delimiter ':' `
            --preview 'bat --color=always --highlight-line {2} {1}' `
            --preview-window 'right:60%:wrap'

    if ($selected) {
        $parts = $selected.Split(":")
        return @($parts[0], [int]$parts[1])
    }
    return @("", 0)
}

# ripgrepの結果をnvimで開く
function rgvi {
    param(
        [Alias('p')]
        [string]$Path = ".",

        [Parameter(Position = 0)]
        [string]$Query
    )

    $file, $line = rgf -p $Path $Query

    if (Test-Path $file) {
        nvim "+$line" -- $file
    }
}

# ripgrepの結果をvscodeで開く
function rgcode {
    param(
        [Alias('p')]
        [string]$Path = ".",

        [Parameter(Position = 0)]
        [string]$Query
    )

    $file, $line = rgf -p $Path $Query

    if (Test-Path $file) {
        code -g "${file}:${line}"
    }
}

Send-TerminalCwd

