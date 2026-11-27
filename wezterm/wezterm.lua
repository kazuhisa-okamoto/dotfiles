local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true
config.font = wezterm.font_with_fallback({
  "JetBrainsMono Nerd Font",
  "Cascadia Code",
  "Meiryo",
})
config.font_size = 12.0
config.use_ime = true
config.window_background_opacity = 0.85
config.macos_window_background_blur = 20
config.win32_system_backdrop = "Acrylic"
config.default_prog = {
  "pwsh.exe"
}

config.default_cursor_style = "SteadyBlock"

config.window_close_confirmation = "NeverPrompt"

-- カラーテーマ
config.color_scheme = "Tokyo Night"
-- 背景色
config.window_background_gradient = {
  colors = { "#1a1b26" },
}

----------------------------------------------------
-- Tab
----------------------------------------------------
-- タイトルバーを非表示
config.window_decorations = "RESIZE"
-- タブバーの表示
config.show_tabs_in_tab_bar = true
-- タブが一つの時も表示する (右端のモード表示とステータスが隠れないように)
config.hide_tab_bar_if_only_one_tab = false

-- falseにするとタブバーの透過が効かなくなる
-- config.use_fancy_tab_bar = false

local tab_bar = require("tab_bar")

config.window_frame = {
  -- タブバーの透過
  inactive_titlebar_bg = "none",
  active_titlebar_bg = "none",
  -- 本文と同じ等幅のフォントにして、タブとステータスの幅を文字数で見積もれるようにする (tab_bar.lua)
  font = wezterm.font_with_fallback({
    { family = tab_bar.FONT_FAMILY, weight = "Bold" },
    "Meiryo",
  }),
  font_size = tab_bar.FONT_SIZE,
}

-- タブ同士の境界線を非表示
config.colors = {
  tab_bar = {
    inactive_tab_edge = "none",
  },
}

-- タブの形をカスタマイズ
-- タブの左側の装飾
local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_lower_right_triangle
-- タブの右側の装飾
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_upper_left_triangle

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local background = "#5c6d74"
  local foreground = "#FFFFFF"
  local edge_background = "none"
  if tab.is_active then
    background = "#ae8b2d"
    foreground = "#FFFFFF"
  end
  local edge_foreground = background
  -- 右側のステータスに重ならない幅 (左右の三角を含む)
  local width = tab_bar.tab_text_width(tab, tabs, max_width)
  local name = tab.active_pane.title
  local name_width = wezterm.column_width(name)
  -- 三角の内側の空白。名前が収まらないときは空白を減らしてから名前を切る
  local padding = 1
  for p = 3, 2, -1 do
    if 2 + 2 * p + name_width <= width then
      padding = p
      break
    end
  end
  if width < 2 + 2 * padding + 1 then
    padding = 0
  end
  local name_room = width - 2 - 2 * padding
  if name_room < 1 then
    -- 三角も置けないほど狭いときは名前だけにする
    return {
      { Background = { Color = background } },
      { Foreground = { Color = foreground } },
      { Text = wezterm.truncate_right(name, width) },
    }
  end
  local spaces = string.rep(" ", padding)
  local title = spaces .. wezterm.truncate_right(name, name_room) .. spaces
  return {
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = SOLID_LEFT_ARROW },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = title },
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = SOLID_RIGHT_ARROW },
  }
end)

----------------------------------------------------
-- keybinds
----------------------------------------------------
config.disable_default_key_bindings = true
config.keys = require("keybinds").keys
config.key_tables = require("keybinds").key_tables
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 2000 }

----------------------------------------------------
-- workspace の保存と、起動時の復元 (workspace_session.lua)
----------------------------------------------------
-- default_prog を使うので、その設定より後で呼ぶ
require("workspace_session").apply_to_config(config)

return config
