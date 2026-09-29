-- ブラウザで markdown をプレビューする (VSCode の Markdown Preview 相当)
return {
  "iamcco/markdown-preview.nvim",
  ft = { "markdown" },
  cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
  -- 事前ビルド済みバイナリ (app/bin/markdown-preview-win.exe) を取得する。
  -- 本来は vim.fn["mkdp#util#install"]() を呼ぶが、build の実行時点では
  -- lazy.nvim がまだ plugin を runtimepath に入れておらず autoload が解決できず
  -- E117: Unknown function: mkdp#util#install になる。install.cmd を直接叩いて回避する。
  -- (Windows 専用。install.cmd は GitHub Releases からバイナリを落とす PowerShell スクリプト)
  build = function(plugin)
    local manifest = vim.json.decode(table.concat(vim.fn.readfile(plugin.dir .. "/package.json"), ""))
    local cmd = { "cmd.exe", "/c", plugin.dir .. "/app/install.cmd", "v" .. manifest.version }
    local result = vim.system(cmd, { cwd = plugin.dir .. "/app" }):wait()
    if result.code ~= 0 then
      error("markdown-preview: install.cmd failed: " .. (result.stderr or "") .. (result.stdout or ""))
    end
  end,
  config = function()
    -- バッファを閉じてもプレビューを残す
    vim.g.mkdp_auto_close = 0
    -- カーソル位置に合わせてプレビュー側もスクロールする
    vim.g.mkdp_preview_options = {
      sync_scroll_type = "middle",
    }
    vim.keymap.set("n", "<leader>mp", "<CMD>MarkdownPreviewToggle<CR>", { desc = "Markdown preview toggle" })
  end,
}
