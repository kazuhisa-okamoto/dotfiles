-- タブバーで、タブが右側のステータス (keybinds.lua の update-right-status) に重ならないようにする
--
-- use_fancy_tab_bar では、WezTerm はタブと右側のステータスを別々に並べ、タブの幅を
-- 右側のステータスの幅に合わせて縮めない (タブを増やすとステータスの上にかぶさる)。
-- そこで update-right-status でウィンドウの幅とステータスの幅を覚えておき、
-- format-tab-title で残りの幅をタブの数で割って、タブ名をその幅に切り詰める。
--
-- 幅は、タブバーのフォント (window_frame.font) の1文字分 (cell) を単位に数える。
-- JetBrainsMono Nerd Font はアイコンや三角の飾りも1文字分で描かれるので、
-- wezterm.column_width で数えた文字数がほぼそのまま幅になる
-- (日本語は 2 と数えるが実際は約 1.6 文字分なので、少し短めに切ることになる)。
local wezterm = require("wezterm")

local M = {}

M.FONT_FAMILY = "JetBrainsMono Nerd Font"
-- WezTerm が Windows のタブバーに使う既定の大きさ (pt)。大きさは変えずにフォントだけそろえる
M.FONT_SIZE = 10.0
-- JetBrains Mono の1文字の幅 (em。1000 units per em のうち 600)
local ADVANCE_EM = 0.6

-- タブ名のほかに WezTerm がタブバーに置くもの (単位は文字数)。
-- wezterm-gui/src/termwindow/render/fancy_tab_bar.rs の 20240203-110809-5046fc22 の値から見積もった
-- タブ1つ: 左右の padding 0.5 ずつ + 閉じるボタン (margin 0.5 + padding 0.25 ずつ + 幅は文字の高さの半分で約 1.1) + 枠線 1px ずつ
local TAB_OVERHEAD = 3.5
-- 新しいタブのボタン: margin 0.5 + padding 0.5 ずつ + 幅約 1.1 + 枠線 1px ずつ
local NEW_TAB_BUTTON = 3
-- タブの列の左端の padding 0.5 と、右側のステータスの左の padding 0.5
local BAR_PADDING = 1
-- 見積もりの誤差のぶん空けておく
local SAFETY = 1
-- WezTerm 自身も、タブ1つの幅を「ウィンドウの幅 ÷ (タブの数 + 1) − 1.5 文字分」までに抑える
local WEZTERM_TAB_MARGIN = 1.5

-- タブ名をこれより短くしないと収まらないときは、右側のステータスを短い表示に切り替える
M.MIN_TAB_TEXT = 8

local function key(window_id)
  return "tab_bar_" .. tostring(window_id)
end

-- wezterm.format に渡す表の Text を足し合わせた表示幅 (文字数)
function M.text_width(cells)
  local width = 0
  for _, cell in ipairs(cells) do
    if type(cell) == "table" and cell.Text then
      width = width + wezterm.column_width(cell.Text)
    end
  end
  return width
end

-- ウィンドウの幅を、タブバーのフォントの文字数で返す
local function bar_cells(dimensions)
  -- WezTerm は文字の幅を pt × dpi ÷ 72 × em の幅で求め、切り上げて px にする (wezterm-gui/src/utilsprites.rs)
  local cell_px = math.ceil(ADVANCE_EM * M.FONT_SIZE * dimensions.dpi / 72)
  return dimensions.pixel_width / cell_px
end

-- タブ名 (format-tab-title が返す文字列) に使える幅。まだ分からなければ nil
local function text_budget(cells, status_width, tab_count)
  local for_tabs = cells - NEW_TAB_BUTTON - BAR_PADDING - SAFETY - status_width
  local budget = for_tabs / tab_count - TAB_OVERHEAD
  local wezterm_cap = cells / (tab_count + 1) - WEZTERM_TAB_MARGIN - TAB_OVERHEAD
  return math.floor(math.min(budget, wezterm_cap))
end

-- update-right-status から呼ぶ。右側のステータスが今のタブの数で収まるかを返す
function M.status_fits(window, status_width)
  local tab_count = #window:mux_window():tabs()
  local cells = bar_cells(window:get_dimensions())
  return text_budget(cells, status_width, tab_count) >= M.MIN_TAB_TEXT
end

-- update-right-status から、set_right_status の直前に呼ぶ。
-- ウィンドウの幅とステータスの幅を覚える。ウィンドウの幅が変わったときは true を返す
-- (ステータスの文字列が前と同じだと WezTerm はタブバーを作り直さないので、呼び出し側で作り直させる)
function M.record(window, status_width)
  local dimensions = window:get_dimensions()
  local cells = bar_cells(dimensions)
  local k = key(window:window_id())
  local old = wezterm.GLOBAL[k]
  if old and old.cells == cells and old.status_width == status_width then
    return false
  end
  wezterm.GLOBAL[k] = { cells = cells, status_width = status_width }
  return old ~= nil and old.cells ~= cells
end

-- format-tab-title から呼ぶ。タブ名に使える幅 (文字数) を返す。まだ分からなければ max_width
function M.tab_text_width(tab, tabs, max_width)
  local info = wezterm.GLOBAL[key(tab.window_id)]
  if not info then
    return max_width
  end
  local budget = text_budget(info.cells, info.status_width, #tabs)
  return math.max(1, math.min(max_width, budget))
end

return M
