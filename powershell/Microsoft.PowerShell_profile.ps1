# 変数定義 
$notedir = "$env:USERPROFILE\Dropbox\Documents\note"
$mydirs = @(
    $notedir
    "$env:USERPROFILE\Dropbox\code"
    "$env:USERPROFILE\dotfiles"
    "$env:USERPROFILE\src"
)

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
    $show_all = $false
    $detail   = $false

    foreach ($arg in $args) {
        if ($arg -match "a") { $show_all = $true }
        if ($arg -match "l") { $detail   = $true }
    }

    $items = if ($show_all) {
        Get-ChildItem -Force
    } else {
        Get-ChildItem
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
    & "C:\Program Files\te250907\te64.exe" (Resolve-Path $path)
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

# lazygit
Set-Alias -Name lg -Value lazygit

# yazi
function y {
	$tmp = (New-TemporaryFile).FullName
	yazi.exe $args --cwd-file="$tmp"
	$cwd = Get-Content -Path $tmp -Encoding UTF8
	if ($cwd -ne $PWD.Path -and (Test-Path -LiteralPath $cwd -PathType Container)) {
		Set-Location -LiteralPath (Resolve-Path -LiteralPath $cwd).Path
	}
	Remove-Item -Path $tmp
}

# ターミナルタブタイトル設定
function Set-PsTabName {
    $dir = Split-Path -Leaf (Get-Location)
    $host.UI.RawUI.WindowTitle = $dir
}

Register-EngineEvent PowerShell.OnIdle -Action {
    Set-PsTabName
} | Out-Null

function python2() {
    $python2path = "C:\Python27\python.exe"
    if (Test-Path $python2path) {
    	& $python2path $args
    } else {
	Write-Host "python2 is not found"
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
    param([string]$query)
    @(
        $mydirs
        fd --type d --hidden --absolute-path $fdExcludeArgs . $mydirs
    ) | fzf --query="$query" --header "Move to Directory" --no-sort | ForEach-Object { Set-Location $_ }
    ls
}

# .gitがあるディレクトリへ移動
function fcdg {
    param([string]$query)
    fd --hidden --fixed-strings ".git" $mydirs --type d --max-depth 5 |
        ForEach-Object { Split-Path $_ -Parent } |
        fzf --query="$query" --header "Move to Git Repository" --no-sort |
        ForEach-Object { Set-Location $_ }
}

# VS Codeで開く. 引数でファイル(-f)/ディレクトリ(-d)を指定.
function fcode {
    $query = ""
    $type = "d"
    foreach ($arg in $args) {
        if ($arg -eq "-f") { $type = "f" }
        elseif ($arg -eq "-d") { $type = "d" }
        elseif ($arg -match "^-") { }
        else { $query += $arg }
    }

    @(
        $mydirs
        fd --type $type --hidden --absolute-path $fdExcludeArgs . $mydirs
    ) | fzf --query="$query" --header "Open with VS Code ($type)" --no-sort | ForEach-Object { code $_ }
}

# Neovimで開く
function fvim {
    param([string]$query)
    @(
        fd --type f --hidden $fdExcludeArgs . $mydirs
    ) | fzf --query="$query" --header "Open with Neovim" --no-sort | ForEach-Object { nvim $_ }
}

# メモディレクトリをvscodeで開く
function fcodememo {
    param([string]$query)
    @(
        $notedir
        fd --type f $fdExcludeArgs . $notedir
    ) | fzf --query="$query" --header "Open Memo (VS Code)" --no-sort | ForEach-Object { code $_ }
}

# メモディレクトリをNeovimで開く
function fvimmemo {
    param([string]$query)
    @(
        $notedir
        fd --type f $fdExcludeArgs . $notedir
    ) | fzf --query="$query" --header "Open Memo (Neovim)" --no-sort | ForEach-Object { nvim $_ }
}

# リポジトリをVS Codeで開く
function fcodeg {
    param([string]$query)
    fd --hidden --fixed-strings ".git" $mydirs --type d --max-depth 5 |
        ForEach-Object { Split-Path $_ -Parent } |
        fzf --query="$query" --header "Open Repository (VS Code)" --no-sort |
        ForEach-Object { code $_ }
}
