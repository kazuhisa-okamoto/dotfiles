# 変数定義 
$notedir = "$env:USERPROFILE\Dropbox\Documents\note"
$mydirs = @(
    $notedir,
    "$env:USERPROFILE\Dropbox\code",
    "$env:USERPROFILE\code",
    "$env:USERPROFILE\.config",
    "$env:USERPROFILE\dotfiles"
)

# Use emacs keybinding in commandline
Import-Module PSReadline
Set-PSReadLineOption -EditMode Emacs
function emacskey {
    Write-Host "C-n, C-p: Next line/Previous line(next command/previous command)"
    Write-Host "C-f, C-b: Forward/Backward one character."
    Write-Host "C-a, C-e: Beginning/End of line."
    Write-Host "M-f, M-b: Forward/Backward one word."
}

$env:PATH = [Environment]::GetEnvironmentVariable("Path", "User") + ';' + [Environment]::GetEnvironmentVariable("Path", "Machine")

# Oh My Posh
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\mytheme.omp.json" | Invoke-Expression
#oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\paradox.omp.json" | Invoke-Expression
#oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\agnoster.omp.json" | Invoke-Expression
#oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\nu4a.omp.json" | Invoke-Expression

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

# ターミナルタブタイトル設定
function nvim() {
    $Host.UI.RawUI.WindowTitle = "Neovim"
    & "nvim.exe" $args
    $Host.UI.RawUI.WindowTitle = "PowerShell"
}

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
$fdExclude = @(".git", ".vscode", ".hg") # fd検索で除外するフォルダ
# 配列と文字列の両方を用意する。
# - $fdExcludeArgs: コマンド実行時に配列展開して渡す用途
# - $fdExcludeOption: 環境変数のコマンド文字列用
$fdExcludeArgs = $fdExclude | ForEach-Object { "--exclude=$_" }
$fdExcludeOption = $fdExcludeArgs -join " "
$env:FZF_DEFAULT_COMMAND = "fd --type f --strip-cwd-prefix --hidden $fdExcludeOption"
# CTRL-T (ファイル検索) 用の設定
$env:FZF_CTRL_T_COMMAND = $env:FZF_DEFAULT_COMMAND

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
    & {
        $mydirs
        fd --type d --hidden --absolute-path $fdExcludeArgs . $mydirs
    } | fzf --query="$query" --header "Move to Directory" --no-sort | ForEach-Object { Set-Location $_ }
}

# .gitがあるディレクトリへ移動
function fcdg {
    param([string]$query)
    & {
        $mydirs
        fd --hidden --fixed-strings ".git" $mydirs --type d --max-depth 5 | ForEach-Object { Split-Path $_ -Parent }
    } | fzf --query="$query" --header "Move to Git Repository" --no-sort | ForEach-Object { Set-Location $_ }
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

    & {
        $mydirs
        fd --type $type --hidden --absolute-path $fdExcludeArgs . $mydirs
    } | fzf --query="$query" --header "Open with VS Code ($type)" --no-sort | ForEach-Object { code $_ }
}

# Neovimで開く
function fvim {
    param([string]$query)
    & {
        $mydirs
        fd --type f --hidden $fdExcludeArgs . $mydirs
    } | fzf --query="$query" --header "Open with Neovim" --no-sort | ForEach-Object { nvim $_ }
}

# メモディレクトリをvscodeで開く
function fcodememo {
    param([string]$query)
    & {
        $notedir
        fd --type f $fdExcludeArgs . $notedir
    } | fzf --query="$query" --header "Open Memo (VS Code)" --no-sort | ForEach-Object { code $_ }
}

# メモディレクトリをNeovimで開く
function fvimmemo {
    param([string]$query)
    & {
        $notedir
        fd --type f $fdExcludeArgs . $notedir
    } | fzf --query="$query" --header "Open Memo (Neovim)" --no-sort | ForEach-Object { nvim $_ }
}

# リポジトリをVS Codeで開く
function fcodeg {
    param([string]$query)
    & {
        $mydirs
        fd --hidden --fixed-strings ".git" $mydirs --type d --max-depth 5 | ForEach-Object { Split-Path $_ -Parent }
    } | fzf --query="$query" --header "Open Repository (VS Code)" --no-sort | ForEach-Object { code $_ }
}
