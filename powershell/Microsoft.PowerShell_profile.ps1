
# Path
# user_path.ps1に$notedir, $mydirsを定義
# $profile_dir はリポジトリの powershell フォルダー。$PROFILE はこのファイルへのシンボリックリンクか、
# (install.ps1 を管理者権限・開発者モードなしで実行したときは) このファイルを読み込むだけのファイル
$profile_target = (Get-Item $PROFILE).Target
if ($profile_target) {
    $profile_dir = Split-Path -Parent $profile_target
} else {
    $profile_dir = $PSScriptRoot
}
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
    Write-Host "C-k: Delete from the cursor to the end of line."
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
# テーマはリポジトリのものを直接読む (無ければ従来どおり POSH_THEMES_PATH から)
$omp_theme = Join-Path (Split-Path -Parent $profile_dir) "oh_my_posh\mytheme.omp.json"
if (-not (Test-Path $omp_theme)) {
    $omp_theme = "$env:POSH_THEMES_PATH\mytheme.omp.json"
}
oh-my-posh init pwsh --config $omp_theme | Invoke-Expression
$ErrorActionPreference = 'Continue'

# 既存の Set-Location をラップ
function Set-Location {
    param(
        [Parameter(Position=0)]
        [string]$Path
    )

    Microsoft.PowerShell.Management\Set-Location @PSBoundParameters
    Send-TerminalCwd
    ls -Limit $cd_ls_limit
}
# cd のあとの ls で表示する最大件数 (ファイルが多いディレクトリで cd が遅くならないように)
$cd_ls_limit = 200

# lsコマンド
# 表示幅: 0xFF より大きい文字 (全角など) を 2、それ以外を 1 として数える
function Get-DisplayWidth($s) {
    $s = [string]$s
    return $s.Length + [regex]::Matches($s, '[^\u0000-ÿ]').Count
}
Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
function ls {
    param(
        [Parameter(Position=0)]
        [string]$Path = ".",
        [switch]$a,
        [switch]$l,
        # 表示する最大件数 (0 は全件)
        [int]$Limit = 0
    )

    $gci_args = @{ Path = $Path }
    if ($a.IsPresent) { $gci_args.Force = $true }

    # Limit があるときは Limit + 1 件で列挙を打ち切る (超えたかどうかだけ分かればよい)
    $items = @(if ($Limit -gt 0) {
        Get-ChildItem @gci_args | Select-Object -First ($Limit + 1)
    } else {
        Get-ChildItem @gci_args
    })
    $truncated = $Limit -gt 0 -and $items.Count -gt $Limit
    if ($truncated) { $items = $items[0..($Limit - 1)] }
    $truncated_message = "... showing the first $Limit entries (run ls to see all)"

    # 詳細表示
    if ($l.IsPresent) {
        $table = $items | Format-Table Mode, LastWriteTime, Length,
            @{Label="Name"; Expression={
                if ($_.PSIsContainer) {
                    "$($PSStyle.Foreground.Blue)$($_.Name)$($PSStyle.Reset)"
                } else {
                    $_.Name
                }
        }}
        if ($truncated) {
            $table | Out-Host
            Write-Host $truncated_message -ForegroundColor DarkGray
        } else {
            $table
        }
        return
    }

    # 通常表示
    $count = $items.Count
    if ($count -eq 0) { return }

    # 名前ごとの表示幅は最初に 1 回だけ数える
    $widths = [int[]]::new($count)
    $min_width = [int]::MaxValue
    for ($i = 0; $i -lt $count; $i++) {
        $widths[$i] = Get-DisplayWidth $items[$i].Name
        if ($widths[$i] -lt $min_width) { $min_width = $widths[$i] }
    }

    $term_width = 79
    try { $term_width = [Console]::WindowWidth - 1 } catch {}
    if ($term_width -lt 1) { $term_width = 79 }

    # どの列も (いちばん短い名前の幅 + 2) 以上になるので、列数はそれで割った数より多くならない
    $cols = [int][Math]::Max(1, [Math]::Min($count, [Math]::Floor($term_width / ($min_width + 2))))
    while ($true) {
        $rows = [int][Math]::Ceiling($count / $cols)
        $col_widths = [int[]]::new($cols)
        $total_width = 0
        for ($c = 0; $c -lt $cols; $c++) {
            $start = $c * $rows
            if ($start -ge $count) { break }
            $end = [Math]::Min($start + $rows, $count)
            $max = 0
            for ($i = $start; $i -lt $end; $i++) {
                if ($widths[$i] -gt $max) { $max = $widths[$i] }
            }
            $col_widths[$c] = $max + 2
            $total_width += $max + 2
            if ($total_width -gt $term_width) { break }
        }
        if ($total_width -le $term_width -or $cols -eq 1) { break }
        $cols--
    }

    # 表示 (まとめて 1 回で書き出す。ディレクトリは明るい青 = Write-Host -ForegroundColor Blue と同じ色)
    $esc = [char]27
    $sb = [System.Text.StringBuilder]::new()
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $i = $c * $rows + $r
            if ($i -ge $count) { break }

            $item = $items[$i]
            $text = $item.Name + (' ' * [Math]::Max(0, $col_widths[$c] - $widths[$i]))
            if ($item.PSIsContainer) {
                [void]$sb.Append("${esc}[94m$text${esc}[0m")
            } else {
                [void]$sb.Append($text)
            }
        }
        [void]$sb.Append("`n")
    }
    Write-Host $sb.ToString() -NoNewline
    if ($truncated) {
        Write-Host $truncated_message -ForegroundColor DarkGray
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

# poetry
# カレントディレクトリのプロジェクトの仮想環境をアクティベート
# 解除はActivate.ps1が定義するdeactivateを使う
function pvenv() {
    if (-not (Get-Command poetry -ErrorAction SilentlyContinue)) {
        Write-Host "poetry is not found"
        return
    }

    $venvpath = poetry env info --path 2>$null
    if (-not $venvpath) {
        Write-Host "Virtual environment is not found. Run 'poetry install' first."
        return
    }

    $activate = Join-Path $venvpath "Scripts\Activate.ps1"
    if (-not (Test-Path $activate)) {
        Write-Host "$activate is not found"
        return
    }

    & $activate
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
        [Parameter(Position=0)][string]$Path
    )

    $roots = Resolve-PathArg $mydirs $Path

    # fd の出力をパイプで直接 fzf に渡す(fdが走っている途中からfzfを動かせる)
    $selected = & {
        $roots
        fd . $roots --type d --hidden --absolute-path $fdExcludeArgs
    } | fzf --header "Move to Directory" --no-sort

    if ($selected) { Set-Location $selected }
}

# .gitがあるディレクトリへ移動
function fcdg {
    param(
        [Parameter(Position=0)][string]$Path
    )
    $roots = Resolve-PathArg $mydirs $Path

    $repos = fd "^\.git$" $roots --hidden --type d |
         ForEach-Object { Split-Path $_ -Parent } |
         Sort-Object
    $selected = $repos |
        fzf --header "Move to Git Repository" --no-sort
    if ($selected) { Set-Location $selected }
}

# VS Code: ファイルは、それを含む git リポジトリのルートを workspace にして開く (bin/code-root.ps1).
# 対話中に打つ code だけを置き換える. git や他のツールが呼ぶ code.cmd はそのまま.
# --wait などのオプション付きの呼び出しは code-root が本物の code にそのまま渡す.
function code {
    if (Get-Command code-root.ps1 -CommandType ExternalScript -ErrorAction SilentlyContinue) {
        code-root.ps1 @args
    }
    else {
        $realCode = Get-Command code -CommandType Application | Select-Object -First 1
        & $realCode @args
    }
}

# VS Codeで開く. 引数でファイル(-f)/ディレクトリ(-d)を指定.
function fcode {
    param(
        [Parameter(Position=0)][string]$Path,
        [switch]$f,
        [switch]$d
    )

    $type = if ($d) { "d" } else { "f" }
    $roots = Resolve-PathArg $mydirs $Path

    $selected = & {
        #if ($type -eq "d") { $mydirs }

        fd . $roots --type $type --hidden --absolute-path $fdExcludeArgs
    } | fzf --header "Open with VS Code ($type)" --no-sort --no-select-1

    if ($selected) { code-root $selected }
}

# Neovimで開く
function fvi {
    param(
        [Parameter(Position=0)][string]$Path,
        [switch]$f,
        [switch]$d
    )
    $type = if ($d) { "d" } else { "f" }
    $roots = Resolve-PathArg $mydirs $Path

    $selected = & {
        fd . $roots --type $type --hidden --absolute-path $fdExcludeArgs
    } | fzf --header "Open with Neovim" --no-sort --multi

    if ($selected) { nvim $selected }
}

# メモをvscodeで開く
function fcodememo {
    param(
        [Parameter(Position=0)][string]$Path
    )
    $roots = Resolve-PathArg $notedir $Path

    $selected = & {
        fd . $roots --type f $fdExcludeArgs
    } | fzf --header "Open Memo (VS Code)" --no-sort --multi

    if ($selected) { code-root $selected }
}

# メモをNeovimで開く
function fvimemo {
    param(
        [Parameter(Position=0)][string]$Path
    )
    $roots = Resolve-PathArg $notedir $Path

    $selected = & {
        fd . $roots --type f $fdExcludeArgs
    } | fzf --header "Open Memo (Neovim)" --no-sort --multi

    if ($selected) { nvim $selected }
}

# リポジトリをVS Codeで開く
function fcodeg {
    param(
        [Parameter(Position=0)][string]$Path
    )
    $roots = Resolve-PathArg $mydirs $Path
    $repos = fd "^\.git$" $roots --hidden --type d |
        ForEach-Object { Split-Path $_ -Parent }
    $repos |
        fzf --header "Open Repository (VS Code)" --no-sort |
        ForEach-Object { code $_ }
}

# リポジトリをNeovimで開く
function fvig {
    param(
        [Parameter(Position=0)][string]$Path
    )
    $roots = Resolve-PathArg $mydirs $Path
    $repos = fd "^\.git$" $roots --hidden --type d |
        ForEach-Object { Split-Path $_ -Parent }
    $repos |
        fzf --header "Open Repository (Neovim)" --no-sort |
        ForEach-Object { nvim $_ }
}

# ripgrep
# ファイルを検索し, 選択したファイル, 行番号を@(ファイル, 行番号)として返す
function rgf {
    param(
        [Parameter(Position = 0)]
        [string]$Path = "."
    )

    $selected = rg --line-number --column --color=always --smart-case . $Path |
        fzf --ansi `
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
        [Parameter(Position = 0)]
        [string]$Path = "."
    )

    $file, $line = rgf $Path

    if (Test-Path $file) {
        nvim "+$line" -- $file
    }
}

# ripgrepの結果をvscodeで開く
function rgcode {
    param(
        [Parameter(Position = 0)]
        [string]$Path = "."
    )

    $file, $line = rgf $Path

    if (Test-Path $file) {
        code-root -g "${file}:${line}"
    }
}

Send-TerminalCwd

