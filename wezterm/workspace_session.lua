-- workspace の保存と、WezTerm 起動時の復元
--
-- 保存するもの: すべての workspace の window / tab / pane の配置と各 pane の cwd、
--              アクティブな workspace / tab / pane、pane で動いている nvim / claude
-- 保存するとき: 自動 (autosave_interval_seconds ごと。変化がなければ書かない) と leader + S
-- 復元するとき: WezTerm の起動時 (gui-startup)
--
-- ブックマーク: workspace を名前で bookmarks.json に登録しておき、閉じたあとでも一覧から開き直せる。
--   leader + B: 今の workspace を登録 (登録済みなら上書き)
--   leader + b: 一覧から開く (開いていればそこへ切り替える) / 一覧から削除
--   leader + W: 今の workspace を登録してから閉じる (メモリを空ける)
--   登録済みの workspace が開いているあいだは、自動保存のたびにブックマークの中身も更新する
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
local bookmarks_file = session_dir .. "\\bookmarks.json"
local panes_dir = session_dir .. "\\panes"

-- 復元した pane で nvim / claude を起動するシェル (config.default_prog)
local shell = { "pwsh.exe" }

-- ほかの wezterm-gui がすでに動いているときに起動した WezTerm (2 つ目) か。
-- 2 つ目は目印ファイルの置き場所を 1 つ目と共有してしまうので、この仕組みを使わない
-- (起動時に目印を消さない・復元しない・保存しない・nvim / claude に目印を書かせない)。
-- 起動して最初に設定を読んだとき (apply_to_config) に 1 回だけ決め、設定を読み直しても変えない
local function is_secondary()
  return wezterm.GLOBAL.workspace_session_secondary == true
end

local function is_gui_process()
  local ok, info = pcall(wezterm.procinfo.get_info_for_pid, wezterm.procinfo.pid())
  return ok and info and info.executable and info.executable:lower():match("wezterm%-gui%.exe$") ~= nil
end

local function other_gui_running()
  local ok, stdout = wezterm.run_child_process({
    "tasklist.exe", "/FI", "IMAGENAME eq wezterm-gui.exe", "/FO", "CSV", "/NH",
  })
  if not ok then
    return false
  end
  local count = 0
  for _ in stdout:lower():gmatch('"wezterm%-gui%.exe"') do
    count = count + 1
  end
  -- この WezTerm 自身も数に入る
  return count > 1
end

-- 起動したばかりの WezTerm はまだ window を持っていない。window があるのに未判定なのは、
-- この判定を入れる前から動いている WezTerm が設定を読み直したときなので、2 つ目ではない
local function has_windows()
  local ok, windows = pcall(mux.all_windows)
  return ok and windows and #windows > 0
end

-- run_child_process は require で読み込んでいる最中には呼べない
-- (attempt to yield across a C-call boundary) ので、apply_to_config から呼ぶ
local function decide_secondary()
  if wezterm.GLOBAL.workspace_session_secondary == nil and is_gui_process() then
    wezterm.GLOBAL.workspace_session_secondary = not has_windows() and other_gui_running()
  end
end

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

local function write_file(path, json)
  local tmp = path .. ".tmp"
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
  os.remove(path)
  local ok, err = os.rename(tmp, path)
  if not ok then
    wezterm.log_error("workspace_session: " .. path .. " に置けない: " .. tostring(err))
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
  -- 2 つ目の WezTerm から見ると、目印は 1 つ目の pane のもの
  if is_secondary() then
    return markers
  end
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

----------------------------------------------------
-- ブックマークの読み書き
----------------------------------------------------
-- bookmarks.json: { version = 1, bookmarks = { { name = "<workspace>", windows = {...} }, ... } }
-- windows は state.json の windows のうち、その workspace のもの
local function read_bookmarks()
  local data = read_json(bookmarks_file)
  return (data and data.bookmarks) or {}
end

-- 前回書いたときから変わっていなければ書かない
local function write_bookmarks(list)
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  local json = wezterm.json_encode({ version = 1, bookmarks = list })
  if json == wezterm.GLOBAL.workspace_session_bookmarks_json then
    return true
  end
  if not write_file(bookmarks_file, json) then
    return false
  end
  wezterm.GLOBAL.workspace_session_bookmarks_json = json
  return true
end

local function find_bookmark(list, name)
  for i, bookmark in ipairs(list) do
    if bookmark.name == name then
      return i
    end
  end
  return nil
end

local function workspace_windows(state, name)
  local windows = {}
  for _, saved_window in ipairs(state.windows) do
    if saved_window.workspace == name then
      table.insert(windows, saved_window)
    end
  end
  return windows
end

local function is_open(name)
  for _, open_name in ipairs(mux.get_workspace_names()) do
    if open_name == name then
      return true
    end
  end
  return false
end

-- 開いている登録済みの workspace のブックマークを、今の状態で更新する。
-- 閉じている最中の workspace (pane が少しずつ消えていく) は更新しない
local function update_open_bookmarks(state)
  local list = read_bookmarks()
  for _, bookmark in ipairs(list) do
    if bookmark.name ~= wezterm.GLOBAL.workspace_session_closing then
      local windows = workspace_windows(state, bookmark.name)
      if #windows > 0 then
        bookmark.windows = windows
      end
    end
  end
  write_bookmarks(list)
end

-- force が false なら、前回保存したときから変わっていなければ書かない
function M.save(force)
  -- 2 つ目の WezTerm の画面で、1 つ目が保存した内容を上書きしない
  if is_secondary() then
    return false
  end
  local state = snapshot()
  -- 終了処理の途中などで window が無いときに、保存済みの内容を空で上書きしない
  if #state.windows == 0 then
    return false
  end
  if file_exists(bookmarks_file) then
    update_open_bookmarks(state)
  end
  local json = wezterm.json_encode(state)
  if not force and json == wezterm.GLOBAL.workspace_session_last_json then
    return true
  end
  if not write_file(state_file, json) then
    return false
  end
  wezterm.GLOBAL.workspace_session_last_json = json
  return true
end

function M.save_action()
  return wezterm.action_callback(function(window, pane)
    if is_secondary() then
      window:toast_notification("WezTerm", "ほかの WezTerm が動いているあいだに起動したので、この WezTerm では保存しません", nil, 5000)
      return
    end
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

-- windows を作り、各 window のアクティブなタブの tab_id を返す
local function restore_windows(windows)
  local active_tab_ids = {}
  for _, saved_window in ipairs(windows) do
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
  -- GUI の初期化 (workspace の切り替え) で各 window のアクティブなタブが先頭に戻されるので、
  -- GUI が動き出してから (次の update-right-status で) もう一度切り替える
  wezterm.GLOBAL.workspace_session_pending_tabs = table.concat(active_tab_ids, ",")
end

local function restore(state)
  restore_windows(state.windows or {})
  if state.active_workspace then
    mux.set_active_workspace(state.active_workspace)
  end
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
-- ブックマークの操作
----------------------------------------------------
local function toast(window, message, ms)
  window:toast_notification("WezTerm", message, nil, ms or 3000)
end

local function secondary_toast(window)
  toast(window, "ほかの WezTerm が動いているあいだに起動したので、この WezTerm ではブックマークを使えません", 5000)
end

-- 今の状態で name のブックマークを登録 / 上書きする
local function bookmark_workspace(name)
  local windows = workspace_windows(snapshot(), name)
  if #windows == 0 then
    return false
  end
  local list = read_bookmarks()
  local i = find_bookmark(list, name)
  if i then
    list[i].windows = windows
  else
    table.insert(list, { name = name, windows = windows })
  end
  return write_bookmarks(list), i ~= nil
end

-- name の workspace に切り替える。開いていなくて登録済みなら、ブックマークから作り直す。
-- 登録していなければ新しい workspace になる (SwitchToWorkspace と同じ)
function M.switch_to(window, pane, name)
  if not is_open(name) and not is_secondary() then
    local list = read_bookmarks()
    local i = find_bookmark(list, name)
    if i then
      local windows = {}
      for _, saved_window in ipairs(list[i].windows or {}) do
        saved_window.workspace = name
        table.insert(windows, saved_window)
      end
      local ok, err = pcall(restore_windows, windows)
      if not ok then
        wezterm.log_error("workspace_session: " .. name .. " を開けない: " .. tostring(err))
        toast(window, name .. " を開けませんでした (Debug Overlay を参照)", 5000)
      end
    end
  end
  window:perform_action(wezterm.action.SwitchToWorkspace({ name = name }), pane)
end

function M.bookmark_action()
  return wezterm.action_callback(function(window, pane)
    if is_secondary() then
      return secondary_toast(window)
    end
    local name = window:active_workspace()
    local ok, updated = bookmark_workspace(name)
    if ok then
      toast(window, string.format("%s を%s", name, updated and "ブックマークし直しました" or "ブックマークしました"))
    else
      toast(window, name .. " をブックマークできませんでした (Debug Overlay を参照)", 5000)
    end
  end)
end

local function bookmark_label(bookmark)
  local tabs, cwd = 0, nil
  for _, saved_window in ipairs(bookmark.windows or {}) do
    for _, saved_tab in ipairs(saved_window.tabs or {}) do
      tabs = tabs + 1
      for _, saved_pane in ipairs(saved_tab.panes or {}) do
        cwd = cwd or saved_pane.cwd
      end
    end
  end
  return string.format(
    "%s %s  (%d tabs)  %s",
    is_open(bookmark.name) and wezterm.nerdfonts.cod_circle_filled or wezterm.nerdfonts.cod_circle_outline,
    bookmark.name,
    tabs,
    cwd or ""
  )
end

-- 削除の項目の id (workspace の名前と重ならないもの)
local DELETE_ID = "<delete bookmarks>"

local function delete_selector(window, pane, list)
  local choices = {}
  for _, bookmark in ipairs(list) do
    table.insert(choices, { id = bookmark.name, label = bookmark_label(bookmark) })
  end
  window:perform_action(
    wezterm.action.InputSelector({
      title = "削除するブックマーク (workspace は閉じない)",
      choices = choices,
      action = wezterm.action_callback(function(win, p, name)
        if not name then
          return
        end
        local current = read_bookmarks()
        local i = find_bookmark(current, name)
        if i then
          table.remove(current, i)
          write_bookmarks(current)
          toast(win, name .. " のブックマークを削除しました")
        end
      end),
    }),
    pane
  )
end

-- 一覧から開く。開いている workspace には ● が付く
function M.bookmarks_action()
  return wezterm.action_callback(function(window, pane)
    if is_secondary() then
      return secondary_toast(window)
    end
    local list = read_bookmarks()
    if #list == 0 then
      return toast(window, "ブックマークはまだありません (leader + B で今の workspace を登録)")
    end
    local choices = {}
    for _, bookmark in ipairs(list) do
      table.insert(choices, { id = bookmark.name, label = bookmark_label(bookmark) })
    end
    table.insert(choices, { id = DELETE_ID, label = wezterm.nerdfonts.cod_trash .. " ブックマークを削除..." })
    window:perform_action(
      wezterm.action.InputSelector({
        title = "Workspace bookmarks",
        choices = choices,
        fuzzy = true,
        action = wezterm.action_callback(function(win, p, name)
          if name == DELETE_ID then
            delete_selector(win, p, list)
          elseif name then
            M.switch_to(win, p, name)
          end
        end),
      }),
      pane
    )
  end)
end

-- name を閉じたあとに切り替える先。ほかに開いている workspace が無ければ、
-- 登録していない名前で新しく作る (登録済みの名前で作ると、自動保存でブックマークが上書きされる)
local function fallback_workspace(name)
  for _, open_name in ipairs(mux.get_workspace_names()) do
    if open_name ~= name then
      return open_name
    end
  end
  local list = read_bookmarks()
  local candidate, n = "default", 1
  while candidate == name or find_bookmark(list, candidate) do
    n = n + 1
    candidate = "default-" .. n
  end
  return candidate
end

local function close_workspace(window, pane, name)
  if not bookmark_workspace(name) then
    return toast(window, name .. " をブックマークできなかったので閉じません (Debug Overlay を参照)", 5000)
  end
  local pane_ids = {}
  for _, mux_window in ipairs(mux.all_windows()) do
    if mux_window:get_workspace() == name then
      for _, tab in ipairs(mux_window:tabs()) do
        for _, p in ipairs(tab:panes()) do
          table.insert(pane_ids, p:pane_id())
        end
      end
    end
  end
  wezterm.GLOBAL.workspace_session_closing = name
  -- 表示中の workspace の pane を消すと GUI の window ごと閉じてしまうので、先に切り替える
  if window:active_workspace() == name then
    window:perform_action(wezterm.action.SwitchToWorkspace({ name = fallback_workspace(name) }), pane)
  end
  -- Lua から pane を閉じる API が無いので wezterm cli を使う (この WezTerm の
  -- WEZTERM_UNIX_SOCKET を受け継ぐので、この WezTerm の pane が閉じる)。
  -- 切り替えが終わってから閉じる
  local cli = wezterm.executable_dir .. "\\wezterm.exe"
  wezterm.time.call_after(0.5, function()
    for _, id in ipairs(pane_ids) do
      local ok, _, stderr = wezterm.run_child_process({ cli, "cli", "kill-pane", "--pane-id", tostring(id) })
      if not ok then
        wezterm.log_warn("workspace_session: pane " .. id .. " を閉じられない: " .. tostring(stderr))
      end
    end
    -- pane が消え終わってから、state.json からもこの workspace を消す
    wezterm.time.call_after(2, function()
      wezterm.GLOBAL.workspace_session_closing = nil
      M.save(true)
    end)
  end)
  toast(window, name .. " をブックマークして閉じました (leader + b で開き直せます)")
end

function M.close_workspace_action()
  return wezterm.action_callback(function(window, pane)
    if is_secondary() then
      return secondary_toast(window)
    end
    local name = window:active_workspace()
    window:perform_action(
      wezterm.action.InputSelector({
        title = name .. " をブックマークして閉じる",
        choices = {
          {
            id = "close",
            label = "閉じる (nvim の保存していない変更は、開き直したときにスワップファイルから復元する)",
          },
          { id = "cancel", label = "やめる" },
        },
        action = wezterm.action_callback(function(win, p, id)
          if id == "close" then
            close_workspace(win, p, name)
          end
        end),
      }),
      pane
    )
  end)
end

----------------------------------------------------
-- 設定への組み込み
----------------------------------------------------
function M.apply_to_config(config)
  shell = config.default_prog or shell
  decide_secondary()

  -- nvim と Claude Code の hook が目印ファイルの置き場所を知るための環境変数。
  -- 2 つ目の WezTerm では空にして、目印を書かせない (1 つ目の WezTerm の中から起動したときに
  -- 受け継いだ値も空で上書きする)
  config.set_environment_variables = config.set_environment_variables or {}
  config.set_environment_variables.WEZTERM_WORKSPACE_SESSION_DIR = is_secondary() and "" or session_dir

  -- まだ一度も保存していなければ、この機能を入れる前から動いている WezTerm でも自動保存してよい
  if wezterm.GLOBAL.workspace_session_autosave == nil and not file_exists(state_file) then
    wezterm.GLOBAL.workspace_session_autosave = true
  end

  wezterm.on("gui-startup", function(cmd)
    -- 2 つ目の WezTerm は、1 つ目の目印を消さず、復元もしない (ふつうの新しい window になる)
    if is_secondary() then
      wezterm.log_info("workspace_session: ほかの wezterm-gui が動いているので復元・保存しない")
      wezterm.GLOBAL.workspace_session_autosave = false
      return
    end
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
