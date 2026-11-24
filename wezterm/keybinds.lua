local wezterm = require("wezterm")
local act = wezterm.action
local claude_status = require("claude_status")

-- キーテーブル (モード) ごとの表示名と背景色 (Tokyo Night の配色)
local key_table_labels = {
  claude_scroll = { text = "CLAUDE SCROLL", color = "#ff9e64" },
  copy_mode = { text = "COPY", color = "#e0af68" },
  resize_pane = { text = "RESIZE", color = "#7aa2f7" },
  activate_pane = { text = "PANE", color = "#9ece6a" },
}

-- 右端の workspace 名の札の色
local WORKSPACE_BG = "#bb9af7"
local WORKSPACE_FG = "#1a1b26"

-- Show which key table is active, the Claude Code states and the workspace name in the status area
wezterm.on("update-right-status", function(window, pane)
  local cells = {}
  local name = window:active_key_table()
  if name then
    local label = key_table_labels[name] or { text = name:upper(), color = "#bb9af7" }
    table.insert(cells, { Background = { Color = label.color } })
    table.insert(cells, { Foreground = { Color = "#1a1b26" } })
    table.insert(cells, { Attribute = { Intensity = "Bold" } })
    table.insert(cells, { Text = " " .. label.text .. " " })
    table.insert(cells, "ResetAttributes")
    table.insert(cells, { Text = " " })
  end
  for _, cell in ipairs(claude_status.status_cells(window, pane)) do
    table.insert(cells, cell)
  end
  -- 右端に、この window の workspace 名
  claude_status.add_segment(
    cells,
    WORKSPACE_BG,
    WORKSPACE_FG,
    string.format(" %s %s ", wezterm.nerdfonts.cod_window, window:active_workspace())
  )
  table.insert(cells, { Text = " " })
  window:set_right_status(wezterm.format(cells))
end)

-- workspaceの名前変更
local rename_workspace = act.PromptInputLine({
  description = "(wezterm) Set workspace title:",
  action = wezterm.action_callback(function(win, pane, line)
    if line then
      wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
    end
  end),
})

-- 背景のぼかし (win32_system_backdrop) のあるなしを、この window だけ切り替える
-- 透過 (window_background_opacity) はそのまま
local toggle_blur = wezterm.action_callback(function(window)
  local overrides = window:get_config_overrides() or {}
  if overrides.win32_system_backdrop then
    overrides.win32_system_backdrop = nil
  else
    overrides.win32_system_backdrop = "Disable"
  end
  window:set_config_overrides(overrides)
end)

return {
  keys = {
    {
      -- workspaceの切り替え
      key = "s",
      mods = "LEADER",
      action = act.ShowLauncherArgs({ flags = "WORKSPACES", title = "Select workspace" }),
    },
    -- workspaceの名前変更
    -- Shiftを伴って入力される記号キーは LEADER と LEADER|SHIFT の両方を登録する
    { key = "$", mods = "LEADER", action = rename_workspace },
    { key = "$", mods = "LEADER|SHIFT", action = rename_workspace },
    {
      key = "n",
      mods = "LEADER",
      action = act.PromptInputLine({
        description = "(wezterm) Create new workspace:",
        action = wezterm.action_callback(function(window, pane, line)
          if line then
            -- ブックマーク済みの名前なら、ブックマークから開く
            require("workspace_session").switch_to(window, pane, line)
          end
        end),
      }),
    },
    -- すべての workspace を今すぐ保存 (起動時に復元される。普段は自動保存)
    { key = "S", mods = "LEADER|SHIFT", action = require("workspace_session").save_action() },
    -- すべての workspace を保存して WezTerm を終了 (window を閉じるとその workspace だけが閉じる)
    { key = "q", mods = "LEADER", action = require("workspace_session").quit_action() },
    -- workspace のブックマーク (workspace_session.lua)
    -- 一覧から開く / 今の workspace を登録 / 登録してから閉じる (メモリを空ける)
    { key = "b", mods = "LEADER", action = require("workspace_session").bookmarks_action() },
    { key = "B", mods = "LEADER|SHIFT", action = require("workspace_session").bookmark_action() },
    { key = "W", mods = "LEADER|SHIFT", action = require("workspace_session").close_workspace_action() },
    -- すべての workspace の Claude Code の一覧を開き、選んだ pane に移る
    { key = "c", mods = "LEADER", action = claude_status.selector_action() },
    -- Debug Overlay / REPL を開く
    { key = "L", mods = "LEADER|SHIFT", action = act.ShowDebugOverlay },

    -- Tab移動
    { key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
    { key = "Tab", mods = "SHIFT|CTRL", action = act.ActivateTabRelative(-1) },
    -- Tab入れ替え
    { key = "h", mods = "LEADER|SHIFT", action = act({ MoveTabRelative = -1 }) },
    { key = "l", mods = "LEADER|SHIFT", action = act({ MoveTabRelative = 1 }) },
    -- Tab新規作成
    { key = "t", mods = "LEADER", action = act({ SpawnTab = "CurrentPaneDomain" }) },
    -- Tabを閉じる
    { key = "w", mods = "LEADER", action = act({ CloseCurrentTab = { confirm = true } }) },

    -- 画面フルスクリーン切り替え
    { key = "Enter", mods = "ALT", action = act.ToggleFullScreen },
    -- 背景のぼかしの切り替え
    { key = "g", mods = "LEADER", action = toggle_blur },

    -- 画面スクロール
    -- プロンプト単位で移動 (oh-my-posh の shell_integration が必要)
    { key = "k", mods = "CTRL|SHIFT", action = act.ScrollToPrompt(-1) },
    { key = "j", mods = "CTRL|SHIFT", action = act.ScrollToPrompt(1) },
    -- 半ページスクロール
    { key = "u", mods = "CTRL|SHIFT", action = act.ScrollByPage(-0.5) },
    { key = "d", mods = "CTRL|SHIFT", action = act.ScrollByPage(0.5) },
    -- 一番下へ
    { key = "g", mods = "CTRL|SHIFT", action = act.ScrollToBottom },

    -- コピーモード
    { key = "[", mods = "LEADER", action = act.ActivateCopyMode },
    -- Claude Code の全画面表示のスクロールモード
    -- (出力が WezTerm のスクロールバックに残らないので, Claude Code にスクロールのキーを送る)
    { key = "u", mods = "LEADER", action = act.ActivateKeyTable({ name = "claude_scroll", one_shot = false }) },
    -- コピ, 貼り付け
    { key = "c", mods = "SHIFT|CTRL", action = act.CopyTo("Clipboard") },
    { key = "v", mods = "SHIFT|CTRL", action = act.PasteFrom("Clipboard") },

    -- Pane作成 leader + r or d
    { key = "d", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
    { key = "r", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    -- Paneを閉じる leader + x
    { key = "x", mods = "LEADER", action = act({ CloseCurrentPane = { confirm = true } }) },
    -- Pane移動 leader + hlkj
    { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
    { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
    { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
    { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
    -- Pane選択
    { key = "[", mods = "CTRL|SHIFT", action = act.PaneSelect },
    -- Pane入れ替え (選んだPaneと位置を交換し、フォーカスは元のPaneのまま)
    { key = "e", mods = "LEADER", action = act.PaneSelect({ mode = "SwapWithActiveKeepFocus" }) },
    -- Paneをローテーション
    { key = "o", mods = "LEADER", action = act.RotatePanes("Clockwise") },
    { key = "O", mods = "LEADER", action = act.RotatePanes("CounterClockwise") },
    -- 選択中のPaneのみ表示
    { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

    -- フォントサイズ切替
    -- "+" は Shift を伴って入力されるので CTRL と CTRL|SHIFT の両方を登録する
    { key = "+", mods = "CTRL", action = act.IncreaseFontSize },
    { key = "+", mods = "CTRL|SHIFT", action = act.IncreaseFontSize },
    { key = "-", mods = "CTRL", action = act.DecreaseFontSize },
    -- フォントサイズのリセット
    { key = "0", mods = "CTRL", action = act.ResetFontSize },

    -- タブ切替 Cmd + 数字
    { key = "1", mods = "LEADER", action = act.ActivateTab(0) },
    { key = "2", mods = "LEADER", action = act.ActivateTab(1) },
    { key = "3", mods = "LEADER", action = act.ActivateTab(2) },
    { key = "4", mods = "LEADER", action = act.ActivateTab(3) },
    { key = "5", mods = "LEADER", action = act.ActivateTab(4) },
    { key = "6", mods = "LEADER", action = act.ActivateTab(5) },
    { key = "7", mods = "LEADER", action = act.ActivateTab(6) },
    { key = "8", mods = "LEADER", action = act.ActivateTab(7) },
    { key = "9", mods = "LEADER", action = act.ActivateTab(-1) },

    -- コマンドパレット
    { key = "p", mods = "SHIFT|CTRL", action = act.ActivateCommandPalette },

    -- 設定再読み込み
    { key = "r", mods = "SHIFT|CTRL", action = act.ReloadConfiguration },
    -- キーテーブル用
    { key = "p", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
    {
      key = "a",
      mods = "LEADER",
      action = act.ActivateKeyTable({ name = "activate_pane", timeout_milliseconds = 1000 }),
    },
  },
  -- キーテーブル
  -- https://wezfurlong.org/wezterm/config/key-tables.html
  key_tables = {
    -- Paneサイズ調整 leader + s
    resize_pane = {
      { key = "h", action = act.AdjustPaneSize({ "Left", 2 }) },
      { key = "l", action = act.AdjustPaneSize({ "Right", 2 }) },
      { key = "k", action = act.AdjustPaneSize({ "Up", 2 }) },
      { key = "j", action = act.AdjustPaneSize({ "Down", 2 }) },

      -- Cancel the mode by pressing escape
      { key = "Escape", action = "PopKeyTable" },
    },
    activate_pane = {
      { key = "h", action = act.ActivatePaneDirection("Left") },
      { key = "l", action = act.ActivatePaneDirection("Right") },
      { key = "k", action = act.ActivatePaneDirection("Up") },
      { key = "j", action = act.ActivatePaneDirection("Down") },
    },
    -- copyモード leader + [
    copy_mode = {
      -- 移動
      { key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
      { key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
      { key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
      { key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
      -- 最初と最後に移動
      -- Shiftを伴って入力される記号キーは NONE と SHIFT の両方を登録する
      -- (アルファベットはWezTermがSHIFTを正規化するため片方でよい)
      { key = "^", mods = "NONE", action = act.CopyMode("MoveToStartOfLineContent") },
      { key = "^", mods = "SHIFT", action = act.CopyMode("MoveToStartOfLineContent") },
      { key = "$", mods = "NONE", action = act.CopyMode("MoveToEndOfLineContent") },
      { key = "$", mods = "SHIFT", action = act.CopyMode("MoveToEndOfLineContent") },
      -- 左端に移動
      { key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
      { key = "o", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEnd") },
      { key = "O", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEndHoriz") },
      --
      { key = ";", mods = "NONE", action = act.CopyMode("JumpAgain") },
      -- 単語ごと移動
      { key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
      { key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
      { key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },
      -- ジャンプ機能 t f
      { key = "t", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = true } }) },
      { key = "f", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = false } }) },
      { key = "T", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = true } }) },
      { key = "F", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
      -- 一番下へ
      { key = "G", mods = "NONE", action = act.CopyMode("MoveToScrollbackBottom") },
      -- 一番上へ
      { key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
      -- viweport
      { key = "H", mods = "NONE", action = act.CopyMode("MoveToViewportTop") },
      { key = "L", mods = "NONE", action = act.CopyMode("MoveToViewportBottom") },
      { key = "M", mods = "NONE", action = act.CopyMode("MoveToViewportMiddle") },
      -- スクロール
      { key = "b", mods = "CTRL", action = act.CopyMode("PageUp") },
      { key = "f", mods = "CTRL", action = act.CopyMode("PageDown") },
      { key = "d", mods = "CTRL", action = act.CopyMode({ MoveByPage = 0.5 }) },
      { key = "u", mods = "CTRL", action = act.CopyMode({ MoveByPage = -0.5 }) },
      -- 範囲選択モード
      { key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
      { key = "v", mods = "CTRL", action = act.CopyMode({ SetSelectionMode = "Block" }) },
      { key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },
      -- コピー
      { key = "y", mods = "NONE", action = act.CopyTo("Clipboard") },

      -- コピーモードを終了
      {
        key = "Enter",
        mods = "NONE",
        action = act.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }),
      },
      { key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
      { key = "c", mods = "CTRL", action = act.CopyMode("Close") },
      { key = "q", mods = "NONE", action = act.CopyMode("Close") },
    },
    -- Claude Code の全画面表示のスクロール leader + u
    -- alt+j / alt+k は ~/.claude/keybindings.json で scroll:lineDown / scroll:lineUp に割り当てている
    claude_scroll = {
      { key = "j", mods = "NONE", action = act.SendKey({ key = "j", mods = "ALT" }) },
      { key = "k", mods = "NONE", action = act.SendKey({ key = "k", mods = "ALT" }) },
      { key = "f", mods = "CTRL", action = act.SendKey({ key = "PageDown" }) },
      { key = "b", mods = "CTRL", action = act.SendKey({ key = "PageUp" }) },

      { key = "Escape", mods = "NONE", action = act.PopKeyTable },
      { key = "q", mods = "NONE", action = act.PopKeyTable },
    },

  },
}
