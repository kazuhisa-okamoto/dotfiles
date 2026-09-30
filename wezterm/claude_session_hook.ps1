# Claude Code の hook から呼ばれ、この Claude Code が動いている pane の目印ファイルを書く。
#   panes/<pane_id>.claude.json: session_id など。WezTerm の workspace 復元 (wezterm/workspace_session.lua) 用
#   panes/<pane_id>.status.json: 状態 (実行中・確認待ちなど)。一覧とステータスバー (wezterm/claude_status.lua) 用
#
# ~/.claude/settings.json には、Claude Code が hook を動かすときの PowerShell の中でそのまま動くよう
#   & "$env:USERPROFILE\.config\wezterm\claude_session_hook.ps1"   ("shell": "powershell")
# の形で登録する。SessionEnd 以外は "async": true (Claude Code が終わるのを待たない)
[Console]::InputEncoding = [Text.Encoding]::UTF8

$dir = $env:WEZTERM_WORKSPACE_SESSION_DIR
$paneId = $env:WEZTERM_PANE
# WezTerm の外、または nvim の :terminal の中 ($NVIM が入る) で動いているときは何もしない
if (-not $dir -or -not $paneId -or $env:NVIM) { exit 0 }

$hook = $null
try { $hook = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch {}
if (-not $hook -or -not $hook.session_id) { exit 0 }

$panesDir = Join-Path $dir 'panes'
$marker = Join-Path $panesDir "$paneId.claude.json"
$statusFile = Join-Path $panesDir "$paneId.status.json"

function Read-Json($path) {
    try { return [IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { return $null }
}

# 状態を書く。$only を渡すと、今の状態がそのどれかのときだけ書く。
# 非同期の hook は終わる順番が前後するので、イベントが起きた時刻 (Claude Code がこの hook の
# PowerShell を起動した時刻) を event_at として書き、それより新しいイベントのときだけ上書きする
function Set-Status([string]$state, [string[]]$only) {
    $eventAt = ([DateTimeOffset](Get-Process -Id $PID).StartTime).ToUnixTimeMilliseconds()
    New-Item -ItemType Directory -Force $panesDir | Out-Null
    # 同じ pane の hook が同時に読み書きしないように排他する
    $mutex = [Threading.Mutex]::new($false, "Local\wezterm-claude-status-$paneId")
    try {
        try { [void]$mutex.WaitOne(5000) } catch [Threading.AbandonedMutexException] {}
        $current = Read-Json $statusFile
        if ($current -and $current.session_id -eq $hook.session_id) {
            if ($current.event_at -gt $eventAt) { return }
            if ($only -and $current.state -notin $only) { return }
        } elseif ($only) {
            return
        }
        $json = @{
            session_id = $hook.session_id
            state      = $state
            event_at   = $eventAt
        } | ConvertTo-Json -Compress
        # WezTerm が書きかけのファイルを読まないよう、別名で書いてから置き換える。
        # WezTerm が読んでいる最中は置き換えられないので、少し待ってやり直す
        $tmp = "$statusFile.$PID.tmp"
        [IO.File]::WriteAllText($tmp, $json)
        for ($i = 0; $i -lt 20; $i++) {
            try {
                if ([IO.File]::Exists($statusFile)) {
                    # PowerShell は文字列の引数の $null を "" にして渡すので NullString を使う
                    [IO.File]::Replace($tmp, $statusFile, [NullString]::Value)
                } else {
                    [IO.File]::Move($tmp, $statusFile)
                }
                break
            } catch {
                Start-Sleep -Milliseconds 25
            }
        }
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

switch ($hook.hook_event_name) {
    'SessionStart' {
        New-Item -ItemType Directory -Force $panesDir | Out-Null
        $json = @{
            session_id      = $hook.session_id
            cwd             = $hook.cwd
            transcript_path = $hook.transcript_path
        } | ConvertTo-Json -Compress
        # BOM なしの UTF-8 で書く (Windows PowerShell の Set-Content -Encoding utf8 は BOM を付ける)
        [IO.File]::WriteAllText($marker, $json)
        # compact (会話の要約) は応答の途中でも起きるので、状態は変えない
        if ($hook.source -ne 'compact') { Set-Status 'idle' }
    }
    'SessionEnd' {
        # /clear では SessionEnd のあとに新しい session_id で SessionStart が来る。
        # 順番が前後しても新しい方を消さないよう、自分の session_id のときだけ消す
        foreach ($path in @($marker, $statusFile)) {
            $current = Read-Json $path
            if ($current -and $current.session_id -eq $hook.session_id) {
                Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
            }
        }
    }
    'UserPromptSubmit' { Set-Status 'running' }
    # 許可された・質問に答えたあとに実行中へ戻す
    'PostToolUse' { Set-Status 'running' }
    'PostToolUseFailure' { Set-Status 'running' }
    # AskUserQuestion (Claude からの質問) と ExitPlanMode (計画の承認) だけを登録する
    'PreToolUse' { Set-Status 'waiting' }
    'PermissionRequest' { Set-Status 'waiting' }
    'Stop' { Set-Status 'done' }
    'StopFailure' { Set-Status 'error' }
    # idle_prompt (60 秒以上入力を待っている) だけを登録する。
    # Esc で止めたときは Stop が来ないので、実行中・確認待ちのまま残った状態をここで戻す
    'Notification' { Set-Status 'idle' @('running', 'waiting') }
}
