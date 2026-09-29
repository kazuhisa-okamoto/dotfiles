-- バッファ内で markdown を整形表示する (ブラウザを開かない)
return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  ft = { "markdown" },
  config = function()
    require("render-markdown").setup({
      -- デフォルトはオフ。<leader>mr (:RenderMarkdown toggle) で切り替える
      enabled = false,
    })
    vim.keymap.set("n", "<leader>mr", "<CMD>RenderMarkdown toggle<CR>", { desc = "Render markdown toggle" })
  end,
}
