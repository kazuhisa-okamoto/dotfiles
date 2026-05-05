return {
  "neovim/nvim-lspconfig",
  config = function()

    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    vim.lsp.config("pyright", {
      capabilities = capabilities,
      on_attach = function(_, bufnr)
        local map = function(key, fn, desc)
          vim.keymap.set("n", key, fn, { buffer = bufnr, desc = desc })
        end
        map("gd", vim.lsp.buf.definition,      "Go to definition")
        map("gD", vim.lsp.buf.declaration,     "Go to declaration")
        map("gr", vim.lsp.buf.references,      "Show references")
        map("gi", vim.lsp.buf.implementation,  "Go to implementation")
        map("K",  vim.lsp.buf.hover,           "Hover documentation")
      end,
    })

    vim.lsp.enable("pyright")

  end,
}
