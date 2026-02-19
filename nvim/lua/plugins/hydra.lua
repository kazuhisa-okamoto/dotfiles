return {
  "anuvyklack/hydra.nvim",

  config = function()
    local Hydra = require("hydra")

    -- 横境界
    -- h:境界を左にずらす
    -- l:境界を右にずらす
    local function resize_horizontal(delta)
      local cur = vim.api.nvim_get_current_win()

      vim.cmd("wincmd h")
      local left = vim.api.nvim_get_current_win()

      if left ~= cur then
        vim.cmd("vertical resize " .. (delta > 0 and "+" or "-") .. math.abs(delta))
        vim.api.nvim_set_current_win(cur)
      else
        vim.cmd("vertical resize " .. (delta > 0 and "+" or "-") .. math.abs(delta))
      end
    end

    -- 縦境界
    -- j:境界を下にずらす
    -- k:境界を上にずらす
    local function resize_vertical(delta)
      local cur = vim.api.nvim_get_current_win()

      vim.cmd("wincmd k")
      local up = vim.api.nvim_get_current_win()

      if up ~= cur then
        vim.cmd("resize " .. (delta > 0 and "+" or "-") .. math.abs(delta))
        vim.api.nvim_set_current_win(cur)
      else
        vim.cmd("resize " .. (delta > 0 and "+" or "-") .. math.abs(delta))
      end
    end

    Hydra({
      name = "Resize",
      mode = "n",
      body = "<leader>w",
      color = "pink",

      heads = {
        { "h", function() resize_horizontal(-3) end },
        { "l", function() resize_horizontal(3) end },
        { "j", function() resize_vertical(3) end },
        { "k", function() resize_vertical(-3) end },
        { "q", nil, { exit = true } },
      },
    })
  end,
}
