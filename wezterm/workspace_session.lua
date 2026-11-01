-- workspace の保存と、WezTerm 起動時の復元
--
-- 保存するもの: すべての workspace の window / tab / pane の配置と各 pane の cwd、
--              アクティブな workspace / tab / pane、pane で動いている nvim / claude
-- 保存するとき: 自動 (autosave_interval_seconds ごと。変化がなければ書かない) と leader + S
-- 復元するとき: WezTerm の起動時 (gui-startup)
--
-- nvim と claude は、自分がどの pane で動いているかを環境変数 WEZTERM_PANE から知り、
-- panes/<pane_id>.nvim.json・panes/<pane_id>.claude.json という目印ファイルを書く。
--   nvim:   nvim/lua/wezterm_session.lua (編集状態は :mksession で nvim/<pid>.vim に書く)
--   claude: wezterm/claude_session_hook.ps1 (Claude Code の SessionStart / SessionEnd hook)
-- pane_id は起動のたびに 0 から振り直されるので、目印ファイルは起動時に消す
local wezterm = require("wezterm")
local mux = wezterm.mux

local M = {}

-- 自動保存の間隔 (秒)
M.autosave_interval_seconds = 10

-- 環境変数で置き場所を変えられる (試験用に別の WezTerm を起動するときなど)
local session_dir = os.getenv("WEZTERM_WORKSPACE_SESSION_DIR")
  or ((os.getenv("LOCALAPPDATA") or wezterm.home_dir) .. "\\wezterm\\workspace_session")
local state_file = session_dir .. "\\state.json"
local panes_dir = session_dir .. "\\panes"

-- 復元した pane で nvim / claude を起動するシェル (config.default_prog)
local shell = { "pwsh.exe" }

----------------------------------------------------
-- ファイル操作
----------------------------------------------------
local function read_file(path)
  local f = path and io.open(path, "rb")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function file_exists(path)
  local f = path and io.open(path, "rb")
  if f then
    f:close()
  end
  return f ~= nil
end

local function read_json(path)
  local content = read_file(path)
  if not content then
    return nil
  end
  -- PowerShell などが付ける UTF-8 の BOM を落とす
  content = content:gsub("^\239\187\191", "")
  local ok, value = pcall(wezterm.json_parse, content)
  if ok then
    return value
  end
  wezterm.log_warn("workspace_session: " .. path .. " を読めない: " .. tostring(value))
  return nil
end

local function list_dir(path)
  local ok, entries = pcall(wezterm.read_dir, path)
  return ok and entries or {}
end

local function write_state(json)
  local tmp = state_file .. ".tmp"
  local f = io.open(tmp, "wb")
  if not f then
    wezterm.run_child_process({ "cmd.exe", "/c", "mkdir", session_dir })
    f = io.open(tmp, "wb")
  end
  if not f then
    wezterm.log_error("workspace_session: " .. tmp .. " に書けない")
    return false
  end
  f:write(json)
  f:close()
  -- Windows の os.rename は移動先があると失敗するので先に消す
  os.remove(state_file)
  local ok, err = os.rename(tmp, state_file)
  if not ok then
    wezterm.log_error("workspace_session: " .. state_file .. " に置けない: " .. tostring(err))
  end
  return ok
end

----------------------------------------------------
-- 保存
----------------------------------------------------
local function pane_cwd(pane)
  local url = pane:get_current_working_dir()
  if not url then
    return nil
  end
  -- Windows では "/C:/Users/..." の形なので先頭の "/" を落とす
  return (url.file_path:gsub("^/(%a:)", "%1"))
end

-- panes/ の目印ファイルを { ["<pane_id>"] = { nvim = {...}, claude = {...} } } の形で読む
local function read_markers()
  local markers = {}
  for _, path in ipairs(list_dir(panes_dir)) do
    local pane_id, kind = path:match("(%d+)%.(%a+)%.json$")
    if pane_id then
      markers[pane_id] = markers[pane_id] or {}
      markers[pane_id][kind] = read_json(path)
    end
  end
  return markers
end
-- claude_status.lua でも使う
M.read_markers = read_markers

local function pane_program(markers, pane_id)
  local marker = markers[tostring(pane_id)]
  if not marker then
    return nil
  end
  -- claude が外部エディタとして nvim を開いているときは目印が両方あるので、claude を優先する
  local claude = marker.claude
  if claude and claude.session_id then
    return {
      name = "claude",
      session_id = claude.session_id,
      cwd = claude.cwd,
      -- 一度も発言していない会話は --resume できない
      resume = file_exists(claude.transcript_path),
    }
  end
  local nvim = marker.nvim
  if nvim and nvim.session_file then
    return { name = "nvim", session_file = nvim.session_file }
  end
  return nil
end

local function snapshot()
  local markers = read_markers()
  local windows = {}
  for _, mux_window in ipairs(mux.all_windows()) do
    local tabs = {}
    for _, tab_info in ipairs(mux_window:tabs_with_info()) do
      local tab = tab_info.tab
      local panes = {}
      for _, info in ipairs(tab:panes_with_info()) do
        table.insert(panes, {
          left = info.left,
          top = info.top,
          width = info.width,
          height = info.height,
          is_active = info.is_active,
          is_zoomed = info.is_zoomed,
          cwd = pane_cwd(info.pane),
          program = pane_program(markers, info.pane:pane_id()),
        })
      end
      local size = tab:get_size()
      table.insert(tabs, {
        title = tab:get_title(),
        is_active = tab_info.is_active,
        cols = size.cols,
        rows = size.rows,
        panes = panes,
      })
    end
    table.insert(windows, { workspace = mux_window:get_workspace(), tabs = tabs })
  end
  return { version = 1, active_workspace = mux.get_active_workspace(), windows = windows }
end

-- force が false なら、前回保存したときから変わっていなければ書かない
function M.save(force)
  local state = snapshot()
  -- 終了処理の途中などで window が無いときに、保存済みの内容を空で上書きしない
  if #state.windows == 0 then
    return false
  end
  local json = wezterm.json_encode(state)
  if not force and json == wezterm.GLOBAL.workspace_session_last_json then
    return true
  end
  if not write_state(json) then
    return false
  end
  wezterm.GLOBAL.workspace_session_last_json = json
  return true
end

function M.save_action()
  return wezterm.action_callback(function(window, pane)
    if M.save(true) then
      -- 手動で保存したら、それ以降は自動保存も有効にする
      wezterm.GLOBAL.workspace_session_autosave = true
      window:toast_notification("WezTerm", "workspace を保存しました", nil, 3000)
    else
      window:toast_notification("WezTerm", "workspace を保存できませんでした (Debug Overlay を参照)", nil, 5000)
    end
  end)
end

-- すべての workspace を保存してから WezTerm を終了する。
-- window を閉じる (Alt+F4 など) と、その workspace だけが閉じて保存内容からも消える
function M.quit_action()
  return wezterm.action_callback(function(window, pane)
    M.save(true)
    -- 終了処理中の自動保存で内容を減らさない
    wezterm.GLOBAL.workspace_session_autosave = false
    window:perform_action(wezterm.action.QuitApplication, pane)
  end)
end

----------------------------------------------------
-- 復元
----------------------------------------------------
-- PowerShell の単一引用符文字列にする
local function pwsh_quote(s)
  return "'" .. s:gsub("'", "''") .. "'"
end

-- nvim / claude を起動してから対話シェルに戻る引数。program が無ければ nil (= default_prog)
local function spawn_args(program, cwd)
  if not program then
    return nil
  end
  local command
  if program.name == "nvim" then
    command = file_exists(program.session_file) and ("nvim -S " .. pwsh_quote(program.session_file)) or "nvim"
  elseif program.name == "claude" then
    command = program.resume and ("claude --resume " .. pwsh_quote(program.session_id)) or "claude"
  else
    return nil
  end
  -- pane:split に args を渡すと、cwd は無視されて分割元の pane の cwd で起動される
  -- (WezTerm 20240203 の Mux::split_pane)。PowerShell は外部コマンドを今いる場所で
  -- 起動するので、先に移動しておく。移動できなければ起動せず、シェルだけを残す。
  -- profile で Set-Location を置き換えている (引数が違う) ので、モジュール名付きで呼ぶ。
  -- WezTerm が知っている cwd は分割元のままなので、OSC 7 で移動先を知らせ直す
  if cwd then
    command = "Microsoft.PowerShell.Management\\Set-Location -LiteralPath " .. pwsh_quote(cwd)
      .. " -ErrorAction Stop; "
      .. "$Host.UI.Write([char]27 + ']7;file://localhost/' + (Get-Location).ProviderPath + [char]27 + '\\'); "
      .. command
  end
  local args = {}
  for _, arg in ipairs(shell) do
    table.insert(args, arg)
  end
  table.insert(args, "-NoExit")
  table.insert(args, "-Command")
  table.insert(args, command)
  return args
end

local function spawn_options(saved_pane)
  local program = saved_pane.program
  -- claude の会話は起動したディレクトリに紐づくので、その cwd で再開する
  local cwd = (program and program.cwd) or saved_pane.cwd
  return { cwd = cwd, args = spawn_args(program, cwd) }
end

local axes = {
  { pos = "left", size = "width", direction = "Right" },
  { pos = "top", size = "height", direction = "Bottom" },
}

local function extent(panes, axis)
  local low, high = math.huge, 0
  for _, p in ipairs(panes) do
    low = math.min(low, p[axis.pos])
    high = math.max(high, p[axis.pos] + p[axis.size])
  end
  return low, high
end

-- panes を左右か上下の 2 組に分ける切れ目を探す。切れ目には 1 セル幅の境界線があるので、
-- 手前の組は pos + size <= cut、奥の組は pos > cut になる。見つからなければ nil
local function split_panes(panes)
  for _, axis in ipairs(axes) do
    local cuts = {}
    for _, p in ipairs(panes) do
      table.insert(cuts, p[axis.pos] + p[axis.size])
    end
    table.sort(cuts)
    for _, cut in ipairs(cuts) do
      local first, second = {}, {}
      for _, p in ipairs(panes) do
        if p[axis.pos] + p[axis.size] <= cut then
          table.insert(first, p)
        elseif p[axis.pos] > cut then
          table.insert(second, p)
        else
          first = nil
          break
        end
      end
      if first and #first > 0 and #second > 0 then
        return first, second, axis
      end
    end
  end
  return nil
end

-- 分割を繰り返したときに、最初の pane のまま残るもの (左上の pane)
local function first_pane(panes)
  local first = split_panes(panes)
  if not first then
    return panes[1]
  end
  return first_pane(first)
end

-- mux_pane (panes 全体の領域を占めている) を分割して panes の配置を作る。
-- created[保存した pane] = 作った mux の pane
local function build_layout(mux_pane, panes, created)
  local first, second, axis = split_panes(panes)
  if not first then
    if #panes > 1 then
      wezterm.log_warn("workspace_session: 分割の仕方が分からない pane があるので 1 つにまとめる")
    end
    created[panes[1]] = mux_pane
    return
  end
  local all_low, all_high = extent(panes, axis)
  local low, high = extent(second, axis)
  local options = spawn_options(first_pane(second))
  options.direction = axis.direction
  options.size = (high - low) / (all_high - all_low)
  local new_pane = mux_pane:split(options)
  build_layout(mux_pane, first, created)
  build_layout(new_pane, second, created)
end

local function restore(state)
  local active_tab_ids = {}
  for _, saved_window in ipairs(state.windows or {}) do
    local mux_window, active_tab
    for _, saved_tab in ipairs(saved_window.tabs or {}) do
      if #(saved_tab.panes or {}) > 0 then
        local options = spawn_options(first_pane(saved_tab.panes))
        local tab, pane
        if not mux_window then
          options.workspace = saved_window.workspace
          -- 保存したときと同じセル数で作ると、分割の比率がそのまま再現される
          options.width = saved_tab.cols
          options.height = saved_tab.rows
          tab, pane, mux_window = mux.spawn_window(options)
        else
          tab, pane = mux_window:spawn_tab(options)
        end

        local created = {}
        build_layout(pane, saved_tab.panes, created)
        for saved_pane, mux_pane in pairs(created) do
          if saved_pane.is_active then
            mux_pane:activate()
            if saved_pane.is_zoomed then
              tab:set_zoomed(true)
            end
          end
        end
        if saved_tab.title and saved_tab.title ~= "" then
          tab:set_title(saved_tab.title)
        end
        if saved_tab.is_active then
          active_tab = tab
        end
      end
    end
    if active_tab then
      active_tab:activate()
      table.insert(active_tab_ids, active_tab:tab_id())
    end
  end
  if state.active_workspace then
    mux.set_active_workspace(state.active_workspace)
  end
  -- GUI の初期化で各 window のアクティブなタブが先頭に戻されるので、GUI が動き出してから
  -- (最初の update-right-status で) もう一度切り替える
  wezterm.GLOBAL.workspace_session_pending_tabs = table.concat(active_tab_ids, ",")
end

local function activate_pending_tabs()
  local pending = wezterm.GLOBAL.workspace_session_pending_tabs
  if not pending then
    return
  end
  wezterm.GLOBAL.workspace_session_pending_tabs = nil
  for tab_id in pending:gmatch("%d+") do
    local ok, tab = pcall(mux.get_tab, tonumber(tab_id))
    if ok and tab then
      tab:activate()
    end
  end
end

local function clear_markers()
  for _, path in ipairs(list_dir(panes_dir)) do
    os.remove(path)
  end
end

----------------------------------------------------
-- 設定への組み込み
----------------------------------------------------
function M.apply_to_config(config)
  shell = config.default_prog or shell

  -- nvim と Claude Code の hook が目印ファイルの置き場所を知るための環境変数
  config.set_environment_variables = config.set_environment_variables or {}
  config.set_environment_variables.WEZTERM_WORKSPACE_SESSION_DIR = session_dir

  -- まだ一度も保存していなければ、この機能を入れる前から動いている WezTerm でも自動保存してよい
  if wezterm.GLOBAL.workspace_session_autosave == nil and not file_exists(state_file) then
    wezterm.GLOBAL.workspace_session_autosave = true
  end

  wezterm.on("gui-startup", function(cmd)
    -- `wezterm start -- <prog>` や `--cwd` のように起動のしかたを指定されたときは復元しない。
    -- このとき自動保存もしないので、保存済みの workspace は上書きされない
    if cmd and (cmd.args or cmd.cwd) then
      wezterm.GLOBAL.workspace_session_autosave = false
      return
    end
    clear_markers()
    local state = read_json(state_file)
    if state and state.windows and #state.windows > 0 then
      local ok, err = pcall(restore, state)
      if not ok then
        -- 途中までしか復元できていない状態で保存済みの内容を上書きしないよう、自動保存を止める
        wezterm.log_error("workspace_session: 復元に失敗: " .. tostring(err))
        wezterm.GLOBAL.workspace_session_autosave = false
        return
      end
    end
    wezterm.GLOBAL.workspace_session_autosave = true
  end)

  -- 定期的に呼ばれるイベントを自動保存のタイマー代わりに使う
  -- (keybinds.lua の update-right-status とは別のハンドラとして並んで呼ばれる)
  wezterm.on("update-right-status", function(window, pane)
    activate_pending_tabs()
    if not wezterm.GLOBAL.workspace_session_autosave then
      return
    end
    local now = os.time()
    if now - (wezterm.GLOBAL.workspace_session_saved_at or 0) < M.autosave_interval_seconds then
      return
    end
    wezterm.GLOBAL.workspace_session_saved_at = now
    M.save(false)
  end)
end

return M
