-- ====================================================
-- 基本設定 (行番号)
-- ====================================================
-- 現在行の絶対行番号を表示
vim.opt.number = true
-- 他の行を相対行番号で表示
vim.opt.relativenumber = true
-- 左端のサインカラムを常に表示（ガタつき防止）
vim.opt.signcolumn = "yes"

-- クリップボード
vim.opt.clipboard:append("unnamedplus")
-- TrueColor対応
-- vim.opt.termguicolors = true

-- ====================================================
-- キーバインド設定
-- ====================================================
-- ESC
vim.keymap.set('i', '<C-j>', '<Esc>', { noremap = true, silent = true })

-- ====================================================
-- 自動コマンド (IME制御: zenhan.exe)
-- ====================================================
local im_select_group = vim.api.nvim_create_augroup("IMSelect", { clear = true })

vim.api.nvim_create_autocmd({ "InsertLeave", "CmdlineLeave" }, {
  group = im_select_group,
  pattern = "*",
  callback = function()
    vim.fn.system([[C:\Users\okamo\bin\zenhan.exe 0]])
  end,
})

-- ====================================================
-- プラグイン
-- ====================================================
-- lazy.nvimがなければ自動インストール
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- 最新の安定版を使用
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- プラグインのセットアップ
require("lazy").setup({
  -- oil.nvim の設定
  {
    'stevearc/oil.nvim',
    dependencies = { "nvim-tree/nvim-web-devicons" }, -- アイコン
    config = function()
      require("oil").setup({
        default_file_explorer = true, -- netrwを置き換える
        columns = {
          "icon",
          -- "permissions",
          -- "size",
          -- "mtime",
        },
        view_options = {
          show_hidden = true, -- 隠しファイルを表示する
        },
      })
      -- キーバインド: - キーでファイルブラウザを開く
      -- vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
    end,
  },

  {
    "ibhagwan/fzf-lua",
    -- アイコンを表示するために必要
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      -- 基本的な呼び出し設定
      require("fzf-lua").setup({})
      
      -- キーバインド設定
      local fzf = require('fzf-lua')
      vim.keymap.set('n', '<leader>ff', fzf.files, { desc = "ファイル検索" })
      vim.keymap.set('n', '<leader>fg', fzf.live_grep, { desc = "全文検索" })
      vim.keymap.set('n', '<leader>fb', fzf.buffers, { desc = "バッファ一覧" })
      vim.keymap.set('n', '<leader>fh', fzf.help_tags, { desc = "ヘルプ検索" })
    end
  },

  -- カラーテーマ
  {
    "NLKNguyen/papercolor-theme",
    lazy = false,
    priority = 1000,
    enabled = true,
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
    enabled = false,
    config = function()
      require("monokai-pro").setup({
        -- , octagon, pro, classic, machine, ristretto, spectrum
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
        -- wave (デフォルト), dragon (より暗い), lotus (明るい) が選べます
        theme = "wave", 
        background = { dark = "wave", light = "lotus" },
      })
      vim.cmd("colorscheme kanagawa")
    end,
  },

})
