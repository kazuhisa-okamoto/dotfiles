-- The main branch is the rewrite that supports Neovim 0.12+.
-- It needs the tree-sitter CLI (0.26.1+), a C compiler, tar and curl to build parsers.
local parsers = {
  "python",
  "cpp",
  "rust",
  "typescript",
  "tsx",
  "markdown",
  "markdown_inline",
}

-- Filetypes that use the parsers above (tsx is the typescriptreact filetype).
local filetypes = {
  "python",
  "cpp",
  "rust",
  "typescript",
  "typescriptreact",
  "markdown",
}

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").install(parsers)

    vim.api.nvim_create_autocmd("FileType", {
      pattern = filetypes,
      callback = function(args)
        if not pcall(vim.treesitter.start, args.buf) then
          return
        end
        vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })
  end,
}
