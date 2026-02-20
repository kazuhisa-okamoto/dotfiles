return {
  "anuvyklack/hydra.nvim",

  config = function()
    local Hydra = require("hydra")

    -- VSCode判定
    local function is_vscode()
      return vim.g.vscode ~= nil
    end

    local function resize_horizontal_nvim(delta)
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

    local function resize_vertical_nvim(delta)
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

    -- VSCode用
    local function resize_horizontal_vscode(delta)
      if delta < 0 then
        -- 左へ動かす
        vim.fn.VSCodeCall("workbench.action.focusLeftGroup")
        vim.fn.VSCodeCall("workbench.action.decreaseViewSize")
        vim.fn.VSCodeCall("workbench.action.focusRightGroup")
      else
        -- 右へ動かす
        vim.fn.VSCodeCall("workbench.action.focusLeftGroup")
        vim.fn.VSCodeCall("workbench.action.increaseViewSize")
        vim.fn.VSCodeCall("workbench.action.focusRightGroup")
      end
    end

    local function resize_vertical_vscode(delta)
      if delta > 0 then
        vim.fn.VSCodeCall("workbench.action.increaseViewSize")
      else
        vim.fn.VSCodeCall("workbench.action.decreaseViewSize")
      end
    end

    local function resize_vertical_vscode(delta)
      if delta < 0 then
        -- 上へ動かす
        vim.fn.VSCodeCall("workbench.action.focusAboveGroup")
        vim.fn.VSCodeCall("workbench.action.decreaseViewSize")
        vim.fn.VSCodeCall("workbench.action.focusBelowGroup")
      else
        -- 下へ動かす
        vim.fn.VSCodeCall("workbench.action.focusAboveGroup")
        vim.fn.VSCodeCall("workbench.action.increaseViewSize")
        vim.fn.VSCodeCall("workbench.action.focusBelowGroup")
      end
    end

    -- Neovim, VSCode共通
    local function resize_horizontal(delta)
      if is_vscode() then
        resize_horizontal_vscode(delta)
      else
        resize_horizontal_nvim(delta)
      end
    end

    local function resize_vertical(delta)
      if is_vscode() then
        resize_vertical_vscode(delta)
      else
        resize_vertical_nvim(delta)
      end
    end

    -- Hydra
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
