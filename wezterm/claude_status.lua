-- すべての workspace で動いている Claude Code の状態を表示する
--
-- leader + c:       一覧を開く。選ぶとその workspace に切り替えて、その pane に移る
-- ステータスバー:    状態ごとの件数 (keybinds.lua の update-right-status から呼ぶ)
--
-- 状態は wezterm/claude_session_hook.ps1 (Claude Code の hook) が panes/<pane_id>.status.json に書く。
-- 会話の session_id は panes/<pane_id>.claude.json にある (workspace_session.lua と共用)
local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action
local workspace_session = require("workspace_session")

local M = {}

-- 一覧でもステータスバーでもこの順に並べる (Tokyo Night の色)
-- icon は一覧用、glyph はステータスバー用 (Nerd Font のアイコン)
local nf = wezterm.nerdfonts
local state_order = { "waiting", "error", "done", "running", "idle" }
local states = {
  waiting = { icon = "?", glyph = nf.md_bell_ring, label = "確認待ち", color = "#e0af68" },
  error = { icon = "✗", glyph = nf.md_alert_circle, label = "エラー", color = "#f7768e" },
  -- 完了してから、まだその pane を見ていない
  done = { icon = "✓", glyph = nf.md_check_circle, label = "完了", color = "#9ece6a" },
  running = { icon = "●", glyph = nf.md_loading, label = "実行中", color = "#7aa2f7" },
  idle = { icon = "·", glyph = nf.md_sleep, label = "待機", color = "#565f89" },
}

-- 完了した pane を見たら、その完了 (event_at) を見たことを覚えておき、待機として表示する
local function seen_key(pane_id)
  return "claude_status_seen_" .. tostring(pane_id)
end

local function tab_index(mux_window, tab)
  for _, info in ipairs(mux_window:tabs_with_info()) do
    if info.tab:tab_id() == tab:tab_id() then
      return info.index + 1
    end
  end
  return 0
end

-- 動いている Claude Code を workspace・タブの順に並べて返す
local function collect()
  local items = {}
  for pane_id, marker in pairs(workspace_session.read_markers()) do
    local claude = marker.claude
    local ok, pane = pcall(mux.get_pane, tonumber(pane_id))
    local tab = ok and pane and pane:tab()
    local mux_window = tab and tab:window()
    if claude and claude.session_id and mux_window then
      local status = marker.status
      -- /clear の直後などで、前の会話の状態が残っていたら使わない
      if status and status.session_id ~= claude.session_id then
        status = nil
      end
      local state = status and states[status.state] and status.state or "idle"
      local event_at = status and status.event_at
      if state == "done" and wezterm.GLOBAL[seen_key(pane_id)] == tostring(event_at) then
        state = "idle"
      end
      table.insert(items, {
        pane_id = pane:pane_id(),
        workspace = mux_window:get_workspace(),
        tab_index = tab_index(mux_window, tab),
        title = pane:get_title(),
        folder = claude.cwd and claude.cwd:match("[^\\/]+$") or "",
        state = state,
        event_at = event_at,
      })
    end
  end
  table.sort(items, function(a, b)
    if a.workspace ~= b.workspace then
      return a.workspace < b.workspace
    end
    if a.tab_index ~= b.tab_index then
      return a.tab_index < b.tab_index
    end
    return a.pane_id < b.pane_id
  end)
  return items
end

local function elapsed(event_at)
  if not event_at then
    return ""
  end
  -- event_at はミリ秒。JSON から小数として読めても整数にそろえる
  local seconds = math.max(0, os.time() - math.floor(event_at / 1000))
  if seconds < 60 then
    return seconds .. "秒前"
  elseif seconds < 3600 then
    return seconds // 60 .. "分前"
  end
  return seconds // 3600 .. "時間前"
end

----------------------------------------------------
-- ステータスバー
----------------------------------------------------
-- タブと同じ斜めの端で囲んだ札を並べる
local LEFT_EDGE = nf.ple_lower_right_triangle
local RIGHT_EDGE = nf.ple_upper_left_triangle
-- 実行中の札で回す。update-right-status (既定で1秒ごと) のたびに1コマ進む
local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
-- 先頭の「Claude」の札の色
local HEADER_BG = "#3b4261"
local HEADER_FG = "#c0caf5"
-- 状態の札の文字色 (ターミナルの背景色と同じ)
local CHIP_FG = "#1a1b26"

-- 札の中で、斜めの端と文字のあいだに入れる空白
local SEGMENT_PADDING = ""
-- 札と札のあいだの空白 (斜めの端どうしのあいだに、これに加えて1文字分ほどの隙間ができる)
local SEGMENT_GAP = ""

-- 札と札のあいだを空ける
function M.add_gap(cells)
  if SEGMENT_GAP ~= "" then
    table.insert(cells, { Text = SEGMENT_GAP })
  end
end

-- keybinds.lua の workspace 名の札でも使う
function M.add_segment(cells, bg, fg, text)
  text = SEGMENT_PADDING .. text .. SEGMENT_PADDING
  table.insert(cells, { Background = { Color = "none" } })
  table.insert(cells, { Foreground = { Color = bg } })
  table.insert(cells, { Text = LEFT_EDGE })
  table.insert(cells, { Background = { Color = bg } })
  table.insert(cells, { Foreground = { Color = fg } })
  table.insert(cells, { Attribute = { Intensity = "Bold" } })
  table.insert(cells, { Text = text })
  table.insert(cells, "ResetAttributes")
  table.insert(cells, { Background = { Color = "none" } })
  table.insert(cells, { Foreground = { Color = bg } })
  table.insert(cells, { Text = RIGHT_EDGE })
end

-- update-right-status から毎回呼ぶ。見ている pane の完了を既読にして、件数の表示を返す
-- compact: タブが多くて幅が足りないときに、状態の名前 (確認待ち など) を省いてアイコンと件数だけにする
function M.status_cells(window, pane, compact)
  local items = collect()
  local counts = {}
  for _, item in ipairs(items) do
    if item.state == "done" and item.pane_id == pane:pane_id() and window:is_focused() then
      wezterm.GLOBAL[seen_key(item.pane_id)] = tostring(item.event_at)
      item.state = "idle"
    end
    counts[item.state] = (counts[item.state] or 0) + 1
  end
  local cells = {}
  if #items == 0 then
    return cells
  end
  -- 先頭に、動いている Claude Code の総数
  local header = compact and string.format("%s %d", nf.md_robot, #items)
    or string.format("%s Claude %d", nf.md_robot, #items)
  M.add_segment(cells, HEADER_BG, HEADER_FG, header)
  for _, state in ipairs(state_order) do
    -- 待機は数えても仕方がないので出さない
    if state ~= "idle" and counts[state] then
      local glyph = states[state].glyph
      if state == "running" then
        glyph = SPINNER[os.time() % #SPINNER + 1]
      end
      M.add_gap(cells)
      M.add_segment(
        cells,
        states[state].color,
        CHIP_FG,
        compact and string.format("%s %d", glyph, counts[state])
          or string.format("%s %s %d", glyph, states[state].label, counts[state])
      )
    end
  end
  M.add_gap(cells)
  return cells
end

----------------------------------------------------
-- 一覧
----------------------------------------------------
local function choice_label(item)
  local state = states[item.state]
  return wezterm.format({
    { Foreground = { Color = state.color } },
    { Text = state.icon .. " " .. wezterm.pad_right(state.label, 8) },
    "ResetAttributes",
    { Text = "  " .. wezterm.pad_right(item.workspace, 16) },
    { Text = "  tab " .. item.tab_index },
    { Text = "  " .. wezterm.pad_right(item.folder, 16) },
    { Text = "  " .. item.title },
    { Foreground = { Color = states.idle.color } },
    { Text = "  " .. elapsed(item.event_at) },
  })
end

local function jump(window, pane, id)
  local ok, target = pcall(mux.get_pane, tonumber(id))
  local tab = ok and target and target:tab()
  local mux_window = tab and tab:window()
  if not mux_window then
    return
  end
  window:perform_action(act.SwitchToWorkspace({ name = mux_window:get_workspace() }), pane)
  tab:activate()
  target:activate()
end

function M.selector_action()
  return wezterm.action_callback(function(window, pane)
    local items = collect()
    if #items == 0 then
      window:toast_notification("WezTerm", "Claude Code は動いていません", nil, 3000)
      return
    end
    local choices = {}
    for _, item in ipairs(items) do
      table.insert(choices, { id = tostring(item.pane_id), label = choice_label(item) })
    end
    window:perform_action(
      act.InputSelector({
        title = "Claude Code",
        choices = choices,
        action = wezterm.action_callback(function(win, p, id)
          if id then
            jump(win, p, id)
          end
        end),
      }),
      pane
    )
  end)
end

return M
