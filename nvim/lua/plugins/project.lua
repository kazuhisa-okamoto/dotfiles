return {
  "ahmedkhalf/project.nvim",
  config = function()
    require("project_nvim").setup({
      -- "lsp" は使わない: このプラグインの LSP 検出は Neovim 0.12 で非推奨の
      -- vim.lsp.buf_get_clients() を呼び、起動のたびに警告が出る (プラグインは 2023 年で更新停止)
      detection_methods = { "pattern" },
      patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json" },
      silent_chdir = true,

      manual_mode = false,
    })
  end,
}
