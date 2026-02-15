-- ====================================================
-- 基本設定
-- ====================================================
-- 現在行の絶対行番号を表示
vim.opt.number = true
-- 他の行を相対行番号で表示
vim.opt.relativenumber = true
-- 左端のサインカラムを常に表示
vim.opt.signcolumn = "yes"
-- ターミナルのタイトル
vim.opt.title = true
-- 表示内容（%t:ファイル名, %F:フルパス）
vim.opt.titlestring = "%t"

-- クリップボード
vim.opt.clipboard:append("unnamedplus")
-- TrueColor対応
-- vim.opt.termguicolors = true

-- インデント基本設定
vim.opt.tabstop = 4        -- タブの見た目幅
vim.opt.shiftwidth = 4     -- >> や自動インデント幅
vim.opt.softtabstop = 4    -- Tabキー押下時の幅
vim.opt.expandtab = true   -- タブをスペースに変換

--  (IME制御: zenhan.exe)
local im_select_group = vim.api.nvim_create_augroup("IMSelect", { clear = true })

vim.api.nvim_create_autocmd({ "InsertLeave", "CmdlineLeave" }, {
  group = im_select_group,
  pattern = "*",
  callback = function()
    vim.fn.system([[C:\Users\okamo\bin\zenhan.exe 0]])
  end,
})

-- ====================================================
-- キーバインド設定
-- ====================================================
-- リーダーキー
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ESC
vim.keymap.set('i', '<C-j>', '<Esc>', { noremap = true, silent = true })

-- 透過
local transparent = false
function ToggleTransparency()
  if transparent then
    vim.cmd("colorscheme monokai-pro")
    transparent = false
  else
    vim.cmd [[
      highlight Normal guibg=NONE ctermbg=NONE
      highlight NormalNC guibg=NONE ctermbg=NONE
      highlight EndOfBuffer guibg=NONE ctermbg=NONE
      highlight SignColumn guibg=NONE
      highlight VertSplit guibg=NONE
      highlight StatusLine guibg=NONE
      highlight StatusLineNC guibg=NONE
    ]]
    transparent = true
  end
end
vim.keymap.set("n", "<leader>t", ToggleTransparency)

-- ====================================================
-- プラグイン
-- ====================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  {
    "NLKNguyen/papercolor-theme",
    lazy = false,
    priority = 1000,
    enabled = false,
    config = function()
      vim.opt.background = "dark"
      vim.cmd([[colorscheme PaperColor]])
    end,
  },

  { 
    "folke/tokyonight.nvim", 
    lazy = false, 
    priority = 1000, 
    enabled = false,
    config = function()
      vim.cmd([[colorscheme tokyonight]])
    end,
  },

  {
    "loctvl842/monokai-pro.nvim",
    lazy = false,
    priority = 1000,
    enabled = true,
    config = function()
      require("monokai-pro").setup({
        -- octagon, pro, classic, machine, ristretto, spectrum
        filter = "pro", 
      })
      vim.cmd("colorscheme monokai-pro")
    end,
  },

  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
    enabled = false,
    config = function()
      require("kanagawa").setup({
        -- wave (デフォルト), dragon (より暗い), lotus (明るい)
        theme = "wave", 
        background = { dark = "wave", light = "lotus" },
      })
      vim.cmd("colorscheme kanagawa")
    end,
  },

  { import = "plugins" },

})
