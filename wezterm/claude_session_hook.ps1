# Claude Code の SessionStart / SessionEnd hook から呼ばれる。
# WezTerm の workspace 復元 (wezterm/workspace_session.lua) 用に、この Claude Code が
# どの pane で動いているかと、その session_id を目印ファイル panes/<pane_id>.claude.json に書く。
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

if ($hook.hook_event_name -eq 'SessionEnd') {
    # /clear では SessionEnd のあとに新しい session_id で SessionStart が来る。
    # 順番が前後しても新しい方を消さないよう、自分の session_id のときだけ消す
    try {
        $current = [IO.File]::ReadAllText($marker) | ConvertFrom-Json
        if ($current.session_id -eq $hook.session_id) { Remove-Item $marker }
    } catch {}
    exit 0
}

New-Item -ItemType Directory -Force $panesDir | Out-Null
$json = @{
    session_id      = $hook.session_id
    cwd             = $hook.cwd
    transcript_path = $hook.transcript_path
} | ConvertTo-Json -Compress
# BOM なしの UTF-8 で書く (Windows PowerShell の Set-Content -Encoding utf8 は BOM を付ける)
[IO.File]::WriteAllText($marker, $json)
