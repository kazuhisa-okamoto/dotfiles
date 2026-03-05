-- Telescopeの設定（すでにある場合は extension の部分に注目してください）
return {
  "nvim-telescope/telescope.nvim",
  dependencies = { "ahmedkhalf/project.nvim" },
  config = function()
    local telescope = require("telescope")
    
    telescope.load_extension('projects')
  end,
  keys = {
    -- プロジェクト一覧を開く
    { "<leader>fp", "<cmd>Telescope projects<cr>", desc = "Projects" },
  },
}
