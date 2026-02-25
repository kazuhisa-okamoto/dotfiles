return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local harpoon = require("harpoon")

    -- 必須の設定
    harpoon:setup()

    -- 基本的なキーバインドの設定
    -- <leader>a で現在のファイルをリストに追加
    vim.keymap.set("n", "<leader>a", function() harpoon:list():add() end)
    
    -- <C-e> (Ctrl+e) でHarpoonのUIメニューを表示
    vim.keymap.set("n", "<C-e>", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)

    -- リスト内のファイルに直接ジャンプ (1〜4)
    -- 設定例: <leader>1 で1番目のファイルへ
    vim.keymap.set("n", "<leader>1", function() harpoon:list():select(1) end)
    vim.keymap.set("n", "<leader>2", function() harpoon:list():select(2) end)
    vim.keymap.set("n", "<leader>3", function() harpoon:list():select(3) end)
    vim.keymap.set("n", "<leader>4", function() harpoon:list():select(4) end)

    -- 前後のファイルへの切り替え (Toggle functionality)
    vim.keymap.set("n", "<C-S-P>", function() harpoon:list():prev() end)
    vim.keymap.set("n", "<C-S-N>", function() harpoon:list():next() end)
  end,
}