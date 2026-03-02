return {
  "mikavilpas/yazi.nvim",
  version = "*", -- use the latest stable version
  --event = "VeryLazy",
  dependencies = {
    { "nvim-lua/plenary.nvim", lazy = true },
  },
  keys = {
    {
      "<leader>e",
      mode = { "n", "v" },
      function()
        if vim.g.vscode then
          -- VSCodeのYazi拡張を起動
          vim.fn.VSCodeNotify("yazi-vscode.toggle")
        else
          -- Neovimのyazi.nvimを起動
          vim.cmd("Yazi")
        end
      end,
      desc = "Open yazi at the current file",
    },
    --{
    --  -- Open in the current working directory
    --  "<leader>w",
    --  "<cmd>Yazi cwd<cr>",
    --  desc = "Open the file manager in nvim's working directory",
    --},
    {
      "<leader>E",
      --"<cmd>Yazi toggle<cr>",
      function()
        if vim.g.vscode then
          vim.fn.VSCodeNotify("yazi-vscode.toggle")
        else
          vim.cmd("Yazi toggle")
        end
      end,
      desc = "Resume the last yazi session",
    },
  },
  ---@type YaziConfig | {}
  opts = {
    open_for_directories = false,
    keymaps = {
      show_help = "<f1>",
    },
  },
  init = function()
    vim.g.loaded_netrwPlugin = 1
  end,
}
