
return {
  "j-morano/buffer_manager.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("buffer_manager").setup({
      short_file_names = true,
      short_term_names = true,
      loop_nav = true,
      use_shortcuts = true,
    })

    -- キーマップ
    local map = vim.keymap.set
    local opts = { noremap = true, silent = true }
    local bmui = require("buffer_manager.ui")

    -- バッファ一覧
    map("n", "<leader>bm", bmui.toggle_quick_menu, opts)

    -- 次/前のバッファへ移動
    map("n", "<S-j>", bmui.nav_next, opts)
    map("n", "<S-k>", bmui.nav_prev, opts)

    -- ID指定でジャンプ
    for i = 1, 10 do
      map("n", "<leader>" .. (i % 10), function()
        bmui.nav_file(i)
      end, opts)
    end
  end,
}
